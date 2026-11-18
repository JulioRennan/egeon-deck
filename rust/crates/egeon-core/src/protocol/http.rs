//! HTTP/1.1 mínimo, porte do `ControlSocket` do Swift: uma requisição por
//! conexão, corpo por `Content-Length`, resposta JSON com `Connection: close`.
//!
//! O bastante para `curl --unix-socket` e para o `egeon`; não é um servidor
//! HTTP de verdade e não tenta ser.
//!
//! Segue o `readRequest` do Swift (`ControlSocket.swift:1050-1084`), com as
//! folgas dele: linha de cabeçalho sem `:` é ignorada, `Content-Length`
//! ausente ou não numérico faz o corpo ser o que já chegou junto do
//! cabeçalho, e a linha de requisição é partida em espaços sem exigir forma
//! (espaço duplo e alvo absoluto passam). Script antigo que funciona contra o
//! Swift funciona aqui.
//!
//! Divergências que ficam:
//! - corpo acima de [`MAX_BODY`] é recusado antes de ler (o Swift guardava o
//!   que viesse, sem teto);
//! - `GET /ui` com upgrade não tem corpo: o que vem depois do cabeçalho já é
//!   do canal (rota nova, o Swift não tem);
//! - `Content-Length:` sem valor, ou negativo, vale como ausente (o Swift caía:
//!   ao indexar a parte que não existe, ou no `prefix(-1)`).

use std::collections::HashMap;

use serde_json::Value;

use super::ProtocolError;

/// Teto do cabeçalho, o mesmo do Swift: quem manda mais que isso sem a linha
/// em branco não é cliente do Egeon.
pub const MAX_HEAD: usize = 1 << 20;

/// Teto do corpo. O Swift não tinha; aqui um `Content-Length` absurdo faria o
/// core guardar o que viesse, e o maior corpo de hoje (o plano do maestro, uma
/// colagem no `/message`) fica muito abaixo disto.
pub const MAX_BODY: usize = 64 << 20;

/// O protocolo que o canal `/ui` pede no `Upgrade` (decisão 16).
pub const UI_PROTOCOL: &str = "egeon-ndjson";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    pub method: String,
    /// O alvo como veio, com a query.
    pub target: String,
    headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

impl Request {
    /// O caminho sem a query: `/dispatch?…` não termina em `/dispatch`.
    pub fn path(&self) -> &str {
        self.target.split('?').next().unwrap_or(&self.target)
    }

    pub fn query(&self) -> HashMap<String, String> {
        parse_query(&self.target)
    }

    /// Primeiro cabeçalho com esse nome, sem diferença de caixa.
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }

    /// `GET /ui` pedindo `Upgrade: egeon-ndjson`.
    pub fn is_ui_upgrade(&self) -> bool {
        self.method == "GET"
            && self.path() == "/ui"
            && self.header("upgrade").is_some_and(|v| {
                v.split(',')
                    .any(|p| p.trim().eq_ignore_ascii_case(UI_PROTOCOL))
            })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Parsed {
    /// Falta chegar coisa.
    Partial,
    /// `consumed` é quanto do buffer a requisição ocupou; o resto já é do
    /// canal, quando houver upgrade.
    Complete { request: Request, consumed: usize },
}

/// Lê uma requisição do começo de `buf`.
///
/// Com `eof`, o par já fechou a escrita: um corpo menor que o
/// `Content-Length` segue com o que chegou, como no Swift.
pub fn parse_request(buf: &[u8], eof: bool) -> Result<Parsed, ProtocolError> {
    let Some(head_end) = find(buf, b"\r\n\r\n") else {
        if buf.len() > MAX_HEAD {
            return Err(ProtocolError::HeadTooLarge);
        }
        return if eof {
            Err(ProtocolError::Truncated)
        } else {
            Ok(Parsed::Partial)
        };
    };
    let head = std::str::from_utf8(&buf[..head_end]).map_err(|_| ProtocolError::HeadNotUtf8)?;
    // `split` do Swift: pedaço vazio não conta, nem entre linhas nem entre
    // palavras.
    let mut lines = head.split("\r\n").filter(|l| !l.is_empty());
    let request_line = lines.next().unwrap_or_default();
    let mut parts = request_line.split(' ').filter(|p| !p.is_empty());
    let method = parts.next().unwrap_or_default().to_owned();
    let target = parts.next().unwrap_or_default().to_owned();

    let headers: Vec<(String, String)> = lines
        .filter_map(|line| line.split_once(':'))
        .map(|(name, value)| (name.trim().to_owned(), value.trim().to_owned()))
        .collect();

    let body_start = head_end + 4;
    let available = buf.len() - body_start;
    let mut request = Request {
        method,
        target,
        headers,
        body: Vec::new(),
    };
    if request.is_ui_upgrade() {
        return Ok(Parsed::Complete {
            request,
            consumed: body_start,
        });
    }
    let length = content_length(head).unwrap_or(available);
    if length > MAX_BODY {
        return Err(ProtocolError::BodyTooLarge(length));
    }
    if available < length && !eof {
        return Ok(Parsed::Partial);
    }
    let take = length.min(available);
    request.body = buf[body_start..body_start + take].to_vec();
    Ok(Parsed::Complete {
        request,
        consumed: body_start + take,
    })
}

/// O `contentLength(in:)` do Swift: a primeira linha que começa com
/// `content-length:`, sem diferença de caixa; valor que não é número dá
/// `None`, e quem chama usa o corpo que já chegou.
fn content_length(head: &str) -> Option<usize> {
    let line = head
        .split("\r\n")
        .find(|l| l.to_ascii_lowercase().starts_with("content-length:"))?;
    line.split(':')
        .filter(|p| !p.is_empty())
        .nth(1)?
        .trim()
        .parse()
        .ok()
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

/// Query como no Swift: pares sem `=` são ignorados, o último valor de uma
/// chave repetida vence, e um valor com escape quebrado fica como veio.
/// `+` não vira espaço — o `egeon` codifica tudo com `%XX`.
pub fn parse_query(target: &str) -> HashMap<String, String> {
    // `split` do Swift: só o trecho entre o primeiro e o segundo `?` conta.
    let Some(raw) = target.split('?').filter(|s| !s.is_empty()).nth(1) else {
        return HashMap::new();
    };
    let mut out = HashMap::new();
    for pair in raw.split('&') {
        let Some((key, value)) = pair.split_once('=') else {
            continue;
        };
        if key.is_empty() || value.is_empty() {
            // O Swift parte com `split`, que joga fora pedaço vazio: `a=` e
            // `=b` não viram par.
            continue;
        }
        let decoded = percent_decode(value).unwrap_or_else(|| value.to_owned());
        out.insert(key.to_owned(), decoded);
    }
    out
}

fn percent_decode(raw: &str) -> Option<String> {
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = bytes.get(i + 1..i + 3)?;
            let hex = std::str::from_utf8(hex).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

pub fn reason(status: u16) -> &'static str {
    match status {
        101 => "Switching Protocols",
        200 => "OK",
        400 => "Bad Request",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        _ => "Service Unavailable",
    }
}

/// Resposta JSON completa, pronta para escrever e fechar.
pub fn json_response(status: u16, json: &Value) -> Vec<u8> {
    let body = serde_json::to_vec(json).unwrap_or_else(|_| b"{}".to_vec());
    let mut out = format!(
        "HTTP/1.1 {status} {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        reason(status),
        body.len()
    )
    .into_bytes();
    out.extend_from_slice(&body);
    out
}

/// O `101` que abre o canal `/ui`.
pub fn upgrade_response() -> Vec<u8> {
    format!(
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: {UI_PROTOCOL}\r\nConnection: Upgrade\r\n\r\n"
    )
    .into_bytes()
}

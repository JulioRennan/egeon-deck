//! Cliente HTTP/1.1 mínimo sobre o socket de controle: uma requisição por
//! conexão, resposta lida por `Content-Length` ou até o par fechar.
//!
//! É o que o `curl --unix-socket` fazia para o script `egeon` e o `socket` do
//! python para o gancho de permissão.

use std::io::{self, Read, Write};
#[cfg(unix)]
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::time::{Duration, Instant};

// O std não tem `AF_UNIX` no Windows; a `uds_windows` dá o mesmo socket com a
// mesma interface (decisão 54).
#[cfg(windows)]
use uds_windows::UnixStream;

/// Quanto esperar o socket.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Limit {
    /// Sem prazo: o comando `egeon` espera o app o tempo que ele levar.
    None,
    /// Teto da requisição inteira (`curl --max-time`): o gancho segura a TUI,
    /// e app fora do ar não pode fazer o usuário esperar.
    Total(Duration),
    /// Prazo de cada operação (`socket.settimeout` do python).
    PerOp(Duration),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub status: u16,
    pub body: Vec<u8>,
}

#[derive(Debug, thiserror::Error)]
pub enum HttpError {
    #[error("não conectou ao socket: {0}")]
    Connect(io::Error),
    #[error("falha na conversa com o socket: {0}")]
    Io(io::Error),
    #[error("o prazo acabou")]
    Timeout,
    #[error("o app fechou sem responder")]
    EmptyReply,
    #[error("resposta que não é HTTP")]
    Malformed,
}

/// Uma requisição, uma resposta. `body` é `None` nos GET: sem corpo, sem
/// `Content-Length`. O alvo vai como bytes porque o que o agente digita não
/// é obrigado a ser UTF-8.
pub fn request(
    sock: &Path,
    method: &str,
    target: &[u8],
    body: Option<&[u8]>,
    limit: Limit,
) -> Result<Response, HttpError> {
    let started = Instant::now();
    let mut stream = UnixStream::connect(sock).map_err(HttpError::Connect)?;

    let mut wire = Vec::with_capacity(target.len() + body.map_or(0, <[u8]>::len) + 96);
    wire.extend_from_slice(method.as_bytes());
    wire.push(b' ');
    wire.extend_from_slice(target);
    wire.extend_from_slice(b" HTTP/1.1\r\nHost: eg\r\n");
    if let Some(body) = body {
        wire.extend_from_slice(format!("Content-Length: {}\r\n", body.len()).as_bytes());
    }
    // Sem isto um servidor que mantém a conexão faria a leitura esperar o
    // prazo inteiro.
    wire.extend_from_slice(b"Connection: close\r\n\r\n");
    if let Some(body) = body {
        wire.extend_from_slice(body);
    }

    apply(&stream, limit, started)?;
    stream.write_all(&wire).map_err(io_error)?;

    let mut buf = Vec::new();
    let mut chunk = [0u8; 8192];
    while !complete(&buf) {
        // Só o teto total encolhe com o tempo; os outros prazos já valem desde
        // antes da escrita.
        if matches!(limit, Limit::Total(_)) {
            apply(&stream, limit, started)?;
        }
        match stream.read(&mut chunk) {
            Ok(0) => break,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
            Err(e) => return Err(io_error(e)),
        }
    }
    parse(&buf)
}

fn io_error(e: io::Error) -> HttpError {
    match e.kind() {
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut => HttpError::Timeout,
        _ => HttpError::Io(e),
    }
}

/// Ajusta o prazo restante antes de cada operação bloqueante.
fn apply(stream: &UnixStream, limit: Limit, started: Instant) -> Result<(), HttpError> {
    let wait = match limit {
        Limit::None => None,
        Limit::PerOp(d) => Some(d),
        Limit::Total(d) => {
            let left = d.saturating_sub(started.elapsed());
            if left.is_zero() {
                return Err(HttpError::Timeout);
            }
            Some(left)
        }
    };
    // No macOS, ajustar o prazo de um socket que o par já fechou dá EINVAL. A
    // resposta que já chegou continua lá para ser lida, então o erro não vale.
    for set in [
        stream.set_read_timeout(wait),
        stream.set_write_timeout(wait),
    ] {
        match set {
            Err(e) if e.kind() != io::ErrorKind::InvalidInput => return Err(HttpError::Io(e)),
            _ => {}
        }
    }
    Ok(())
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn content_length(head: &[u8]) -> Option<usize> {
    let head = String::from_utf8_lossy(head);
    head.split("\r\n").skip(1).find_map(|line| {
        let (name, value) = line.split_once(':')?;
        if name.trim().eq_ignore_ascii_case("content-length") {
            value.trim().parse().ok()
        } else {
            None
        }
    })
}

/// Já chegou tudo o que o `Content-Length` prometeu?
fn complete(buf: &[u8]) -> bool {
    let Some(end) = find(buf, b"\r\n\r\n") else {
        return false;
    };
    content_length(&buf[..end]).is_some_and(|len| buf.len() >= end + 4 + len)
}

fn parse(buf: &[u8]) -> Result<Response, HttpError> {
    if buf.is_empty() {
        return Err(HttpError::EmptyReply);
    }
    let end = find(buf, b"\r\n\r\n").ok_or(HttpError::Malformed)?;
    let head = String::from_utf8_lossy(&buf[..end]);
    let status = head
        .lines()
        .next()
        .and_then(|line| line.split(' ').nth(1))
        .and_then(|code| code.parse().ok())
        .ok_or(HttpError::Malformed)?;
    let mut body = buf[end + 4..].to_vec();
    if let Some(len) = content_length(&buf[..end]) {
        body.truncate(len);
    }
    Ok(Response { status, body })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn le_o_corpo_pelo_content_length() {
        let raw = b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabcXYZ";
        assert!(complete(raw));
        let resp = parse(raw).unwrap_or_else(|e| unreachable!("{e}"));
        assert_eq!(resp.status, 200);
        assert_eq!(resp.body, b"abc");
    }

    #[test]
    fn sem_content_length_o_corpo_e_o_que_veio() {
        let raw = b"HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n{\"e\":1}";
        assert!(!complete(raw));
        let resp = parse(raw).unwrap_or_else(|e| unreachable!("{e}"));
        assert_eq!(resp.status, 404);
        assert_eq!(resp.body, b"{\"e\":1}");
    }

    #[test]
    fn vazio_e_lixo_sao_erros() {
        assert!(matches!(parse(b""), Err(HttpError::EmptyReply)));
        assert!(matches!(parse(b"oi"), Err(HttpError::Malformed)));
        assert!(matches!(
            parse(b"HTTP/1.1 abc\r\n\r\n"),
            Err(HttpError::Malformed)
        ));
    }
}

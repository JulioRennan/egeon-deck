//! Os subcomandos do `egeon` — porte do script que o Swift instalava em
//! `~/.egeon/bin/egeon`, com as mesmas rotas e a mesma saída.
//!
//! O comando não diz nem envia quem está chamando: o app descobre pelo
//! processo do outro lado do socket. Um parâmetro aqui seria só uma sugestão, e
//! as guardas de cadeia não podem depender de algo que o agente escreve.

use std::io::{Read, Write};
use std::path::Path;

use crate::encode::enc;
use crate::http::{self, HttpError, Limit};

/// As linhas 2 a 25 do script, sem os dois primeiros caracteres: o que o
/// `egeon` sem argumento imprimia (por defeito do script, o `deny` e o último
/// parágrafo ficam de fora — porte fiel).
pub const USAGE: &str = include_str!("usage.txt");

/// O manual do maestro, embutido: um CLI sem skill precisa dele mesmo quando o
/// maestro ainda não foi ligado.
const GUIDE: &str = include_str!("guide.md");

pub struct Streams<'a> {
    pub stdin: &'a mut dyn Read,
    pub out: &'a mut dyn Write,
    pub err: &'a mut dyn Write,
}

enum Body {
    Stdin,
    Bytes(Vec<u8>),
}

/// Executa um comando e devolve o código de saída. `args` não inclui o nome do
/// programa.
pub fn run(args: &[Vec<u8>], sock: &Path, io: &mut Streams) -> i32 {
    let arg = |i: usize| args.get(i).map(Vec::as_slice);
    let command = arg(0).unwrap_or_default();
    match command {
        b"peers" => get(io, sock, b"/peers".to_vec()),
        b"send" => {
            let Some(target) = arg(1) else {
                return usage_error(io, "uso: egeon send <endereço> (texto no stdin)");
            };
            // Codificado: endereço com espaço no nome da bancada quebrava a
            // linha HTTP.
            post(
                io,
                sock,
                join(&[b"/message?target=", enc(target).as_bytes()]),
                Body::Stdin,
            )
        }
        b"peek" => {
            let Some(target) = arg(1) else {
                return usage_error(io, "uso: egeon peek <endereço> [linhas]");
            };
            let mut path = join(&[b"/peek?target=", enc(target).as_bytes()]);
            // As linhas vão sem escapar, como no script — e passam pelo mesmo
            // crivo de URL que o curl aplicava.
            if let Some(lines) = arg(2).filter(|l| !l.is_empty()) {
                let Some(lines) = curl_raw(lines) else {
                    return url_rejected(io);
                };
                path.extend_from_slice(b"&lines=");
                path.extend_from_slice(&lines);
            }
            get(io, sock, path)
        }
        b"trace" => {
            // Texto nos argumentos ou no stdin: uma linha cabe na chamada, e o
            // heredoc é para quando vem mais que isso.
            let body = if args.len() >= 2 {
                Body::Bytes(args[1..].join(&b' '))
            } else {
                Body::Stdin
            };
            post(io, sock, b"/trace".to_vec(), body)
        }
        b"status" => get(io, sock, b"/status".to_vec()),
        b"tasks" => get(io, sock, b"/tasks".to_vec()),
        b"task" => task(args, sock, io),
        b"ps" => ps(args, sock, io),
        b"bench" => get(io, sock, b"/maestro/bench".to_vec()),
        b"models" => get(io, sock, b"/maestro/models".to_vec()),
        b"plan" => post(io, sock, b"/maestro/apply?dry=1".to_vec(), Body::Stdin),
        b"apply" => post(io, sock, b"/maestro/apply".to_vec(), Body::Stdin),
        b"permissions" => get(io, sock, b"/maestro/asks".to_vec()),
        b"allow" | b"deny" => answer(args, sock, io),
        b"guide" => {
            let _ = io.out.write_all(GUIDE.as_bytes());
            0
        }
        _ => {
            let _ = io.out.write_all(USAGE.as_bytes());
            2
        }
    }
}

fn task(args: &[Vec<u8>], sock: &Path, io: &mut Streams) -> i32 {
    let (Some(action), Some(id)) = (args.get(1), args.get(2)) else {
        return usage_error(
            io,
            "uso: egeon task done|ask|note <id> [texto, ou no stdin]",
        );
    };
    let path = join(&[
        b"/task?action=",
        enc(action).as_bytes(),
        b"&id=",
        enc(id).as_bytes(),
    ]);
    if args.len() > 3 {
        post(io, sock, path, Body::Bytes(args[3..].join(&b' ')))
    } else if action == b"done" {
        // Marcar não pede texto: sem isto, ficaria esperando o stdin.
        post(io, sock, path, Body::Bytes(Vec::new()))
    } else {
        post(io, sock, path, Body::Stdin)
    }
}

fn ps(args: &[Vec<u8>], sock: &Path, io: &mut Streams) -> i32 {
    match args.get(1).map(Vec::as_slice) {
        Some(b"--orphans") => get(io, sock, b"/processes?orphans=1".to_vec()),
        Some(b"--kill") => {
            // Os pids vão sem escapar, separados por vírgula, e passam pelo
            // mesmo crivo de URL que o curl aplicava.
            let pids = args[2..].join(&b',');
            let mut path = b"/processes/kill".to_vec();
            if !pids.is_empty() {
                let Some(pids) = curl_raw(&pids) else {
                    return url_rejected(io);
                };
                path.extend_from_slice(b"?pid=");
                path.extend_from_slice(&pids);
            }
            post(io, sock, path, Body::Bytes(Vec::new()))
        }
        _ => get(io, sock, b"/processes".to_vec()),
    }
}

fn answer(args: &[Vec<u8>], sock: &Path, io: &mut Streams) -> i32 {
    let command = args.first().map(Vec::as_slice).unwrap_or_default();
    let Some(id) = args.get(1) else {
        let line = format!(
            "uso: egeon {} <id do pedido>",
            String::from_utf8_lossy(command)
        );
        return usage_error(io, &line);
    };
    let always = command == b"allow" && args.get(2).is_some_and(|a| a == b"--always");
    let answer: &[u8] = if always { b"always" } else { command };
    let path = join(&[
        b"/maestro/answer?id=",
        enc(id).as_bytes(),
        b"&answer=",
        answer,
    ]);
    post(io, sock, path, Body::Bytes(Vec::new()))
}

/// O que o curl fazia com o pedaço da URL que o script não escapava: confere a
/// URL inteira — recusa o que não cabe numa URL: espaço e controle (senão
/// `\r\n` injetaria cabeçalho), DEL, e `{ } [ ]`, que o curl toma por glob — e
/// só depois corta no `#`, porque fragmento não vai na requisição.
fn curl_raw(raw: &[u8]) -> Option<Vec<u8>> {
    let bad = |&b: &u8| b <= b' ' || b == 0x7f || matches!(b, b'{' | b'}' | b'[' | b']');
    if raw.iter().any(bad) {
        return None;
    }
    let end = raw.iter().position(|&b| b == b'#').unwrap_or(raw.len());
    Some(raw[..end].to_vec())
}

fn url_rejected(io: &mut Streams) -> i32 {
    let _ = writeln!(
        io.err,
        "curl: (3) URL rejected: Malformed input to a URL function"
    );
    3
}

fn join(parts: &[&[u8]]) -> Vec<u8> {
    parts.concat()
}

fn usage_error(io: &mut Streams, line: &str) -> i32 {
    let _ = writeln!(io.err, "{line}");
    2
}

fn get(io: &mut Streams, sock: &Path, target: Vec<u8>) -> i32 {
    call(io, sock, "GET", &target, None)
}

fn post(io: &mut Streams, sock: &Path, target: Vec<u8>, body: Body) -> i32 {
    let bytes = match body {
        Body::Bytes(bytes) => bytes,
        Body::Stdin => {
            let mut bytes = Vec::new();
            // Stdin ilegível vale como vazio: o app responde o que faltou.
            let _ = io.stdin.read_to_end(&mut bytes);
            bytes
        }
    };
    call(io, sock, "POST", &target, Some(&bytes))
}

/// `curl -sS --fail-with-body`: o corpo sai no stdout mesmo com erro HTTP, e o
/// código é o do curl (22 para status ≥ 400, 7 sem conexão). A mensagem de
/// erro mantém o texto do curl porque os agentes e as skills já a conhecem.
fn call(io: &mut Streams, sock: &Path, method: &str, target: &[u8], body: Option<&[u8]>) -> i32 {
    match http::request(sock, method, target, body, Limit::None) {
        Ok(response) => {
            let _ = io.out.write_all(&response.body);
            if response.status >= 400 {
                let _ = writeln!(
                    io.err,
                    "curl: (22) The requested URL returned error: {}",
                    response.status
                );
                22
            } else {
                0
            }
        }
        Err(e) => {
            let (code, message) = curl_error(&e);
            let _ = writeln!(io.err, "curl: ({code}) {message}");
            code
        }
    }
}

fn curl_error(error: &HttpError) -> (i32, String) {
    match error {
        HttpError::Connect(_) => (
            7,
            "Failed to connect to eg port 80 after 0 ms: Couldn't connect to server".into(),
        ),
        HttpError::EmptyReply => (52, "Empty reply from server".into()),
        HttpError::Malformed => (8, "Weird server reply".into()),
        HttpError::Timeout => (28, "Operation timed out".into()),
        HttpError::Io(e) => (56, format!("Recv failure: {e}")),
    }
}

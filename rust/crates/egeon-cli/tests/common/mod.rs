//! Servidor falso do socket de controle: grava o que chegou e responde o que o
//! teste mandar. Faz o papel do app sem depender do core.

// O clippy só perdoa `unwrap` dentro de `#[test]`; este módulo é de apoio e
// cada teste compartilha só o que usa.
#![allow(dead_code, clippy::unwrap_used, clippy::expect_used)]

use std::cell::Cell;
use std::io::{Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{Receiver, channel};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use egeon_cli::commands::{self, Streams};
use egeon_cli::hook::{self, Clock, Setup};

#[derive(Debug, Clone)]
pub struct Seen {
    pub method: String,
    pub target: String,
    pub head: String,
    pub body: Vec<u8>,
}

impl Seen {
    pub fn body_text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }
}

pub struct FakeServer {
    pub sock: PathBuf,
    seen: Receiver<Seen>,
    stop: Arc<AtomicBool>,
    handle: Option<JoinHandle<()>>,
    _dir: tempfile::TempDir,
}

impl FakeServer {
    /// `handler` devolve `(status, corpo)`; status 0 fecha sem responder.
    pub fn start(handler: impl Fn(&Seen) -> (u16, Vec<u8>) + Send + 'static) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let sock = dir.path().join("sock");
        let listener = UnixListener::bind(&sock).unwrap();
        listener.set_nonblocking(true).unwrap();
        let (tx, seen) = channel();
        let stop = Arc::new(AtomicBool::new(false));
        let flag = Arc::clone(&stop);
        let handle = std::thread::spawn(move || {
            while !flag.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => {
                        if let Some(request) = read_request(stream.try_clone().unwrap()) {
                            let (status, body) = handler(&request);
                            let _ = tx.send(request);
                            reply(stream, status, &body);
                        }
                    }
                    Err(_) => std::thread::sleep(Duration::from_millis(2)),
                }
            }
        });
        FakeServer {
            sock,
            seen,
            stop,
            handle: Some(handle),
            _dir: dir,
        }
    }

    /// Escreve `reply` cru, de uma vez, e fecha — como um servidor que
    /// responde e sai antes de o cliente ler.
    pub fn raw(reply: Vec<u8>) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let sock = dir.path().join("sock");
        let listener = UnixListener::bind(&sock).unwrap();
        listener.set_nonblocking(true).unwrap();
        let (tx, seen) = channel();
        let stop = Arc::new(AtomicBool::new(false));
        let flag = Arc::clone(&stop);
        let handle = std::thread::spawn(move || {
            while !flag.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((mut stream, _)) => {
                        if let Some(request) = read_request(stream.try_clone().unwrap()) {
                            let _ = tx.send(request);
                            let _ = stream.write_all(&reply);
                        }
                    }
                    Err(_) => std::thread::sleep(Duration::from_millis(2)),
                }
            }
        });
        FakeServer {
            sock,
            seen,
            stop,
            handle: Some(handle),
            _dir: dir,
        }
    }

    /// Responde sempre o mesmo corpo com 200.
    pub fn ok(body: &str) -> Self {
        let body = body.as_bytes().to_vec();
        Self::start(move |_| (200, body.clone()))
    }

    /// O que chegou desde a última chamada.
    pub fn seen(&self) -> Vec<Seen> {
        self.seen.try_iter().collect()
    }
}

impl Drop for FakeServer {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

fn read_request(mut stream: UnixStream) -> Option<Seen> {
    stream.set_nonblocking(false).ok()?;
    stream.set_read_timeout(Some(Duration::from_secs(5))).ok()?;
    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        if let Some(end) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            let head = String::from_utf8_lossy(&buf[..end]).into_owned();
            let length = head
                .lines()
                .find_map(|l| {
                    let (k, v) = l.split_once(':')?;
                    k.eq_ignore_ascii_case("content-length")
                        .then(|| v.trim().parse::<usize>().ok())?
                })
                .unwrap_or(0);
            if buf.len() >= end + 4 + length {
                let mut first = head.lines().next()?.split(' ');
                return Some(Seen {
                    method: first.next()?.to_owned(),
                    target: first.next()?.to_owned(),
                    head,
                    body: buf[end + 4..end + 4 + length].to_vec(),
                });
            }
        }
        match stream.read(&mut chunk) {
            Ok(0) | Err(_) => return None,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
        }
    }
}

fn reply(mut stream: UnixStream, status: u16, body: &[u8]) {
    if status == 0 {
        return;
    }
    let head = format!(
        "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = stream.write_all(head.as_bytes());
    let _ = stream.write_all(body);
}

pub struct Outcome {
    pub code: i32,
    pub out: Vec<u8>,
    pub err: String,
}

impl Outcome {
    pub fn out_text(&self) -> String {
        String::from_utf8_lossy(&self.out).into_owned()
    }
}

/// Roda `egeon <args>` contra o socket, com `stdin` dado.
pub fn egeon(server: &FakeServer, args: &[&str], stdin: &[u8]) -> Outcome {
    egeon_at(&server.sock, args, stdin)
}

pub fn egeon_at(sock: &std::path::Path, args: &[&str], stdin: &[u8]) -> Outcome {
    let args: Vec<Vec<u8>> = args.iter().map(|a| a.as_bytes().to_vec()).collect();
    let mut input = stdin;
    let (mut out, mut err) = (Vec::new(), Vec::new());
    let code = commands::run(
        &args,
        sock,
        &mut Streams {
            stdin: &mut input,
            out: &mut out,
            err: &mut err,
        },
    );
    Outcome {
        code,
        out,
        err: String::from_utf8_lossy(&err).into_owned(),
    }
}

/// Relógio que só anda quando o gancho dorme.
pub struct FakeClock {
    base: Instant,
    elapsed: Cell<Duration>,
}

impl FakeClock {
    pub fn new() -> Self {
        FakeClock {
            base: Instant::now(),
            elapsed: Cell::new(Duration::ZERO),
        }
    }
}

impl Clock for FakeClock {
    fn now(&self) -> Instant {
        self.base + self.elapsed.get()
    }

    fn sleep(&self, duration: Duration) {
        self.elapsed.set(self.elapsed.get() + duration);
    }
}

/// Roda `egeon hook <event>` e devolve o que saiu no stdout.
pub fn hook(
    sock: &std::path::Path,
    event: &str,
    payload: &str,
    in_egeon: bool,
    wait: Duration,
) -> String {
    let clock = FakeClock::new();
    let mut out = Vec::new();
    hook::run(
        event.as_bytes(),
        payload.as_bytes(),
        &Setup {
            sock,
            in_egeon,
            clock: &clock,
            permission_wait: wait,
        },
        &mut out,
    );
    String::from_utf8_lossy(&out).into_owned()
}

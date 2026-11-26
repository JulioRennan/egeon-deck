//! O core no Windows de ponta a ponta: sobe com `EGEON_HOME` temporário,
//! atende no socket AF_UNIX e encerra quando o stdin fecha (decisão 21), que é
//! como a UI o encerra — o Windows não tem SIGTERM.

#![cfg(windows)]
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use uds_windows::UnixStream;

/// Pasta curta de propósito: o caminho do socket tem de caber em 108 bytes.
struct TempHome(PathBuf);

impl TempHome {
    fn new(tag: &str) -> Self {
        let dir = std::env::temp_dir().join(format!("eg-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Self(dir)
    }
}

impl Drop for TempHome {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn http(sock: &Path, request: &str) -> String {
    let mut s = UnixStream::connect(sock).unwrap();
    s.write_all(request.as_bytes()).unwrap();
    let mut out = String::new();
    s.read_to_string(&mut out).unwrap();
    out.split_once("\r\n\r\n").unwrap().1.to_owned()
}

fn until(what: &str, mut check: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        if check() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    panic!("esperei demais: {what}");
}

fn launch(home: &TempHome) -> Child {
    Command::new(env!("CARGO_BIN_EXE_egeon-app"))
        .arg("--exit-with-stdin")
        .env("EGEON_HOME", &home.0)
        .env_remove("CLAUDE_CONFIG_DIR")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap()
}

/// O `Path::exists` segue o ponto de nova análise do socket e diz `false`
/// com o arquivo lá.
fn on_disk(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok()
}

#[test]
fn sobe_responde_targets_e_sai_quando_o_stdin_fecha() {
    let home = TempHome::new("win");
    let sock = home.0.join("sock");
    let mut app = launch(&home);
    until("o socket aparecer", || UnixStream::connect(&sock).is_ok());

    let targets = http(&sock, "GET /targets HTTP/1.1\r\nConnection: close\r\n\r\n");
    assert!(targets.contains("\"targets\":["), "veio {targets}");
    let about = http(&sock, "GET /about HTTP/1.1\r\nConnection: close\r\n\r\n");
    assert!(about.contains("\"ok\":true"), "veio {about}");

    drop(app.stdin.take());
    let mut status = None;
    until("o app sair", || {
        status = app.try_wait().unwrap();
        status.is_some()
    });
    assert!(status.is_some_and(|s| s.success()), "{status:?}");
    assert!(!on_disk(&sock), "o socket ficou para trás");
}

#[test]
fn opcao_desconhecida_e_recusada() {
    let out = Command::new(env!("CARGO_BIN_EXE_egeon-app"))
        .arg("--voar")
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2));
}

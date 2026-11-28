//! Encerrar um terminal mata a árvore inteira, como o
//! `ProcessScanner.terminateTree` do Swift: um trabalho em primeiro plano do
//! zsh interativo fica noutro grupo, e o HUP e o KILL no grupo do shell não o
//! alcançam.

#![cfg(unix)]
// Os ajudantes daqui são código de teste, mas não são `#[test]`: o clippy não
// os reconhece pelo `allow-*-in-tests`.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

/// Pasta curta de propósito: o caminho do socket tem de caber em 104 bytes.
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
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if check() {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("esperei demais: {what}");
}

fn alive(pid: u32) -> bool {
    Command::new("ps")
        .args(["-p", &pid.to_string()])
        .stdout(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

/// Mata com KILL o que o teste subiu, também quando ele falha no meio: o
/// trabalho teimoso ignora HUP e TERM, e sem isto sobreviveria à rodada. Só
/// mata quem ainda roda o comando esperado — o pid de quem já saiu pode ser
/// de outro processo.
#[derive(Default)]
struct Reaper(Vec<(u32, String)>);

impl Reaper {
    fn watch(&mut self, pid: u32, command: impl Into<String>) {
        self.0.push((pid, command.into()));
    }
}

impl Drop for Reaper {
    fn drop(&mut self) {
        for (pid, command) in &self.0 {
            let running = Command::new("ps")
                .args(["-o", "command=", "-p", &pid.to_string()])
                .output()
                .is_ok_and(|out| String::from_utf8_lossy(&out.stdout).contains(command.as_str()));
            if running {
                let _ = Command::new("kill")
                    .args(["-KILL", &pid.to_string()])
                    .status();
            }
        }
    }
}

fn launch(home: &TempHome) -> Child {
    Command::new(env!("CARGO_BIN_EXE_egeon-app"))
        .env("EGEON_HOME", &home.0)
        // Sem herdar a config do Claude do shell que roda o teste: o app
        // isolado não tem por que escrever nela.
        .env_remove("CLAUDE_CONFIG_DIR")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .unwrap()
}

/// Um zsh interativo com um trabalho em primeiro plano que ignora HUP e TERM:
/// só o SIGKILL do segundo passo o leva. Devolve o pid do `sleep`.
fn stubborn_foreground_job(sock: &Path, seconds: u32) -> u32 {
    http(sock, "POST /terminal HTTP/1.1\r\nContent-Length: 0\r\n\r\n");
    // O `; true` impede o `exec` do sleep: ele fica filho do zsh -c, com os
    // sinais ignorados herdados.
    let input = format!("zsh -c \"trap '' HUP TERM; sleep {seconds}; true\"\n");
    http(
        sock,
        &format!(
            "POST /terminal/t1/input HTTP/1.1\r\nContent-Length: {}\r\n\r\n{input}",
            input.len()
        ),
    );
    let mut pid = 0;
    until("o sleep subir", || {
        let out = Command::new("pgrep")
            .args(["-f", &format!("^sleep {seconds}$")])
            .output()
            .unwrap();
        pid = String::from_utf8_lossy(&out.stdout)
            .trim()
            .parse()
            .unwrap_or(0);
        pid != 0
    });
    pid
}

/// Número de segundos que só este teste usa, para o `pgrep` não achar o de
/// outro.
fn unique_seconds(offset: u32) -> u32 {
    200_000 + (std::process::id() % 100_000) * 2 + offset
}

#[test]
fn remover_o_no_mata_o_trabalho_que_ignora_hup_e_term() {
    let home = TempHome::new("tree");
    let sock = home.0.join("sock");
    let mut app = launch(&home);
    let mut reaper = Reaper::default();
    reaper.watch(app.id(), "egeon-app");
    until("o socket aparecer", || UnixStream::connect(&sock).is_ok());
    let stubborn = stubborn_foreground_job(&sock, unique_seconds(0));
    reaper.watch(stubborn, format!("sleep {}", unique_seconds(0)));

    let mut ui = UnixStream::connect(&sock).unwrap();
    ui.write_all(b"GET /ui HTTP/1.1\r\nUpgrade: egeon-ndjson\r\n\r\n")
        .unwrap();
    ui.write_all(b"{\"id\":1,\"cmd\":\"close_terminal\",\"node\":\"t1\"}\n")
        .unwrap();
    let mut reader = BufReader::new(ui.try_clone().unwrap());
    let mut line = String::new();
    loop {
        line.clear();
        assert_ne!(reader.read_line(&mut line).unwrap(), 0, "o canal fechou");
        if line.contains("\"re\":1") {
            break;
        }
    }
    assert!(line.contains("\"ok\":true"), "{line}");

    until("o trabalho teimoso morrer", || !alive(stubborn));
    let _ = Command::new("kill")
        .args(["-TERM", &app.id().to_string()])
        .status();
    until("o app sair", || app.try_wait().unwrap().is_some());
}

#[test]
fn encerrar_o_app_mata_o_trabalho_que_ignora_hup_e_term() {
    let home = TempHome::new("treequit");
    let sock = home.0.join("sock");
    let mut app = launch(&home);
    let mut reaper = Reaper::default();
    reaper.watch(app.id(), "egeon-app");
    until("o socket aparecer", || UnixStream::connect(&sock).is_ok());
    let stubborn = stubborn_foreground_job(&sock, unique_seconds(1));
    reaper.watch(stubborn, format!("sleep {}", unique_seconds(1)));

    Command::new("kill")
        .args(["-TERM", &app.id().to_string()])
        .status()
        .unwrap();
    let mut status = None;
    until("o app sair", || {
        status = app.try_wait().unwrap();
        status.is_some()
    });
    assert!(status.is_some_and(|s| s.success()), "{status:?}");
    until("o trabalho teimoso morrer", || !alive(stubborn));
}

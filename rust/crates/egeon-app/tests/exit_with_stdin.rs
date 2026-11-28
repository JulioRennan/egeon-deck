//! O core lançado pela UI morre com ela (decisão 21): fechar o stdin do
//! `egeon-app --exit-with-stdin` encerra o app, o shell do terminal e o que
//! ele abriu.

#![cfg(unix)]
// Os ajudantes daqui são código de teste, mas não são `#[test]`: o clippy não
// os reconhece pelo `allow-*-in-tests`.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use std::io::{Read, Write};
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

/// O pid do `sleep` filho de `shell`, esperando ele subir.
fn sleep_under(shell: u32) -> u32 {
    let mut pid = 0;
    until("o sleep do terminal subir", || {
        let out = Command::new("pgrep")
            .args(["-P", &shell.to_string(), "sleep"])
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

fn launch(home: &TempHome, exit_with_stdin: bool) -> Child {
    launch_with(home, exit_with_stdin, Stdio::null(), Stdio::null())
}

fn launch_with(home: &TempHome, exit_with_stdin: bool, stdout: Stdio, stderr: Stdio) -> Child {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_egeon-app"));
    if exit_with_stdin {
        cmd.arg("--exit-with-stdin");
    }
    cmd.env("EGEON_HOME", &home.0)
        // Sem herdar a config do Claude do shell que roda o teste: o app
        // isolado não tem por que escrever nela.
        .env_remove("CLAUDE_CONFIG_DIR")
        .stdin(Stdio::piped())
        .stdout(stdout)
        .stderr(stderr)
        .spawn()
        .unwrap()
}

fn pid_in(body: &str) -> u32 {
    body.split("\"pid\":")
        .nth(1)
        .and_then(|rest| rest.split(|c: char| !c.is_ascii_digit()).next())
        .and_then(|n| n.parse().ok())
        .unwrap_or_else(|| panic!("sem pid em {body}"))
}

/// Abre um terminal com um `sleep` em segundo plano e devolve os pids do
/// shell e do neto.
fn terminal_with_grandchild(sock: &Path) -> (u32, u32) {
    let shell = pid_in(&http(
        sock,
        "POST /terminal HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
    ));
    let input = "sleep 1000 &\n";
    http(
        sock,
        &format!(
            "POST /terminal/t1/input HTTP/1.1\r\nContent-Length: {}\r\n\r\n{input}",
            input.len()
        ),
    );
    (shell, sleep_under(shell))
}

#[test]
fn fechar_o_stdin_encerra_o_app_e_os_terminais() {
    let home = TempHome::new("stdin");
    let sock = home.0.join("sock");
    let mut app = launch(&home, true);
    until("o socket aparecer", || UnixStream::connect(&sock).is_ok());
    let (shell, grandchild) = terminal_with_grandchild(&sock);

    // Fechar o cano é o que acontece quando a UI sai, até no `kill -9`.
    drop(app.stdin.take());

    let mut status = None;
    until("o app sair", || {
        status = app.try_wait().unwrap();
        status.is_some()
    });
    assert!(status.is_some_and(|s| s.success()), "{status:?}");
    until("o shell e o neto morrerem", || {
        !alive(shell) && !alive(grandchild)
    });
    assert!(!sock.exists(), "o socket ficou para trás");
}

#[test]
fn sem_a_opcao_o_stdin_fechado_nao_encerra() {
    let home = TempHome::new("nostdin");
    let sock = home.0.join("sock");
    let mut app = launch(&home, false);
    until("o socket aparecer", || UnixStream::connect(&sock).is_ok());
    drop(app.stdin.take());
    std::thread::sleep(Duration::from_millis(500));
    assert!(app.try_wait().unwrap().is_none(), "saiu sem a opção");
    assert!(http(&sock, "GET /about HTTP/1.1\r\n\r\n").contains("\"ok\":true"));
    // Encerra por sinal, que é o caminho sem a opção.
    Command::new("kill")
        .args(["-TERM", &app.id().to_string()])
        .status()
        .unwrap();
    until("o app sair", || app.try_wait().unwrap().is_some());
}

#[test]
fn opcao_desconhecida_e_recusada() {
    let out = Command::new(env!("CARGO_BIN_EXE_egeon-app"))
        .arg("--voar")
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("--exit-with-stdin"));
}

/// O `kill -9` da UI de verdade: stdin, stdout e stderr são canos dela, e
/// fecham juntos. O log do core não pode entrar em pânico com o stderr
/// quebrado, senão o encerramento ordenado não roda e o que ignora HUP fica.
#[test]
fn canos_todos_fechados_juntos_encerram_ate_quem_ignora_hup() {
    let home = TempHome::new("pipes");
    let sock = home.0.join("sock");
    let mut app = launch_with(&home, true, Stdio::piped(), Stdio::piped());
    until("o socket aparecer", || UnixStream::connect(&sock).is_ok());

    // O `; true` impede o zsh de dar `exec` no sleep: ele fica filho do shell,
    // com o HUP ignorado herdado.
    let body = r#"{"command":"trap '' HUP; sleep 302; true"}"#;
    let created = http(
        &sock,
        &format!(
            "POST /terminal HTTP/1.1\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        ),
    );
    let shell = pid_in(&created);
    let stubborn = sleep_under(shell);

    drop(app.stdin.take());
    drop(app.stdout.take());
    drop(app.stderr.take());

    let mut status = None;
    until("o app sair", || {
        status = app.try_wait().unwrap();
        status.is_some()
    });
    assert!(
        status.is_some_and(|s| s.success()),
        "saiu com {status:?}: o log entrou em pânico?"
    );
    until("o sleep que ignora HUP morrer", || !alive(stubborn));
    assert!(!alive(shell));
    assert!(!sock.exists(), "o socket ficou para trás");
}

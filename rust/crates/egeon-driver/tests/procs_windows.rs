//! Processos de verdade no Windows: um PowerShell num ConPTY, com filhos
//! reais. Nada aqui toca `~/.egeon`. O par do `procs.rs` do unix.

#![cfg(windows)]
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use egeon_core::features::processes::tree::terminate_tree;
use egeon_core::ports::local_conn::LocalConnDriver;
use egeon_core::ports::procs::{
    ProcessDetail, ProcessDriver, ProcessError, ProcessSignal, RawProcess, descendants,
};
use egeon_core::ports::pty::{PtyDriver, PtySession, PtySignal, PtySize, PtySpec};
use egeon_driver::{SystemLocalConn, SystemProcs, SystemPty};

const LIMIT: Duration = Duration::from_secs(30);
/// O mesmo prazo do resto: prazo maior esconderia travamento.
const SHELL_LIMIT: Duration = LIMIT;

fn system_root() -> PathBuf {
    std::env::var_os("SystemRoot").map_or_else(|| PathBuf::from(r"C:\Windows"), PathBuf::from)
}

/// O shell de um terminal: o PowerShell, como o nó do Egeon o abre no Windows.
struct Shell {
    session: Box<dyn PtySession>,
}

fn start_shell(script: &str) -> Result<Shell, String> {
    let root = system_root().display().to_string();
    let child = SystemPty
        .spawn(PtySpec {
            program: egeon_driver::environment::user_shell(),
            args: vec![
                "-NoLogo".into(),
                "-NoProfile".into(),
                "-Command".into(),
                script.into(),
            ],
            env: vec![
                ("SystemRoot".into(), root.clone()),
                ("PATH".into(), format!(r"{root}\System32;{root}")),
            ],
            cwd: None,
            size: PtySize { cols: 80, rows: 24 },
        })
        .map_err(|e| e.to_string())?;
    // O cano enche se ninguém lê, e o filho trava na escrita.
    let mut events = child.events;
    thread::spawn(move || while events.blocking_recv().is_some() {});
    Ok(Shell {
        session: child.session,
    })
}

impl Shell {
    /// Espera a árvore do shell ter `count` processos de nome `name` (sem
    /// caixa: o `ping` do System32 é `PING.EXE`).
    fn wait_for(&self, name: &str, count: usize) -> Result<Vec<RawProcess>, String> {
        let begun = Instant::now();
        let deadline = begun + SHELL_LIMIT;
        let mut failure = None;
        loop {
            // A tabela que falha uma vez não encerra a espera, mas o erro sai
            // no fim: é como se sabe se foi o retrato ou o usuário do token.
            let all = SystemProcs.list(ProcessDetail::Tree).unwrap_or_else(|e| {
                failure = Some(e.to_string());
                Vec::new()
            });
            let tree = descendants(self.session.pid(), &all);
            if tree
                .iter()
                .filter(|p| p.name.eq_ignore_ascii_case(name))
                .count()
                >= count
            {
                return Ok(tree);
            }
            if Instant::now() > deadline {
                return Err(format!(
                    "esperava {count} {name} (após {:.1?}); árvore: {tree:?}; último erro da \
                     tabela: {failure:?}",
                    begun.elapsed()
                ));
            }
            thread::sleep(Duration::from_millis(100));
        }
    }
}

impl Drop for Shell {
    fn drop(&mut self) {
        let _ = self.session.signal(PtySignal::Kill);
    }
}

fn alive(pid: u32) -> bool {
    SystemProcs
        .list(ProcessDetail::Tree)
        .map(|all| all.iter().any(|p| p.pid == pid))
        .unwrap_or(false)
}

fn wait_dead(tree: &[RawProcess], within: Duration) -> Result<(), String> {
    let deadline = Instant::now() + within;
    loop {
        let survivors: Vec<&RawProcess> = tree.iter().filter(|p| alive(p.pid)).collect();
        if survivors.is_empty() {
            return Ok(());
        }
        if Instant::now() > deadline {
            return Err(format!("sobreviveram: {survivors:?}"));
        }
        thread::sleep(Duration::from_millis(100));
    }
}

/// O `TerminateProcess` não se ignora: a política do core (SIGTERM, prazo,
/// SIGKILL) encerra a árvore já no primeiro passo.
#[test]
fn encerrar_o_terminal_mata_a_arvore() -> Result<(), String> {
    let shell = start_shell(
        "foreach ($n in 300, 301) { \
           $i = [Diagnostics.ProcessStartInfo]::new('ping.exe', \"-n $n 127.0.0.1\"); \
           $i.UseShellExecute = $false; $null = [Diagnostics.Process]::Start($i) }; \
         [Threading.Thread]::Sleep(300000)",
    )?;
    let tree = shell.wait_for("ping", 2)?;

    let hit = terminate_tree(
        Arc::new(SystemProcs),
        shell.session.pid(),
        Duration::from_secs(600),
        "teste",
    );
    assert!(hit.len() >= 2, "dois ping na árvore, veio {hit:?}");
    wait_dead(&tree, Duration::from_secs(10))
}

#[test]
fn le_pai_ambiente_e_linha_de_comando() -> Result<(), String> {
    let me = std::env::current_exe().map_err(|e| e.to_string())?;
    let mut child = Command::new(me)
        .args(["--exact", "filho_dorminhoco", "--nocapture"])
        .env("EGEON_SONECA", "1")
        .env("EGEON_NODE", "bancada/teste")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    let pid = child.id();

    assert_eq!(SystemProcs.parent_of(pid), Some(std::process::id()));
    let deadline = Instant::now() + LIMIT;
    let env = loop {
        let env = SystemProcs.environment_of(pid).unwrap_or_default();
        if env.contains_key("EGEON_NODE") || Instant::now() > deadline {
            break env;
        }
        thread::sleep(Duration::from_millis(20));
    };
    assert_eq!(
        env.get("EGEON_NODE").map(String::as_str),
        Some("bancada/teste")
    );
    let all = SystemProcs
        .list(ProcessDetail::Full)
        .map_err(|e| e.to_string())?;
    let found = all.iter().find(|p| p.pid == pid).ok_or("fora da lista")?;
    assert!(
        found
            .command
            .ends_with("--exact filho_dorminhoco --nocapture"),
        "linha: {}",
        found.command
    );
    assert!(
        found.name.starts_with("procs_windows-"),
        "nome: {}",
        found.name
    );
    assert!(!found.name.ends_with(".exe"));
    assert_eq!(
        found.environment.get("EGEON_NODE").map(String::as_str),
        Some("bancada/teste")
    );

    let light = SystemProcs
        .list(ProcessDetail::Tree)
        .map_err(|e| e.to_string())?;
    let found = light.iter().find(|p| p.pid == pid).ok_or("fora da lista")?;
    assert_eq!(found.command, found.name);
    assert!(found.environment.is_empty());

    let _ = child.kill();
    let _ = child.wait();
    Ok(())
}

#[test]
fn sinal_para_processo_que_acabou_e_gone() -> Result<(), String> {
    let mut child = Command::new(system_root().join("System32").join("cmd.exe"))
        .args(["/d", "/c", "exit"])
        .spawn()
        .map_err(|e| e.to_string())?;
    let pid = child.id();
    child.wait().map_err(|e| e.to_string())?;
    // O `Child` ainda segura o handle: o pid só é solto depois de largá-lo.
    drop(child);
    assert!(matches!(
        SystemProcs.signal(pid, ProcessSignal::Terminate),
        Err(ProcessError::Gone(p)) if p == pid
    ));
    // O pid some do retrato com prazo: um terceiro (o antivírus) pode segurar
    // o processo acabado por um instante, e o Windows reaproveita o pid logo
    // (a ci/win-15 o viu ainda na tabela). Reaproveitado, o dono é outro pai.
    let me = std::process::id();
    let deadline = Instant::now() + LIMIT;
    while SystemProcs.parent_of(pid) == Some(me) {
        assert!(
            Instant::now() < deadline,
            "o {pid} seguiu na tabela como nosso filho"
        );
        thread::sleep(Duration::from_millis(100));
    }
    Ok(())
}

#[test]
fn pids_do_sistema_sao_recusados() {
    for pid in [0, 4] {
        assert!(matches!(
            SystemProcs.signal(pid, ProcessSignal::Kill),
            Err(ProcessError::Signal { .. })
        ));
    }
}

/// Não é um teste: é o filho de `le_pai_ambiente_e_linha_de_comando`.
#[test]
fn filho_dorminhoco() {
    if std::env::var_os("EGEON_SONECA").is_some() {
        thread::sleep(Duration::from_secs(60));
    }
}

/// A identidade de quem chama: o `curl.exe` do Windows (que fala AF_UNIX)
/// roda dentro do PowerShell do terminal, o socket diz o pid dele, e subindo
/// de pai em pai chega-se ao shell.
#[tokio::test(flavor = "multi_thread")]
async fn pid_do_par_sobe_a_arvore_ate_o_shell_do_terminal() -> Result<(), String> {
    let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
    let path = dir.path().join("sock");
    let listener = SystemLocalConn.listen(&path).map_err(|e| e.to_string())?;
    let curl = system_root().join("System32").join("curl.exe");
    let shell = start_shell(&format!(
        "& '{}' -s --max-time 20 --unix-socket '{}' http://eg/targets; [Threading.Thread]::Sleep(300000)",
        curl.display(),
        path.display()
    ))?;

    let conn = tokio::time::timeout(LIMIT, listener.accept())
        .await
        .map_err(|_| "ninguém conectou".to_string())?
        .map_err(|e| e.to_string())?;
    let mut current = conn.peer_pid.ok_or("sem pid do par")?;
    assert_ne!(current, shell.session.pid());
    let mut hops = 0;
    while current != shell.session.pid() {
        current = SystemProcs
            .parent_of(current)
            .ok_or("a cadeia acabou antes do shell")?;
        hops += 1;
        assert!(hops <= 32, "cadeia longa demais");
    }
    Ok(())
}

//! Processos de verdade: um zsh interativo num pty, com filhos reais. Nada
//! aqui toca `~/.egeon`.

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
use egeon_core::ports::pty::{PtyDriver, PtySession, PtySize, PtySpec};
use egeon_driver::{SystemLocalConn, SystemProcs, SystemPty};

const LIMIT: Duration = Duration::from_secs(10);

/// O shell de um terminal: zsh interativo, como o nó do Egeon o abre.
struct Shell {
    session: Box<dyn PtySession>,
    home: tempfile::TempDir,
}

fn start_shell() -> Result<Shell, String> {
    let home = tempfile::tempdir().map_err(|e| e.to_string())?;
    let child = SystemPty
        .spawn(PtySpec {
            program: PathBuf::from("/bin/zsh"),
            args: vec!["-f".into(), "-i".into()],
            env: vec![
                ("PATH".into(), "/usr/bin:/bin".into()),
                ("TERM".into(), "xterm-256color".into()),
                ("HOME".into(), home.path().display().to_string()),
            ],
            cwd: None,
            size: PtySize { cols: 80, rows: 24 },
        })
        .map_err(|e| e.to_string())?;
    // O pty enche se ninguém lê: o shell trava no `write` e o teste não passa
    // do primeiro comando.
    let mut events = child.events;
    thread::spawn(move || while events.blocking_recv().is_some() {});
    Ok(Shell {
        session: child.session,
        home,
    })
}

impl Shell {
    fn type_line(&self, line: &str) -> Result<(), String> {
        self.session
            .write(format!("{line}\n").as_bytes())
            .map_err(|e| e.to_string())
    }

    /// Espera a árvore do shell ter `count` processos de nome `name`.
    fn wait_for(&self, name: &str, count: usize) -> Result<Vec<RawProcess>, String> {
        let deadline = Instant::now() + LIMIT;
        loop {
            let all = SystemProcs
                .list(ProcessDetail::Tree)
                .map_err(|e| e.to_string())?;
            let tree = descendants(self.session.pid(), &all);
            if tree.iter().filter(|p| p.name == name).count() >= count {
                return Ok(tree);
            }
            if Instant::now() > deadline {
                return Err(format!("esperava {count} {name}; árvore: {tree:?}"));
            }
            thread::sleep(Duration::from_millis(50));
        }
    }
}

impl Drop for Shell {
    fn drop(&mut self) {
        let _ = self.session.signal(egeon_core::ports::pty::PtySignal::Kill);
        let _ = &self.home;
    }
}

/// A política de matar a árvore é do core; aqui roda sobre processos de verdade.
fn terminate(root: u32, grace: Duration) -> Vec<RawProcess> {
    terminate_tree(Arc::new(SystemProcs), root, grace, "teste")
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
        thread::sleep(Duration::from_millis(50));
    }
}

#[test]
fn encerrar_o_terminal_mata_o_job_que_ignora_hup_e_o_de_outro_grupo() -> Result<(), String> {
    let shell = start_shell()?;
    // O de fundo vai para um grupo próprio (shell interativo); o da frente
    // ignora o HUP que o shell mandaria ao sair.
    shell.type_line("sleep 3012 & sh -c \"trap '' HUP; sleep 3011\"")?;
    let tree = shell.wait_for("sleep", 2)?;

    // `grace` enorme: se tudo morrer logo, foi o SIGTERM, não o SIGKILL.
    let hit = terminate(shell.session.pid(), Duration::from_secs(600));
    assert!(hit.len() >= 3, "sh e dois sleep na árvore, veio {hit:?}");
    wait_dead(&tree, Duration::from_secs(5))
}

#[test]
fn quem_ignora_o_sigterm_leva_sigkill_depois_do_prazo() -> Result<(), String> {
    let shell = start_shell()?;
    shell.type_line("sh -c \"trap '' HUP TERM; sleep 3021\"")?;
    let tree = shell.wait_for("sleep", 1)?;

    let hit = terminate(shell.session.pid(), Duration::from_secs(3));
    assert!(!hit.is_empty());
    thread::sleep(Duration::from_millis(500));
    assert!(
        tree.iter().any(|p| alive(p.pid)),
        "o SIGTERM sozinho não devia ter bastado"
    );
    wait_dead(&tree, Duration::from_secs(10))
}

#[test]
fn arvore_vazia_nao_faz_nada() {
    let shell = match start_shell() {
        Ok(shell) => shell,
        Err(e) => panic!("{e}"),
    };
    assert!(terminate(shell.session.pid(), Duration::ZERO).is_empty());
    assert!(alive(shell.session.pid()));
}

#[test]
fn le_pai_ambiente_e_linha_de_comando() -> Result<(), String> {
    // O kernel não entrega o ambiente de binário da Apple (`/bin/sleep`): o
    // filho é o próprio executável de teste, que dorme quando manda o ambiente.
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
    // Entre o fork e o exec o filho ainda tem o ambiente do pai.
    let deadline = Instant::now() + LIMIT;
    let env = loop {
        let env = SystemProcs.environment_of(pid).ok_or("sem ambiente")?;
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
            .ends_with("--exact filho_dorminhoco --nocapture")
    );
    assert!(found.name.starts_with("procs-"));
    assert_eq!(
        found.environment.get("EGEON_NODE").map(String::as_str),
        Some("bancada/teste")
    );

    // O modo barato não lê linha de comando nem ambiente.
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
    let mut child = Command::new("/usr/bin/true")
        .spawn()
        .map_err(|e| e.to_string())?;
    let pid = child.id();
    child.wait().map_err(|e| e.to_string())?;
    assert!(matches!(
        SystemProcs.signal(pid, ProcessSignal::Terminate),
        Err(ProcessError::Gone(p)) if p == pid
    ));
    assert_eq!(SystemProcs.parent_of(pid), None);
    Ok(())
}

#[test]
fn pids_que_atingiriam_grupo_ou_sistema_sao_recusados() {
    for pid in [0, 1, u32::MAX] {
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

/// A identidade de quem chama: o `nc` roda dentro do zsh do terminal, o socket
/// diz o pid dele, e subindo de pai em pai chega-se ao shell.
#[tokio::test(flavor = "multi_thread")]
async fn pid_do_par_sobe_a_arvore_ate_o_shell_do_terminal() -> Result<(), String> {
    let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
    let path = dir.path().join("sock");
    let listener = SystemLocalConn.listen(&path).map_err(|e| e.to_string())?;
    let shell = start_shell()?;
    shell.type_line(&format!("nc -U '{}'", path.display()))?;

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

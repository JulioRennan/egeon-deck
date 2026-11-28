//! Encerrar a árvore de processos de um nó — porte do
//! `ProcessScanner.terminateTree` do Swift.
//!
//! O `killpg` no shell do nó não basta: o Bash dos agentes põe cada comando num
//! grupo próprio, e o servidor que um agente subiu sobrevivia ao nó, órfão, por
//! dias. A árvore é lida AGORA, enquanto ainda existe — depois que o shell
//! morre, os filhos já são do `init`. O driver só lê a tabela e manda sinal
//! (`ports::procs`); o que fazer com eles é daqui.

use std::collections::HashMap;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, SystemTime};

use crate::log;
use crate::ports::procs::{ProcessDetail, ProcessDriver, ProcessSignal, RawProcess, descendants};

/// Encerra tudo o que descende de `root` (sem ele), de qualquer grupo: SIGTERM
/// agora e devolve a árvore atingida. Quem ignorar o SIGTERM leva SIGKILL depois
/// de `grace`, se ainda for o mesmo processo (pid e início): pid reaproveitado
/// não paga pelo antigo. Com `grace` zero não há SIGKILL aqui — quem chama o faz
/// com [`kill_stubborn`] quando quiser. Bloqueia (lê a tabela): chamar de
/// `spawn_blocking`.
pub fn terminate_tree(
    driver: Arc<dyn ProcessDriver>,
    root: u32,
    grace: Duration,
    reason: &str,
) -> Vec<RawProcess> {
    let Ok(all) = driver.list(ProcessDetail::Tree) else {
        return Vec::new();
    };
    let tree = descendants(root, &all);
    if tree.is_empty() {
        return tree;
    }
    for process in &tree {
        let _ = driver.signal(process.pid, ProcessSignal::Terminate);
    }
    log!(
        "processos: {reason} — SIGTERM em {} descendente(s) do pid {root}",
        tree.len()
    );
    if grace.is_zero() {
        return tree;
    }
    let victims = tree.clone();
    let reason = reason.to_string();
    // Numa thread, e não numa tarefa: o chamador não espera o `grace`, e o
    // SIGKILL não pode depender de um runtime que talvez já esteja fechando.
    let _ = thread::Builder::new()
        .name("processos-kill".into())
        .spawn(move || {
            thread::sleep(grace);
            kill_stubborn(&*driver, &victims, &reason);
        });
    tree
}

/// SIGKILL em quem de `victims` ainda é o mesmo processo (pid e início).
pub fn kill_stubborn(driver: &dyn ProcessDriver, victims: &[RawProcess], reason: &str) {
    let Ok(now) = driver.list(ProcessDetail::Tree) else {
        return;
    };
    let stubborn = still_alive(victims, &now);
    if stubborn.is_empty() {
        return;
    }
    for process in &stubborn {
        let _ = driver.signal(process.pid, ProcessSignal::Kill);
    }
    log!(
        "processos: {reason} — SIGKILL em {} que ignoraram o SIGTERM",
        stubborn.len()
    );
}

/// Dos `victims`, os que a tabela de agora ainda tem com o mesmo pid e o mesmo
/// início: pid reaproveitado por outro processo tem outro início.
fn still_alive<'a>(victims: &'a [RawProcess], now: &[RawProcess]) -> Vec<&'a RawProcess> {
    let alive: HashMap<u32, SystemTime> = now.iter().map(|p| (p.pid, p.started)).collect();
    victims
        .iter()
        .filter(|p| alive.get(&p.pid) == Some(&p.started))
        .collect()
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;
    use std::time::Duration;

    use super::*;
    use crate::ports::procs::{ProcessError, RawProcess};

    fn process(pid: u32, ppid: u32, started: u64) -> RawProcess {
        RawProcess {
            pid,
            ppid,
            started: SystemTime::UNIX_EPOCH + Duration::from_secs(started),
            name: "p".into(),
            command: "p".into(),
            environment: HashMap::new(),
        }
    }

    /// Uma tabela fixa e o registro dos sinais mandados.
    struct Table {
        rows: Vec<RawProcess>,
        signals: Mutex<Vec<(u32, ProcessSignal)>>,
    }

    impl Table {
        fn new(rows: Vec<RawProcess>) -> Self {
            Self {
                rows,
                signals: Mutex::new(Vec::new()),
            }
        }

        fn sent(&self) -> Vec<(u32, ProcessSignal)> {
            self.signals.lock().map(|s| s.clone()).unwrap_or_default()
        }
    }

    impl ProcessDriver for Table {
        fn list(&self, _: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError> {
            Ok(self.rows.clone())
        }

        fn environment_of(&self, _: u32) -> Option<HashMap<String, String>> {
            None
        }

        fn parent_of(&self, _: u32) -> Option<u32> {
            None
        }

        fn signal(&self, pid: u32, signal: ProcessSignal) -> Result<(), ProcessError> {
            if let Ok(mut sent) = self.signals.lock() {
                sent.push((pid, signal));
            }
            Ok(())
        }
    }

    fn tree() -> Vec<RawProcess> {
        vec![
            process(1, 0, 1),
            process(10, 1, 5),
            process(11, 10, 6),
            process(12, 11, 7),
            process(20, 1, 8),
        ]
    }

    #[test]
    fn sigterm_em_todos_os_descendentes_e_so_neles() {
        let table = Arc::new(Table::new(tree()));
        let hit = terminate_tree(table.clone(), 10, Duration::ZERO, "teste");
        let mut pids: Vec<u32> = hit.iter().map(|p| p.pid).collect();
        pids.sort_unstable();
        assert_eq!(pids, [11, 12]);
        let mut sent = table.sent();
        sent.sort_by_key(|(pid, _)| *pid);
        assert_eq!(
            sent,
            [
                (11, ProcessSignal::Terminate),
                (12, ProcessSignal::Terminate)
            ]
        );
    }

    #[test]
    fn sem_descendentes_nada_e_enviado() {
        let table = Arc::new(Table::new(tree()));
        assert!(terminate_tree(table.clone(), 12, Duration::ZERO, "teste").is_empty());
        assert!(table.sent().is_empty());
    }

    #[test]
    fn sigkill_so_em_quem_continua_o_mesmo_processo() {
        let victims = [process(11, 10, 6), process(12, 11, 7), process(13, 11, 9)];
        // 11 segue igual; 12 morreu (some); 13 tem outro início: pid reaproveitado.
        let now = vec![process(11, 10, 6), process(13, 1, 99)];
        let table = Table::new(now);
        kill_stubborn(&table, &victims, "teste");
        assert_eq!(table.sent(), [(11, ProcessSignal::Kill)]);
    }

    #[test]
    fn leitura_que_falha_nao_mata_ninguem() {
        struct Broken;
        impl ProcessDriver for Broken {
            fn list(&self, _: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError> {
                Err(ProcessError::Gone(0))
            }
            fn environment_of(&self, _: u32) -> Option<HashMap<String, String>> {
                None
            }
            fn parent_of(&self, _: u32) -> Option<u32> {
                None
            }
            fn signal(&self, pid: u32, _: ProcessSignal) -> Result<(), ProcessError> {
                Err(ProcessError::Gone(pid))
            }
        }
        assert!(terminate_tree(Arc::new(Broken), 10, Duration::ZERO, "teste").is_empty());
        kill_stubborn(&Broken, &[process(11, 10, 6)], "teste");
    }
}

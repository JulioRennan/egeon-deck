//! Lê os processos do usuário pelo driver e diz quais são do Egeon (ADR-083),
//! e encerra o que a leitura de agora confirma ser dele.

use std::collections::HashSet;

use super::model::{EgeonProcess, classify};
use crate::ports::procs::{ProcessDetail, ProcessDriver, ProcessSignal, RawProcess};

/// Quem somos, para a leitura saber o que é nosso: o pid do app e o rótulo do
/// flavor (`EGEON_DECK`).
#[derive(Debug, Clone)]
pub struct ScanContext {
    pub app_pid: u32,
    pub deck: String,
}

pub struct ProcessScanner<'a> {
    driver: &'a dyn ProcessDriver,
    context: &'a ScanContext,
}

impl<'a> ProcessScanner<'a> {
    pub fn new(driver: &'a dyn ProcessDriver, context: &'a ScanContext) -> Self {
        ProcessScanner { driver, context }
    }

    /// Bloqueia: chamar fora do ator. Tabela ilegível é lista vazia, como no
    /// Swift.
    pub fn scan(&self) -> Vec<EgeonProcess> {
        let all = self.driver.list(ProcessDetail::Full).unwrap_or_default();
        classify(&all, self.context.app_pid, &self.context.deck)
    }

    /// A árvore sem linha de comando nem ambiente: barata o bastante para rodar
    /// na remoção de um nó.
    pub fn tree(&self) -> Vec<RawProcess> {
        self.driver.list(ProcessDetail::Tree).unwrap_or_default()
    }

    /// Encerra só o que a leitura de agora diz ser do Egeon — um pid que veio
    /// de fora não basta, ele pode já ter sido reaproveitado por outro
    /// processo. Sem `pids`, os órfãos todos.
    pub fn terminate(&self, pids: Option<&HashSet<u32>>) -> Vec<EgeonProcess> {
        let targets: Vec<EgeonProcess> = self
            .scan()
            .into_iter()
            .filter(|p| pids.map_or(p.orphan, |set| set.contains(&p.pid)))
            .collect();
        for process in &targets {
            let _ = self.driver.signal(process.pid, ProcessSignal::Terminate);
        }
        if !targets.is_empty() {
            let who: Vec<String> = targets
                .iter()
                .map(|p| format!("{} {}", p.pid, p.node.as_deref().unwrap_or("app")))
                .collect();
            crate::log!(
                "processos: SIGTERM em {} — {}",
                targets.len(),
                who.join(", ")
            );
        }
        targets
    }
}

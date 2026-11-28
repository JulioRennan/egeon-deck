//! A limpeza que encerra os órfãos velhos (ADR-083). Rede de segurança: o
//! grosso morre junto com o nó (`terminate_tree`); aqui cai o que escapou —
//! app que caiu, processo que se soltou sozinho.
//!
//! Quem dá a batida é o core: [`OrphanReaper::start`] diz de quanto em quanto
//! tempo, e cada batida chama [`OrphanReaper::reap_now`] fora do ator.

use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use super::model::{EgeonProcess, ReapPolicy};
use super::policy_file::{load_policy, save_policy};
use super::scanner::ProcessScanner;

pub struct OrphanReaper {
    policy: ReapPolicy,
    file: PathBuf,
    /// Quando a limpeza rodou pela última vez e quantos levou.
    last: Option<(SystemTime, usize)>,
}

impl OrphanReaper {
    pub fn new(file: PathBuf) -> Self {
        OrphanReaper {
            policy: load_policy(&file),
            file,
            last: None,
        }
    }

    pub fn policy(&self) -> &ReapPolicy {
        &self.policy
    }

    pub fn last(&self) -> Option<(SystemTime, usize)> {
        self.last
    }

    /// De quanto em quanto o core deve chamar a limpeza; `None` com ela
    /// desligada. A batida tem tolerância de 30 s.
    pub fn start(&self) -> Option<Duration> {
        self.policy
            .enabled
            .then(|| Duration::from_secs_f64(self.policy.interval_minutes * 60.0))
    }

    /// O menu "Limpar órfãos automaticamente". Relê o arquivo antes, para não
    /// pisar numa edição à mão.
    pub fn set_enabled(&mut self, on: bool) -> Option<Duration> {
        self.policy = load_policy(&self.file);
        self.policy.enabled = on;
        save_policy(&self.file, &self.policy);
        crate::log!(
            "processos: limpeza automática {}",
            if on { "ligada" } else { "desligada" }
        );
        self.start()
    }

    /// Bloqueia: chamar fora do ator. É o que `/processes/reap` usa para
    /// conferir sem esperar o relógio; `dry` só diz quem seria levado.
    pub fn reap_now(
        &mut self,
        scanner: &ProcessScanner<'_>,
        now: SystemTime,
        dry: bool,
    ) -> Vec<EgeonProcess> {
        let killed = reap(&self.policy, scanner, now, dry);
        if !dry {
            self.record(now, killed.len());
        }
        killed
    }

    /// Anota que a limpeza rodou. Separado de [`reap`] para o core levar a
    /// política para fora do ator, rodar lá, e só voltar com o resultado.
    pub fn record(&mut self, now: SystemTime, killed: usize) {
        self.last = Some((now, killed));
    }
}

/// A limpeza em si, sem estado: lê os processos, escolhe os órfãos que a
/// política leva e, fora do `dry`, os encerra. Bloqueia.
pub fn reap(
    policy: &ReapPolicy,
    scanner: &ProcessScanner<'_>,
    now: SystemTime,
    dry: bool,
) -> Vec<EgeonProcess> {
    let victims = policy.victims(&scanner.scan(), now);
    if dry || victims.is_empty() {
        return if dry { victims } else { Vec::new() };
    }
    let pids = victims.iter().map(|p| p.pid).collect();
    scanner.terminate(Some(&pids))
}

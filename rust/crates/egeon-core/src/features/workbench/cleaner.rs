//! Limpar a bancada tem duração, e a ordem importa (ADR-059). Porte do
//! `WorkbenchCleaner`.
//!
//! O `clear` de cada agente vai pela fila do Dispatcher: terminal ocupado só
//! recebe quando ficar livre, e até lá o turno que ele ainda escreve continua
//! caindo no `chat.jsonl`. Arquivar no mesmo instante do disparo — o que se
//! fazia — deixava o rabo da conversa velha dentro da conversa nova. Aqui a
//! limpeza espera: manda o `clear`, espera os agentes assentarem, ARQUIVA e só
//! então se diz pronta.
//!
//! Sem estado de bancada nem relógio próprio: quem sabe despachar, quem sabe se
//! um terminal está ocupado e quem sabe arquivar entram pelo [`CleanerHost`], e a
//! hora entra como parâmetro — o ator chama `tick` de tempos em tempos.

use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use serde_json::{Value, json};

use crate::features::activity::model::Activity;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CleanAgent {
    pub id: String,
    pub address: String,
    /// O `clear` do perfil. Vazio ou nulo = CLI que não declara — pulado, nunca
    /// morto.
    pub command: Option<String>,
}

/// Onde a limpeza está. É o que o loading mostra.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    /// Esperando `remaining` agentes terminarem o que estavam fazendo e
    /// engolirem o `clear`.
    Clearing {
        remaining: usize,
    },
    /// Movendo chat e trilha para `chat-archive/` e `trace-archive/`.
    Archiving,
    Done,
}

impl Phase {
    pub fn label(&self) -> Option<String> {
        match self {
            Phase::Clearing { remaining } if *remaining > 0 => Some(format!(
                "Limpando {remaining} agente{}…",
                if *remaining == 1 { "" } else { "s" }
            )),
            Phase::Clearing { .. } => Some("Limpando os agentes…".to_owned()),
            Phase::Archiving => Some("Arquivando o chat e a trilha…".to_owned()),
            Phase::Done => None,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Archived {
    pub chat: Option<PathBuf>,
    pub trace: Option<PathBuf>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CleanResult {
    pub cleared: Vec<String>,
    pub skipped: Vec<String>,
    pub chat: Option<PathBuf>,
    pub trace: Option<PathBuf>,
    /// Algum agente não assentou dentro do teto: arquivou-se assim mesmo.
    pub timed_out: bool,
}

impl CleanResult {
    /// O corpo da resposta da rota `/workbench/clear`.
    pub fn payload(&self) -> Value {
        let path = |p: &Option<PathBuf>| {
            p.as_ref().map_or(Value::Null, |p| {
                Value::String(p.to_string_lossy().into_owned())
            })
        };
        json!({
            "ok": true,
            "cleared": self.cleared,
            "skipped": self.skipped,
            "archived": path(&self.chat),
            "trace": path(&self.trace),
            "timeout": self.timed_out,
        })
    }
}

/// O que a limpeza pede ao resto do app.
pub trait CleanerHost {
    /// Manda o `clear` do agente pela fila. `false` = o agente já não está no
    /// Dispatcher (terminal fechado): vai para os pulados.
    fn dispatch(&mut self, agent: &CleanAgent) -> bool;
    fn is_busy(&mut self, agent: &CleanAgent) -> bool;
    fn archive(&mut self) -> Archived;
    fn on_phase(&mut self, _phase: Phase) {}
    fn on_finish(&mut self, result: CleanResult);
}

/// Um terminal ainda pode engolir o `clear` sozinho?
///
/// `Asking` é não: ele parou pedindo permissão e depende de VOCÊ, não da
/// limpeza — a fila dele não anda enquanto a caixa estiver na tela, e esperar
/// significava esperar o teto inteiro com a cortina de pé (45 s parada, visto no
/// DEV). O `clear` continua na fila e é entregue quando você responder.
pub fn is_busy(activity: &Activity, pending: usize) -> bool {
    if *activity == Activity::Asking {
        return false;
    }
    pending > 0 || *activity == Activity::Working || *activity == Activity::Starting
}

pub struct WorkbenchCleaner {
    agents: Vec<CleanAgent>,
    /// Antes disto ninguém conta como assentado: o texto acabou de ser colado na
    /// TUI e o gancho de início de turno ainda não chegou. Sem a folga, a
    /// primeira olhada via todo mundo parado e arquivava na hora — o bug que
    /// este controller existe para tirar.
    grace: Duration,
    /// Teto. Agente atolado numa tarefa longa não pode prender o loading para
    /// sempre: estourou, arquiva-se com o que há e o resultado diz que estourou.
    timeout: Duration,
    started_at: Option<SystemTime>,
    result: CleanResult,
    phase: Phase,
}

impl WorkbenchCleaner {
    pub fn new(agents: Vec<CleanAgent>, grace: Duration, timeout: Duration) -> Self {
        Self {
            agents,
            grace,
            timeout,
            started_at: None,
            result: CleanResult::default(),
            phase: Phase::Done,
        }
    }

    /// Os tempos do app: 2,5 s de folga e 45 s de teto.
    pub fn with_defaults(agents: Vec<CleanAgent>) -> Self {
        Self::new(agents, Duration::from_millis(2500), Duration::from_secs(45))
    }

    pub fn phase(&self) -> Phase {
        self.phase
    }

    /// Dispara o `clear` em cada agente que o declara.
    pub fn start(&mut self, now: SystemTime, host: &mut dyn CleanerHost) {
        self.started_at = Some(now);
        self.result = CleanResult::default();
        for agent in &self.agents {
            let declared = agent.command.as_deref().is_some_and(|c| !c.is_empty());
            if declared && host.dispatch(agent) {
                self.result.cleared.push(agent.id.clone());
            } else {
                self.result.skipped.push(agent.id.clone());
            }
        }
        self.phase = Phase::Clearing {
            remaining: self.result.cleared.len(),
        };
        host.on_phase(self.phase);
        // Bancada sem agente que aceite `clear` não tem o que esperar.
        if self.result.cleared.is_empty() {
            self.finish(host);
        }
    }

    /// Chamado de tempos em tempos enquanto a fase for `Clearing`.
    pub fn tick(&mut self, now: SystemTime, host: &mut dyn CleanerHost) {
        if !matches!(self.phase, Phase::Clearing { .. }) {
            return;
        }
        let elapsed = self
            .started_at
            .and_then(|start| now.duration_since(start).ok())
            .unwrap_or_default();
        let cleared = self.result.cleared.clone();
        let busy = self
            .agents
            .iter()
            .filter(|a| cleared.contains(&a.id))
            .filter(|a| host.is_busy(a))
            .count();
        if elapsed >= self.timeout {
            self.result.timed_out = true;
            crate::log!(
                "limpar: {busy} agente(s) ainda ocupado(s) depois de {}s — arquivando assim mesmo",
                self.timeout.as_secs()
            );
            self.finish(host);
            return;
        }
        if elapsed < self.grace || busy > 0 {
            let next = Phase::Clearing { remaining: busy };
            if next != self.phase {
                self.phase = next;
                host.on_phase(next);
            }
            return;
        }
        self.finish(host);
    }

    fn finish(&mut self, host: &mut dyn CleanerHost) {
        self.phase = Phase::Archiving;
        host.on_phase(self.phase);
        let archived = host.archive();
        self.result.chat = archived.chat;
        self.result.trace = archived.trace;
        self.phase = Phase::Done;
        host.on_phase(self.phase);
        host.on_finish(self.result.clone());
    }
}

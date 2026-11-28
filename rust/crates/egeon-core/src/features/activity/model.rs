//! O que um terminal está fazendo e o resumo por bancada. Porte de
//! `Activity.swift`; o rótulo e a cor do card são da UI.

use std::time::SystemTime;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Activity {
    /// Subiu, mas ainda está no aquecimento ou não escreveu o primeiro byte.
    Starting,
    /// Aqueceu e está parado sem ter feito nada de substancial.
    Ready,
    Working,
    /// Trabalhou e parou: terminou.
    Waiting,
    /// Parou e depende de você.
    Asking,
    /// Parou com trabalho de fundo (`[[ED:wait]]`, ADR-063).
    Background,
    /// Parou depois de acionar vizinhos que ainda não responderam (ADR-067).
    Awaiting(Vec<String>),
    /// Erro passageiro da API; o app tenta de novo sozinho às `at` (ADR-072).
    Retrying {
        attempt: u32,
        at: SystemTime,
    },
    /// Erro da API e o app desistiu. Chama você, em vermelho.
    Failed(String),
    Dead,
}

impl Activity {
    /// Estados que INTERROMPEM: borda e som. "Terminou" você lê quando olhar
    /// (ADR-024).
    pub fn needs_attention(&self) -> bool {
        matches!(self, Activity::Asking | Activity::Failed(_))
    }
}

/// Quantos terminais de uma bancada estão em cada situação — o que a barra
/// lateral mostra das bancadas que não estão na tela.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ActivitySummary {
    pub starting: u32,
    pub working: u32,
    /// Fundo e quem aguarda vizinho: para a barra é o mesmo "volta sozinho".
    pub background: u32,
    pub attention: u32,
    pub done: u32,
    /// Subconjunto dos que pararam por erro da API, desistidos ou tentando.
    pub failed: u32,
    /// Os de `failed` que ainda vão tentar de novo.
    pub retrying: u32,
}

impl ActivitySummary {
    pub fn count(&mut self, activity: &Activity) {
        match activity {
            Activity::Starting => self.starting += 1,
            Activity::Working => self.working += 1,
            Activity::Background | Activity::Awaiting(_) | Activity::Retrying { .. } => {
                self.background += 1;
            }
            Activity::Asking | Activity::Failed(_) => self.attention += 1,
            Activity::Waiting => self.done += 1,
            Activity::Ready | Activity::Dead => {}
        }
        match activity {
            Activity::Failed(_) => self.failed += 1,
            Activity::Retrying { .. } => {
                self.failed += 1;
                self.retrying += 1;
            }
            _ => {}
        }
    }

    /// Só terminais subindo, nada mais a dizer: é a bancada se preparando.
    pub fn is_preparing(&self) -> bool {
        self.starting > 0
            && self.working == 0
            && self.background == 0
            && self.attention == 0
            && self.done == 0
    }
}

/// O tom da borda da bancada que parou: laranja vence verde.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RingTone {
    Asking,
    Done,
}

impl RingTone {
    pub fn for_summary(summary: &ActivitySummary) -> Option<Self> {
        if summary.attention > 0 {
            return Some(Self::Asking);
        }
        (summary.done > 0).then_some(Self::Done)
    }
}

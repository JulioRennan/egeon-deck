//! O que a fila faz a cada batida do relógio, pelo estado do agente destino.
//!
//! Fechar o item é "o agente trabalhou e voltou a ficar parado" — e não "parou
//! de sair byte", que acontece no meio do turno. Por isso o `saw_work`: quem
//! chama marca que viu o agente trabalhando depois do envio, e só então o
//! silêncio conta como fim.

use std::time::{Duration, SystemTime};

use super::model::PromptQueue;
use crate::features::activity::model::Activity;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Step {
    /// Item em andamento que fechou agora.
    pub finish: Option<String>,
    /// Item a mandar agora.
    pub send: Option<String>,
}

/// Item enviado sem nunca ver o agente trabalhar, e parado há este tanto: a
/// entrega se perdeu, e a fila não pode ficar presa nele para sempre.
pub const LOST_AFTER: Duration = Duration::from_secs(120);

pub struct QueueRunner;

impl QueueRunner {
    /// Parado esperando prompt: terminou o turno, ou nem começou nenhum. A
    /// pergunta (`Asking`) não entra — o agente parou por você, e mandar o
    /// próximo por cima da pergunta atropelaria a resposta.
    pub fn is_free(activity: &Activity) -> bool {
        matches!(activity, Activity::Waiting | Activity::Ready)
    }

    /// Estados em que o agente está trabalhando no que recebeu — inclusive
    /// parado por você no meio, que ainda é o mesmo turno.
    pub fn is_busy(activity: &Activity) -> bool {
        matches!(
            activity,
            Activity::Working
                | Activity::Background
                | Activity::Awaiting(_)
                | Activity::Asking
                | Activity::Retrying { .. }
        )
    }

    pub fn step(
        queue: &PromptQueue,
        activity: Option<&Activity>,
        saw_work: bool,
        now: SystemTime,
    ) -> Step {
        if !activity.is_some_and(Self::is_free) {
            return Step::default();
        }
        let mut step = Step::default();
        if let Some(current) = queue.in_flight() {
            // Pergunta aberta: o turno fechou por você, e a tarefa continua.
            if current.awaiting {
                return Step::default();
            }
            let sent = current.sent_at.unwrap_or(now);
            let lost = now.duration_since(sent).unwrap_or(Duration::ZERO) >= LOST_AFTER;
            if !(saw_work || lost) {
                return step;
            }
            step.finish = Some(current.id.clone());
        }
        if queue.auto
            && let Some(next) = queue.next_pending()
        {
            step.send = Some(next.id.clone());
        }
        step
    }
}

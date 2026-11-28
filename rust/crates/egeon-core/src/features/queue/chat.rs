//! Uma fila como a coluna do chat a mostra: o nó e o que resumir dele.
//!
//! A largura do painel ao lado da conversa é geometria de tela, e fica na UI.

use super::model::PromptQueue;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatQueue {
    pub id: String,
    pub pending: usize,
    /// O agente perguntou numa tarefa e espera você.
    pub asking: bool,
    /// Com quem está a tarefa em andamento.
    pub working_with: Option<String>,
}

impl ChatQueue {
    pub fn new(id: impl Into<String>, queue: &PromptQueue) -> Self {
        ChatQueue {
            id: id.into(),
            pending: queue.pending_count(),
            asking: queue.items.iter().any(|i| i.awaiting),
            working_with: queue.in_flight().and_then(|i| i.sent_to.clone()),
        }
    }

    /// A pergunta vem antes de tudo: é a única coisa aqui que espera você.
    pub fn summary(&self) -> String {
        if self.asking {
            return "? pergunta".to_owned();
        }
        let count = if self.pending == 1 {
            "1 pendente".to_owned()
        } else {
            format!("{} pendentes", self.pending)
        };
        match &self.working_with {
            Some(with) if self.pending == 0 => format!("com {with}"),
            Some(with) => format!("{count} · com {with}"),
            None if self.pending == 0 => "nada pendente".to_owned(),
            None => count,
        }
    }
}

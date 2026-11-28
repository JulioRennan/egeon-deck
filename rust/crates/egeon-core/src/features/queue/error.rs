//! Os erros da fila. O texto é o que o usuário e o agente leem — o mesmo do
//! Swift, que devolvia a frase pronta.

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum QueueError {
    #[error("Ligue a fila a um agente: arraste o + da borda até ele.")]
    NoDestination,
    #[error("item sumiu")]
    NoItem,
    #[error("esta tarefa já foi enviada: continue pela thread")]
    AlreadySent,
    #[error("tarefa vazia")]
    EmptyTask,
    #[error("nada pendente")]
    NothingPending,
    #[error("tarefa {typed} não existe na fila {queue} (veja `egeon tasks`)")]
    NoSuchTask { typed: String, queue: String },
    #[error("pergunta vazia — o que você quer saber?")]
    EmptyQuestion,
    #[error("comentário vazio")]
    EmptyNote,
    #[error("ação desconhecida {0} — use done, ask ou note")]
    UnknownAction(String),
    /// O envio ao terminal falhou; o texto é o do despacho.
    #[error("{0}")]
    Dispatch(String),
}

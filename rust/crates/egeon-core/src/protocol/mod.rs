//! Mensagens do socket: comandos, respostas, eventos empurrados e rotas.
//!
//! Não depende do transporte: UI, `egeon` e `curl` falam o mesmo protocolo.

pub mod app;
pub mod chat;
pub mod handler;
pub mod http;
pub mod message;
pub mod node;
pub mod org;
pub mod routes;
pub mod screen;

#[cfg(test)]
mod app_fixtures;
#[cfg(test)]
mod node_fixtures;
#[cfg(test)]
mod org_fixtures;
#[cfg(test)]
mod tests;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ProtocolError {
    #[error("cabeçalho maior que 1 MiB")]
    HeadTooLarge,
    #[error("conexão fechada antes do fim do cabeçalho")]
    Truncated,
    #[error("cabeçalho não é UTF-8")]
    HeadNotUtf8,
    #[error("corpo de {0} bytes passa do teto de 64 MiB")]
    BodyTooLarge(usize),
    #[error("json inválido: {0}")]
    InvalidJson(String),
    #[error("comando sem id numérico")]
    MissingId,
    #[error("comando {id} inválido: {reason}")]
    BadCommand { id: u64, reason: String },
    #[error(transparent)]
    Id(#[from] crate::commons::ids::IdError),
    #[error(
        "tópico desconhecido: {0:?} (use terminals, screen/<id>, workspaces, workbench/<id>/nodes, chat/<id>, node/<wb>/<nó> ou app)"
    )]
    UnknownTopic(String),
    #[error("mensagem sem serializar: {0}")]
    Encode(String),
}

//! A fila de prompts de um nó: tarefas anotadas, enviadas a um agente ligado
//! por aresta, que as marca, pergunta e comenta pelo `egeon task`. No modo
//! automático ela anda sozinha a cada fim de turno do agente.
//!
//! Código puro: quem está ligado, o estado do agente e o envio chegam pelo
//! [`QueueHost`], e o relógio por parâmetro. O core liga isso ao ator e às
//! rotas `/queue`, `/tasks` e `/task`.

pub mod chat;
pub mod error;
pub mod model;
pub mod routes;
pub mod runner;
pub mod service;
pub mod store;

pub use chat::ChatQueue;
pub use error::QueueError;
pub use model::{PromptQueue, QueueItem, QueueMessage};
pub use runner::{QueueRunner, Step};
pub use service::{Linked, QueueController, QueueHost};
pub use store::QueueStore;

#[cfg(test)]
mod tests;

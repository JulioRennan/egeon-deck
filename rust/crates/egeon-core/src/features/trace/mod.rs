//! A trilha da bancada: um Markdown por bancada, em
//! `workbenches/<id>/trace.md`, onde cada agente registra o que fez no turno
//! (`egeon trace`) e o app carimba quem, com que CLI e modelo (ADR-036).

pub mod model;
pub mod routes;
pub mod store;

pub use model::TraceEntry;
pub use store::{OffsetAt, TraceLog};

#[cfg(test)]
mod tests;

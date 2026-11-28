//! Chat no core: o transcript do Claude como turnos e blocos, o histórico
//! (`chat.jsonl`), o diff de blocos para a UI e o texto da bolha (markdown,
//! sintaxe, diff).

pub mod blocks;
pub mod diff_hunk;
pub mod layout;
pub mod markdown;
pub mod model;
pub mod parsers;
pub mod routes;
pub mod runtime;
pub mod store;
pub mod syntax;
pub mod thread;
pub mod time;
pub mod view;

#[cfg(test)]
mod runtime_tests;
#[cfg(test)]
mod tests;

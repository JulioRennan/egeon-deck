//! Os processos do Egeon (ADR-083) e os apps de desktop que ele abre
//! (ADR-084): a marca de procedência no ambiente, quem é nosso na tabela do
//! sistema, a ordem da lista, a limpeza dos órfãos e o fechamento do app que o
//! último usuário deixa.
//!
//! A tabela, os sinais, os apps abertos e os sockets vêm do driver
//! (`ports::procs`); aqui só se decide sobre eles, e os testes usam um sistema
//! de mentira.

pub mod claims;
pub mod containers;
pub mod keeper;
pub mod mark;
pub mod model;
pub mod policy_file;
pub mod reaper;
pub mod routes;
pub mod scanner;
pub mod tree;
pub mod view;

pub use claims::AppClaims;
pub use containers::ContainerOwners;
pub use keeper::{AppKeeper, Closing, Drivers};
pub use reaper::OrphanReaper;
pub use scanner::{ProcessScanner, ScanContext};

#[cfg(test)]
mod tests;

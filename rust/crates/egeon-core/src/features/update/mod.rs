//! A atualização do app (ADR-089): procura versão nova, baixa, confere e troca.
//!
//! Nunca reinicia sozinha: o terminal morre com o app (ADR-010), e reiniciar
//! por conta própria derrubaria agentes no meio do trabalho. No automático ela
//! só baixa, e a troca acontece quando você fechar o app.
//!
//! O core decide e confere: a versão, a assinatura do zip, o identificador do
//! app, o fluxo. Rede (consultar a release, baixar) e o que muda por sistema
//! (descompactar, assinatura de código, trocar o app depois que ele sai)
//! ficam de fora: a rede é do core que liga, e o resto está atrás de
//! [`AppInstaller`](crate::ports::installer::AppInstaller).

pub mod controller;
pub mod fetch;
pub mod installer;
pub mod policy;
pub mod prompt;
pub mod release;
pub mod routes;
pub mod settings;
pub mod signature;
pub mod version;

pub use controller::{Effect, FetchOutcome, State, UpdateConfig, UpdateController};
pub use fetch::{Completion, UpdateClient};
pub use installer::{Failure, UpdateInstaller};
pub use policy::{Action, Reason, UpdatePolicy};
pub use release::{AssetNames, AvailableUpdate};
pub use version::AppVersion;

#[cfg(test)]
mod tests;

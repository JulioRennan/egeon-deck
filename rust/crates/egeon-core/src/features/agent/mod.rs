//! Agentes: perfis de CLI (`agents.json`), catálogo de modelos, regras do
//! system prompt, comandos de barra — e o que é específico do Claude Code em
//! [`claude`].
//!
//! Nada aqui conhece "Claude Code" fora de `claude/`: trocar de agente é
//! editar o `agents.json` do flavor (ADR-009).

pub mod claude;
pub mod effort_dial;
pub mod gauge;
pub mod model;
pub mod model_catalog;
pub mod rules;
pub mod slash;
pub mod store;

pub use effort_dial::EffortDialState;
pub use gauge::ContextGauge;
pub use model::{
    AgentProfile, AttentionConfig, IdleConfig, InjectConfig, Marker, MarkerConfig, ModelChoice,
};
pub use model_catalog::{CatalogModel, ModelCatalog};
pub use rules::agent_rules_block;
pub use slash::{SlashCommand, SlashSource};

#[cfg(test)]
mod tests;

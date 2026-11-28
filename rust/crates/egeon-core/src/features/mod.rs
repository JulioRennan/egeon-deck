//! Um módulo por feature, planos, agrupados quando fizer sentido.
//!
//! Cada feature tem as mesmas três camadas:
//! - `model.rs` — entidades e leitura/gravação tolerante;
//! - `store.rs` — persistência em disco;
//! - `service.rs` — regras e casos de uso.

pub mod activity;
pub mod agent;
pub mod canvas;
pub mod chat;
pub mod dispatch;
pub mod edge;
pub mod json_file;
pub mod maestro;
pub mod node;
pub mod path_text;
pub mod permission;
pub mod processes;
pub mod queue;
pub mod terminal;
pub mod trace;
pub mod update;
pub mod usage;
pub mod workbench;
pub mod workspace;
pub mod worktree;

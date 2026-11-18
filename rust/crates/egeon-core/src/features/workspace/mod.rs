//! Workspace → projeto → bancada (ADR-043): modelo, `workspaces.json`, a
//! imagem do workspace, a conciliação, a árvore da barra lateral, mover,
//! multi-projeto e projeto novo.

pub mod links;
pub mod model;
pub mod multi;
pub mod new_project;
pub mod reorder;
pub mod routes;
pub mod service;
pub mod sidebar_drop;
pub mod store;
pub mod tree;

pub use model::{ProjectConfig, WorkspaceConfig};
pub use tree::{SidebarItem, WorkspaceTree};

#[cfg(test)]
mod tests;
#[cfg(test)]
mod tests_multi;
#[cfg(test)]
mod tests_routes;
#[cfg(test)]
mod tests_tree;

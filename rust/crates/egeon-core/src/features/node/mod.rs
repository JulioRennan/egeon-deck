//! O nó de uma bancada e o componente (preset de nó): modelo, `components.json`
//! e as regras de capturar e instanciar.

pub mod edit;
pub mod launch;
pub mod model;
pub mod service;
pub mod store;

pub use model::{Frame, NodeConfig, NodeKind, NodeTemplate, Overrides, Resolved};

#[cfg(test)]
mod tests;
#[cfg(test)]
mod tests_launch;

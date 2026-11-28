//! Permissão do CLI respondida pelo app (ADR-068): o pedido que o gancho
//! `PermissionRequest` abre e a resposta que ele vem buscar.

pub mod model;
pub mod service;

pub mod routes;
#[cfg(test)]
mod tests;

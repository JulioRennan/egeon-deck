//! O maestro: o terminal que o usuário autorizou a desenhar e reger a bancada
//! (ADR-066).

pub mod controller;
pub mod guide;
pub mod layout;
pub mod links;
pub mod permissions;
pub mod plan;
pub mod planner;
pub mod snapshot;

pub mod routes;
#[cfg(test)]
mod tests;

//! Envio entre agentes: a fila de injeção de cada terminal, as guardas de
//! cadeia, o envelope de procedência e o fim de turno pelos ganchos e
//! marcadores `[[ED:…]]`. Porte de `Features/Dispatch` do Swift.

pub mod failure;
pub mod marker;
pub mod profile;
pub mod request;
pub mod service;
pub mod stop;
pub mod target;

pub mod coordination;
pub mod routes;
#[cfg(test)]
mod routes_tests;
#[cfg(test)]
mod tests;

pub use service::{DispatchError, Dispatcher, Peer, Topology};
pub use target::{Effect, Hook, Surface, Target};

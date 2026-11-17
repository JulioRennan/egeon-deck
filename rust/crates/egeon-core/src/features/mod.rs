//! Um módulo por feature, planos, agrupados quando fizer sentido.
//!
//! Cada feature tem as mesmas três camadas:
//! - `model.rs` — entidades e leitura/gravação tolerante;
//! - `store.rs` — persistência em disco;
//! - `service.rs` — regras e casos de uso.

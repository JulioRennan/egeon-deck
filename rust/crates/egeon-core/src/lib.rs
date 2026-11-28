//! Core do Egeon Deck: toda a lógica do app.
//!
//! Usa direto o que é igual em qualquer plataforma (arquivos, git, rede,
//! relógio). O que muda por sistema fica atrás das interfaces de [`ports`],
//! implementadas pelos crates `egeon-driver` e `egeon-terminal`.
//!
//! O padrão deste workspace está em `docs/migracao/3-proposta.html` e na skill
//! `padrao-rust`.

// Chamada ao sistema e ao Ghostty mora só no driver e no terminal; aqui o
// compilador garante.
#![forbid(unsafe_code)]
// `eprintln!` e `println!` entram em pânico com o cano quebrado (a UI morta
// com kill -9); o core escreve só por `log!`, e o compilador garante.
#![deny(clippy::print_stdout, clippy::print_stderr)]

pub mod commons;
pub mod features;
pub mod ports;
pub mod protocol;
pub mod runtime;

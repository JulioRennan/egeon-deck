//! `egeon`: o comando dos agentes e os ganchos dos CLIs.
//!
//! Só fala o protocolo do socket; não conhece o resto do app. Os subcomandos
//! portam o script `egeon` do Swift, e `egeon hook <evento>` porta o
//! `agent-hook.sh` — um processo nativo no lugar de bash, curl e python3.

#![forbid(unsafe_code)]

pub mod commands;
pub mod encode;
pub mod hook;
pub mod http;
pub mod pyjson;

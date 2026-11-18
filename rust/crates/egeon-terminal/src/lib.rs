//! Emulador de terminal do Egeon Deck, sobre o `libghostty-vt`.
//!
//! Implementa a interface de tela definida em `egeon_core::ports::screen`:
//! bytes entram, linhas e texto saem. Não tem pty nem código por plataforma.
//! O binário do Ghostty vem do `build.rs`, com versão e sha256 fixos.

mod ffi;
mod key;
mod line;
mod link;
mod screen;
mod sink;

pub use screen::{GhosttyScreen, GhosttyScreens};

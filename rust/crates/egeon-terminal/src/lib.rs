//! Emulador de terminal do Egeon Deck, sobre o `libghostty-vt`.
//!
//! Implementa a interface de tela definida em `egeon_core::ports`: bytes
//! entram, linhas e texto saem. Não tem pty nem código por plataforma.

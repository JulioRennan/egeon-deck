//! Driver do Egeon Deck: só o acesso ao sistema operacional que muda de uma
//! plataforma para outra.
//!
//! Implementa as interfaces de `egeon_core::ports`. Um módulo por capacidade
//! e, dentro dele, um arquivo por plataforma escolhido na compilação.

//! Abrir um arquivo ou uma URL com o app padrão do sistema, e o aviso de que
//! não havia o que abrir.
//!
//! Implementada por `egeon-driver`: o app padrão e o som de alerta são do
//! sistema. Resolver o texto do ⌘-clique contra as pastas do terminal é do
//! core (`features/terminal/link.rs`).

use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpenTarget {
    File(PathBuf),
    Url(String),
}

pub trait Opener: Send + Sync {
    /// Abre com o app padrão; `false` se o sistema não achou quem abra (URL
    /// inválida, arquivo que sumiu). Não espera o app terminar de abrir.
    fn open(&self, target: &OpenTarget) -> bool;

    /// O alerta sonoro do sistema, para o ⌘-clique em texto sem destino.
    fn beep(&self);
}

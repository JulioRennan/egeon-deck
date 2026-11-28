//! `update.json`: a opção de atualizar sozinho.

use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::features::json_file::parse;

pub const FILE: &str = "update.json";

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Settings {
    #[serde(default)]
    pub auto: bool,
}

impl Settings {
    /// Arquivo ausente ou ilegível é o padrão (desligado).
    pub fn load(path: &Path) -> Settings {
        std::fs::read(path)
            .ok()
            .and_then(|bytes| parse(&bytes).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, path: &Path) {
        // Compacto, como o `JSONEncoder` do Swift grava.
        let written = serde_json::to_vec(self)
            .map_err(std::io::Error::other)
            .and_then(|bytes| std::fs::write(path, bytes));
        if let Err(error) = written {
            crate::log!("atualização: não gravei {} — {error}", path.display());
        }
    }
}

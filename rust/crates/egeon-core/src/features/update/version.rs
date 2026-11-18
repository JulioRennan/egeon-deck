//! Número de versão comparável: `v1.10.0` é maior que `1.9.2`, o que comparar
//! como texto erraria.

use std::cmp::Ordering;

#[derive(Debug, Clone)]
pub struct AppVersion {
    parts: Vec<i64>,
}

impl AppVersion {
    /// `None` para o que não é só números separados por ponto
    /// (`1.6.0-beta`, `nightly`).
    pub fn parse(text: &str) -> Option<AppVersion> {
        let bare = text.strip_prefix('v').unwrap_or(text);
        let parts: Option<Vec<i64>> = bare.split('.').map(|p| p.parse().ok()).collect();
        parts.map(|parts| AppVersion { parts })
    }
}

impl Ord for AppVersion {
    /// Parte que falta vale zero: `1.6` é `1.6.0`.
    fn cmp(&self, other: &Self) -> Ordering {
        let len = self.parts.len().max(other.parts.len());
        for index in 0..len {
            let left = self.parts.get(index).copied().unwrap_or(0);
            let right = other.parts.get(index).copied().unwrap_or(0);
            if left != right {
                return left.cmp(&right);
            }
        }
        Ordering::Equal
    }
}

impl PartialOrd for AppVersion {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for AppVersion {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}

impl Eq for AppVersion {}

//! `processes.json`: a política da limpeza dos órfãos (ADR-083), editável à
//! mão; chave que faltar fica no padrão.

use std::path::Path;

use serde::Serialize;

use super::model::ReapPolicy;
use crate::features::json_file::{parse, read_bytes, write_pretty};

pub const FILE: &str = "processes.json";

/// O arquivo como o Swift o grava (`JSONEncoder`, chaves em ordem).
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PolicyFile {
    enabled: bool,
    interval_minutes: f64,
    min_age_minutes: f64,
}

/// Arquivo ausente ou ilegível é o padrão; chave que faltar também.
pub fn load_policy(path: &Path) -> ReapPolicy {
    read_bytes(path)
        .and_then(|bytes| parse(&bytes).ok())
        .unwrap_or_default()
}

pub fn save_policy(path: &Path, policy: &ReapPolicy) {
    let file = PolicyFile {
        enabled: policy.enabled,
        interval_minutes: policy.interval_minutes,
        min_age_minutes: policy.min_age_minutes,
    };
    if let Err(error) = write_pretty(path, &file) {
        crate::log!("processos: não gravei {} — {error}", path.display());
    }
}

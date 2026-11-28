//! A confiança do Claude Code numa pasta, como ele guarda no `.claude.json`
//! (ADR-071).
//!
//! O diálogo "você confia nesta pasta?" lê `projects[<pasta>]
//! .hasTrustDialogAccepted`, subindo pelos pais. A pasta nova de toda worktree
//! não tem entrada, e a cada branch o Claude perguntava de novo, embora o
//! repositório de origem já fosse aceito.

use std::path::Path;

use serde_json::{Map, Value, json};

pub const TRUST: &str = "hasTrustDialogAccepted";
pub const INCLUDES: [&str; 2] = [
    "hasClaudeMdExternalIncludesApproved",
    "hasClaudeMdExternalIncludesWarningShown",
];

/// O que o Claude Code põe numa entrada nova de `projects` — sem estes campos
/// ele lê `undefined` onde espera lista.
pub fn blank_project() -> Value {
    json!({
        "allowedTools": [], "mcpContextUris": [], "mcpServers": {},
        "enabledMcpjsonServers": [], "disabledMcpjsonServers": [],
        "hasTrustDialogAccepted": false, "hasClaudeMdExternalIncludesApproved": false,
        "hasClaudeMdExternalIncludesWarningShown": false,
    })
}

/// A entrada mais próxima, a da pasta ou a de um pai, que tem a chave ligada.
pub fn granted(key: &str, projects: &Map<String, Value>, path: &str) -> bool {
    // Sem normalizar o caminho: a chave do Claude é o `realpath`, com `/private`.
    let trimmed = if path.len() > 1 && path.ends_with('/') {
        &path[..path.len() - 1]
    } else {
        path
    };
    let mut current = trimmed.to_owned();
    loop {
        if projects
            .get(&current)
            .and_then(|p| p.get(key))
            .and_then(Value::as_bool)
            == Some(true)
        {
            return true;
        }
        let parent = Path::new(&current)
            .parent()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default();
        if parent.is_empty() || parent == current {
            return false;
        }
        current = parent;
    }
}

/// O `.claude.json` com `target` herdando o que TODAS as origens já têm aceito.
/// `None` quando não há o que mudar: sem origem, origem não aceita, ou o alvo já
/// aceito.
///
/// Todas, e não alguma: a pasta junta os repositórios, e confiar nela é confiar
/// em cada um.
pub fn inheriting(root: &Value, target: &str, origins: &[String]) -> Option<Value> {
    if origins.is_empty() {
        return None;
    }
    let projects = root
        .get("projects")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let mut entry = projects.get(target).cloned().unwrap_or_else(blank_project);
    let mut changed = false;
    for key in std::iter::once(TRUST).chain(INCLUDES) {
        if granted(key, &projects, target) || !origins.iter().all(|o| granted(key, &projects, o)) {
            continue;
        }
        if let Some(object) = entry.as_object_mut() {
            object.insert(key.to_owned(), Value::Bool(true));
            changed = true;
        }
    }
    if !changed {
        return None;
    }
    let mut updated = root.clone();
    let mut all = projects;
    all.insert(target.to_owned(), entry);
    updated
        .as_object_mut()?
        .insert("projects".to_owned(), Value::Object(all));
    Some(updated)
}

/// O `.claude.json` com `target` aceito: a confiança e os dois avisos dos
/// imports externos do CLAUDE.md, cada um só se nem a pasta nem um pai já o tem.
/// `None` quando não há o que mudar.
///
/// Vai além do Swift, por decisão do Julio: o checkout principal nunca aceito
/// (ou qualquer pasta sem origem) também deixa de perguntar.
pub fn accepting(root: &Value, target: &str) -> Option<Value> {
    let projects = root
        .get("projects")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let mut entry = projects.get(target).cloned().unwrap_or_else(blank_project);
    let mut changed = false;
    for key in std::iter::once(TRUST).chain(INCLUDES) {
        if granted(key, &projects, target) {
            continue;
        }
        if let Some(object) = entry.as_object_mut() {
            object.insert(key.to_owned(), Value::Bool(true));
            changed = true;
        }
    }
    if !changed {
        return None;
    }
    let mut updated = root.clone();
    let mut all = projects;
    all.insert(target.to_owned(), entry);
    updated
        .as_object_mut()?
        .insert("projects".to_owned(), Value::Object(all));
    Some(updated)
}

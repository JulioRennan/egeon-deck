//! `workspaces.json` e a imagem de cada workspace. Caminho como parâmetro;
//! chamado de `spawn_blocking`.

use std::path::{Path, PathBuf};

use serde_json::Value;

use super::model::WorkspaceConfig;
use crate::features::json_file::{PersistError, parse, read_bytes, write_pretty};

pub const FILE: &str = "workspaces.json";

#[derive(Debug, Clone, PartialEq)]
pub struct Loaded {
    pub workspaces: Vec<WorkspaceConfig>,
    /// O arquivo existe e não abre: a lista vem vazia, como no Swift, e a
    /// conciliação recria o "Geral". Quem chama deve guardar uma cópia antes de
    /// gravar por cima.
    pub broken: bool,
    /// Faltava `id` em workspace ou projeto e o `serde` gerou um: sem gravar, a
    /// bancada se desliga da pasta dela a cada carga.
    pub needs_save: bool,
}

/// `None` quando o arquivo não existe — é o que dispara a migração. Arquivo
/// vazio é uma lista vazia, e a conciliação também recria o padrão.
pub fn load(path: &Path) -> Option<Loaded> {
    let bytes = read_bytes(path)?;
    Some(match parse::<Vec<WorkspaceConfig>>(&bytes) {
        Ok(workspaces) => Loaded {
            workspaces,
            broken: false,
            needs_save: missing_ids(&bytes),
        },
        Err(_) => Loaded {
            workspaces: Vec::new(),
            broken: true,
            needs_save: false,
        },
    })
}

fn missing_ids(bytes: &[u8]) -> bool {
    let Ok(Value::Array(spaces)) = parse::<Value>(bytes) else {
        return false;
    };
    let lacks = |item: &Value| !item.get("id").is_some_and(Value::is_string);
    spaces.iter().any(|space| {
        lacks(space)
            || space
                .get("projects")
                .and_then(Value::as_array)
                .is_some_and(|projects| projects.iter().any(lacks))
    })
}

pub fn save(path: &Path, list: &[WorkspaceConfig]) -> Result<(), PersistError> {
    write_pretty(path, &list)
}

// ── Imagem ─────────────────────────────────────────────────────────────────

/// `workspaces/<id>/`, dentro da pasta de dados: hoje só a imagem dele mora aqui.
pub fn directory(home: &Path, workspace_id: &str) -> PathBuf {
    home.join("workspaces").join(workspace_id)
}

pub fn icon_path(home: &Path, workspace: &WorkspaceConfig) -> Option<PathBuf> {
    let icon = workspace.icon.as_deref()?;
    Some(directory(home, &workspace.id).join(icon))
}

/// Copia a imagem escolhida para a pasta do workspace e aponta `icon` para ela.
/// Cópia, e não referência: a original pode estar em Downloads e sumir na
/// semana seguinte.
pub fn install_icon(
    home: &Path,
    source: &Path,
    workspace: &mut WorkspaceConfig,
) -> std::io::Result<()> {
    let dir = directory(home, &workspace.id);
    std::fs::create_dir_all(&dir)?;
    let ext = source
        .extension()
        .and_then(|e| e.to_str())
        .filter(|e| !e.is_empty())
        .map_or_else(|| "png".to_owned(), str::to_lowercase);
    let name = format!("icon.{ext}");
    let destination = dir.join(&name);
    if destination.exists() {
        std::fs::remove_file(&destination)?;
    }
    std::fs::copy(source, &destination)?;
    if let Some(old) = workspace.icon.as_deref()
        && old != name
    {
        let _ = std::fs::remove_file(dir.join(old));
    }
    workspace.icon = Some(name);
    Ok(())
}

pub fn remove_icon(home: &Path, workspace: &mut WorkspaceConfig) {
    if let Some(path) = icon_path(home, workspace) {
        let _ = std::fs::remove_file(path);
    }
    workspace.icon = None;
}

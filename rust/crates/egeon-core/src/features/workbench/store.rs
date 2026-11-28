//! `workbenches.json` (com o `sessions.json` antigo como reserva de leitura) e
//! `templates.json`. Caminho como parâmetro; chamado de `spawn_blocking`.

use std::collections::BTreeMap;
use std::path::Path;

use serde_json::Value;

use super::model::{WorkbenchConfig, WorkbenchTemplate};
use crate::features::json_file::{PersistError, parse, read_bytes, write_pretty};

pub const FILE: &str = "workbenches.json";
/// Onde o arquivo morava quando bancada se chamava sessão. Lido só quando o
/// novo não existe, e nunca escrito: a primeira gravação já sai com o nome novo.
pub const LEGACY_FILE: &str = "sessions.json";
pub const TEMPLATES_FILE: &str = "templates.json";

/// De onde veio a lista.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    /// O `workbenches.json`.
    Config,
    /// O `sessions.json` antigo, porque o novo nunca existiu.
    Legacy,
    /// O `workbenches.json` existe e não abre. A lista vem vazia, como no
    /// Swift; quem chama deve guardar uma cópia antes de gravar por cima.
    Broken,
    /// Nenhum dos dois existe.
    Nothing,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Loaded {
    pub workbenches: Vec<WorkbenchConfig>,
    pub source: Source,
    /// O que foi lido precisa voltar ao disco: id gerado (sem gravá-lo a
    /// bancada se desliga da pasta dela a cada carga), nome antigo de conversa
    /// absorvido, ou lista vinda do `sessions.json`.
    pub needs_save: bool,
}

/// Carrega as bancadas. O arquivo antigo só vale quando o novo nunca existiu:
/// lista vazia é o estado de quem apagou a última bancada, e cair no antigo
/// traria de volta bancadas que já saíram, com os agentes delas subindo
/// sozinhos. Arquivo novo quebrado também não cai no antigo.
pub fn load(config: &Path, legacy: &Path) -> Loaded {
    if config.exists() {
        return match decode(config) {
            Some((workbenches, needs_save)) => Loaded {
                workbenches,
                source: Source::Config,
                needs_save,
            },
            None => Loaded {
                workbenches: Vec::new(),
                source: Source::Broken,
                needs_save: false,
            },
        };
    }
    if let Some((workbenches, _)) = decode(legacy) {
        return Loaded {
            workbenches,
            source: Source::Legacy,
            needs_save: true,
        };
    }
    // Sem nada para carregar, começa vazio: chutar caminhos de projeto só
    // produz bancadas quebradas que o usuário tem de limpar.
    Loaded {
        workbenches: Vec::new(),
        source: Source::Nothing,
        needs_save: false,
    }
}

fn decode(path: &Path) -> Option<(Vec<WorkbenchConfig>, bool)> {
    let bytes = read_bytes(path)?;
    let list: Vec<WorkbenchConfig> = parse(&bytes).ok()?;
    let missing_id = missing_ids(&bytes);
    // Arquivo gravado antes do rename traz `sessionId`/`sessionStarted`. Sem
    // absorver aqui, todo agente perderia a conversa no primeiro arranque: o
    // terminal subiria limpo em vez de retomar.
    let legacy_names = list
        .iter()
        .flat_map(|w| &w.nodes)
        .any(|n| n.session_id.is_some() || n.session_started.is_some());
    let list = list
        .into_iter()
        .map(|mut w| {
            w.nodes = w
                .nodes
                .into_iter()
                .map(|n| n.migrating_legacy_names())
                .collect();
            w
        })
        .collect();
    Some((list, missing_id || legacy_names))
}

/// Há bancada sem `id` no texto? (O `serde` já gerou um; aqui se sabe que isso
/// aconteceu.)
fn missing_ids(bytes: &[u8]) -> bool {
    let Ok(Value::Array(items)) = parse::<Value>(bytes) else {
        return false;
    };
    items
        .iter()
        .any(|item| !item.get("id").is_some_and(Value::is_string))
}

pub fn save(path: &Path, list: &[WorkbenchConfig]) -> Result<(), PersistError> {
    write_pretty(path, &list)
}

// ── templates.json ─────────────────────────────────────────────────────────

/// Arquivo ausente, ilegível ou com erro é mapa vazio.
pub fn load_templates(path: &Path) -> BTreeMap<String, WorkbenchTemplate> {
    read_bytes(path)
        .and_then(|bytes| parse(&bytes).ok())
        .unwrap_or_default()
}

pub fn save_templates(
    path: &Path,
    map: &BTreeMap<String, WorkbenchTemplate>,
) -> Result<(), PersistError> {
    write_pretty(path, map)
}

/// Os nomes em ordem estável, para o menu de templates não se embaralhar.
pub fn template_names(path: &Path) -> Vec<String> {
    load_templates(path).into_keys().collect()
}

pub fn template(path: &Path, name: &str) -> Option<WorkbenchTemplate> {
    load_templates(path).remove(name)
}

pub fn put_template(
    path: &Path,
    name: &str,
    template: WorkbenchTemplate,
) -> Result<(), PersistError> {
    let mut map = load_templates(path);
    map.insert(name.to_owned(), template);
    save_templates(path, &map)
}

pub fn remove_template(path: &Path, name: &str) -> Result<(), PersistError> {
    let mut map = load_templates(path);
    map.remove(name);
    save_templates(path, &map)
}

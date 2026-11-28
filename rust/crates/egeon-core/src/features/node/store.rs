//! `components.json`: os componentes (presets de nó), nome → componente.
//!
//! O arquivo continua se chamando `components.json` — é editado à mão e já
//! existe nas duas casas. Caminho como parâmetro; chamado de `spawn_blocking`.

use std::collections::BTreeMap;
use std::path::Path;

use super::model::{NodeTemplate, decode_components};
use crate::features::json_file::{PersistError, read_bytes, write_pretty};

pub const FILE: &str = "components.json";

/// Arquivo ausente ou ilegível é mapa vazio. Nó de tipo aposentado é pulado;
/// qualquer outro erro esvazia o mapa, como no Swift.
pub fn load(path: &Path) -> BTreeMap<String, NodeTemplate> {
    read_bytes(path)
        .and_then(|bytes| decode_components(&bytes))
        .unwrap_or_default()
}

pub fn save(path: &Path, map: &BTreeMap<String, NodeTemplate>) -> Result<(), PersistError> {
    write_pretty(path, map)
}

/// Os nomes em ordem estável, para o menu de componentes não se embaralhar.
pub fn names(path: &Path) -> Vec<String> {
    load(path).into_keys().collect()
}

pub fn component(path: &Path, name: &str) -> Option<NodeTemplate> {
    load(path).remove(name)
}

pub fn put(path: &Path, component: NodeTemplate) -> Result<(), PersistError> {
    let mut map = load(path);
    map.insert(component.name.clone(), component);
    save(path, &map)
}

pub fn remove(path: &Path, name: &str) -> Result<(), PersistError> {
    let mut map = load(path);
    map.remove(name);
    save(path, &map)
}

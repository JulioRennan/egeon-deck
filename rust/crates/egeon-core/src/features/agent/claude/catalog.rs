//! O catálogo do Claude Code instalado, com cache por binário.
//!
//! Ler a tabela é varrer um executável de ~200 MB — coisa de segundo. O
//! resultado vai para `claude-models.json` com o caminho, o tamanho e a data do
//! binário; enquanto os três baterem, é só ler o JSON. O Claude Code se atualiza
//! quase todo dia, e aí a releitura roda em segundo plano: quem perguntar antes
//! dela acabar fica com o catálogo anterior.
//!
//! Aqui está a regra e a leitura; o ator do core decide quando e em que thread
//! rodar [`read_binary`], e guarda o resultado com [`CatalogMemo::store`].

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use serde::{Deserialize, Serialize};

use super::binary_source::FileBytes;
use super::command_registry::CommandRegistry;
use super::model_registry;
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::ModelCatalog;
use crate::features::usage::ModelPrice;

/// O catálogo vale para o perfil que roda o `claude` — outro binário no comando
/// não tem tabela nenhuma para ler.
pub fn applies_to(profile: &AgentProfile) -> bool {
    profile.command.first().map(String::as_str) == Some("claude")
}

pub fn cache_file(home: &Path) -> PathBuf {
    home.join("claude-models.json")
}

/// O tamanho e a data do binário, que dizem se o cache ainda vale.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Stamp {
    pub size: u64,
    /// Segundos desde 1970, como o cache do Swift guarda a data.
    pub modified: f64,
}

pub fn stamp_of(binary: &Path) -> Option<Stamp> {
    let meta = fs::metadata(binary).ok()?;
    let modified = meta.modified().ok()?.duration_since(UNIX_EPOCH).ok()?;
    Some(Stamp {
        size: meta.len(),
        modified: modified.as_secs_f64(),
    })
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Cache {
    pub binary: String,
    pub size: u64,
    pub modified: f64,
    pub catalog: ModelCatalog,
    /// O `/` do CLI; `None` ou de outra versão é cache de antes da leitura de
    /// hoje.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub commands: Option<CommandRegistry>,
}

impl Cache {
    /// O cache ainda vale para este binário? Cache de antes da leitura de preços
    /// ou de comandos relê uma vez.
    pub fn is_fresh(&self, binary: &Path, stamp: Stamp) -> bool {
        self.binary == binary.to_string_lossy()
            && self.size == stamp.size
            // O `serde_json` sem `float_roundtrip` pode errar 1 ulp ao reler a
            // data: igualdade exata invalidaria o cache a cada abertura.
            && (self.modified - stamp.modified).abs() < 0.001
            && self.catalog.prices.is_some()
            && self.catalog.schema == Some(ModelCatalog::CURRENT_SCHEMA)
            && self.commands.as_ref().and_then(|c| c.version)
                == Some(CommandRegistry::CURRENT_VERSION)
    }
}

/// O executável de verdade: o `claude` do PATH costuma ser um link para
/// `~/.local/share/claude/versions/<versão>`, e é o destino que muda. `path` é o
/// PATH já enriquecido pelo ambiente do app.
///
/// `is_executable` é de quem conhece o sistema (o bit de execução é de unix): o
/// core não tem `cfg` por plataforma, então o driver entrega a checagem.
pub fn resolve(name: &str, path: &str, is_executable: Executable) -> Option<PathBuf> {
    std::env::split_paths(path)
        .filter(|d| !d.as_os_str().is_empty())
        .map(|d| d.join(name))
        .find(|candidate| is_executable(candidate))
        .map(|candidate| crate::commons::paths::canonicalize(&candidate).unwrap_or(candidate))
}

/// O arquivo existe e roda? (`isExecutableFile` do Swift.)
pub type Executable = fn(&Path) -> bool;

/// Varre o binário e monta o cache novo. `None` quando não há tabela de modelos
/// — aí ficam os apelidos do `agents.json`. É a parte cara: rodar fora do ator.
pub fn read_binary(binary: &Path, stamp: Stamp) -> Option<Cache> {
    read_source(FileBytes::open(binary)?, binary, stamp)
}

/// Em blocos, não o arquivo inteiro: o binário passa de 300 MB (ver
/// `binary_source`). Binário que mudou no meio da leitura não gera cache.
fn read_source(mut source: FileBytes, binary: &Path, stamp: Stamp) -> Option<Cache> {
    let models = model_registry::parse_source(&mut source);
    if models.is_empty() || source.failed() {
        return None;
    }
    let prices = model_registry::prices_from_source(&mut source, &models);
    let commands = CommandRegistry::parse_source(&mut source);
    if source.failed() {
        return None;
    }
    Some(Cache {
        binary: binary.to_string_lossy().into_owned(),
        size: stamp.size,
        modified: stamp.modified,
        catalog: ModelCatalog::new(models, Some(prices)),
        commands: Some(commands),
    })
}

pub fn load_cache(file: &Path) -> Option<Cache> {
    crate::features::json_file::parse(&fs::read(file).ok()?).ok()
}

pub fn save_cache(file: &Path, cache: &Cache) {
    let Ok(value) = serde_json::to_value(cache) else {
        return;
    };
    if let Ok(text) = serde_json::to_string_pretty(&value) {
        let _ = fs::write(file, text);
    }
}

/// O que o ator guarda do catálogo: o último cache e as releituras em curso.
#[derive(Debug)]
pub struct CatalogMemo {
    is_executable: Executable,
    memo: Option<Cache>,
    loaded: bool,
    refreshing: Vec<PathBuf>,
}

/// Uma releitura que o chamador deve rodar fora do ator.
#[derive(Debug, Clone, PartialEq)]
pub struct Refresh {
    pub binary: PathBuf,
    pub stamp: Stamp,
}

impl CatalogMemo {
    pub fn new(is_executable: Executable) -> CatalogMemo {
        CatalogMemo {
            is_executable,
            memo: None,
            loaded: false,
            refreshing: Vec::new(),
        }
    }

    /// O cache do binário do perfil, e a releitura a disparar quando ele não
    /// vale. O anterior serve enquanto o novo não chega: modelo raramente some.
    pub fn cache(
        &mut self,
        file: &Path,
        binary_name: &str,
        path: &str,
    ) -> (Option<&Cache>, Option<Refresh>) {
        let Some(binary) = resolve(binary_name, path, self.is_executable) else {
            return (None, None);
        };
        let Some(stamp) = stamp_of(&binary) else {
            return (None, None);
        };
        if !self.loaded {
            self.memo = load_cache(file);
            self.loaded = true;
        }
        let fresh = self
            .memo
            .as_ref()
            .is_some_and(|m| m.is_fresh(&binary, stamp));
        let refresh = if fresh || self.refreshing.contains(&binary) {
            None
        } else {
            self.refreshing.push(binary.clone());
            Some(Refresh { binary, stamp })
        };
        (self.memo.as_ref(), refresh)
    }

    /// A releitura terminou: guarda e grava o cache novo. `None` (binário sem
    /// tabela) só libera a próxima tentativa.
    pub fn store(
        &mut self,
        file: &Path,
        refresh: &Refresh,
        result: Option<Cache>,
    ) -> Option<&ModelCatalog> {
        self.refreshing.retain(|b| b != &refresh.binary);
        let cache = result?;
        save_cache(file, &cache);
        self.memo = Some(cache);
        self.loaded = true;
        self.memo.as_ref().map(|c| &c.catalog)
    }

    /// Os embutidos e as skills do binário — o que o `/` oferece além do disco
    /// —, do último cache guardado. `None` enquanto não se leu.
    pub fn commands(&self) -> Option<&CommandRegistry> {
        self.memo.as_ref()?.commands.as_ref()
    }

    /// Os preços do Claude Code instalado — a camada do meio da `PriceTable` —,
    /// do último cache guardado.
    pub fn installed_prices(&self) -> BTreeMap<String, ModelPrice> {
        self.memo
            .as_ref()
            .and_then(|c| c.catalog.prices.clone())
            .unwrap_or_default()
    }
}

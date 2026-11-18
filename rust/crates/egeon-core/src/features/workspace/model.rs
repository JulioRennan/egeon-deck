//! Workspace e projeto, porte do `WorkspaceConfig` e do `ProjectConfig`.

use std::collections::BTreeMap;
use std::path::Path;

use serde::{Deserialize, Deserializer, Serialize};

use crate::features::path_text;
use crate::features::workbench::model::{id_or_new, new_id};

/// Um projeto é uma pasta — um repositório, quase sempre.
///
/// É a raiz a que as bancadas pertencem. A bancada aberta no checkout principal
/// e a aberta numa worktree dele são do MESMO projeto: tratar cada worktree
/// como projeto encheria a barra de pastas que ninguém escolheu (ADR-043).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(from = "ProjectWire")]
pub struct ProjectConfig {
    pub id: String,
    pub name: String,
    pub path: String,
    /// Recolhido na barra lateral. Mora aqui, e não em preferência à parte,
    /// porque o arquivo é editado à mão e a árvore inteira tem de estar num
    /// lugar só.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub collapsed: Option<bool>,
    /// Guardado: sai da lista de cima e vai para a gaveta do workspace. É
    /// ESCOLHA sua, não dedução por tempo sem uso (ADR-052).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stored: Option<bool>,
    /// Multi-projeto: os ids dos projetos de pasta, deste mesmo workspace, que
    /// ele junta. `path` passa a ser a pasta de links que os reúne — é ela que
    /// a bancada abre. Por id e não por caminho: renomear ou reposicionar o
    /// projeto de pasta não desfaz o conjunto.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub members: Option<Vec<String>>,
}

/// O formato em disco: `id` e `name` podem faltar.
#[derive(Deserialize)]
struct ProjectWire {
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    name: Option<String>,
    path: String,
    #[serde(default)]
    collapsed: Option<bool>,
    #[serde(default)]
    stored: Option<bool>,
    #[serde(default)]
    members: Option<Vec<String>>,
}

impl From<ProjectWire> for ProjectConfig {
    /// Projeto escrito no arquivo sem `id` ganha um ao carregar, como a bancada;
    /// sem `name`, o da pasta.
    fn from(wire: ProjectWire) -> Self {
        let name = wire
            .name
            .unwrap_or_else(|| path_text::last_component(&wire.path));
        ProjectConfig {
            id: wire.id.unwrap_or_else(new_id),
            name,
            path: wire.path,
            collapsed: wire.collapsed,
            stored: wire.stored,
            members: wire.members,
        }
    }
}

impl ProjectConfig {
    pub fn new(name: impl Into<String>, path: impl Into<String>) -> Self {
        Self {
            id: new_id(),
            name: name.into(),
            path: path.into(),
            collapsed: None,
            stored: None,
            members: None,
        }
    }

    pub fn is_multi(&self) -> bool {
        self.members.is_some()
    }

    /// Bancada deste projeto só nasce em worktree. Multi-projeto no checkout
    /// principal seria vários agentes mexendo nos repositórios de verdade, cada
    /// um na branch em que o repo estiver — o conjunto existe para isolar a
    /// frente de trabalho numa branch só (ADR-065).
    pub fn requires_worktree(&self) -> bool {
        self.is_multi()
    }

    pub fn is_collapsed(&self) -> bool {
        self.collapsed.unwrap_or(false)
    }

    pub fn is_stored(&self) -> bool {
        self.stored.unwrap_or(false)
    }

    /// A pasta do projeto, com `~` expandido e sem barra no fim.
    pub fn url_path(&self, home: &str) -> String {
        path_text::normalize(&self.path, home)
    }

    pub fn exists(&self, home: &str) -> bool {
        Path::new(&self.url_path(home)).exists()
    }

    /// Esta é a pasta do projeto? Compara como o disco compara: `~` expandido,
    /// sem barra no fim.
    pub fn owns(&self, path: &str, home: &str) -> bool {
        path_text::normalize(&self.path, home) == path_text::normalize(path, home)
    }

    /// Projeto novo para uma pasta: o nome é o da pasta, o caminho vai com `~`.
    pub fn for_folder(path: &str, home: &str) -> ProjectConfig {
        let normalized = path_text::normalize(path, home);
        ProjectConfig::new(
            path_text::last_component(&normalized),
            path_text::abbreviate_tilde(&normalized, home),
        )
    }
}

/// `null` e ausente são o valor padrão (`decodeIfPresent ?? default`).
fn null_default<'de, D, T>(de: D) -> Result<T, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de> + Default,
{
    Ok(Option::<T>::deserialize(de)?.unwrap_or_default())
}

/// Um workspace é um nome e um punhado de projetos. É a camada de cima da
/// organização.
///
/// Não é perfil: todos aparecem na barra ao mesmo tempo, expansíveis, porque
/// trabalhar em dois workspaces no mesmo dia é o caso normal.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceConfig {
    #[serde(default = "new_id", deserialize_with = "id_or_new")]
    pub id: String,
    pub name: String,
    /// Nome do arquivo de imagem dentro de `workspaces/<id>/`. Ausente = a
    /// inicial numa pastilha.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
    #[serde(default, deserialize_with = "null_default")]
    pub projects: Vec<ProjectConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub collapsed: Option<bool>,
    /// A gaveta dos guardados está aberta.
    #[serde(
        default,
        rename = "storedOpen",
        skip_serializing_if = "Option::is_none"
    )]
    pub stored_open: Option<bool>,
    /// A última configuração escolhida para cada CLI (chave do `agents.json`)
    /// num terminal deste workspace: é o que um terminal novo sugere.
    #[serde(
        default,
        rename = "lastConfigs",
        skip_serializing_if = "Option::is_none"
    )]
    pub last_configs: Option<BTreeMap<String, String>>,
}

impl WorkspaceConfig {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            id: new_id(),
            name: name.into(),
            icon: None,
            projects: Vec::new(),
            collapsed: None,
            stored_open: None,
            last_configs: None,
        }
    }

    pub fn is_collapsed(&self) -> bool {
        self.collapsed.unwrap_or(false)
    }

    pub fn is_stored_open(&self) -> bool {
        self.stored_open.unwrap_or(false)
    }

    /// Os projetos de cada lado da gaveta, na ordem em que você os deixou.
    pub fn active_projects(&self) -> impl Iterator<Item = &ProjectConfig> {
        self.projects.iter().filter(|p| !p.is_stored())
    }

    pub fn stored_projects(&self) -> impl Iterator<Item = &ProjectConfig> {
        self.projects.iter().filter(|p| p.is_stored())
    }

    /// A inicial do nome, maiúscula, para a pastilha sem imagem.
    pub fn initial(&self) -> String {
        let is_blank = |c: char| {
            c == ' '
                || c == '\t'
                || (c.is_whitespace() && !"\n\r\u{b}\u{c}\u{85}\u{2028}\u{2029}".contains(c))
        };
        self.name
            .trim_matches(is_blank)
            .chars()
            .next()
            .map(|c| c.to_uppercase().collect())
            .unwrap_or_default()
    }

    pub fn project_with_id(&self, id: &str) -> Option<&ProjectConfig> {
        self.projects.iter().find(|p| p.id == id)
    }

    pub fn project_owning(&self, path: &str, home: &str) -> Option<&ProjectConfig> {
        self.projects.iter().find(|p| p.owns(path, home))
    }

    /// Os projetos de pasta que um multi-projeto junta, na ordem dele. Membro
    /// que sumiu do workspace é pulado, e membro que também é multi-projeto não
    /// entra: o arquivo é editável à mão.
    pub fn members_of(&self, project: &ProjectConfig) -> Vec<&ProjectConfig> {
        project
            .members
            .iter()
            .flatten()
            .filter_map(|id| self.project_with_id(id))
            .filter(|member| !member.is_multi())
            .collect()
    }

    /// Guarda a escolha. Escolher o padrão da CLI também é escolha: apaga a
    /// lembrança, e o próximo terminal sugere o padrão.
    pub fn remember(&mut self, config: Option<&str>, agent: &str) {
        let mut map = self.last_configs.take().unwrap_or_default();
        match config {
            Some(config) => {
                map.insert(agent.to_owned(), config.to_owned());
            }
            None => {
                map.remove(agent);
            }
        }
        self.last_configs = if map.is_empty() { None } else { Some(map) };
    }
}

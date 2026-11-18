//! O "Novo projeto…" do workspace: onde sugerir e o que recusar (ADR-092).
//! Porte do `NewProject`.
//!
//! Antes só se adicionava pasta que já existia, e criar um repositório novo era
//! sair para o terminal, `mkdir`, `git init` e voltar ao formulário do
//! workspace. A pasta-mãe sugerida é a que os projetos do workspace já dividem:
//! quem tem três repositórios em `~/Documents/duck` cria o quarto ali.

use std::collections::HashMap;

use super::model::WorkspaceConfig;
use crate::features::path_text;

pub const FALLBACK_PARENT: &str = "~/Documents";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Problem {
    EmptyName,
    /// Barra vira subpasta e dois-pontos o Finder mostra como barra; ponto no
    /// começo esconde a pasta — nada disso é nome de projeto.
    InvalidName,
    MissingParent(String),
    /// Já há um ARQUIVO com esse nome: pasta existente é adotada, arquivo não.
    FileInTheWay(String),
    AlreadyProject(String),
}

impl Problem {
    pub fn message(&self) -> String {
        match self {
            Problem::EmptyName => "Dê um nome ao projeto.".to_owned(),
            Problem::InvalidName => {
                "O nome não pode ter \"/\" nem \":\", nem começar com ponto.".to_owned()
            }
            Problem::MissingParent(p) => format!("A pasta {p} não existe."),
            Problem::FileInTheWay(p) => format!("Já existe um arquivo em {p}."),
            Problem::AlreadyProject(name) => {
                format!("Essa pasta já é o projeto \"{name}\" deste workspace.")
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    /// Caminho com `~`, como o `workspaces.json` guarda.
    pub path: String,
    /// A pasta ainda não existe e vai ser criada; senão é adotada como está.
    pub create: bool,
}

/// O pai de um caminho, como o `deletingLastPathComponent`: a raiz fica na
/// raiz e um nome solto não tem pai.
fn parent_of(path: &str) -> String {
    let trimmed = path.trim_end_matches('/');
    match trimmed.rfind('/') {
        Some(0) => "/".to_owned(),
        Some(i) => trimmed[..i].to_owned(),
        None if path.starts_with('/') => "/".to_owned(),
        None => String::new(),
    }
}

/// A pasta-mãe mais comum entre os projetos de pasta do workspace; empate fica
/// com a do projeto mais recente, que é onde você mexeu por último. O
/// multi-projeto não conta: ele mora na pasta do app.
pub fn suggested_parent(workspace: &WorkspaceConfig, home: &str) -> String {
    let parents: Vec<String> = workspace
        .projects
        .iter()
        .filter(|p| !p.is_multi())
        .map(|p| parent_of(&path_text::normalize(&p.path, home)))
        .collect();
    if parents.is_empty() {
        return FALLBACK_PARENT.to_owned();
    }
    let mut count: HashMap<&str, usize> = HashMap::new();
    for parent in &parents {
        *count.entry(parent).or_default() += 1;
    }
    let best = count.values().copied().max().unwrap_or(0);
    let winner = parents
        .iter()
        .rev()
        .find(|p| count.get(p.as_str()) == Some(&best))
        .unwrap_or(&parents[parents.len() - 1]);
    path_text::abbreviate_tilde(winner, home)
}

/// `kind` diz o que há no caminho: `None` (nada), `Some(true)` (pasta) ou
/// `Some(false)` (arquivo). Entra como função para o teste não depender do
/// disco; o caminho chega com o `~` já expandido.
pub fn plan(
    name: &str,
    parent: &str,
    workspace: &WorkspaceConfig,
    home: &str,
    kind: impl Fn(&str) -> Option<bool>,
) -> Result<Plan, Problem> {
    let name = name.trim();
    if name.is_empty() {
        return Err(Problem::EmptyName);
    }
    if name.contains('/') || name.contains(':') || name.starts_with('.') {
        return Err(Problem::InvalidName);
    }
    let base = path_text::normalize(parent, home);
    if kind(&base) != Some(true) {
        return Err(Problem::MissingParent(path_text::abbreviate_tilde(
            &base, home,
        )));
    }
    let full = format!("{}/{name}", base.trim_end_matches('/'));
    let path = path_text::abbreviate_tilde(&full, home);
    if let Some(existing) = workspace.project_owning(&full, home) {
        return Err(Problem::AlreadyProject(existing.name.clone()));
    }
    let there = kind(&full);
    if there == Some(false) {
        return Err(Problem::FileInTheWay(path));
    }
    Ok(Plan {
        path,
        create: there.is_none(),
    })
}

/// O que há no caminho, no disco: `None` (nada), `Some(true)` (pasta) ou
/// `Some(false)` (arquivo).
pub fn disk_kind(path: &str) -> Option<bool> {
    std::fs::metadata(path).ok().map(|m| m.is_dir())
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum MaterializeError {
    #[error("não consegui criar {path}: {reason}")]
    Create { path: String, reason: String },
    #[error("git init falhou em {path}: {output}")]
    GitInit { path: String, output: String },
}

/// O que o "Novo projeto…" faz no disco: a pasta e, se pedido, o `git init`.
///
/// Pasta adotada que já é repositório fica como está: `git init` por cima de um
/// repositório não estraga nada, mas também não tem o que fazer. A pasta é criada
/// sem criar os pais — o pai existe, `plan` conferiu.
pub fn materialize(
    plan: &Plan,
    git_init: bool,
    home: &str,
    git: &crate::features::worktree::git::Git,
) -> Result<(), MaterializeError> {
    let folder = path_text::normalize(&plan.path, home);
    if plan.create {
        std::fs::create_dir(&folder).map_err(|e| MaterializeError::Create {
            path: plan.path.clone(),
            reason: e.to_string(),
        })?;
    }
    let dir = std::path::Path::new(&folder);
    if !git_init || dir.join(".git").exists() {
        return Ok(());
    }
    git.run(&["init", "--quiet"], dir)
        .map(|_| ())
        .map_err(|e| MaterializeError::GitInit {
            path: plan.path.clone(),
            output: e.to_string(),
        })
}

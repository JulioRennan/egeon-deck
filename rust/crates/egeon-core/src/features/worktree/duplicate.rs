//! Duplicar a bancada numa worktree, e abrir a de um multi-projeto. Porte do
//! que o `main.swift` faz por trás do `/worktree` e do menu — a parte sem tela
//! e sem estado do app: git, caminhos e a bancada que sai disso. Quem a põe na
//! lista, ativa e grava é o ator do core.

use std::collections::BTreeMap;
use std::io;
use std::path::Path;

use super::git::Git;
use super::model::{Created, Failure};
use super::node::{self, NodeWorktree};
use super::service;
use crate::commons::ids::{BranchName, WorkbenchName};
use crate::features::node::model::NodeConfig;
use crate::features::path_text;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workbench::service::colored_among;
use crate::features::workspace::links;
use crate::features::workspace::model::ProjectConfig;
use crate::features::workspace::multi::{branches, link_names, worktree_root};

/// `feature/PROJ-1234` viraria subdiretório e nome de bancada com barra:
/// achatado, é previsível e fácil de apagar (`Worktree.sanitize`).
pub fn sanitize(branch: &str) -> String {
    branch.replace('/', "-")
}

/// Os nós de uma bancada numa worktree nova, com a pasta de cada um apontando
/// para o lugar certo.
///
/// Um nó que ganhou worktree própria (`cwds`) abre nela. Os outros partem do
/// `cwd` que tinham, resolvido contra a raiz da origem: dentro da raiz vira
/// relativo (e vale na worktree nova); fora dela segue apontando para o mesmo
/// lugar, com aviso no log.
///
/// A versão anterior só olhava `cwd` começando com `/` ou `~`, e por isso
/// `../nexus-backend` atravessava a duplicação **literal**: na origem `..` era a
/// pasta de projetos, e na worktree passou a ser `worktrees/<repo>/`, que não
/// tem backend nenhum. O terminal abria na raiz da worktree em silêncio, e o
/// agente do backend trabalhava no frontend.
///
/// A conversa nunca vem junto: copiar um nó é copiar a montagem.
pub fn repointed(
    nodes: &[NodeConfig],
    origin_root: &str,
    cwds: &BTreeMap<String, String>,
    home: &str,
) -> Vec<NodeConfig> {
    nodes
        .iter()
        .cloned()
        .map(|node| {
            let mut node = node.without_conversation();
            if let Some(novo) = cwds.get(&node.id) {
                node.cwd = Some(novo.clone());
                return node;
            }
            let Some(cwd) = node.cwd.clone() else {
                return node;
            };
            let resolved = WorkbenchConfig::resolve(&cwd, origin_root, home);
            let inside = format!("{}/", origin_root.trim_end_matches('/'));
            if resolved == origin_root {
                node.cwd = None;
            } else if let Some(relative) = resolved.strip_prefix(&inside) {
                node.cwd = Some(relative.to_owned());
            } else {
                crate::log!(
                    "duplicar: nó \"{}\" abre fora do repositório ({cwd}) — segue apontando para \
                     {resolved}",
                    node.id
                );
                node.cwd = Some(node::short(&resolved, home));
            }
            node
        })
        .collect()
}

/// O que fazer com a worktree recém-criada.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Target {
    /// Bancada nova na lista; a de origem continua intacta e rodando.
    #[default]
    NewWorkbench,
    /// A bancada atual passa a apontar para a worktree. Os terminais são
    /// reiniciados lá — não há como trocar o diretório de um pty em curso.
    MoveCurrent,
}

/// O que a duplicação criou em disco, e como a bancada fica.
#[derive(Debug, Clone, PartialEq)]
pub struct Duplicated {
    pub created: Created,
    /// `created.path`, com `~`, como o `workbenches.json` o guarda.
    pub worktree_path: String,
    /// Os nós da origem, apontando para a worktree.
    pub nodes: Vec<NodeConfig>,
    /// As worktrees dos terminais que ganharam a sua, `(repo, pasta)`.
    pub extra_worktrees: Vec<(String, String)>,
}

impl Duplicated {
    /// O que copiar do que o git não versiona, na ordem. Worktree reaproveitada
    /// fica de fora: ela já tem o `.env` e as dependências dela, e passar por
    /// cima seria estragar o que se pediu para reusar.
    pub fn pending_copies(&self, repo_root: &str) -> Vec<(String, String)> {
        let mut out = Vec::new();
        if !self.created.reused {
            out.push((repo_root.to_owned(), self.created.path.clone()));
        }
        out.extend(self.extra_worktrees.iter().cloned());
        out
    }
}

/// A duplicação em si, sem diálogo: cria a worktree da bancada, depois as dos
/// terminais (a falha de uma vizinha não pode impedir a principal de existir) e
/// reaponta os nós.
///
/// Devolve o erro em vez de apresentá-lo: quem chamou sabe se há usuário
/// olhando.
pub fn duplicate(
    git: &Git,
    origin: &WorkbenchConfig,
    repo_root: &str,
    branch: &BranchName,
    node_plans: &[NodeWorktree],
    home: &str,
) -> Result<Duplicated, Failure> {
    let created = service::create(
        git,
        repo_root,
        branch.as_str(),
        &service::suggested_path(repo_root, branch),
        true,
    )?;

    let mut extra_worktrees = Vec::new();
    let node_cwds = node::materialize(git, node_plans, home, |repo, path| {
        extra_worktrees.push((repo.to_owned(), path.to_owned()));
    });

    let origin_root = origin.url_path(home);
    let nodes = repointed(&origin.nodes, &origin_root, &node_cwds, home);
    let worktree_path = path_text::abbreviate_tilde(&created.path, home);
    Ok(Duplicated {
        created,
        worktree_path,
        nodes,
        extra_worktrees,
    })
}

/// A bancada nova de uma duplicação.
///
/// As ligações vêm junto: elas são parte da montagem, tanto quanto os nós. A
/// aresta guarda id de nó, e a duplicação preserva os ids, então a rede da
/// worktree nasce igual à da origem. O modo vem junto pelo mesmo motivo: é
/// montagem, não estado de conversa. É do mesmo projeto que a origem: saiu dela.
pub fn new_workbench(
    origin: &WorkbenchConfig,
    duplicated: &Duplicated,
    existing: &[WorkbenchConfig],
) -> WorkbenchConfig {
    let taken: Vec<&str> = existing.iter().map(|w| w.name.as_str()).collect();
    let name = WorkbenchName::available(&sanitize(&duplicated.created.branch), &taken);
    let mut config = WorkbenchConfig::new(
        name.as_str(),
        duplicated.worktree_path.clone(),
        duplicated.nodes.clone(),
    );
    config.template = origin.template.clone();
    config.project = origin.project.clone();
    config.edges = origin.edges.clone();
    config.view = origin.view;
    colored_among(config, existing)
}

/// A bancada de origem apontada para a worktree (`Target::MoveCurrent`).
pub fn moved(origin: &WorkbenchConfig, duplicated: &Duplicated) -> WorkbenchConfig {
    let mut config = origin.clone();
    config.path = duplicated.worktree_path.clone();
    config.nodes = duplicated.nodes.clone();
    config
}

// ── Multi-projeto ──────────────────────────────────────────────────────────

/// O que abrir as worktrees de um multi-projeto deixou.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MultiOpened {
    /// A pasta que junta as worktrees.
    pub root: String,
    /// Os repositórios que recusaram, em texto para o alerta.
    pub failures: Vec<String>,
    /// O que copiar do não versionado, `(repo, worktree)`.
    pub pending: Vec<(String, String)>,
    /// Pelo menos um repositório aceitou, e portanto há bancada.
    pub any_opened: bool,
}

/// Bancada de multi-projeto em worktree: a mesma branch em cada repositório,
/// todas dentro de uma pasta só (ADR-065).
///
/// Repositório que recusa não derruba os outros: a bancada nasce com o que deu,
/// e o alerta diz o que faltou. `make_link(alvo, link)` põe o link quando a
/// branch já estava aberta em outro lugar — o git não deixa abrir de novo, e o
/// link é o que a põe aqui mesmo assim.
pub fn open_multi(
    git: &Git,
    project: &ProjectConfig,
    members: &[&ProjectConfig],
    branch: &str,
    overrides: &BTreeMap<String, String>,
    home: &str,
    make_link: &dyn Fn(&Path, &Path) -> io::Result<()>,
) -> MultiOpened {
    let link_list = link_names(members, home);
    let names: Vec<String> = link_list.iter().map(|l| l.name.clone()).collect();
    let per_link = branches(&names, branch, overrides);
    let root = worktree_root(project, members, branch, home);
    if let Err(error) = std::fs::create_dir_all(&root) {
        return MultiOpened {
            failures: vec![format!("{root}: {error}")],
            root,
            pending: Vec::new(),
            any_opened: false,
        };
    }

    let mut pending = Vec::new();
    let mut failures = Vec::new();
    for (link, member) in link_list.iter().zip(members) {
        let member_path = member.url_path(home);
        let repo_root = service::main_repo(git, &member_path).unwrap_or(member_path);
        let destination = format!("{root}/{}", link.name);
        let wanted = per_link.get(&link.name).map_or(branch, String::as_str);
        let opened =
            service::create(git, &repo_root, wanted, &destination, true).and_then(|created| {
                if created.path != destination {
                    make_link(Path::new(&created.path), Path::new(&destination)).map_err(|e| {
                        Failure::Git {
                            command: "ln -s".to_owned(),
                            output: e.to_string(),
                        }
                    })?;
                    crate::log!(
                        "multi-projeto: {} já estava aberta em {} — ligada",
                        link.name,
                        created.path
                    );
                }
                Ok(created)
            });
        match opened {
            Ok(created) if !created.reused => pending.push((repo_root, created.path)),
            Ok(_) => {}
            Err(error) => {
                crate::log!(
                    "multi-projeto: worktree de {} falhou — {error}",
                    member.name
                );
                failures.push(format!("{}: {error}", member.name));
            }
        }
    }
    if failures.len() >= members.len() {
        if let Some(line) = links::prune_root(Path::new(&root)) {
            crate::log!("{line}");
        }
        return MultiOpened {
            root,
            failures,
            pending,
            any_opened: false,
        };
    }
    MultiOpened {
        root,
        failures,
        pending,
        any_opened: true,
    }
}

/// A bancada de um multi-projeto em worktree. Os nós vêm da bancada de origem
/// (reapontados) ou do template; sem nenhum dos dois, nasce vazia.
pub fn multi_workbench(
    project_id: &str,
    branch: &str,
    root: &str,
    origin: Option<&WorkbenchConfig>,
    template: Option<(&str, Vec<NodeConfig>)>,
    existing: &[WorkbenchConfig],
    home: &str,
) -> WorkbenchConfig {
    let nodes = match (origin, &template) {
        (Some(o), _) => repointed(&o.nodes, &o.url_path(home), &BTreeMap::new(), home),
        (None, Some((_, nodes))) => nodes.clone(),
        (None, None) => Vec::new(),
    };
    let taken: Vec<&str> = existing.iter().map(|w| w.name.as_str()).collect();
    let name = WorkbenchName::available(&sanitize(branch), &taken);
    let mut config = WorkbenchConfig::new(
        name.as_str(),
        path_text::abbreviate_tilde(root, home),
        nodes,
    );
    config.template = origin
        .and_then(|o| o.template.clone())
        .or_else(|| template.map(|(name, _)| name.to_owned()));
    config.project = Some(project_id.to_owned());
    config.edges = origin.and_then(|o| o.edges.clone());
    config.rules = origin.and_then(|o| o.rules.clone());
    config.view = origin.and_then(|o| o.view);
    colored_among(config, existing)
}

//! A rota `/worktree` (`ControlSocket.swift:779`): worktree da bancada ou de um
//! terminal só, sem passar pelo diálogo — o que `makeWorktree` do `main.swift`
//! faz por trás.
//!
//! `GET /worktree?target=ws[/id]&branch=X[&nodes=back:fix/api,sub:spike]`.
//! `ws` duplica a bancada numa worktree nova, levando os terminais de repo
//! vizinho junto; `ws/id` leva só aquele terminal; em multi-projeto, uma
//! worktree por repositório. `nodes` customiza a branch de terminais (ou, em
//! multi-projeto, de repositórios); `back:` com branch vazia é o "não me leve".
//!
//! Diferente dos outros handlers, esta função é BLOQUEANTE e trabalha sobre uma
//! cópia do estado: ela chama o git, que leva de segundos a minutos. O core a
//! roda em `spawn_blocking` com um [`OrgSnapshot`] e aplica os [`WorktreeEffect`]
//! no ator — quem põe a bancada na lista, ativa, grava e copia o não versionado.

use std::collections::BTreeMap;
use std::io;
use std::path::Path;

use serde_json::json;

use super::duplicate::{self, Duplicated};
use super::git::Git;
use super::node::{self, NodeWorktree};
use super::service;
use crate::commons::ids::BranchName;
use crate::features::workbench::model::{WorkbenchConfig, WorkbenchTemplate};
use crate::features::workspace::model::WorkspaceConfig;
use crate::protocol::handler::{RouteReply, RouteRequest};

/// O que a rota precisa saber da organização, copiado do ator.
#[derive(Debug, Clone)]
pub struct OrgSnapshot {
    pub workbenches: Vec<WorkbenchConfig>,
    pub workspaces: Vec<WorkspaceConfig>,
}

/// O que o ator faz depois que a rota respondeu.
#[derive(Debug, Clone, PartialEq)]
pub enum WorktreeEffect {
    /// Bancada nova: entra no fim da lista, é conciliada com os projetos,
    /// ativada e gravada; depois `copies` (`(repo, worktree)`) recebem o que o
    /// git não versiona, uma de cada vez.
    AddWorkbench {
        config: WorkbenchConfig,
        copies: Vec<(String, String)>,
    },
    /// Um terminal passa a abrir na worktree: o nó (já sem a conversa e com o
    /// `cwd` novo) troca o antigo, e o terminal é refeito — um pty não muda de
    /// diretório depois de aberto. Se o terminal não está de pé, não há o que
    /// refazer e a rota responde como o Swift responde.
    RepointNode {
        workbench_id: String,
        node: Box<crate::features::node::model::NodeConfig>,
        copies: Vec<(String, String)>,
    },
    /// A bancada de origem passa a apontar para a worktree (`Target::MoveCurrent`):
    /// os nós já vêm reapontados, e todos os terminais são refeitos lá.
    MoveWorkbench {
        config: WorkbenchConfig,
        copies: Vec<(String, String)>,
    },
}

/// O que o formulário escolheu além da branch (decisão 37).
#[derive(Debug, Clone, Default)]
pub struct FormChoice {
    pub destination: duplicate::Target,
    /// A bancada nova nasce deste template (nome e conteúdo), e não dos nós da
    /// origem — é o "Nova bancada em worktree" do formulário sem origem.
    pub template: Option<(String, WorkbenchTemplate)>,
}

/// `deck/back` → (`deck`, `Some("back")`); `deck` e `deck/` → (`deck`, `None`).
/// Barra no começo some e o resto depois da primeira barra é o nó, como o
/// `split(maxSplits: 1)` do Swift.
fn split_target(target: &str) -> Option<(&str, Option<&str>)> {
    let s = target.trim_start_matches('/');
    if s.is_empty() {
        return None;
    }
    Some(match s.split_once('/') {
        Some((bench, node)) if !node.is_empty() => (bench, Some(node)),
        Some((bench, _)) => (bench, None),
        None => (s, None),
    })
}

/// `back:fix/api,sub:spike` → `{back: fix/api, sub: spike}`. `back:` é a branch
/// vazia; um par sem id é pulado.
fn node_branches(raw: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for pair in raw.split(',').filter(|p| !p.is_empty()) {
        // O split do Swift omite os vazios: `:x` é o id `x` sem branch.
        let trimmed = pair.trim_start_matches(':');
        let (id, branch) = match trimmed.split_once(':') {
            Some((id, branch)) => (id, branch),
            None => (trimmed, ""),
        };
        if !id.is_empty() {
            out.insert(id.to_owned(), branch.to_owned());
        }
    }
    out
}

fn failed(error: impl std::fmt::Display) -> RouteReply {
    RouteReply::err(400, error.to_string())
}

fn branch_or_suggested(git: &Git, branch: &str, current: &str, repo_root: &str) -> String {
    if branch.is_empty() {
        service::available_branch(git, current, repo_root)
    } else {
        branch.to_owned()
    }
}

/// A rota. `make_link(alvo, link)` é o `symlink` do sistema (multi-projeto cuja
/// branch já estava aberta em outro lugar).
pub fn worktree(
    req: &RouteRequest,
    org: &OrgSnapshot,
    home: &str,
    git: &Git,
    make_link: &dyn Fn(&Path, &Path) -> io::Result<()>,
) -> (RouteReply, Vec<WorktreeEffect>) {
    worktree_with(req, org, home, git, make_link, &FormChoice::default())
}

/// A rota com as escolhas do formulário. `choice` só vale para a bancada de um
/// repositório só: terminal e multi-projeto seguem o caminho deles.
pub fn worktree_with(
    req: &RouteRequest,
    org: &OrgSnapshot,
    home: &str,
    git: &Git,
    make_link: &dyn Fn(&Path, &Path) -> io::Result<()>,
    choice: &FormChoice,
) -> (RouteReply, Vec<WorktreeEffect>) {
    let target = req.param("target").unwrap_or("");
    let branch = req.param("branch").unwrap_or("");
    let nodes = node_branches(req.param("nodes").unwrap_or(""));

    let Some((bench_name, node_id)) = split_target(target) else {
        return (failed(format!("bancada desconhecida '{target}'")), vec![]);
    };
    let Some(origin) = org.workbenches.iter().find(|w| w.name == bench_name) else {
        return (failed(format!("bancada desconhecida '{target}'")), vec![]);
    };

    if let Some(node_id) = node_id {
        return for_node(git, origin, node_id, branch, home);
    }

    let project = origin
        .project
        .as_deref()
        .and_then(|id| {
            org.workspaces
                .iter()
                .find_map(|w| w.project_with_id(id).map(|p| (w, p)))
        })
        .filter(|(_, p)| p.is_multi());
    if let Some((space, project)) = project {
        if branch.is_empty() {
            return (failed("multi-projeto pede branch"), vec![]);
        }
        let members = space.members_of(project);
        let opened = duplicate::open_multi(git, project, &members, branch, &nodes, home, make_link);
        let mut effects = Vec::new();
        let mut name = String::new();
        if opened.any_opened {
            let config = duplicate::multi_workbench(
                &project.id,
                branch,
                &opened.root,
                Some(origin),
                None,
                &org.workbenches,
                home,
            );
            name.clone_from(&config.name);
            effects.push(WorktreeEffect::AddWorkbench {
                config,
                copies: opened.pending,
            });
        }
        let json = json!({"ok": opened.any_opened, "path": opened.root, "failed": opened.failures, "workbench": name});
        let status = if opened.any_opened { 200 } else { 400 };
        return (RouteReply::with_status(status, json), effects);
    }

    for_workbench(git, origin, org, branch, &nodes, home, choice)
}

/// `ws/id`: o repositório é o da pasta em que o terminal abre, que pode ser
/// vizinho. Sempre pelo checkout principal — partir de uma worktree ligada
/// aninharia worktree dentro de worktree. O nome pedido vai como veio: se a
/// branch já existe, é nela que o terminal abre (ADR-018); só o vazio é
/// sugerido pelo app.
fn for_node(
    git: &Git,
    origin: &WorkbenchConfig,
    node_id: &str,
    branch: &str,
    home: &str,
) -> (RouteReply, Vec<WorktreeEffect>) {
    let Some(node) = origin.nodes.iter().find(|n| n.id == node_id) else {
        return (failed(format!("nó desconhecido '{node_id}'")), vec![]);
    };
    let directory = origin.directory(node, home);
    if let Some(warning) = &directory.warning {
        crate::log!("{warning}");
    }
    let current = directory.path;
    let Some(repo_root) = service::main_repo(git, &current) else {
        return (failed(format!("{current} não é repositório git")), vec![]);
    };
    let Ok(status) = service::status(git, &repo_root) else {
        return (failed(format!("{current} não é repositório git")), vec![]);
    };

    let name = branch_or_suggested(git, branch, &status.branch, &repo_root);
    let Ok(valid) = BranchName::new(name.as_str()) else {
        return (failed(format!("branch inválida '{name}'")), vec![]);
    };
    let destination = service::suggested_path(&repo_root, &valid);
    let created = match service::create(git, &repo_root, &name, &destination, true) {
        Ok(created) => created,
        Err(error) => return (failed(error), vec![]),
    };

    // Sem a conversa: ela é da pasta antiga, e retomá-la aqui traria o agente no
    // meio de um assunto que era de outro checkout.
    let mut updated = node.clone().without_conversation();
    updated.cwd = Some(node::short(&created.path, home));
    crate::log!(
        "worktree por terminal: \"{node_id}\" de {} passou a abrir em {} (branch {}){}",
        origin.name,
        created.path,
        created.branch,
        if created.reused {
            " — worktree que já existia"
        } else {
            ""
        }
    );
    let copies = if created.reused {
        Vec::new()
    } else {
        vec![(repo_root.clone(), created.path.clone())]
    };
    let reply = RouteReply::ok(json!({
        "ok": true, "node": node_id, "repo": repo_root,
        "branch": name, "path": created.path, "reused": created.reused,
    }));
    let effect = WorktreeEffect::RepointNode {
        workbench_id: origin.id.clone(),
        node: Box::new(updated),
        copies,
    };
    (reply, vec![effect])
}

/// `ws`: duplica a bancada, levando junto os terminais de repo vizinho.
fn for_workbench(
    git: &Git,
    origin: &WorkbenchConfig,
    org: &OrgSnapshot,
    branch: &str,
    custom: &BTreeMap<String, String>,
    home: &str,
    choice: &FormChoice,
) -> (RouteReply, Vec<WorktreeEffect>) {
    let origin_path = origin.url_path(home);
    let (Some(repo_root), Ok(status)) = (
        service::main_repo(git, &origin_path),
        service::status(git, &origin_path),
    ) else {
        return (
            failed(format!("{} não é repositório git", origin.path)),
            vec![],
        );
    };
    let name = branch_or_suggested(git, branch, &status.branch, &repo_root);

    // Cada terminal herda a branch da bancada, e `nodes` sobrescreve quem foi
    // pedido — é o mesmo que digitar na linha dele. A decisão de quem ganha
    // worktree própria sai daí, e não de uma marcação separada.
    let plans: Vec<NodeWorktree> = node::inspect(git, origin, &origin_path, &name, home)
        .into_iter()
        .filter(|_| choice.template.is_none())
        .map(|mut plan| {
            if let Some(own) = custom.get(&plan.node_id) {
                plan.branch.clone_from(own);
                plan.touched = true;
            }
            plan.decided(&name)
        })
        .collect();

    let Ok(valid) = BranchName::new(name.as_str()) else {
        return (failed(format!("branch inválida '{name}'")), vec![]);
    };
    let done: Duplicated = match duplicate::duplicate(git, origin, &repo_root, &valid, &plans, home)
    {
        Ok(done) => done,
        Err(error) => return (failed(error), vec![]),
    };
    let copies = done.pending_copies(&repo_root);
    if choice.destination == duplicate::Target::MoveCurrent {
        let config = duplicate::moved(origin, &done);
        let reply = RouteReply::ok(json!({
            "ok": true,
            "workbench": config.name,
            "branch": name,
            "path": config.url_path(home),
        }));
        return (
            reply,
            vec![WorktreeEffect::MoveWorkbench { config, copies }],
        );
    }
    let mut done = done;
    if let Some((_, template)) = &choice.template {
        done.nodes = template.instantiate();
    }
    let mut config = duplicate::new_workbench(origin, &done, &org.workbenches);
    if let Some((template_name, template)) = &choice.template {
        // Nasce do molde, e não da origem: nem ligações nem modo vêm dela.
        config.template = Some(template_name.clone());
        config.edges = None;
        config.view = template.view;
    }
    // A pasta vem da bancada que acabou de nascer, e não do caminho sugerido:
    // com branch que já existe a worktree pode ser outra, e é justamente isso que
    // quem chamou precisa poder conferir.
    //
    // O Swift escreve a chave "workbench" duas vezes no mesmo literal (a da
    // origem e a da nova); o literal com chave repetida é erro de execução lá, e
    // a rota nunca respondeu. Aqui vale a intenção: a bancada nova.
    let reply = RouteReply::ok(json!({
        "ok": true,
        "workbench": config.name,
        "branch": name,
        "path": config.url_path(home),
        "nodes": plans.iter().filter(|p| p.enabled)
            .map(|p| json!({"id": p.node_id, "repo": p.repo_name()})).collect::<Vec<_>>(),
    }));
    (reply, vec![WorktreeEffect::AddWorkbench { config, copies }])
}

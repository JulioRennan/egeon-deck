//! Bancada nova numa worktree de uma pasta, sem bancada de origem
//! (`createWorkbenchFromWorktree` do `main.swift`): o repositório vem de um
//! projeto da barra lateral ou de uma pasta escolhida, a worktree sai do HEAD
//! dele em uma branch, e a bancada nasce lá com os nós de um template (ou
//! vazia). Multi-projeto abre uma worktree por repositório, como na rota
//! `/worktree`.
//!
//! BLOQUEANTE, como [`super::routes::worktree`]: o git leva de segundos a
//! minutos, e o ator aplica o [`WorktreeEffect`] que sai daqui.

use std::io;
use std::path::Path;

use serde_json::json;

use super::duplicate;
use super::git::Git;
use super::routes::{OrgSnapshot, WorktreeEffect};
use super::service;
use crate::commons::ids::{BranchName, WorkbenchName};
use crate::features::path_text;
use crate::features::workbench::model::{WorkbenchConfig, WorkbenchTemplate};
use crate::features::workbench::service::colored_among;
use crate::protocol::handler::RouteReply;

/// De onde sai o repositório.
#[derive(Debug, Clone, Copy, Default)]
pub struct Source<'a> {
    /// A pasta do repositório (`~` aceito).
    pub path: Option<&'a str>,
    /// O projeto da barra lateral em que a bancada nasce. Sem `path`, o
    /// repositório é a pasta dele.
    pub project: Option<&'a str>,
}

fn failed(error: impl std::fmt::Display) -> (RouteReply, Vec<WorktreeEffect>) {
    (RouteReply::err(400, error.to_string()), Vec::new())
}

pub fn from_folder(
    git: &Git,
    org: &OrgSnapshot,
    source: Source<'_>,
    branch: &str,
    template: Option<&(String, WorkbenchTemplate)>,
    home: &str,
    make_link: &dyn Fn(&Path, &Path) -> io::Result<()>,
) -> (RouteReply, Vec<WorktreeEffect>) {
    let project = match source.project {
        Some(id) => match org
            .workspaces
            .iter()
            .find_map(|w| w.project_with_id(id).map(|p| (w, p)))
        {
            Some(found) => Some(found),
            None => return failed(format!("projeto desconhecido '{id}'")),
        },
        None => None,
    };

    if let Some((space, project)) = project.filter(|(_, p)| p.is_multi()) {
        if branch.is_empty() {
            return failed("multi-projeto pede branch");
        }
        let members = space.members_of(project);
        if members.is_empty() {
            return failed(format!("\"{}\" não junta pasta nenhuma", project.name));
        }
        let opened = duplicate::open_multi(
            git,
            project,
            &members,
            branch,
            &Default::default(),
            home,
            make_link,
        );
        let mut effects = Vec::new();
        let mut name = String::new();
        if opened.any_opened {
            let config = duplicate::multi_workbench(
                &project.id,
                branch,
                &opened.root,
                None,
                template.map(|(n, t)| (n.as_str(), t.instantiate())),
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

    let folder = match (source.path, project) {
        (Some(path), _) => path_text::normalize(path, home),
        (None, Some((_, project))) => project.url_path(home),
        (None, None) => return failed("pede a pasta do repositório"),
    };
    let not_a_repo = || failed(format!("{folder} não é repositório git"));
    let Ok(status) = service::status(git, &folder) else {
        return not_a_repo();
    };
    // Do checkout principal, mesmo que a pasta já seja uma worktree: sair dela
    // aninharia uma worktree dentro da outra.
    let repo_root = service::main_repo(git, &folder).unwrap_or_else(|| status.repo_root.clone());
    let name = if branch.is_empty() {
        service::available_branch(git, &status.branch, &repo_root)
    } else {
        branch.to_owned()
    };
    let Ok(valid) = BranchName::new(name.as_str()) else {
        return failed(format!("branch inválida '{name}'"));
    };
    let created = match service::create(
        git,
        &repo_root,
        &name,
        &service::suggested_path(&repo_root, &valid),
        true,
    ) {
        Ok(created) => created,
        Err(error) => return failed(error),
    };

    let taken: Vec<&str> = org.workbenches.iter().map(|w| w.name.as_str()).collect();
    let bench_name = WorkbenchName::available(&duplicate::sanitize(&created.branch), &taken);
    let nodes = template.map_or_else(Vec::new, |(_, t)| t.instantiate());
    let mut config = WorkbenchConfig::new(
        bench_name.as_str(),
        path_text::abbreviate_tilde(&created.path, home),
        nodes,
    );
    if let Some((template_name, preset)) = template {
        config.template = Some(template_name.clone());
        config.view = preset.view;
    }
    config.project = source.project.map(str::to_owned);
    let config = colored_among(config, &org.workbenches);
    // Worktree reaproveitada não é copiada: ela já tem o `.env` e as
    // dependências dela.
    let copies = if created.reused {
        Vec::new()
    } else {
        vec![(repo_root, created.path.clone())]
    };
    let reply = RouteReply::ok(json!({
        "ok": true, "workbench": config.name, "branch": name, "path": created.path,
    }));
    (reply, vec![WorktreeEffect::AddWorkbench { config, copies }])
}

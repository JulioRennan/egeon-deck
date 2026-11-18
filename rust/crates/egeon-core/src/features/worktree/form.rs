//! As leituras do formulário de worktree (decisão 37): o que a tela mostra antes
//! de criar nada. `worktree_info` descreve a bancada e o que acontece com cada
//! terminal; `worktree_plan` diz, a cada tecla, o que o nome de branch digitado
//! vai fazer (ADR-018). Só lê: git roda fora do ator e nada é escrito.

use super::git::Git;
use super::model::{BranchPlan, Status};
use super::node;
use super::service;
use crate::commons::ids::{BranchName, NodeId};
use crate::features::path_text;
use crate::features::workbench::model::WorkbenchConfig;
use crate::protocol::org::{
    BranchVerdict, WorktreeInfo, WorktreeNode, WorktreeNodeState, WorktreePlan,
};

/// O repositório da bancada: o checkout principal, mesmo que ela já esteja numa
/// worktree — partir de uma worktree ligada aninharia uma dentro da outra.
fn repository(
    git: &Git,
    origin: &WorkbenchConfig,
    home: &str,
) -> Result<(String, Status, String), String> {
    let path = origin.url_path(home);
    let not_a_repo = || format!("{} não é repositório git", origin.path);
    let status = service::status(git, &path).map_err(|_| not_a_repo())?;
    let root = service::main_repo(git, &path).unwrap_or_else(|| status.repo_root.clone());
    Ok((root, status, path))
}

/// O que vai junto, em linhas. De onde a worktree sai e o que acontece com as
/// mudanças não commitadas dependem da branch digitada, e ficam em
/// [`BranchPlan::summary`]: repetir aqui contradiria essa linha na metade dos
/// casos.
fn summary(status: &Status, copy_script: &str) -> String {
    let mut lines = Vec::new();
    if !status.untracked.is_empty() {
        lines.push(format!(
            "{} arquivo(s) novo(s) vão junto.",
            status.untracked.len()
        ));
    }
    // "Quando a worktree nasce" porque ela pode ser uma que já existe, e ali
    // nada é copiado: sobrescrever o `.env` de uma pasta com trabalho dentro
    // estragaria o que se pediu para reaproveitar.
    lines.push(format!(
        "Quando a worktree nasce, o que o .gitignore esconde (.env, node_modules, build…) é \
         copiado depois, por {copy_script}."
    ));
    lines.join("\n")
}

/// `worktree_info`: o resumo, a branch que o app sugere e o estado de cada
/// terminal com pasta (nó `web` não abre pasta).
pub fn info(
    git: &Git,
    origin: &WorkbenchConfig,
    home: &str,
    copy_script: &str,
) -> Result<WorktreeInfo, String> {
    let (root, status, path) = repository(git, origin, home)?;
    let suggested = service::available_branch(git, &status.branch, &root);
    let nodes = node::inspect(git, origin, &path, &suggested, home)
        .into_iter()
        .filter_map(|plan| {
            let plan = plan.decided(&suggested);
            let state = if plan.enabled {
                WorktreeNodeState::OwnWorktree
            } else if plan.repo_root.is_some() {
                WorktreeNodeState::FollowsWorkbench
            } else {
                WorktreeNodeState::NoRepo
            };
            // Id que não cabe no protocolo (um `nodes.json` antigo, escrito à mão)
            // fica de fora da lista em vez de derrubar o formulário.
            Some(WorktreeNode {
                branch: plan.enabled.then(|| plan.branch.clone()),
                node: NodeId::new(plan.node_id.as_str()).ok()?,
                state,
            })
        })
        .collect();
    Ok(WorktreeInfo {
        summary: summary(&status, copy_script),
        suggested_branch: suggested,
        nodes,
    })
}

/// `worktree_plan`: o veredito do nome, a pasta que vai ser usada e a linha que
/// o formulário mostra embaixo do campo.
pub fn plan(
    git: &Git,
    origin: &WorkbenchConfig,
    branch: &str,
    home: &str,
) -> Result<WorktreePlan, String> {
    let (root, status, _) = repository(git, origin, home)?;
    let plan = service::index(git, &root).plan(branch);
    let folder = match &plan {
        BranchPlan::AlreadyCheckedOut(path) => path.clone(),
        _ => {
            let valid =
                BranchName::new(branch).map_err(|_| format!("branch inválida '{branch}'"))?;
            service::suggested_path(&root, &valid)
        }
    };
    let verdict = match plan {
        BranchPlan::New => BranchVerdict::Create,
        BranchPlan::ExistingLocal => BranchVerdict::OpenExisting,
        BranchPlan::Remote(_) => BranchVerdict::FollowRemote,
        BranchPlan::AlreadyCheckedOut(_) => BranchVerdict::AlreadyOpen,
    };
    Ok(WorktreePlan {
        verdict,
        folder: path_text::abbreviate_tilde(&folder, home),
        message: Some(plan.summary(&status.branch, status.is_dirty(), home)),
    })
}

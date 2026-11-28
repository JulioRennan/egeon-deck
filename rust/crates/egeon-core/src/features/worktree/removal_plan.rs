//! O que remover uma bancada leva do disco: as worktrees que ela usa, o que cada
//! uma perde e a resposta da rota `/remove`. Porte do `worktrees(of:)`, do
//! `lossLines` e do `payload` do `removeWorkbench(named:)` do `main.swift`.
//!
//! É git em cada pasta: síncrono e bloqueante, para o ator chamar de fora dele.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::{Value, json};

use super::git::Git;
use super::service;
use crate::features::node::model::NodeKind;
use crate::features::path_text;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workbench::removal::Removal;
use crate::features::workspace::links;
use crate::features::workspace::model::ProjectConfig;

/// Uma worktree que esta bancada usa.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BenchWorktree {
    pub path: String,
    /// O nome do repositório principal.
    pub repo: String,
    pub branch: Option<String>,
    /// Quem dentro da bancada abre nela: "bancada", ou os ids dos nós.
    pub owners: Vec<String>,
    /// Outra bancada que abre esta MESMA pasta. Apagar levaria o trabalho dela, e
    /// ela continuaria na lista apontando para o vazio.
    pub used_by: Option<String>,
}

/// O que o levantamento precisa saber do resto do app, tirado do ator: ele roda
/// fora dele e não pode ler a lista de bancadas.
#[derive(Debug, Clone, Default)]
pub struct RemovalContext {
    pub is_multi: bool,
    /// Nome e pasta das OUTRAS bancadas.
    pub others: Vec<(String, String)>,
}

/// Toda worktree ligada que a bancada usa: a pasta dela e a de cada nó que abre
/// fora dela.
///
/// Nó dentro da pasta da bancada não entra: é a mesma worktree, e apagá-la duas
/// vezes daria erro na segunda. Só worktree LIGADA — oferecer apagar o checkout
/// principal seria oferecer apagar o repositório.
pub fn involved(
    git: &Git,
    config: &WorkbenchConfig,
    context: &RemovalContext,
    home: &str,
) -> Vec<BenchWorktree> {
    let mut owners: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let root = config.url_path(home);

    if config.exists(home) && service::is_linked_worktree(git, &root) {
        owners.insert(root.clone(), vec!["bancada".to_owned()]);
    }

    // Bancada de multi-projeto em worktree: a raiz não é repositório, e cada
    // subpasta é uma worktree. Link não entra — é a pasta de links do checkout
    // principal, ou uma worktree de outro lugar reaproveitada, e nenhuma das
    // duas é desta bancada para apagar (ADR-065).
    if context.is_multi && !service::is_linked_worktree(git, &root) {
        for child in links::real_subfolders(Path::new(&root)) {
            if service::is_linked_worktree(git, &child) {
                owners.insert(child, vec!["bancada".to_owned()]);
            }
        }
    }

    for node in config.nodes.iter().filter(|n| n.kind != NodeKind::Web) {
        let path = config.resolved_directory(node, home);
        if path == root
            || path_text::inside(&path, &root).is_some()
            || !Path::new(&path).exists()
            || !service::is_linked_worktree(git, &path)
        {
            continue;
        }
        owners.entry(path).or_default().push(node.id.clone());
    }

    owners
        .into_iter()
        .map(|(path, owners)| {
            let main = service::main_repo(git, &path).unwrap_or_else(|| path.clone());
            BenchWorktree {
                repo: path_text::last_component(&main),
                branch: service::branch_of(git, &path),
                used_by: context
                    .others
                    .iter()
                    .find(|(_, other)| *other == path)
                    .map(|(name, _)| name.clone()),
                path,
                owners,
            }
        })
        .collect()
}

/// O que cada worktree perde, em linhas para o alerta. Uma seção por worktree:
/// com três repositórios envolvidos, somar os números num total só não diria em
/// qual deles está o trabalho que você não quer perder.
pub fn loss_lines(git: &Git, worktrees: &[BenchWorktree]) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for wt in worktrees {
        let Ok(losses) = service::losses(git, &wt.path) else {
            continue;
        };
        if losses.is_empty() {
            continue;
        }
        let branch = wt.branch.as_deref().unwrap_or("?");
        if !lines.is_empty() {
            lines.push(String::new());
        }
        lines.push(format!("{} · {branch}", wt.repo));
        if !losses.modified.is_empty() {
            lines.push(format!(
                "{} arquivo(s) com mudanças não commitadas:",
                losses.modified.len()
            ));
            lines.extend(losses.modified.iter().take(6).map(|m| format!("   {m}")));
            if losses.modified.len() > 6 {
                lines.push(format!("   … e outros {}", losses.modified.len() - 6));
            }
        }
        if !losses.untracked.is_empty() {
            lines.push(format!(
                "{} arquivo(s) novo(s), nunca commitados.",
                losses.untracked.len()
            ));
        }
        if losses.unpushed_commits > 0 {
            lines.push(format!(
                "{} commit(s) ainda não enviados — esses sobrevivem na branch {branch}, que \
                 não é apagada.",
                losses.unpushed_commits
            ));
        }
    }
    lines
}

/// A pasta-mãe de uma bancada multi-projeto em worktree, para sair junto com as
/// worktrees de dentro. A do checkout principal é a pasta de links do projeto, e
/// fica.
pub fn multi_roots(
    config: &WorkbenchConfig,
    project: Option<&ProjectConfig>,
    home: &str,
) -> Vec<PathBuf> {
    match project {
        Some(p) if p.is_multi() && !p.owns(&config.url_path(home), home) => {
            vec![PathBuf::from(config.url_path(home))]
        }
        _ => Vec::new(),
    }
}

/// O corpo da resposta de `/remove` (e do comando equivalente).
///
/// `outcome` é `None` quando nada foi apagado do disco (`worktrees` desligado).
pub fn payload(name: &str, involved: &[BenchWorktree], outcome: Option<&Removal>) -> Value {
    let mut out = json!({
        "workbench": name,
        "removed": outcome.map_or_else(Vec::new, |o| o.removed.iter().map(|t| t.path.clone()).collect()),
        "sweeping": outcome.map_or_else(Vec::new, |o| o.leftovers.clone()),
        "kept": involved.iter().filter(|w| w.used_by.is_some())
            .map(|w| json!({"path": w.path, "usedBy": w.used_by.clone().unwrap_or_default()}))
            .collect::<Vec<_>>(),
        "worktrees": involved.iter().map(|w| json!({
            "path": w.path, "repo": w.repo, "branch": w.branch.clone().unwrap_or_default(),
            "owners": w.owners,
        })).collect::<Vec<_>>(),
    });
    match outcome {
        Some(o) if !o.succeeded() => {
            out["ok"] = Value::Bool(false);
            out["error"] = Value::String("worktree não removida".to_owned());
            out["failed"] = Value::Array(
                o.failures
                    .iter()
                    .map(|(t, e)| Value::String(format!("{}: {e}", t.path)))
                    .collect(),
            );
        }
        _ => out["ok"] = Value::Bool(true),
    }
    out
}

//! A conciliação: toda bancada tem projeto, e há sempre um workspace.

use super::model::{ProjectConfig, WorkspaceConfig};
use crate::features::workbench::model::WorkbenchConfig;

/// Nome do workspace que nasce sozinho na primeira carga. Quem já tinha
/// bancadas não escolheu workspace nenhum, e elas precisam de um teto.
pub const DEFAULT_NAME: &str = "Geral";

#[derive(Debug, Clone, PartialEq)]
pub struct Reconciled {
    pub workspaces: Vec<WorkspaceConfig>,
    pub workbenches: Vec<WorkbenchConfig>,
    /// Alguma coisa mudou e precisa ir para o disco.
    pub changed: bool,
    /// O que foi decidido sem você, para o log.
    pub notes: Vec<String>,
}

/// Dá projeto a toda bancada que não tem um, criando o que faltar.
///
/// Roda na carga e depois de toda bancada criada por caminho livre. A regra de
/// pertencimento é uma só: a bancada é do projeto cuja pasta é o repositório
/// principal dela — `main_repo` resolve worktree para o checkout de origem, e
/// entra como função porque é git, e o teste não quer git.
///
/// Bancada com `project` apontando para id que não existe mais é tratada como
/// sem projeto: o arquivo é editável à mão e o id pode ter sido apagado.
pub fn reconcile(
    workspaces: &[WorkspaceConfig],
    workbenches: &[WorkbenchConfig],
    home: &str,
    main_repo: impl Fn(&str) -> Option<String>,
) -> Reconciled {
    let mut spaces = workspaces.to_vec();
    let mut benches = workbenches.to_vec();
    let mut changed = false;
    let mut notes = Vec::new();

    if spaces.is_empty() {
        spaces.push(WorkspaceConfig::new(DEFAULT_NAME));
        changed = true;
        notes.push(format!("workspace \"{DEFAULT_NAME}\" criado"));
    }

    let has_project = |spaces: &[WorkspaceConfig], id: &str| {
        spaces.iter().any(|s| s.project_with_id(id).is_some())
    };
    let project_owning = |spaces: &[WorkspaceConfig], path: &str| {
        spaces
            .iter()
            .find_map(|s| s.project_owning(path, home))
            .map(|p| p.id.clone())
    };

    for bench in &mut benches {
        if bench
            .project
            .as_deref()
            .is_some_and(|id| has_project(&spaces, id))
        {
            continue;
        }

        let path = bench.url_path(home);
        let root = main_repo(&path).unwrap_or(path);
        if let Some(id) = project_owning(&spaces, &root) {
            bench.project = Some(id);
            changed = true;
            continue;
        }

        let project = ProjectConfig::for_folder(&root, home);
        notes.push(format!(
            "projeto \"{}\" criado em \"{}\" para a bancada \"{}\"",
            project.name, spaces[0].name, bench.name
        ));
        bench.project = Some(project.id.clone());
        spaces[0].projects.push(project);
        changed = true;
    }

    Reconciled {
        workspaces: spaces,
        workbenches: benches,
        changed,
        notes,
    }
}

//! A legalidade de um arrasto na barra lateral: onde cada coisa pode cair e o
//! que a árvore vira. Porte do `switch (drag.item, target)` do
//! `Sidebar.handle(_:)` e do que o `WorkspaceMove` decide.
//!
//! A geometria — do pixel ao "dentro de qual pai, nesta posição" (a conta de
//! quantos meios ficam acima do cursor, descontando a própria linha, a tampa
//! da gaveta, o vão entre cartões) — é da tela, que é quem sabe onde cada
//! linha está desenhada. O core recebe o resultado, um [`Drop`], e diz se ele
//! vale e como fica a árvore: bancada só cai em projeto, projeto só em
//! workspace, e workspace entre workspaces — a árvore não muda de forma no
//! arrasto.

use super::model::WorkspaceConfig;
use super::reorder::{self, WorkbenchMove};
use super::tree::SidebarItem;
use crate::features::workbench::model::WorkbenchConfig;

/// Onde uma linha arrastada cai.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Drop {
    Workspace {
        position: usize,
    },
    /// `stored` diz de que lado da gaveta o projeto cai (ADR-052).
    Project {
        workspace_id: String,
        position: usize,
        stored: bool,
    },
    Workbench {
        project_id: String,
        position: usize,
    },
}

/// Como a árvore fica depois de um arrasto que vale.
#[derive(Debug, Clone, PartialEq)]
pub enum Landed {
    /// Workspace ou projeto mudou de lugar: a lista de workspaces nova.
    Workspaces(Vec<WorkspaceConfig>),
    /// Bancada mudou de lugar: a lista nova e o mapa dos índices.
    Workbenches(WorkbenchMove),
}

/// O que acontece quando `item` é solto em `target`. `None` é o arrasto que não
/// vale — tipo que não casa, algo que não existe, ou o mesmo lugar em que já
/// estava — e nada muda.
pub fn plan_move(
    workspaces: &[WorkspaceConfig],
    workbenches: &[WorkbenchConfig],
    item: &SidebarItem,
    target: &Drop,
) -> Option<Landed> {
    match (item, target) {
        (SidebarItem::Workspace { id }, Drop::Workspace { position }) => {
            reorder::workspace(id, *position, workspaces).map(Landed::Workspaces)
        }
        (
            SidebarItem::Project { id, .. },
            Drop::Project {
                workspace_id,
                position,
                stored,
            },
        ) => reorder::project(id, workspace_id, *position, Some(*stored), workspaces)
            .map(Landed::Workspaces),
        (
            SidebarItem::Workbench { index },
            Drop::Workbench {
                project_id,
                position,
            },
        ) => {
            reorder::workbench(*index, project_id, *position, workbenches).map(Landed::Workbenches)
        }
        _ => None,
    }
}

/// O arrasto vale?
pub fn lands(
    workspaces: &[WorkspaceConfig],
    workbenches: &[WorkbenchConfig],
    item: &SidebarItem,
    target: &Drop,
) -> bool {
    plan_move(workspaces, workbenches, item, target).is_some()
}

//! O que a barra lateral lista, na ordem, já respeitando o que está recolhido.
//! Porte do `WorkspaceTree`.

use std::collections::HashSet;

use super::model::WorkspaceConfig;
use crate::features::workbench::model::WorkbenchConfig;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SidebarItem {
    Workspace {
        id: String,
    },
    Project {
        workspace_id: String,
        id: String,
    },
    /// Índice em `workbenches`: é como o resto do app endereça a bancada na tela.
    Workbench {
        index: usize,
    },
    /// Cabeçalho das bancadas cujo projeto não existe. Não deveria acontecer
    /// depois da conciliação, mas o arquivo é editável e a barra não pode
    /// esconder bancada nenhuma.
    Orphans,
}

/// Workspaces → projetos → bancadas, achatado para a barra.
///
/// A lista de bancadas continua plana e indexada por posição — é o que o ator e
/// o socket usam; a árvore é só o jeito de olhar para ela.
#[derive(Debug, Clone, Copy)]
pub struct WorkspaceTree<'a> {
    pub workspaces: &'a [WorkspaceConfig],
    pub workbenches: &'a [WorkbenchConfig],
}

impl<'a> WorkspaceTree<'a> {
    pub fn new(workspaces: &'a [WorkspaceConfig], workbenches: &'a [WorkbenchConfig]) -> Self {
        Self {
            workspaces,
            workbenches,
        }
    }

    fn known_projects(&self) -> HashSet<&str> {
        self.workspaces
            .iter()
            .flat_map(|w| &w.projects)
            .map(|p| p.id.as_str())
            .collect()
    }

    pub fn indices_in_project(&self, id: &str) -> Vec<usize> {
        (0..self.workbenches.len())
            .filter(|&i| self.workbenches[i].project.as_deref() == Some(id))
            .collect()
    }

    pub fn indices_in_workspace(&self, id: &str) -> Vec<usize> {
        let Some(space) = self.workspaces.iter().find(|w| w.id == id) else {
            return Vec::new();
        };
        let ids: HashSet<&str> = space.projects.iter().map(|p| p.id.as_str()).collect();
        (0..self.workbenches.len())
            .filter(|&i| {
                self.workbenches[i]
                    .project
                    .as_deref()
                    .is_some_and(|p| ids.contains(p))
            })
            .collect()
    }

    /// As bancadas sem projeto, ou com projeto que não existe mais.
    pub fn orphans(&self) -> Vec<usize> {
        let known = self.known_projects();
        (0..self.workbenches.len())
            .filter(|&i| {
                self.workbenches[i]
                    .project
                    .as_deref()
                    .is_none_or(|p| !known.contains(p))
            })
            .collect()
    }

    pub fn rows(&self) -> Vec<SidebarItem> {
        let mut out = Vec::new();
        for space in self.workspaces {
            out.push(SidebarItem::Workspace {
                id: space.id.clone(),
            });
            if space.is_collapsed() {
                continue;
            }
            for project in &space.projects {
                out.push(SidebarItem::Project {
                    workspace_id: space.id.clone(),
                    id: project.id.clone(),
                });
                if project.is_collapsed() {
                    continue;
                }
                out.extend(
                    self.indices_in_project(&project.id)
                        .into_iter()
                        .map(|index| SidebarItem::Workbench { index }),
                );
            }
        }
        let lost = self.orphans();
        if !lost.is_empty() {
            out.push(SidebarItem::Orphans);
            out.extend(
                lost.into_iter()
                    .map(|index| SidebarItem::Workbench { index }),
            );
        }
        out
    }

    /// Quem esconde a bancada `index` quando recolhido — o projeto e o workspace
    /// dela. Serve para abrir o caminho até uma bancada ativada por fora.
    pub fn ancestors(&self, index: usize) -> Option<(&'a str, &'a str)> {
        let benches: &'a [WorkbenchConfig] = self.workbenches;
        let spaces: &'a [WorkspaceConfig] = self.workspaces;
        let project = benches.get(index)?.project.as_deref()?;
        let space = spaces
            .iter()
            .find(|space| space.project_with_id(project).is_some())?;
        Some((space.id.as_str(), project))
    }
}

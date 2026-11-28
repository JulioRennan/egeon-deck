//! Como a barra lateral abre: os projetos com bancada à vista e no topo do
//! workspace. Decisão do app novo, não porte: no Swift cada projeto ficava como
//! estava ao fechar.

use std::collections::HashSet;

use super::model::WorkspaceConfig;
use crate::features::workbench::model::WorkbenchConfig;

/// Abre os projetos que têm bancada e os põe antes dos outros, sem mudar a
/// ordem entre eles. Vale na partida, para que recolher durante o uso continue
/// sendo possível. A ordem mexe no arquivo, e não só na vista, porque o
/// arrasto na barra conta posições pela lista gravada.
///
/// Devolve se mudou algo, para a partida gravar.
pub fn open_projects_with_benches(
    workspaces: &mut [WorkspaceConfig],
    workbenches: &[WorkbenchConfig],
) -> bool {
    let busy: HashSet<&str> = workbenches
        .iter()
        .filter_map(|b| b.project.as_deref())
        .collect();
    let mut changed = false;
    for space in workspaces {
        for project in &mut space.projects {
            if busy.contains(project.id.as_str()) && project.is_collapsed() {
                project.collapsed = None;
                changed = true;
            }
        }
        let before: Vec<String> = space.projects.iter().map(|p| p.id.clone()).collect();
        // `sort_by_key` é estável: dentro de cada grupo a ordem fica a do arquivo.
        space
            .projects
            .sort_by_key(|p| !busy.contains(p.id.as_str()));
        changed |= space.projects.iter().map(|p| &p.id).ne(before.iter());
    }
    changed
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::workspace::model::ProjectConfig;

    fn bench(project: &str) -> WorkbenchConfig {
        let mut w = WorkbenchConfig::new(project, "~/x", vec![]);
        w.project = Some(project.to_owned());
        w
    }

    fn space(projects: &[(&str, bool)]) -> WorkspaceConfig {
        let mut w = WorkspaceConfig::new("ws");
        w.projects = projects
            .iter()
            .map(|(id, collapsed)| {
                let mut p = ProjectConfig::new(*id, format!("~/{id}"));
                p.id = (*id).to_owned();
                p.collapsed = collapsed.then_some(true);
                p
            })
            .collect();
        w
    }

    fn ids(space: &WorkspaceConfig) -> Vec<&str> {
        space.projects.iter().map(|p| p.id.as_str()).collect()
    }

    #[test]
    fn projetos_com_bancada_sobem_na_ordem_em_que_estavam() {
        let mut spaces = vec![space(&[
            ("a", false),
            ("b", false),
            ("c", false),
            ("d", false),
        ])];
        let changed = open_projects_with_benches(&mut spaces, &[bench("d"), bench("b")]);
        assert!(changed);
        assert_eq!(ids(&spaces[0]), ["b", "d", "a", "c"]);
    }

    #[test]
    fn projeto_com_bancada_abre_e_sem_bancada_fica_como_estava() {
        let mut spaces = vec![space(&[("a", true), ("b", true)])];
        open_projects_with_benches(&mut spaces, &[bench("a")]);
        assert!(!spaces[0].projects[0].is_collapsed());
        assert!(spaces[0].projects[1].is_collapsed());
    }

    #[test]
    fn ja_arrumado_nao_pede_gravacao() {
        let mut spaces = vec![space(&[("a", false), ("b", true)])];
        assert!(!open_projects_with_benches(&mut spaces, &[bench("a")]));
    }
}

//! Mover workspace, projeto e bancada de lugar. Porte do `WorkspaceMove`.
//!
//! Funções puras: recebem a árvore, devolvem a árvore nova — quem grava e quem
//! redesenha é o dono do estado (ADR-051). `None` quando nada mudaria.
//!
//! A bancada é o caso delicado: a lista dela é **plana e indexada por
//! posição**, e é por índice que o app inteiro a endereça. Por isso mover
//! devolve também o mapa `índice antigo → novo`: sem ele, os terminais na tela
//! apontariam para a bancada errada — o mesmo cuidado que remover já tomava.

use std::collections::BTreeMap;

use super::model::WorkspaceConfig;
use crate::features::workbench::model::WorkbenchConfig;

/// Workspace para outra posição na barra. `to` é a posição final desejada na
/// lista já sem ele; além do fim encosta no fim.
pub fn workspace(id: &str, to: usize, spaces: &[WorkspaceConfig]) -> Option<Vec<WorkspaceConfig>> {
    let from = spaces.iter().position(|w| w.id == id)?;
    let mut out = spaces.to_vec();
    let moved = out.remove(from);
    let at = to.min(out.len());
    out.insert(at, moved);
    (out != spaces).then_some(out)
}

/// Projeto para um workspace (o mesmo ou outro), na posição `position`
/// **dentro do lado dele** — em uso ou guardado (ADR-052). `stored` `None`
/// mantém o lado em que ele estava. Mudar de workspace não toca nas bancadas:
/// elas seguem o projeto pelo `project` que já guardam.
pub fn project(
    id: &str,
    target: &str,
    position: usize,
    stored: Option<bool>,
    spaces: &[WorkspaceConfig],
) -> Option<Vec<WorkspaceConfig>> {
    let source = spaces
        .iter()
        .position(|w| w.project_with_id(id).is_some())?;
    let destination = spaces.iter().position(|w| w.id == target)?;
    let from = spaces[source].projects.iter().position(|p| p.id == id)?;
    // Multi-projeto aponta para projetos DESTE workspace, por id: levar um dos
    // lados para outro workspace desfaria o conjunto sem aviso.
    if source != destination {
        let tied = spaces[source].projects[from].is_multi()
            || spaces[source].projects.iter().any(|p| {
                p.members
                    .as_ref()
                    .is_some_and(|m| m.iter().any(|x| x == id))
            });
        if tied {
            return None;
        }
    }
    let mut out = spaces.to_vec();
    let mut moved = out[source].projects.remove(from);
    if let Some(stored) = stored {
        moved.stored = stored.then_some(true);
    }

    // A posição é a do lado; a lista é uma só. O lugar sai dos vizinhos do
    // mesmo lado: sem nenhum, guardado vai para o fim e em uso para antes do
    // primeiro guardado.
    let list = &out[destination].projects;
    let siblings: Vec<usize> = (0..list.len())
        .filter(|&i| list[i].is_stored() == moved.is_stored())
        .collect();
    let landing = if siblings.is_empty() {
        if moved.is_stored() {
            list.len()
        } else {
            list.iter()
                .position(|p| p.is_stored())
                .unwrap_or(list.len())
        }
    } else if position >= siblings.len() {
        siblings[siblings.len() - 1] + 1
    } else {
        siblings[position]
    };
    let count = list.len();
    out[destination].projects.insert(landing.min(count), moved);
    (out != spaces).then_some(out)
}

/// A lista de bancadas depois de mover uma, com o mapa dos índices que mudaram.
#[derive(Debug, Clone, PartialEq)]
pub struct WorkbenchMove {
    pub list: Vec<WorkbenchConfig>,
    /// Índice antigo → índice novo, só de quem saiu do lugar.
    pub map: BTreeMap<usize, usize>,
}

/// Bancada para um projeto, na posição `position` **dentro daquele projeto** —
/// é assim que a barra pensa, e a lista plana se ajusta.
pub fn workbench(
    index: usize,
    project: &str,
    position: usize,
    benches: &[WorkbenchConfig],
) -> Option<WorkbenchMove> {
    if index >= benches.len() {
        return None;
    }
    let mut moved = benches[index].clone();
    let mut rest = benches.to_vec();
    rest.remove(index);

    // A posição dentro do projeto vira posição na lista plana: o lugar da
    // n-ésima bancada dele, ou logo depois da última quando é o fim.
    let members: Vec<usize> = (0..rest.len())
        .filter(|&i| rest[i].project.as_deref() == Some(project))
        .collect();
    let target = if members.is_empty() {
        rest.len()
    } else if position >= members.len() {
        members[members.len() - 1] + 1
    } else {
        members[position]
    };
    moved.project = Some(project.to_owned());
    let landing = target.min(rest.len());
    rest.insert(landing, moved);

    // Nada mudou: mesmo lugar e mesmo projeto. `WorkbenchConfig` tem nós,
    // arestas e modo, então a comparação é de posição e projeto — o que esta
    // operação mexe.
    if landing == index && benches[index].project.as_deref() == Some(project) {
        return None;
    }
    Some(WorkbenchMove {
        list: rest,
        map: index_map(index, landing),
    })
}

/// Para onde foi cada índice quando um item saiu de `from` e entrou em `to`.
/// Só quem está entre os dois se desloca.
pub fn index_map(from: usize, to: usize) -> BTreeMap<usize, usize> {
    let mut out = BTreeMap::new();
    if from == to {
        return out;
    }
    out.insert(from, to);
    if from < to {
        for i in (from + 1)..=to {
            out.insert(i, i - 1);
        }
    } else {
        for i in to..from {
            out.insert(i, i + 1);
        }
    }
    out
}

//! Porte da árvore do WorkspaceTests, do WorkspaceMoveTests e do SidebarDropTests
//! (a conta; o desenho e o `CountSeal` são da tela).

use std::collections::BTreeMap;

use super::model::{ProjectConfig, WorkspaceConfig};
use super::reorder;
use super::sidebar_drop::{Drop, Landed, lands, plan_move};
use super::tree::{SidebarItem, WorkspaceTree};
use crate::features::workbench::model::WorkbenchConfig;

fn bench(name: &str, project: Option<&str>) -> WorkbenchConfig {
    let mut w = WorkbenchConfig::new(name, "~/x", vec![]);
    w.project = project.map(str::to_owned);
    w
}

fn project(id: &str) -> ProjectConfig {
    let mut p = ProjectConfig::new(id, format!("~/{id}"));
    p.id = id.to_owned();
    p
}

fn space(id: &str, projects: &[&str]) -> WorkspaceConfig {
    let mut w = WorkspaceConfig::new(id);
    w.id = id.to_owned();
    w.projects = projects.iter().map(|p| project(p)).collect();
    w
}

fn ids(spaces: &[WorkspaceConfig]) -> Vec<&str> {
    spaces.iter().map(|w| w.id.as_str()).collect()
}

fn project_ids(space: &WorkspaceConfig) -> Vec<&str> {
    space.projects.iter().map(|p| p.id.as_str()).collect()
}

fn names(list: &[WorkbenchConfig]) -> Vec<&str> {
    list.iter().map(|w| w.name.as_str()).collect()
}

// ── Árvore ─────────────────────────────────────────────────────────────────

fn sample() -> (Vec<WorkspaceConfig>, Vec<WorkbenchConfig>) {
    let spaces = vec![space("w-duck", &["p-deck"]), space("w-agro", &["p-nexus"])];
    let benches = vec![
        bench("deck-1", Some("p-deck")),
        bench("nexus-1", Some("p-nexus")),
        bench("deck-2", Some("p-deck")),
        bench("perdida", Some("nada")),
    ];
    (spaces, benches)
}

fn ws(id: &str) -> SidebarItem {
    SidebarItem::Workspace { id: id.into() }
}
fn pr(w: &str, id: &str) -> SidebarItem {
    SidebarItem::Project {
        workspace_id: w.into(),
        id: id.into(),
    }
}
fn wb(index: usize) -> SidebarItem {
    SidebarItem::Workbench { index }
}

#[test]
fn linhas_seguem_workspace_projeto_e_depois_as_orfas() {
    let (spaces, benches) = sample();
    assert_eq!(
        WorkspaceTree::new(&spaces, &benches).rows(),
        [
            ws("w-duck"),
            pr("w-duck", "p-deck"),
            wb(0),
            wb(2),
            ws("w-agro"),
            pr("w-agro", "p-nexus"),
            wb(1),
            SidebarItem::Orphans,
            wb(3),
        ]
    );
}

#[test]
fn workspace_recolhido_esconde_projetos_e_projeto_recolhido_esconde_bancadas() {
    let (mut spaces, benches) = sample();
    spaces[0].collapsed = Some(true);
    spaces[1].projects[0].collapsed = Some(true);
    assert_eq!(
        WorkspaceTree::new(&spaces, &benches).rows(),
        [
            ws("w-duck"),
            ws("w-agro"),
            pr("w-agro", "p-nexus"),
            SidebarItem::Orphans,
            wb(3)
        ]
    );
}

#[test]
fn pertencimento_e_ancestrais() {
    let (spaces, benches) = sample();
    let tree = WorkspaceTree::new(&spaces, &benches);
    assert_eq!(tree.indices_in_workspace("w-duck"), [0, 2]);
    assert_eq!(tree.indices_in_workspace("sumido"), Vec::<usize>::new());
    assert_eq!(tree.indices_in_project("p-nexus"), [1]);
    assert_eq!(tree.orphans(), [3]);
    assert_eq!(tree.ancestors(2), Some(("w-duck", "p-deck")));
    assert_eq!(tree.ancestors(3), None);
    assert_eq!(tree.ancestors(99), None);
}

#[test]
fn bancada_sem_projeto_tambem_e_orfa() {
    let spaces = vec![space("w", &["p"])];
    let benches = vec![bench("solta", None)];
    let tree = WorkspaceTree::new(&spaces, &benches);
    assert_eq!(tree.orphans(), [0]);
    assert_eq!(tree.ancestors(0), None);
}

// ── WorkspaceMoveTests ─────────────────────────────────────────────────────

#[test]
fn workspace_muda_de_lugar() {
    let spaces = [space("a", &[]), space("b", &[]), space("c", &[])];
    assert_eq!(
        ids(&reorder::workspace("c", 0, &spaces).unwrap()),
        ["c", "a", "b"]
    );
    assert_eq!(
        ids(&reorder::workspace("a", 2, &spaces).unwrap()),
        ["b", "c", "a"]
    );
    // Posição além do fim encosta no fim; para o mesmo lugar, nada muda.
    assert_eq!(
        ids(&reorder::workspace("a", 99, &spaces).unwrap()),
        ["b", "c", "a"]
    );
    assert!(reorder::workspace("a", 0, &spaces).is_none());
    assert!(reorder::workspace("nada", 0, &spaces).is_none());
}

#[test]
fn projeto_anda_dentro_e_entre_workspaces() {
    let spaces = [space("a", &["p1", "p2"]), space("b", &["p3"])];

    let inside = reorder::project("p2", "a", 0, None, &spaces).unwrap();
    assert_eq!(project_ids(&inside[0]), ["p2", "p1"]);

    let across = reorder::project("p1", "b", 0, None, &spaces).unwrap();
    assert_eq!(project_ids(&across[0]), ["p2"]);
    assert_eq!(project_ids(&across[1]), ["p1", "p3"]);
    assert!(reorder::project("p1", "nada", 0, None, &spaces).is_none());
    assert!(reorder::project("nada", "a", 0, None, &spaces).is_none());
}

#[test]
fn bancada_reordena_dentro_do_projeto() {
    let list = [
        bench("um", Some("p1")),
        bench("dois", Some("p1")),
        bench("três", Some("p1")),
    ];
    let moved = reorder::workbench(2, "p1", 0, &list).unwrap();
    assert_eq!(names(&moved.list), ["três", "um", "dois"]);
    // Quem estava no caminho desceu um; o resto ficou.
    assert_eq!(moved.map, BTreeMap::from([(2, 0), (0, 1), (1, 2)]));
    assert!(reorder::workbench(0, "p1", 0, &list).is_none());
    assert!(reorder::workbench(9, "p1", 0, &list).is_none());
}

#[test]
fn bancada_muda_de_projeto_e_cai_entre_as_novas_vizinhas() {
    let list = [
        bench("um", Some("p1")),
        bench("dois", Some("p2")),
        bench("três", Some("p2")),
    ];
    let moved = reorder::workbench(0, "p2", 1, &list).unwrap();
    assert_eq!(names(&moved.list), ["dois", "um", "três"]);
    let projects: Vec<_> = moved.list.iter().map(|w| w.project.as_deref()).collect();
    assert_eq!(projects, [Some("p2"), Some("p2"), Some("p2")]);

    // Para o fim do projeto, e para um projeto ainda vazio.
    let last = reorder::workbench(0, "p2", 9, &list).unwrap();
    assert_eq!(names(&last.list), ["dois", "três", "um"]);
    let empty = reorder::workbench(1, "p9", 0, &list).unwrap();
    assert_eq!(names(&empty.list), ["um", "três", "dois"]);
    assert_eq!(empty.list.last().unwrap().project.as_deref(), Some("p9"));
}

/// Guardar é escolha, não dedução: o projeto muda de lado da gaveta e a posição
/// passa a ser contada entre os do lado novo (ADR-052).
#[test]
fn projeto_entra_e_sai_da_gaveta() {
    let mut guardado = project("p3");
    guardado.stored = Some(true);
    let mut a = space("a", &["p1", "p2"]);
    a.projects.push(guardado);
    let spaces = [a];

    let stored = reorder::project("p1", "a", 0, Some(true), &spaces).unwrap();
    let active: Vec<_> = stored[0].active_projects().map(|p| p.id.as_str()).collect();
    let in_drawer: Vec<_> = stored[0].stored_projects().map(|p| p.id.as_str()).collect();
    assert_eq!(active, ["p2"]);
    assert_eq!(in_drawer, ["p1", "p3"]);

    // De volta ao uso, no fim do lado de cima — e antes do primeiro guardado.
    let back = reorder::project("p3", "a", 9, Some(false), &spaces).unwrap();
    assert_eq!(
        back[0]
            .active_projects()
            .map(|p| p.id.as_str())
            .collect::<Vec<_>>(),
        ["p1", "p2", "p3"]
    );
    assert_eq!(back[0].stored_projects().count(), 0);
    assert_eq!(
        project_ids(&back[0]),
        ["p1", "p2", "p3"],
        "guardado sai de baixo da lista"
    );
    assert_eq!(
        back[0].projects[2].stored, None,
        "em uso não grava `stored: false`"
    );

    // Sem dizer o lado, ele fica onde estava.
    let same = reorder::project("p1", "a", 1, None, &spaces).unwrap();
    assert_eq!(
        same[0]
            .active_projects()
            .map(|p| p.id.as_str())
            .collect::<Vec<_>>(),
        ["p2", "p1"]
    );
    assert_eq!(
        same[0]
            .stored_projects()
            .map(|p| p.id.as_str())
            .collect::<Vec<_>>(),
        ["p3"]
    );
}

/// O mapa é o que salva os terminais na tela: cada índice antigo tem de achar a
/// sua bancada na lista nova.
#[test]
fn mapa_leva_cada_indice_movido_para_a_casa_nova() {
    let list = [
        bench("um", Some("p")),
        bench("dois", Some("p")),
        bench("três", Some("p")),
        bench("quatro", Some("p")),
    ];
    for (from, to) in [(0, 3), (3, 0), (1, 2), (2, 1)] {
        let moved = reorder::workbench(from, "p", to, &list).unwrap();
        for (&old, &new) in &moved.map {
            assert_eq!(
                moved.list[new].name, list[old].name,
                "{from}→{to}: o índice {old} devia virar {new}"
            );
        }
        // Quem não está no mapa não saiu do lugar.
        for index in 0..list.len() {
            if !moved.map.contains_key(&index) {
                assert_eq!(moved.list[index].name, list[index].name);
            }
        }
    }
    assert!(reorder::index_map(2, 2).is_empty());
}

#[test]
fn projeto_amarrado_nao_muda_de_workspace() {
    let mut multi = project("m");
    multi.members = Some(vec!["web".into()]);
    let spaces = [
        {
            let mut s = space("s1", &["web", "back"]);
            s.projects.push(multi);
            s
        },
        space("s2", &[]),
    ];
    assert!(reorder::project("m", "s2", 0, None, &spaces).is_none());
    assert!(reorder::project("web", "s2", 0, None, &spaces).is_none());
    assert!(reorder::project("back", "s2", 0, None, &spaces).is_some());
    // Dentro do mesmo workspace pode.
    assert!(reorder::project("web", "s1", 1, None, &spaces).is_some());
}

// ── SidebarDropTests: a legalidade (a geometria é da tela) ─────────────────

fn drop_of(
    item: &SidebarItem,
    target: &Drop,
    s: &(Vec<WorkspaceConfig>, Vec<WorkbenchConfig>),
) -> Option<Landed> {
    plan_move(&s.0, &s.1, item, target)
}

#[test]
fn bancada_so_cai_em_projeto_projeto_so_em_workspace_e_workspace_entre_workspaces() {
    let s = sample();
    let bench = SidebarItem::Workbench { index: 1 };
    let proj = pr("w-agro", "p-nexus");
    let space = ws("w-agro");
    let to_bench = Drop::Workbench {
        project_id: "p-deck".into(),
        position: 0,
    };
    let to_proj = Drop::Project {
        workspace_id: "w-duck".into(),
        position: 0,
        stored: false,
    };
    let to_space = Drop::Workspace { position: 0 };

    let Some(Landed::Workbenches(moved)) = drop_of(&bench, &to_bench, &s) else {
        panic!()
    };
    assert_eq!(
        names(&moved.list),
        ["nexus-1", "deck-1", "deck-2", "perdida"]
    );
    assert_eq!(moved.list[0].project.as_deref(), Some("p-deck"));
    let Some(Landed::Workspaces(spaces)) = drop_of(&proj, &to_proj, &s) else {
        panic!()
    };
    assert_eq!(project_ids(&spaces[0]), ["p-nexus", "p-deck"]);
    let Some(Landed::Workspaces(spaces)) = drop_of(&space, &to_space, &s) else {
        panic!()
    };
    assert_eq!(ids(&spaces), ["w-agro", "w-duck"]);

    // Tipo que não casa: nada muda — a árvore não muda de forma no arrasto.
    for (item, target) in [
        (&bench, &to_proj),
        (&bench, &to_space),
        (&proj, &to_bench),
        (&proj, &to_space),
        (&space, &to_bench),
        (&space, &to_proj),
    ] {
        assert_eq!(drop_of(item, target, &s), None, "{item:?} em {target:?}");
    }
    // A pilha de órfãs não sai do lugar nem recebe.
    for target in [&to_bench, &to_proj, &to_space] {
        assert_eq!(drop_of(&SidebarItem::Orphans, target, &s), None);
    }
}

#[test]
fn soltar_onde_ja_estava_ou_no_que_nao_existe_nao_vale() {
    let s = sample();
    // `perdida` já é a única bancada do projeto dela, e já está no fim da lista.
    let same = Drop::Workbench {
        project_id: "nada".into(),
        position: 0,
    };
    assert!(!lands(
        &s.0,
        &s.1,
        &SidebarItem::Workbench { index: 3 },
        &same
    ));
    let other = Drop::Workbench {
        project_id: "p-deck".into(),
        position: 0,
    };
    assert!(lands(
        &s.0,
        &s.1,
        &SidebarItem::Workbench { index: 3 },
        &other
    ));
    let ghost = other.clone();
    assert!(!lands(
        &s.0,
        &s.1,
        &SidebarItem::Workbench { index: 99 },
        &ghost
    ));
    let nowhere = Drop::Project {
        workspace_id: "nada".into(),
        position: 0,
        stored: false,
    };
    assert!(!lands(&s.0, &s.1, &pr("w-duck", "p-deck"), &nowhere));
    assert!(
        !lands(&s.0, &s.1, &ws("w-duck"), &Drop::Workspace { position: 0 }),
        "já é o primeiro"
    );
}

/// Soltar abaixo da tampa guarda o projeto; acima dela, tira (ADR-052).
#[test]
fn soltar_na_gaveta_guarda_o_projeto_e_fora_dela_tira() {
    let s = sample();
    let store = Drop::Project {
        workspace_id: "w-duck".into(),
        position: 0,
        stored: true,
    };
    let Some(Landed::Workspaces(spaces)) = drop_of(&pr("w-duck", "p-deck"), &store, &s) else {
        panic!()
    };
    assert_eq!(
        spaces[0]
            .stored_projects()
            .map(|p| p.id.as_str())
            .collect::<Vec<_>>(),
        ["p-deck"]
    );
    let back = Drop::Project {
        workspace_id: "w-duck".into(),
        position: 0,
        stored: false,
    };
    let again = (spaces.clone(), s.1.clone());
    let Some(Landed::Workspaces(out)) = drop_of(&pr("w-duck", "p-deck"), &back, &again) else {
        panic!()
    };
    assert_eq!(out[0].stored_projects().count(), 0);
}

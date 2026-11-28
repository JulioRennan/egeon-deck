//! Porte de WorkspaceTests (modelo e conciliação; a árvore é da US-104).

use std::fs;

use super::model::*;
use super::service::*;
use super::store;
use crate::features::workbench::model::WorkbenchConfig;

const HOME: &str = "/Users/eu";

fn bench(name: &str, path: &str, project: Option<&str>) -> WorkbenchConfig {
    let mut w = WorkbenchConfig::new(name, path, vec![]);
    w.project = project.map(str::to_owned);
    w
}

fn project(id: &str, name: &str, path: &str) -> ProjectConfig {
    let mut p = ProjectConfig::new(name, path);
    p.id = id.to_owned();
    p
}

fn space(id: &str, name: &str, projects: Vec<ProjectConfig>) -> WorkspaceConfig {
    let mut w = WorkspaceConfig::new(name);
    w.id = id.to_owned();
    w.projects = projects;
    w
}

// ── Modelo ─────────────────────────────────────────────────────────────────

#[test]
fn projeto_e_dono_do_caminho_ignorando_til_e_barra_final() {
    let p = ProjectConfig::new("deck", "~/repos/deck");
    assert!(p.owns("/Users/eu/repos/deck", HOME));
    assert!(p.owns("/Users/eu/repos/deck/", HOME));
    assert!(!p.owns("/Users/eu/repos/deck2", HOME));
}

#[test]
fn projeto_para_pasta_leva_o_nome_da_pasta_e_abrevia() {
    let p = ProjectConfig::for_folder("/Users/eu/repos/deck/", HOME);
    assert_eq!(p.name, "deck");
    assert_eq!(p.path, "~/repos/deck");
}

#[test]
fn leitura_preenche_id_e_nome_do_projeto() {
    let json = r#"[{"name":"Duck","projects":[{"path":"/repos/deck"}]}]"#;
    let spaces: Vec<WorkspaceConfig> = serde_json::from_str(json).unwrap();
    assert_eq!(spaces[0].id.len(), 8);
    assert_eq!(spaces[0].projects[0].name, "deck");
    assert_eq!(spaces[0].projects[0].id.len(), 8);
    assert_eq!(spaces[0].initial(), "D");
    assert!(!spaces[0].is_collapsed());
}

#[test]
fn leitura_tolerante_de_workspace() {
    // `projects` ausente ou null é lista vazia; chave desconhecida é ignorada.
    let a: WorkspaceConfig = serde_json::from_str(r#"{"name":"A","projects":null,"x":1}"#).unwrap();
    assert!(a.projects.is_empty());
    assert!(
        serde_json::from_str::<WorkspaceConfig>(r#"{"projects":[]}"#).is_err(),
        "sem nome"
    );
    assert!(
        serde_json::from_str::<WorkspaceConfig>(r#"{"name":"A","projects":[{"name":"x"}]}"#)
            .is_err(),
        "projeto sem pasta"
    );
}

#[test]
fn projeto_e_workspace_vao_e_voltam() {
    let mut p = project("p1", "deck", "~/deck");
    p.collapsed = Some(true);
    p.stored = Some(true);
    p.members = Some(vec!["a".into(), "b".into()]);
    let mut w = space("w1", "Duck", vec![p]);
    w.icon = Some("icon.png".into());
    w.collapsed = Some(false);
    w.stored_open = Some(true);
    w.remember(Some("~/.claude-agro"), "claude");
    let text = serde_json::to_string(&w).unwrap();
    for key in [
        "storedOpen",
        "lastConfigs",
        "collapsed",
        "stored",
        "members",
        "icon",
    ] {
        assert!(text.contains(&format!("\"{key}\"")), "{key}: {text}");
    }
    assert_eq!(serde_json::from_str::<WorkspaceConfig>(&text).unwrap(), w);
}

#[test]
fn inicial_apara_so_espaco_e_poe_em_maiuscula() {
    assert_eq!(WorkspaceConfig::new("  agro").initial(), "A");
    assert_eq!(WorkspaceConfig::new("éter").initial(), "É");
    assert_eq!(WorkspaceConfig::new("").initial(), "");
}

#[test]
fn gaveta_separa_ativos_e_guardados() {
    let mut guardado = project("g", "g", "/g");
    guardado.stored = Some(true);
    let w = space(
        "w",
        "W",
        vec![project("a", "a", "/a"), guardado, project("b", "b", "/b")],
    );
    assert_eq!(
        w.active_projects()
            .map(|p| p.id.as_str())
            .collect::<Vec<_>>(),
        ["a", "b"]
    );
    assert_eq!(
        w.stored_projects()
            .map(|p| p.id.as_str())
            .collect::<Vec<_>>(),
        ["g"]
    );
}

// Membro que sumiu do workspace é pulado; multi dentro de multi não entra.
#[test]
fn membros_do_multi_na_ordem_dele_sem_os_que_sumiram() {
    let mut multi = project("m", "m", "/links");
    multi.members = Some(vec![
        "b".into(),
        "sumido".into(),
        "a".into(),
        "outro-multi".into(),
    ]);
    let mut outro = project("outro-multi", "o", "/o");
    outro.members = Some(vec![]);
    let w = space(
        "w",
        "W",
        vec![
            project("a", "a", "/a"),
            project("b", "b", "/b"),
            outro,
            multi.clone(),
        ],
    );
    let ids: Vec<_> = w.members_of(&multi).iter().map(|p| p.id.as_str()).collect();
    assert_eq!(ids, ["b", "a"]);
    assert!(multi.is_multi() && multi.requires_worktree());
}

#[test]
fn lembrar_a_configuracao_e_apagar_com_o_padrao() {
    let mut w = WorkspaceConfig::new("W");
    w.remember(Some("~/.claude-agro"), "claude");
    w.remember(Some("~/.codex"), "codex");
    assert_eq!(w.last_configs.as_ref().unwrap()["claude"], "~/.claude-agro");
    w.remember(None, "claude");
    assert_eq!(w.last_configs.as_ref().unwrap().len(), 1);
    w.remember(None, "codex");
    assert_eq!(w.last_configs, None, "mapa vazio some do arquivo");
}

// ── Conciliação ────────────────────────────────────────────────────────────

#[test]
fn concilia_cria_o_workspace_padrao_e_um_projeto_por_repo() {
    let benches = [
        bench("a", "/repos/deck", None),
        bench("b", "/repos/deck", None),
        bench("c", "/repos/nexus", None),
    ];
    let out = reconcile(&[], &benches, HOME, |_| None);
    assert!(out.changed);
    assert_eq!(out.workspaces.len(), 1);
    assert_eq!(out.workspaces[0].name, DEFAULT_NAME);
    let names: Vec<_> = out.workspaces[0]
        .projects
        .iter()
        .map(|p| p.name.as_str())
        .collect();
    assert_eq!(names, ["deck", "nexus"]);
    assert_eq!(out.workbenches[0].project, out.workbenches[1].project);
    assert_ne!(out.workbenches[0].project, out.workbenches[2].project);
    assert_eq!(out.notes.len(), 3, "workspace + dois projetos");
}

// A bancada em worktree é do projeto do checkout principal: saiu dele.
#[test]
fn concilia_liga_a_worktree_ao_projeto_do_repo_principal() {
    let w = space("w1", "Duck", vec![project("p-deck", "deck", "/repos/deck")]);
    let benches = [bench("wt", "/repos/deck-worktrees/feature-x", None)];
    let out = reconcile(&[w], &benches, HOME, |p| {
        p.contains("worktrees").then(|| "/repos/deck".to_owned())
    });
    assert_eq!(out.workbenches[0].project.as_deref(), Some("p-deck"));
    assert_eq!(out.workspaces[0].projects.len(), 1);
    assert!(out.changed);
}

#[test]
fn concilia_guarda_a_atribuicao_existente_e_diz_que_nada_mudou() {
    let w = space("w1", "Duck", vec![project("p-deck", "deck", "/repos/deck")]);
    // Bancada apontando para pasta de OUTRO projeto, mas com `project` válido:
    // pertencimento é por id, e o arquivo é editado à mão de propósito.
    let benches = [bench("a", "/repos/outra", Some("p-deck"))];
    let out = reconcile(&[w], &benches, HOME, |_| None);
    assert!(!out.changed);
    assert_eq!(out.workbenches[0].project.as_deref(), Some("p-deck"));
    assert!(out.notes.is_empty());
}

#[test]
fn concilia_realoca_id_de_projeto_desconhecido() {
    let w = space("w1", "Duck", vec![project("p-deck", "deck", "/repos/deck")]);
    let benches = [bench("a", "/repos/deck", Some("apagado"))];
    let out = reconcile(&[w], &benches, HOME, |_| None);
    assert!(out.changed);
    assert_eq!(out.workbenches[0].project.as_deref(), Some("p-deck"));
}

#[test]
fn concilia_cria_o_projeto_que_falta_no_primeiro_workspace() {
    let first = space("w1", "Duck", vec![]);
    let second = space("w2", "Agro", vec![]);
    let benches = [bench("a", "/repos/deck", None)];
    let out = reconcile(&[first, second], &benches, HOME, |_| None);
    let names: Vec<_> = out.workspaces[0]
        .projects
        .iter()
        .map(|p| p.name.as_str())
        .collect();
    assert_eq!(names, ["deck"]);
    assert!(out.workspaces[1].projects.is_empty());
    assert_eq!(
        out.workbenches[0].project.as_ref(),
        Some(&out.workspaces[0].projects[0].id)
    );
}

#[test]
fn concilia_compara_pelo_til_e_pela_barra_final() {
    let w = space("w1", "Duck", vec![project("p", "deck", "~/repos/deck")]);
    let benches = [bench("a", "/Users/eu/repos/deck/", None)];
    let out = reconcile(&[w], &benches, HOME, |_| None);
    assert_eq!(out.workbenches[0].project.as_deref(), Some("p"));
    assert_eq!(out.workspaces[0].projects.len(), 1);
}

// ── workspaces.json ────────────────────────────────────────────────────────

#[test]
fn sem_arquivo_e_none_para_disparar_a_migracao() {
    let dir = tempfile::tempdir().unwrap();
    assert!(store::load(&dir.path().join(store::FILE)).is_none());
}

#[test]
fn arquivo_quebrado_e_lista_vazia_e_vazio_tambem() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join(store::FILE);
    fs::write(&file, "{quebrado").unwrap();
    let broken = store::load(&file).unwrap();
    assert!(broken.workspaces.is_empty() && broken.broken && !broken.needs_save);
    fs::write(&file, "[]").unwrap();
    let empty = store::load(&file).unwrap();
    assert!(empty.workspaces.is_empty() && !empty.broken);
}

#[test]
fn id_gerado_na_carga_pede_gravacao_e_o_id_fica() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join(store::FILE);
    fs::write(
        &file,
        r#"[{"name":"Duck","projects":[{"path":"/repos/deck"}]}]"#,
    )
    .unwrap();
    let first = store::load(&file).unwrap();
    assert!(first.needs_save);
    store::save(&file, &first.workspaces).unwrap();
    let second = store::load(&file).unwrap();
    assert!(!second.needs_save);
    assert_eq!(second.workspaces, first.workspaces);
}

#[test]
fn imagem_do_workspace_e_copiada_e_a_antiga_sai() {
    let home = tempfile::tempdir().unwrap();
    let origem = tempfile::tempdir().unwrap();
    let png = origem.path().join("Foto.PNG");
    let jpg = origem.path().join("outra.jpg");
    fs::write(&png, b"png").unwrap();
    fs::write(&jpg, b"jpg").unwrap();
    let mut w = WorkspaceConfig::new("Duck");

    store::install_icon(home.path(), &png, &mut w).unwrap();
    assert_eq!(w.icon.as_deref(), Some("icon.png"));
    let path = store::icon_path(home.path(), &w).unwrap();
    assert_eq!(fs::read(&path).unwrap(), b"png");
    assert!(png.exists(), "é cópia, a original fica");

    store::install_icon(home.path(), &jpg, &mut w).unwrap();
    assert_eq!(w.icon.as_deref(), Some("icon.jpg"));
    assert!(!path.exists(), "a imagem anterior saiu");

    let jpg_path = store::icon_path(home.path(), &w).unwrap();
    store::remove_icon(home.path(), &mut w);
    assert_eq!(w.icon, None);
    assert!(!jpg_path.exists());

    // Sem extensão, png.
    let sem = origem.path().join("semext");
    fs::write(&sem, b"x").unwrap();
    store::install_icon(home.path(), &sem, &mut w).unwrap();
    assert_eq!(w.icon.as_deref(), Some("icon.png"));
}

//! Porte do MultiProjectTests (modelo, formulário, links, branches e a
//! pasta de bancada em worktree), do NewProjectTests e do LastConfigTests.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use super::links;
use super::model::{ProjectConfig, WorkspaceConfig};
use super::multi::*;
use super::new_project::{self, FALLBACK_PARENT, Plan, Problem};

const HOME: &str = "/Users/eu";

fn web() -> ProjectConfig {
    let mut p = ProjectConfig::new("nexus-web-app", "/src/agro/nexus-web-app");
    p.id = "web".into();
    p
}

fn back() -> ProjectConfig {
    let mut p = ProjectConfig::new("nexus-backend", "/src/agro/nexus-backend");
    p.id = "back".into();
    p
}

fn multi_project(id: &str, name: &str, path: &str, members: &[&str]) -> ProjectConfig {
    let mut p = ProjectConfig::new(name, path);
    p.id = id.into();
    p.members = Some(members.iter().map(|m| (*m).to_owned()).collect());
    p
}

fn link(id: &str) -> String {
    format!("/links/{id}")
}

fn ids(projects: &[ProjectConfig]) -> Vec<&str> {
    projects.iter().map(|p| p.id.as_str()).collect()
}

fn strings(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| (*s).to_owned()).collect()
}

fn draft(id: Option<&str>, name: &str, folders: &[&str]) -> MultiProjectDraft {
    MultiProjectDraft {
        id: id.map(str::to_owned),
        name: name.into(),
        folders: strings(folders),
    }
}

#[test]
fn projeto_antigo_abre_como_pasta() {
    let p: ProjectConfig = serde_json::from_str(r#"{"id":"a","name":"x","path":"/x"}"#).unwrap();
    assert!(!p.is_multi());
}

#[test]
fn membros_vao_e_voltam() {
    let multi = multi_project("m", "Nexus", "/links/m", &["web", "back"]);
    let back_again: ProjectConfig =
        serde_json::from_str(&serde_json::to_string(&multi).unwrap()).unwrap();
    assert_eq!(back_again.members, Some(strings(&["web", "back"])));
}

#[test]
fn membros_pulam_o_que_sumiu_e_o_multi() {
    let multi = multi_project("m", "N", "/l", &["web", "sumiu", "m", "back"]);
    let mut space = WorkspaceConfig::new("Agro");
    space.projects = vec![web(), back(), multi.clone()];
    let members = space.members_of(&multi);
    assert_eq!(
        members.iter().map(|p| p.id.as_str()).collect::<Vec<_>>(),
        ["web", "back"]
    );
}

#[test]
fn multi_novo_resolve_as_pastas_para_ids() {
    let d = draft(None, "Nexus", &[&web().path, &back().path]);
    let out = apply_edit(
        &[web(), back()],
        &strings(&[&web().path, &back().path]),
        &[d],
        HOME,
        link,
        |_| false,
    );
    let multi = out.projects.last().unwrap();
    assert_eq!(multi.members, Some(strings(&["web", "back"])));
    assert_eq!(multi.path, format!("/links/{}", multi.id));
    let folders: Vec<_> = out
        .projects
        .iter()
        .filter(|p| !p.is_multi())
        .map(|p| p.id.as_str())
        .collect();
    assert_eq!(folders, ["web", "back"]);
}

#[test]
fn multi_pode_usar_pasta_adicionada_no_mesmo_formulario() {
    let d = draft(None, "Tudo", &["/src/agro/novo", &web().path]);
    let out = apply_edit(
        &[web()],
        &strings(&[&web().path, "/src/agro/novo"]),
        &[d],
        HOME,
        link,
        |_| false,
    );
    let novo = out
        .projects
        .iter()
        .find(|p| p.path == "/src/agro/novo")
        .unwrap();
    assert_eq!(
        out.projects.last().unwrap().members,
        Some(vec![novo.id.clone(), "web".to_owned()])
    );
}

#[test]
fn editar_guarda_o_id_e_a_pasta_ignora_multis() {
    let multi = multi_project("m", "Velho", "/links/m", &["web"]);
    let d = draft(Some("m"), "Nexus", &[&web().path, &back().path]);
    let out = apply_edit(
        &[web(), back(), multi],
        &strings(&[&web().path, &back().path]),
        &[d],
        HOME,
        link,
        |_| false,
    );
    assert_eq!(ids(&out.projects), ["web", "back", "m"]);
    assert_eq!(out.projects[2].name, "Nexus");
    assert_eq!(out.projects[2].members, Some(strings(&["web", "back"])));

    // Nome vazio guarda o que já era.
    let again = apply_edit(
        &out.projects,
        &strings(&[&web().path, &back().path]),
        &[draft(Some("m"), "  ", &[&web().path])],
        HOME,
        link,
        |_| false,
    );
    assert_eq!(again.projects[2].name, "Nexus");
    assert_eq!(again.projects[2].members, Some(strings(&["web"])));
}

#[test]
fn multi_tirado_com_bancada_fica() {
    let multi = multi_project("m", "Nexus", "/links/m", &["web"]);
    let out = apply_edit(
        &[web(), multi],
        &strings(&[&web().path]),
        &[],
        HOME,
        link,
        |id| id == "m",
    );
    assert_eq!(ids(&out.projects), ["web", "m"]);
    assert_eq!(out.refused, ["Nexus"]);
}

#[test]
fn multi_tirado_sem_bancada_vai_embora() {
    let multi = multi_project("m", "Nexus", "/links/m", &["web"]);
    let out = apply_edit(
        &[web(), multi],
        &strings(&[&web().path]),
        &[],
        HOME,
        link,
        |_| false,
    );
    assert_eq!(ids(&out.projects), ["web"]);
    assert!(out.refused.is_empty());
}

#[test]
fn pasta_tirada_com_bancada_fica_e_pasta_nova_entra() {
    let out = apply_edit(
        &[web(), back()],
        &strings(&["/src/agro/nova"]),
        &[],
        HOME,
        link,
        |id| id == "back",
    );
    assert_eq!(
        out.projects
            .iter()
            .map(|p| p.path.as_str())
            .collect::<Vec<_>>(),
        ["/src/agro/nexus-backend", "/src/agro/nova"]
    );
    assert_eq!(out.refused, ["nexus-backend"]);
}

#[test]
fn nome_vazio_do_multi_novo_usa_o_resumo() {
    let d = draft(None, "  ", &[&web().path, &back().path]);
    assert_eq!(d.summary(HOME), "nexus-web-app + nexus-backend");
    let out = apply_edit(
        &[web(), back()],
        &strings(&[&web().path, &back().path]),
        &[d],
        HOME,
        link,
        |_| false,
    );
    assert_eq!(
        out.projects.last().unwrap().name,
        "nexus-web-app + nexus-backend"
    );
}

#[test]
fn rascunhos_vem_do_workspace_salvo() {
    let mut space = WorkspaceConfig::new("Agro");
    space.projects = vec![
        web(),
        back(),
        multi_project("m", "Nexus", "/l", &["back", "web"]),
    ];
    assert_eq!(
        drafts(&space),
        [draft(
            Some("m"),
            "Nexus",
            &["/src/agro/nexus-backend", "/src/agro/nexus-web-app"]
        )]
    );
}

#[test]
fn nomes_de_link_desambiguam_a_mesma_pasta() {
    let a = ProjectConfig::new("api", "/a/api");
    let b = ProjectConfig::new("api", "/b/api");
    let names: Vec<_> = link_names(&[&a, &b], HOME)
        .into_iter()
        .map(|l| l.name)
        .collect();
    assert_eq!(names, ["api", "api-2"]);
    let targets: Vec<_> = link_names(&[&a, &b], HOME)
        .into_iter()
        .map(|l| l.target)
        .collect();
    assert_eq!(targets, ["/a/api", "/b/api"]);
}

#[test]
fn raiz_da_worktree_mora_sob_o_pai_comum_e_o_nome_do_projeto() {
    let multi = ProjectConfig::new("Nexus completo", "/l");
    assert_eq!(
        worktree_root(&multi, &[&web(), &back()], "feat/login", HOME),
        "/src/agro/worktrees/Nexus completo/feat-login"
    );
}

#[test]
fn pai_comum_cai_no_primeiro_quando_so_a_raiz_e_comum() {
    assert_eq!(
        common_parent(&strings(&["/Volumes/x/a", "/Users/y/b"]), HOME),
        "/Volumes/x"
    );
    assert_eq!(
        common_parent(&strings(&["/src/a/x", "/src/b/y"]), HOME),
        "/src"
    );
    assert_eq!(common_parent(&strings(&["/src/a/x"]), HOME), "/src/a");
    assert_eq!(common_parent(&[], HOME), HOME);
}

// ── As branches do multi-projeto ───────────────────────────────────────────

#[test]
fn todo_repo_segue_a_branch_da_bancada_por_padrao() {
    assert_eq!(
        branches(&strings(&["web", "back"]), "feat/login", &BTreeMap::new()),
        BTreeMap::from([
            ("web".to_owned(), "feat/login".to_owned()),
            ("back".to_owned(), "feat/login".to_owned())
        ])
    );
}

#[test]
fn a_troca_muda_so_aquele_repo() {
    let overrides = BTreeMap::from([
        ("back".to_owned(), "fix/api".to_owned()),
        ("web".to_owned(), "  ".to_owned()),
    ]);
    assert_eq!(
        branches(&strings(&["web", "back"]), "feat/login", &overrides),
        BTreeMap::from([
            ("web".to_owned(), "feat/login".to_owned()),
            ("back".to_owned(), "fix/api".to_owned())
        ])
    );
}

#[test]
fn a_raiz_leva_o_nome_da_branch_da_bancada_seja_qual_for_a_do_repo() {
    let multi = ProjectConfig::new("Nexus", "/l");
    let web = ProjectConfig::new("web", "/src/web");
    assert_eq!(
        worktree_root(&multi, &[&web], "feat/login", HOME),
        "/src/worktrees/Nexus/feat-login"
    );
}

#[test]
fn so_o_multi_exige_worktree() {
    assert!(multi_project("m", "N", "/l", &["a"]).requires_worktree());
    assert!(!ProjectConfig::new("web", "/src/web").requires_worktree());
}

// ── A pasta de links ───────────────────────────────────────────────────────

#[cfg(unix)]
fn make_link(target: &Path, at: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(target, at)
}

#[cfg(unix)]
#[test]
fn sincronizar_cria_troca_e_guarda_o_que_nao_e_link() {
    let tmp = tempfile::tempdir().unwrap();
    let dir = tmp.path().join("m");
    fs::create_dir_all(&dir).unwrap();
    fs::write(dir.join("NOTAS.md"), b"").unwrap();
    let ln = |name: &str, target: &str| LinkName {
        name: name.into(),
        target: target.into(),
    };

    assert!(
        links::sync(
            &dir,
            &[ln("web", "/src/web"), ln("back", "/src/back")],
            &make_link
        )
        .is_empty()
    );
    assert!(links::sync(&dir, &[ln("web", "/src/web2")], &make_link).is_empty());

    assert_eq!(
        fs::read_link(dir.join("web")).unwrap(),
        Path::new("/src/web2")
    );
    assert!(
        fs::symlink_metadata(dir.join("back")).is_err(),
        "o link que saiu da lista foi apagado"
    );
    assert!(dir.join("NOTAS.md").exists());

    // Arquivo no lugar de um link pedido: fica, e o problema volta para o log.
    let problems = links::sync(&dir, &[ln("NOTAS.md", "/src/x")], &make_link);
    assert_eq!(problems.len(), 1);
    assert!(
        problems[0].contains("NOTAS.md") && problems[0].contains("não é link"),
        "{problems:?}"
    );
    assert!(dir.join("NOTAS.md").is_file());
}

#[cfg(unix)]
#[test]
fn sincronizar_tudo_cobre_cada_multi_projeto() {
    let tmp = tempfile::tempdir().unwrap();
    let home = tmp.path().to_str().unwrap();
    let mut space = WorkspaceConfig::new("Agro");
    let folder = tmp.path().join("repos/web");
    fs::create_dir_all(&folder).unwrap();
    let mut web = ProjectConfig::new("web", folder.to_str().unwrap());
    web.id = "web".into();
    let pasta_links = tmp.path().join("projects/m");
    let multi = multi_project(
        "m",
        "Conjunto",
        pasta_links.to_str().unwrap(),
        &["web", "sumiu"],
    );
    space.projects = vec![web, multi];

    let log = links::sync_all(&[space], home, &make_link);
    assert!(log.is_empty(), "{log:?}");
    assert_eq!(fs::read_link(pasta_links.join("web")).unwrap(), folder);
}

#[cfg(unix)]
#[test]
fn podar_so_apaga_pasta_so_de_links() {
    let tmp = tempfile::tempdir().unwrap();
    let only_links = tmp.path().join("so-links");
    let busy = tmp.path().join("com-pasta");
    fs::create_dir_all(&only_links).unwrap();
    fs::create_dir_all(busy.join("web")).unwrap();
    std::os::unix::fs::symlink("/tmp", only_links.join("x")).unwrap();
    fs::write(only_links.join(".DS_Store"), b"").unwrap();

    assert!(links::prune_root(&only_links).is_some());
    assert!(links::prune_root(&busy).is_none());
    assert!(links::prune_root(&tmp.path().join("nada")).is_none());
    assert!(!only_links.exists());
    assert!(busy.exists());
    assert_eq!(
        links::real_subfolders(&busy),
        [busy.join("web").to_str().unwrap()]
    );
}

#[cfg(unix)]
#[test]
fn subpastas_de_verdade_nao_incluem_links() {
    let tmp = tempfile::tempdir().unwrap();
    fs::create_dir_all(tmp.path().join("b")).unwrap();
    fs::create_dir_all(tmp.path().join("a")).unwrap();
    std::os::unix::fs::symlink(tmp.path().join("a"), tmp.path().join("c-link")).unwrap();
    fs::write(tmp.path().join("arquivo"), b"").unwrap();
    let found = links::real_subfolders(tmp.path());
    assert_eq!(
        found,
        [
            tmp.path().join("a").to_str().unwrap(),
            tmp.path().join("b").to_str().unwrap()
        ]
    );
}

// ── NewProjectTests ────────────────────────────────────────────────────────

fn space_of(paths: &[&str]) -> WorkspaceConfig {
    let mut w = WorkspaceConfig::new("duck");
    w.projects = paths
        .iter()
        .map(|p| ProjectConfig::for_folder(&format!("{HOME}/{}", p.trim_start_matches("~/")), HOME))
        .collect();
    w
}

#[test]
fn sugere_a_pasta_mae_que_mais_projetos_dividem() {
    let ws = space_of(&["~/Documents/duck/a", "~/Code/x", "~/Documents/duck/b"]);
    assert_eq!(new_project::suggested_parent(&ws, HOME), "~/Documents/duck");
}

#[test]
fn empate_fica_com_o_projeto_mais_novo() {
    let ws = space_of(&["~/Documents/duck/a", "~/Code/x"]);
    assert_eq!(new_project::suggested_parent(&ws, HOME), "~/Code");
}

/// Multi-projeto mora na pasta do app: sugerir ali seria criar repositório
/// dentro de `~/.egeon`.
#[test]
fn ignora_multi_projeto_e_cai_no_padrao_quando_vazio() {
    let mut ws = space_of(&[]);
    ws.projects
        .push(multi_project("m", "m", "~/.egeon/projects/m", &[]));
    assert_eq!(new_project::suggested_parent(&ws, HOME), FALLBACK_PARENT);
}

#[test]
fn pasta_nova_e_criada_com_caminho_com_til() {
    let plan = new_project::plan("  api ", "~/Documents/duck", &space_of(&[]), HOME, |p| {
        (p == "/Users/eu/Documents/duck").then_some(true)
    });
    assert_eq!(
        plan,
        Ok(Plan {
            path: "~/Documents/duck/api".into(),
            create: true
        })
    );
}

#[test]
fn pasta_existente_e_adotada_nao_recriada() {
    let plan = new_project::plan("api", "~/Documents/duck", &space_of(&[]), HOME, |_| {
        Some(true)
    });
    assert_eq!(
        plan,
        Ok(Plan {
            path: "~/Documents/duck/api".into(),
            create: false
        })
    );
}

#[test]
fn recusas() {
    let problem = |name: &str, ws: &WorkspaceConfig, kind: &dyn Fn(&str) -> Option<bool>| {
        new_project::plan(name, "~/Documents/duck", ws, HOME, kind).err()
    };
    let dirs = |_: &str| Some(true);
    let empty = space_of(&[]);
    assert_eq!(problem("   ", &empty, &dirs), Some(Problem::EmptyName));
    assert_eq!(problem("a/b", &empty, &dirs), Some(Problem::InvalidName));
    assert_eq!(problem("a:b", &empty, &dirs), Some(Problem::InvalidName));
    assert_eq!(problem(".env", &empty, &dirs), Some(Problem::InvalidName));
    assert_eq!(problem("..", &empty, &dirs), Some(Problem::InvalidName));
    assert_eq!(
        problem("api", &empty, &|_| None),
        Some(Problem::MissingParent("~/Documents/duck".into()))
    );
    assert_eq!(
        problem("api", &empty, &|p| Some(!p.ends_with("/api"))),
        Some(Problem::FileInTheWay("~/Documents/duck/api".into()))
    );
    assert_eq!(
        problem("api", &space_of(&["~/Documents/duck/api"]), &dirs),
        Some(Problem::AlreadyProject("api".into()))
    );
}

#[test]
fn as_mensagens_das_recusas() {
    assert_eq!(Problem::EmptyName.message(), "Dê um nome ao projeto.");
    assert_eq!(
        Problem::MissingParent("~/x".into()).message(),
        "A pasta ~/x não existe."
    );
    assert_eq!(
        Problem::AlreadyProject("api".into()).message(),
        "Essa pasta já é o projeto \"api\" deste workspace."
    );
}

#[test]
fn o_tipo_no_disco() {
    let tmp = tempfile::tempdir().unwrap();
    let file = tmp.path().join("f");
    fs::write(&file, b"").unwrap();
    assert_eq!(
        new_project::disk_kind(tmp.path().to_str().unwrap()),
        Some(true)
    );
    assert_eq!(new_project::disk_kind(file.to_str().unwrap()), Some(false));
    assert_eq!(
        new_project::disk_kind(tmp.path().join("nada").to_str().unwrap()),
        None
    );
}

// ── LastConfigTests ────────────────────────────────────────────────────────

/// O workspace lembra a última configuração de cada CLI.
#[test]
fn lembrar_e_esquecer() {
    let mut space = WorkspaceConfig::new("Agro");
    space.remember(Some("/Users/x/.claude-agro"), "claude");
    assert_eq!(
        space.last_configs,
        Some(BTreeMap::from([(
            "claude".to_owned(),
            "/Users/x/.claude-agro".to_owned()
        )]))
    );
    let decoded: WorkspaceConfig =
        serde_json::from_str(&serde_json::to_string(&space).unwrap()).unwrap();
    assert_eq!(decoded.last_configs, space.last_configs);
    space.remember(None, "claude");
    assert_eq!(
        space.last_configs, None,
        "escolher o padrão apaga a lembrança"
    );
}

// ── ProjectFolder.materialize ──────────────────────────────────────────────

#[test]
fn cria_a_pasta_e_o_git_init_e_adota_a_que_ja_existe() {
    let tmp = tempfile::tempdir().unwrap();
    let home = fs::canonicalize(tmp.path()).unwrap();
    let home_s = home.to_str().unwrap();
    let git = crate::features::worktree::git::Git::new(
        std::env::vars_os()
            .filter(|(k, _)| !k.to_string_lossy().starts_with("GIT_"))
            .collect(),
    );

    let plan = Plan {
        path: "~/api".into(),
        create: true,
    };
    new_project::materialize(&plan, true, home_s, &git).unwrap();
    assert!(home.join("api/.git").exists());
    // Criar de novo a mesma pasta é erro; adotar não é, e não refaz o init.
    assert!(matches!(
        new_project::materialize(&plan, true, home_s, &git),
        Err(new_project::MaterializeError::Create { .. })
    ));
    let adopt = Plan {
        path: "~/api".into(),
        create: false,
    };
    new_project::materialize(&adopt, true, home_s, &git).unwrap();

    // Sem git: só a pasta.
    let plain = Plan {
        path: "~/solta".into(),
        create: true,
    };
    new_project::materialize(&plain, false, home_s, &git).unwrap();
    assert!(home.join("solta").is_dir() && !home.join("solta/.git").exists());
}

#[test]
fn o_nome_padrao_vem_das_pastas_na_ordem() {
    let folders = strings(&["/src/agro/nexus-web-app", "~/code/nexus-backend/"]);
    assert_eq!(
        default_name(&folders, HOME),
        "nexus-web-app + nexus-backend"
    );
    assert_eq!(default_name(&[], HOME), "");
    assert_eq!(default_name(&strings(&["/src/a"]), HOME), "a");
}

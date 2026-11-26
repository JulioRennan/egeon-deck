//! As respostas das rotas de organização: chaves e status iguais aos do Swift.

use std::collections::HashMap;

use serde_json::{Value, json};

use super::model::{ProjectConfig, WorkspaceConfig};
use super::routes::*;
use crate::features::activity::model::ActivitySummary;
use crate::features::node::model::{NodeConfig, NodeKind};
use crate::features::path_text::native;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::worktree::git::Git;
use crate::protocol::handler::RouteRequest;

fn req(path: &str, query: &[(&str, &str)]) -> RouteRequest {
    RouteRequest {
        method: "GET".into(),
        target: path.into(),
        path: path.into(),
        query: query
            .iter()
            .map(|(k, v)| ((*k).into(), (*v).into()))
            .collect(),
        body: vec![],
        origin: None,
    }
}

fn project(id: &str) -> ProjectConfig {
    let mut p = ProjectConfig::new(id, format!("~/{id}"));
    p.id = id.into();
    p
}

fn bench(id: &str, name: &str, project: Option<&str>) -> WorkbenchConfig {
    let mut w = WorkbenchConfig::new(name, format!("~/{name}"), vec![]);
    w.id = id.into();
    w.project = project.map(str::to_owned);
    w
}

fn state() -> OrgState {
    let mut w1 = WorkspaceConfig::new("Um");
    w1.id = "w1".into();
    w1.projects = vec![project("p1"), project("p2")];
    let mut w2 = WorkspaceConfig::new("Dois");
    w2.id = "w2".into();
    w2.projects = vec![project("p3")];
    OrgState {
        workspaces: vec![w1, w2],
        workbenches: vec![
            bench("b1", "um", Some("p1")),
            bench("b2", "dois", Some("p1")),
            bench("b3", "tres", Some("p2")),
            bench("b4", "perdida", Some("nada")),
        ],
        open_tabs: vec!["b3".into(), "b1".into(), "b2".into()],
        active_id: Some("b1".into()),
    }
}

fn names(v: &Value) -> Vec<&str> {
    v.as_array()
        .unwrap()
        .iter()
        .map(|x| x.as_str().unwrap())
        .collect()
}

#[test]
fn a_arvore_tem_as_chaves_da_barra() {
    let reply = workspaces(&state());
    assert_eq!(reply.status, 200);
    let tree = &reply.json;
    assert_eq!(tree["orphans"], json!(["perdida"]));
    let w1 = &tree["workspaces"][0];
    assert_eq!(w1["id"], "w1");
    assert_eq!(w1["icon"], "", "sem imagem é vazio, não ausente");
    assert_eq!(w1["collapsed"], false);
    assert_eq!(w1["projects"][0]["workbenches"], json!(["um", "dois"]));
    assert_eq!(w1["projects"][0]["path"], "~/p1");
    assert_eq!(
        tree["workspaces"][1]["projects"][0]["workbenches"],
        json!([])
    );
}

#[test]
fn mover_cada_tipo_de_coisa() {
    let mut s = state();
    let (reply, effects) = move_in_tree(
        &mut s,
        &req("/move", &[("kind", "workspace"), ("id", "w2"), ("to", "0")]),
    );
    assert_eq!((reply.status, reply.json["ok"].clone()), (200, json!(true)));
    assert_eq!(reply.json["tree"]["workspaces"][0]["id"], "w2");
    assert_eq!(effects, [OrgEffect::SaveWorkspaces]);

    // Mesmo lugar: nada mudou, ok false e 400, sem efeito.
    let (reply, effects) = move_in_tree(
        &mut s,
        &req("/move", &[("kind", "workspace"), ("id", "w2"), ("to", "0")]),
    );
    assert_eq!(
        (reply.status, reply.json["ok"].clone()),
        (400, json!(false))
    );
    assert!(effects.is_empty() && reply.json["tree"].is_object());

    // Projeto para outro workspace.
    let (reply, _) = move_in_tree(
        &mut s,
        &req(
            "/move",
            &[
                ("kind", "project"),
                ("id", "p1"),
                ("parent", "w2"),
                ("to", "0"),
            ],
        ),
    );
    assert_eq!(reply.status, 200);
    assert_eq!(s.workspaces[0].projects[0].id, "p1");

    // Bancada pelo NOME (ou pelo id), para dentro de outro projeto.
    let (reply, effects) = move_in_tree(
        &mut s,
        &req(
            "/move",
            &[
                ("kind", "workbench"),
                ("id", "tres"),
                ("parent", "p1"),
                ("to", "0"),
            ],
        ),
    );
    assert_eq!(reply.status, 200, "{}", reply.json);
    assert_eq!(s.workbenches[0].name, "tres");
    assert_eq!(effects, [OrgEffect::PersistWorkbenches]);
    let (reply, _) = move_in_tree(
        &mut s,
        &req(
            "/move",
            &[("kind", "workbench"), ("id", "nada"), ("parent", "p1")],
        ),
    );
    assert_eq!(reply.status, 400);
    assert_eq!(
        reply.json,
        json!({"ok": false, "error": "bancada desconhecida 'nada'"})
    );

    let (reply, _) = move_in_tree(&mut s, &req("/move", &[("kind", "robo")]));
    assert_eq!(
        reply.json,
        json!({"ok": false, "error": "kind é workspace, project, workbench, store, unstore ou drawer"})
    );
}

#[test]
fn guardar_abre_a_gaveta_e_tirar_nao_e_o_drawer_alterna() {
    let mut s = state();
    let (reply, effects) = move_in_tree(
        &mut s,
        &req(
            "/move",
            &[("kind", "store"), ("id", "p1"), ("parent", "w1")],
        ),
    );
    assert_eq!(reply.status, 200);
    assert!(
        s.workspaces[0]
            .projects
            .iter()
            .any(|p| p.id == "p1" && p.is_stored())
    );
    assert!(
        s.workspaces[0].is_stored_open(),
        "guardar com a gaveta fechada faria o projeto sumir"
    );
    assert_eq!(
        effects,
        [OrgEffect::SaveWorkspaces, OrgEffect::SaveWorkspaces]
    );

    move_in_tree(
        &mut s,
        &req(
            "/move",
            &[("kind", "unstore"), ("id", "p1"), ("parent", "w1")],
        ),
    );
    assert!(!s.workspaces[0].projects.iter().any(|p| p.is_stored()));

    move_in_tree(&mut s, &req("/move", &[("kind", "drawer"), ("id", "w1")]));
    assert!(!s.workspaces[0].is_stored_open());
    move_in_tree(&mut s, &req("/move", &[("kind", "drawer"), ("id", "w1")]));
    assert!(s.workspaces[0].is_stored_open());
    // Workspace desconhecido: o Swift responde ok mesmo assim.
    let (reply, _) = move_in_tree(&mut s, &req("/move", &[("kind", "drawer"), ("id", "x")]));
    assert_eq!(reply.json["ok"], true);
}

#[test]
fn projeto_novo_cria_a_pasta_o_git_e_entra_no_workspace() {
    let tmp = tempfile::tempdir().unwrap();
    let home = crate::commons::paths::canonicalize(tmp.path()).unwrap();
    let home_s = home.to_str().unwrap();
    std::fs::create_dir_all(home.join("Documents/duck")).unwrap();
    let git = Git::new(
        std::env::vars_os()
            .filter(|(k, _)| !k.to_string_lossy().starts_with("GIT_"))
            .collect(),
    );
    let mut s = state();
    s.workspaces[0].projects = vec![ProjectConfig::for_folder(
        &native(&format!("{home_s}/Documents/duck/a")),
        home_s,
    )];
    s.workspaces[0].collapsed = Some(true);

    let (reply, effects) = project_new(
        &s,
        &req("/project/new", &[("workspace", "Um"), ("name", "api")]),
        home_s,
        &git,
    );
    assert_eq!(reply.status, 200, "{}", reply.json);
    assert_eq!(reply.json["path"], native("~/Documents/duck/api"));
    assert_eq!(reply.json["created"], true);
    assert!(home.join("Documents/duck/api/.git").exists());
    // O retrato já mostra o projeto novo, com o workspace aberto.
    let projects = reply.json["tree"]["workspaces"][0]["projects"]
        .as_array()
        .unwrap();
    assert_eq!(
        projects.last().unwrap()["path"],
        native("~/Documents/duck/api")
    );
    assert_eq!(reply.json["tree"]["workspaces"][0]["collapsed"], false);
    let [
        effect @ OrgEffect::AddProject { workspace_id, .. },
        OrgEffect::SaveWorkspaces,
        OrgEffect::Log { .. },
    ] = effects.as_slice()
    else {
        panic!("{effects:?}");
    };
    assert_eq!(workspace_id, "w1");
    apply_add_project(&mut s, effect);
    assert_eq!(s.workspaces[0].projects.len(), 2);
    assert_eq!(s.workspaces[0].collapsed, None);

    // `git=0`, `parent` explícito e a pasta que já existe é adotada.
    let (reply, _) = project_new(
        &s,
        &req(
            "/project/new",
            &[
                ("workspace", "w2"),
                ("name", "solta"),
                ("parent", "~/Documents"),
                ("git", "0"),
            ],
        ),
        home_s,
        &git,
    );
    assert_eq!(reply.json["path"], native("~/Documents/solta"));
    assert!(home.join("Documents/solta").is_dir() && !home.join("Documents/solta/.git").exists());
}

#[test]
fn projeto_novo_recusa_com_a_mensagem_do_swift() {
    let tmp = tempfile::tempdir().unwrap();
    let home = tmp.path().to_str().unwrap();
    let git = Git::inheriting();
    let s = state();
    let ask = |q: &[(&str, &str)]| project_new(&s, &req("/project/new", q), home, &git).0;
    let unknown = ask(&[("workspace", "ninguém"), ("name", "x")]);
    assert_eq!(
        (unknown.status, unknown.json),
        (
            400,
            json!({"ok": false, "error": "workspace desconhecido 'ninguém'"})
        )
    );
    assert_eq!(
        ask(&[("workspace", "w1"), ("name", "  ")]).json["error"],
        "Dê um nome ao projeto."
    );
    assert_eq!(
        ask(&[("workspace", "w1"), ("name", "a/b")]).json["error"],
        "O nome não pode ter \"/\" nem \":\", nem começar com ponto."
    );
    assert!(
        ask(&[
            ("workspace", "w1"),
            ("name", "x"),
            ("parent", "/nao/existe")
        ])
        .json["error"]
            .as_str()
            .unwrap()
            .starts_with("A pasta /nao/existe não existe")
    );
}

#[test]
fn a_cor_da_bancada() {
    let mut s = state();
    let (reply, effects) = workbench_color(
        &mut s,
        &req("/workbench/color", &[("name", "um"), ("color", "Areia")]),
    );
    assert_eq!(
        reply.json,
        json!({"ok": true, "workbench": "um", "color": "sand"})
    );
    assert_eq!(s.workbenches[0].color.map(|c| c.raw()), Some("sand"));
    assert!(effects.contains(&OrgEffect::PersistWorkbenches));
    // A mesma cor de novo: ok e sem gravar.
    let (_, effects) = workbench_color(
        &mut s,
        &req("/workbench/color", &[("name", "um"), ("color", "sand")]),
    );
    assert!(effects.is_empty());

    let (bad, _) = workbench_color(
        &mut s,
        &req("/workbench/color", &[("name", "um"), ("color", "dourado")]),
    );
    assert_eq!(bad.status, 400);
    assert_eq!(bad.json["error"], "cor desconhecida 'dourado'");
    assert_eq!(bad.json["palette"].as_array().unwrap().len(), 24);
    let (nobody, _) = workbench_color(
        &mut s,
        &req("/workbench/color", &[("name", "x"), ("color", "sand")]),
    );
    assert_eq!(
        nobody.json,
        json!({"ok": false, "error": "bancada desconhecida 'x'"})
    );
    let (show, effects) = workbench_color(&mut s, &req("/workbench/color", &[("show", "1")]));
    assert_eq!(
        (show.json, effects),
        (json!({"ok": true}), vec![OrgEffect::ShowPalette])
    );
}

fn tabs_call(s: &mut OrgState, q: &[(&str, &str)]) -> (u16, Value, Vec<OrgEffect>) {
    let activity: HashMap<String, ActivitySummary> = HashMap::from([(
        "tres".to_owned(),
        ActivitySummary {
            attention: 1,
            ..Default::default()
        },
    )]);
    let (reply, effects) = tabs(s, &req("/tabs", q), &activity, &TabsView::default());
    (reply.status, reply.json, effects)
}

#[test]
fn o_retrato_da_faixa() {
    let mut s = state();
    let (status, body, effects) = tabs_call(&mut s, &[]);
    assert_eq!(status, 200);
    assert_eq!(
        body,
        json!({"open": ["  tres ●!", "▸ um", "  dois"], "active": "um", "visible": false,
               "placement": [], "inset": -1.0, "count": 3})
    );
    assert!(effects.is_empty());
}

#[test]
fn mover_a_aba_como_o_arrasto() {
    let mut s = state();
    let (status, body, effects) = tabs_call(&mut s, &[("move", "dois"), ("to", "0")]);
    assert_eq!(status, 200);
    assert_eq!(
        (
            body["ok"].clone(),
            body["moved"].clone(),
            body["to"].clone()
        ),
        (json!(true), json!("dois"), json!(0))
    );
    assert_eq!(body["open"], json!(["  dois", "  tres ●!", "▸ um"]));
    assert_eq!(s.open_tabs, ["b2", "b3", "b1"]);
    assert!(effects.contains(&OrgEffect::ReorderTabs {
        order: s.open_tabs.clone()
    }));

    let (status, body, _) = tabs_call(&mut s, &[("move", "dois"), ("to", "9")]);
    assert_eq!(status, 404);
    assert_eq!(body["error"], "posição fora da faixa (0…2)");
    assert_eq!(
        tabs_call(&mut s, &[("move", "dois")]).1["error"],
        "posição fora da faixa (0…2)"
    );
    assert_eq!(
        tabs_call(&mut s, &[("move", "perdida"), ("to", "0")]).1["error"],
        "'perdida' não está na faixa"
    );
    assert_eq!(
        tabs_call(&mut s, &[("move", "x"), ("to", "0")]).1["error"],
        "bancada desconhecida 'x'"
    );
}

#[test]
fn fechar_a_aba_leva_para_a_vizinha_e_a_bancada_continua_de_pe() {
    let mut s = state();
    let (status, body, effects) = tabs_call(&mut s, &[("close", "um")]);
    assert_eq!(status, 200);
    assert_eq!(body["closed"], "um");
    assert_eq!(body["count"], 2);
    assert_eq!(
        body["active"], "dois",
        "a vizinha da direita entra no lugar"
    );
    assert_eq!(s.workbenches.len(), 4, "a bancada continua de pé");
    assert!(effects.contains(&OrgEffect::Activate { id: "b2".into() }));
    assert!(effects.contains(&OrgEffect::CloseTab { id: "b1".into() }));

    // A última aba: não sobra quem ativar.
    tabs_call(&mut s, &[("close", "dois")]);
    let (_, body, effects) = tabs_call(&mut s, &[("close", "tres")]);
    assert_eq!(body["active"], "");
    assert_eq!(body["count"], 0);
    assert!(
        !effects
            .iter()
            .any(|e| matches!(e, OrgEffect::Activate { .. }))
    );
    let (status, body, _) = tabs_call(&mut s, &[("close", "tres")]);
    assert_eq!(
        (status, body["error"].clone()),
        (404, json!("'tres' não está na faixa"))
    );
}

#[test]
fn ativar_a_bancada() {
    let s = state();
    let (reply, effects) = activate(&s, &req("/activate", &[("target", "dois")]));
    assert_eq!(reply.status, 200);
    assert_eq!(reply.json["ok"], true);
    assert_eq!(reply.json["workspace"], "dois");
    assert_eq!(
        names(&reply.json["known"]),
        ["um", "dois", "tres", "perdida"]
    );
    assert_eq!(effects, [OrgEffect::Activate { id: "b2".into() }]);
    let (reply, effects) = activate(&s, &req("/activate", &[("target", "nada")]));
    assert_eq!(reply.status, 404);
    assert!(effects.is_empty());
}

#[test]
fn a_rota_de_ligacao() {
    let mut s = state();
    s.workbenches[0].nodes = vec![
        NodeConfig::new(NodeKind::Agent, "a"),
        NodeConfig::new(NodeKind::Agent, "b"),
    ];
    let (reply, effects) = edge(
        &mut s,
        &req("/edge", &[("target", "um"), ("from", "a"), ("to", "b")]),
    );
    assert_eq!(reply.status, 200);
    assert_eq!(
        reply.json,
        json!({"ok": true, "a": "a", "b": "b", "direction": "<->", "maxSends": 2, "edges": ["a→b", "b→a"]})
    );
    assert!(effects.contains(&OrgEffect::PersistWorkbenches));
    assert!(effects.contains(&OrgEffect::Log {
        line: "aresta[um]: a ↔ b".into()
    }));

    let (reply, effects) = edge(
        &mut s,
        &req("/edge", &[("target", "um"), ("from", "a"), ("to", "b")]),
    );
    assert_eq!(reply.json["direction"], "<->");
    assert!(effects.is_empty(), "consulta não grava");

    let (reply, _) = edge(
        &mut s,
        &req("/edge", &[("target", "um"), ("from", "a"), ("to", "x")]),
    );
    assert_eq!(reply.status, 400);
    let (reply, _) = edge(&mut s, &req("/edge", &[("target", "nada")]));
    assert_eq!(
        reply.json,
        json!({"ok": false, "error": "bancada desconhecida 'nada'"})
    );
}

#[test]
fn guardar_na_posicao_pedida_dentro_da_gaveta() {
    let mut s = state();
    s.workspaces[0].projects = vec![project("p1"), project("p2"), project("p3")];
    for id in ["p2", "p3"] {
        move_in_tree(
            &mut s,
            &req("/move", &[("kind", "store"), ("id", id), ("parent", "w1")]),
        );
    }
    let drawer = |s: &OrgState| {
        s.workspaces[0]
            .stored_projects()
            .map(|p| p.id.clone())
            .collect::<Vec<_>>()
    };
    assert_eq!(drawer(&s), ["p2", "p3"], "sem `to`, no fim");
    move_in_tree(
        &mut s,
        &req(
            "/move",
            &[
                ("kind", "store"),
                ("id", "p1"),
                ("parent", "w1"),
                ("to", "0"),
            ],
        ),
    );
    assert_eq!(drawer(&s), ["p1", "p2", "p3"], "com `to`, na posição");
}

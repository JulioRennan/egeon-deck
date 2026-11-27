//! Remover bancada, worktree sem bancada de origem, multi-projeto e templates
//! de bancada, pelo socket da UI.

use serde_json::{Value, json};

use super::{Harness, TempHome, git_in, repo_with_env, saved_eventually};

fn data_json(h: &Harness, file: &str) -> Value {
    let text = std::fs::read_to_string(h._home.0.join("data").join(file)).unwrap_or_default();
    serde_json::from_str(&text).unwrap_or(Value::Null)
}

/// Uma bancada numa worktree com trabalho não commitado: o plano só lista a
/// worktree (rápido, o diálogo abre logo); o texto da 2ª confirmação vem
/// depois, por `removal_losses`, com a cortina de pé enquanto o git corre.
#[tokio::test]
async fn plano_de_remocao_lista_as_worktrees_e_o_que_se_perde() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let wt = repo.parent().unwrap().join("wt-feat");
    git_in(
        &repo,
        &["worktree", "add", "-q", "-b", "feat", wt.to_str().unwrap()],
    );
    std::fs::write(wt.join("a.txt"), "mudou").unwrap();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": wt.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "sh"}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "plan_remove_workbench", "workbench": "1a2b3c4d"}))
        .await;
    let plan = ui.reply(1).await;
    let list = plan["worktrees"].as_array().expect("lista, não número");
    assert_eq!(list.len(), 1, "{plan}");
    assert_eq!(list[0]["repo"], "repo");
    assert_eq!(list[0]["branch"], "feat");
    assert!(list[0]["used_by"].is_null());
    assert!(
        plan.get("losses").is_none(),
        "o git status fica para depois"
    );

    ui.send(json!({"id": 2, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    ui.until(|v| v["topic"] == "workspaces").await;
    ui.send(json!({"id": 3, "cmd": "removal_losses", "workbench": "1a2b3c4d"}))
        .await;
    let curtain = ui
        .until(|v| {
            v["topic"] == "workspaces"
                && bench_of(v, "1a2b3c4d").is_some_and(|b| b["busy"].is_string())
        })
        .await;
    assert_eq!(
        bench_of(&curtain, "1a2b3c4d").unwrap()["busy"],
        "Conferindo o que se perde…"
    );
    let answer = ui.reply(3).await;
    let losses = answer["losses"].as_array().expect("lista");
    assert_eq!(losses[0], "repo · feat");
    assert!(
        losses.iter().any(|l| l.as_str().unwrap().contains("a.txt")),
        "{answer}"
    );
    ui.send(json!({"id": 4, "cmd": "removal_losses", "workbench": "ffffffff"}))
        .await;
    assert_eq!(
        ui.reply(4).await["error"],
        "bancada desconhecida 'ffffffff'"
    );
    h.stop().await.unwrap();
}

#[tokio::test]
async fn formulario_de_worktree_sem_bancada_le_a_pasta_ou_o_projeto() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let spaces = json!([{"id": "9f8e7d6c", "name": "w", "projects": [
        {"id": "aaaa0001", "name": "repo", "path": repo.to_string_lossy()}
    ]}]);
    let h = Harness::start_with_files(&[("workspaces.json", spaces.to_string())]).await;
    let mut ui = h.ui().await;

    ui.send(json!({"id": 1, "cmd": "worktree_info", "path": repo.to_string_lossy()}))
        .await;
    let info = ui.reply(1).await;
    assert_eq!(info["suggested_branch"], "main-2", "{info}");
    assert_eq!(info["repo"], "repo");
    assert_eq!(info["nodes"], json!([]));

    ui.send(json!({"id": 2, "cmd": "worktree_info", "project": "aaaa0001"}))
        .await;
    assert_eq!(ui.reply(2).await["repo"], "repo");

    ui.send(json!({"id": 3, "cmd": "worktree_plan", "project": "aaaa0001", "branch": "nova"}))
        .await;
    let plan = ui.reply(3).await;
    assert_eq!(plan["verdict"], "create", "{plan}");

    ui.send(json!({"id": 4, "cmd": "worktree_info"})).await;
    assert_eq!(ui.reply(4).await["error"], "pede a pasta do repositório");
    ui.send(json!({"id": 5, "cmd": "worktree_info", "project": "ffffffff"}))
        .await;
    assert_eq!(
        ui.reply(5).await["error"],
        "projeto desconhecido 'ffffffff'"
    );
    let plain = dir.0.join("solta");
    std::fs::create_dir_all(&plain).unwrap();
    ui.send(json!({"id": 6, "cmd": "worktree_info", "path": plain.to_string_lossy()}))
        .await;
    assert!(
        ui.reply(6).await["error"]
            .as_str()
            .unwrap()
            .ends_with("não é repositório git")
    );

    // Criar a partir do projeto: a bancada nasce no projeto, na worktree.
    ui.send(json!({"id": 7, "cmd": "worktree", "project": "aaaa0001", "branch": "nova"}))
        .await;
    let done = ui.reply(7).await;
    assert_eq!(done["ok"], true, "{done}");
    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.len() == 1)).await;
    assert_eq!(saved[0]["project"], "aaaa0001");
    assert_eq!(saved[0]["id"], done["workbench"]);
    h.stop().await.unwrap();
}

/// Multi-projeto: o formulário é o de um campo por repositório, e a branch de
/// cada um vale na criação.
#[tokio::test]
async fn multi_projeto_tem_formulario_proprio_e_branch_por_repositorio() {
    let dir = TempHome::new();
    let root = crate::commons::paths::canonicalize(&dir.0).unwrap();
    let make = |name: &str| {
        let repo = root.join(name);
        std::fs::create_dir_all(&repo).unwrap();
        git_in(&repo, &["init", "-q", "-b", "main", "."]);
        git_in(&repo, &["config", "user.email", "t@e"]);
        git_in(&repo, &["config", "user.name", "t"]);
        std::fs::write(repo.join("a.txt"), "a").unwrap();
        git_in(&repo, &["add", "-A"]);
        git_in(&repo, &["commit", "-qm", "init"]);
        repo
    };
    let (api, web) = (make("api"), make("web"));
    let spaces = json!([{"id": "9f8e7d6c", "name": "w", "projects": [
        {"id": "aaaa0001", "name": "api", "path": api.to_string_lossy()},
        {"id": "aaaa0002", "name": "web", "path": web.to_string_lossy()},
        {"id": "aaaa0003", "name": "Nexus", "path": root.join("links").to_string_lossy(),
         "members": ["aaaa0001", "aaaa0002"]}
    ]}]);
    let h = Harness::start_with_files(&[("workspaces.json", spaces.to_string())]).await;
    let mut ui = h.ui().await;

    ui.send(json!({"id": 1, "cmd": "worktree_info", "project": "aaaa0003"}))
        .await;
    let info = ui.reply(1).await;
    assert_eq!(
        info["multi"],
        json!({"project": "Nexus", "repos": ["api", "web"]}),
        "{info}"
    );

    ui.send(
        json!({"id": 2, "cmd": "worktree", "project": "aaaa0003", "branch": "frente",
                   "repos": {"web": "fix/web"}}),
    )
    .await;
    let done = ui.reply(2).await;
    assert_eq!(done["ok"], true, "{done}");
    let path = std::path::PathBuf::from(done["path"].as_str().unwrap());
    let branch_of = |repo: &str| {
        let out = std::process::Command::new("git")
            .args(["branch", "--show-current"])
            .current_dir(path.join(repo))
            .output()
            .unwrap();
        String::from_utf8_lossy(&out.stdout).trim().to_owned()
    };
    assert_eq!(branch_of("api"), "frente");
    assert_eq!(branch_of("web"), "fix/web");

    // A bancada multi que nasceu dali duplica pelo mesmo formulário.
    let id = done["workbench"].as_str().unwrap().to_owned();
    saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.len() == 1)).await;
    ui.send(json!({"id": 3, "cmd": "worktree_info", "workbench": id}))
        .await;
    assert_eq!(ui.reply(3).await["multi"]["project"], "Nexus");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn salvar_template_planeja_grava_e_atualiza_o_de_origem() {
    let dir = TempHome::new();
    let benches = json!([
        {"id": "1a2b3c4d", "name": "deck", "path": "~/deck",
         "nodes": [{"type": "agent", "id": "rev", "agent": "claude", "conversationId": "VELHA"},
                   {"type": "web", "id": "w", "url": "http://localhost:3000/a/b"}]},
        {"id": "5e6f7a8b", "name": "vazia", "path": dir.0.to_string_lossy(), "nodes": []}
    ]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;

    ui.send(
        json!({"id": 1, "cmd": "save_template", "workbench": "1a2b3c4d",
                   "name": "dupla", "dry_run": true}),
    )
    .await;
    let plan = ui.reply(1).await;
    assert_eq!(
        plan["summary"],
        "1 agente, 1 web — com posição, tamanho, pasta de cada nó e ~/deck como pasta inicial."
    );
    assert_eq!(plan["nodes"], 2);
    assert_eq!(plan["template"], "dupla");
    assert_eq!(plan["exists"], false);
    assert_eq!(data_json(&h, "templates.json"), Value::Null, "só planeja");

    // Atualizar sem origem não tem alvo.
    ui.send(json!({"id": 2, "cmd": "save_template", "workbench": "1a2b3c4d"}))
        .await;
    assert_eq!(
        ui.reply(2).await["error"],
        "a bancada não nasceu de um template"
    );

    ui.send(json!({"id": 3, "cmd": "save_template", "workbench": "1a2b3c4d", "name": " dupla "}))
        .await;
    assert_eq!(ui.reply(3).await["template"], "dupla");
    let templates = data_json(&h, "templates.json");
    let nodes = &templates["dupla"]["nodes"];
    assert_eq!(nodes.as_array().unwrap().len(), 2);
    assert!(
        nodes[0].get("conversationId").is_none(),
        "molde sem conversa"
    );
    assert_eq!(nodes[1]["url"], "http://localhost:3000");
    assert_eq!(templates["dupla"]["basePath"], "~/deck");
    let saved = saved_eventually(&h, |v| v[0]["template"] == "dupla").await;
    assert_eq!(
        saved[0]["template"], "dupla",
        "a bancada passa a ter origem"
    );

    ui.send(json!({"id": 4, "cmd": "save_template", "workbench": "1a2b3c4d", "dry_run": true}))
        .await;
    let plan = ui.reply(4).await;
    assert_eq!(plan["template"], "dupla");
    assert_eq!(plan["exists"], true);
    ui.send(json!({"id": 5, "cmd": "save_template", "workbench": "1a2b3c4d"}))
        .await;
    assert_eq!(ui.reply(5).await["template"], "dupla");

    // O template apagado à mão: atualizar não vira "salvar como".
    std::fs::write(
        h._home
            .0
            .join(crate::features::path_text::native("data/templates.json")),
        "{}",
    )
    .unwrap();
    ui.send(json!({"id": 6, "cmd": "save_template", "workbench": "1a2b3c4d"}))
        .await;
    assert_eq!(
        ui.reply(6).await["error"],
        "o template \"dupla\" não existe mais"
    );

    ui.send(json!({"id": 7, "cmd": "save_template", "workbench": "5e6f7a8b", "name": "x"}))
        .await;
    assert_eq!(ui.reply(7).await["error"], "canvas vazio");
    ui.send(json!({"id": 8, "cmd": "save_template", "workbench": "1a2b3c4d", "name": "  "}))
        .await;
    assert_eq!(ui.reply(8).await["error"], "o template pede um nome");
    h.stop().await.unwrap();
}

fn bench_of<'a>(tree: &'a Value, id: &str) -> Option<&'a Value> {
    tree["workbenches"]
        .as_array()?
        .iter()
        .find(|b| b["id"] == id)
}

/// A cortina "um instante" vem pronta do core enquanto a remoção corre.
#[tokio::test]
async fn remover_publica_a_cortina_um_instante() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&super::two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    ui.until(|v| v["topic"] == "workspaces").await;
    ui.send(json!({"id": 2, "cmd": "remove_workbench", "workbench": "5e6f7a8b"}))
        .await;
    let busy = ui
        .until(|v| {
            v["topic"] == "workspaces"
                && bench_of(v, "5e6f7a8b").is_some_and(|b| b["busy"].is_string())
        })
        .await;
    assert_eq!(
        bench_of(&busy, "1a2b3c4d").map(|b| b.get("busy").is_none()),
        Some(true),
        "só a que sai"
    );
    assert_eq!(
        bench_of(&busy, "5e6f7a8b").unwrap()["busy"],
        "Removendo a bancada…"
    );
    h.stop().await.unwrap();
}

/// A faixa diz o que está sendo copiado para a worktree nova e, no fim, o
/// resumo da cópia.
#[tokio::test]
async fn worktree_nova_mostra_a_faixa_da_copia() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": repo.to_string_lossy(),
                          "nodes": []}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    ui.until(|v| v["topic"] == "workspaces").await;
    ui.send(json!({"id": 2, "cmd": "worktree", "workbench": "1a2b3c4d", "branch": "faixa"}))
        .await;
    let banner = |v: &Value, prefix: &str| {
        v["topic"] == "workspaces"
            && v["workbenches"].as_array().is_some_and(|list| {
                list.iter().any(|b| {
                    b["banner"]
                        .as_str()
                        .is_some_and(|text| text.starts_with(prefix))
                })
            })
    };
    ui.until(|v| banner(v, "Copiando o que o git não versiona em repo"))
        .await;
    ui.until(|v| banner(v, "repo: ")).await;
    h.stop().await.unwrap();
}

#[tokio::test]
async fn copiar_alvos_devolve_um_endereco_por_linha() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&super::two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "open_workbench", "workbench": "1a2b3c4d"}))
        .await;
    ui.reply(1).await;
    let mut text = String::new();
    for id in 2..200 {
        ui.send(json!({"id": id, "cmd": "copy_targets"})).await;
        text = ui.reply(id).await["text"].as_str().unwrap().to_owned();
        if text.contains("deck/sh") {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    let lines: Vec<&str> = text.lines().collect();
    assert!(lines.contains(&"deck/sh"), "{text}");
    let mut sorted = lines.clone();
    sorted.sort_unstable();
    assert_eq!(lines, sorted, "em ordem, como o `sorted()` do Swift");
    h.stop().await.unwrap();
}

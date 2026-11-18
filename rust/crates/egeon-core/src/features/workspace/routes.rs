//! As rotas de organização do `ControlSocket.swift` que são regra pura de
//! árvore, aba e ligação: `/workspaces`, `/move`, `/project/new`, `/workbench/color`,
//! `/tabs`, `/activate` e `/edge`.
//!
//! Cada handler recebe o [`OrgState`] (a organização que o ator guarda) e a
//! requisição, aplica a regra nele e devolve a resposta com as chaves do Swift
//! mais os [`OrgEffect`] que o ator ainda tem de cumprir — gravar, ativar,
//! fechar a aba na tela. `/project/new` mexe em disco e no git: é a única
//! BLOQUEANTE, e trabalha sobre uma cópia do estado (o core a chama em
//! `spawn_blocking` e aplica `AddProject`).
//!
//! `/remove`, `/workbench/clear`, `/node/clear`, `/model`, `/layout`, `/sidebar`
//! e `/geometry` dependem de terminais e de tela: são do runtime.

use std::collections::HashMap;

use serde_json::{Map, Value, json};

use super::model::{ProjectConfig, WorkspaceConfig};
use super::new_project::{self, disk_kind};
use super::reorder;
use super::tree::WorkspaceTree;
use crate::features::activity::model::ActivitySummary;
use crate::features::canvas::edges;
use crate::features::workbench::model::{WorkbenchColor, WorkbenchConfig};
use crate::features::workbench::service::id_of_name;
use crate::features::workbench::tabs::{build_tabs, moved, neighbour};
use crate::features::worktree::git::Git;
use crate::protocol::handler::{RouteReply, RouteRequest};

/// A organização como o ator a guarda.
#[derive(Debug, Clone, Default)]
pub struct OrgState {
    pub workspaces: Vec<WorkspaceConfig>,
    /// A lista plana, indexada por posição.
    pub workbenches: Vec<WorkbenchConfig>,
    /// Os ids das bancadas abertas na faixa, na ordem dela.
    pub open_tabs: Vec<String>,
    pub active_id: Option<String>,
}

/// O que o ator cumpre depois do handler.
#[derive(Debug, Clone, PartialEq)]
pub enum OrgEffect {
    /// `workspaces.json` mudou.
    SaveWorkspaces,
    /// `workbenches.json` mudou (com atraso e junto, como o Swift agenda).
    PersistWorkbenches,
    /// Põe a bancada na frente.
    Activate { id: String },
    /// A aba foi fechada no estado; a bancada continua de pé. O ator troca a
    /// tela para a vizinha (`active_id` já aponta para ela) ou a esvazia.
    CloseTab { id: String },
    /// A faixa foi reordenada no estado.
    ReorderTabs { order: Vec<String> },
    /// Abre a grade de cores na bancada ativa (`/workbench/color?show=1`).
    ShowPalette,
    /// O banner de ciclo de ligação.
    Banner { text: String },
    /// Projeto novo: entra no fim da lista do workspace (que abre, se estava
    /// recolhido).
    AddProject {
        workspace_id: String,
        project: ProjectConfig,
    },
    /// Linha de log.
    Log { line: String },
}

fn log(line: String) -> OrgEffect {
    OrgEffect::Log { line }
}

fn status_by_ok(json: &Value, bad: u16) -> u16 {
    if json["ok"].as_bool().unwrap_or(false) {
        200
    } else {
        bad
    }
}

// ── /workspaces ────────────────────────────────────────────────────────────

/// A árvore da barra lateral (ADR-043), para conferir conciliação e
/// pertencimento sem abrir a barra.
pub fn tree_snapshot(state: &OrgState) -> Value {
    let tree = WorkspaceTree::new(&state.workspaces, &state.workbenches);
    let name = |i: usize| state.workbenches[i].name.clone();
    json!({
        "workspaces": state.workspaces.iter().map(|space| json!({
            "id": space.id, "name": space.name, "icon": space.icon.clone().unwrap_or_default(),
            "collapsed": space.is_collapsed(),
            "projects": space.projects.iter().map(|project| json!({
                "id": project.id, "name": project.name, "path": project.path,
                "collapsed": project.is_collapsed(),
                "workbenches": tree.indices_in_project(&project.id).into_iter().map(name).collect::<Vec<_>>(),
            })).collect::<Vec<_>>(),
        })).collect::<Vec<_>>(),
        "orphans": tree.orphans().into_iter().map(name).collect::<Vec<_>>(),
    })
}

/// `GET /workspaces` (`ControlSocket.swift:640`).
pub fn workspaces(state: &OrgState) -> RouteReply {
    RouteReply::ok(tree_snapshot(state))
}

// ── /move ──────────────────────────────────────────────────────────────────

fn position(req: &RouteRequest) -> usize {
    // `Int(query["to"]) ?? 0`; negativo cai em 0, como o `max(0, …)` de quem
    // recebe.
    req.param("to")
        .and_then(|t| t.parse::<i64>().ok())
        .map_or(0, |n| usize::try_from(n).unwrap_or(0))
}

/// `GET /move?kind=workspace|project|workbench|store|unstore|drawer&id=<id>&to=<n>[&parent=<id>]`
/// (`ControlSocket.swift:549`) — reposiciona na árvore. Arrastar não é dirigível
/// de fora sem Acessibilidade (ADR-003), e esta é a mesma operação.
pub fn move_in_tree(state: &mut OrgState, req: &RouteRequest) -> (RouteReply, Vec<OrgEffect>) {
    let kind = req.param("kind").unwrap_or("");
    let id = req.param("id").unwrap_or("");
    let parent = req.param("parent").unwrap_or("");
    let to = position(req);
    let mut effects = Vec::new();

    let ok = match kind {
        "workspace" => apply_spaces(
            state,
            &mut effects,
            reorder::workspace(id, to, &state.workspaces),
        ),
        "project" => {
            let moved = reorder::project(id, parent, to, None, &state.workspaces);
            apply_spaces(state, &mut effects, moved)
        }
        "store" | "unstore" => {
            let stored = kind == "store";
            // Sem `to` vai para o fim do lado de destino, que é onde a mão o
            // deixaria; com `to`, na posição pedida dentro da gaveta (decisão 24).
            let at = if req.param("to").is_some() {
                to
            } else {
                usize::MAX
            };
            let moved = reorder::project(id, parent, at, Some(stored), &state.workspaces);
            apply_spaces(state, &mut effects, moved);
            // Guardar com a gaveta fechada faria o projeto sumir sem explicação.
            if stored
                && let Some(space) = state.workspaces.iter_mut().find(|w| w.id == parent)
                && !space.is_stored_open()
            {
                space.stored_open = Some(true);
                effects.push(OrgEffect::SaveWorkspaces);
            }
            true
        }
        "drawer" => {
            if let Some(space) = state.workspaces.iter_mut().find(|w| w.id == id) {
                space.stored_open = if space.is_stored_open() {
                    None
                } else {
                    Some(true)
                };
                effects.push(OrgEffect::SaveWorkspaces);
            }
            true
        }
        "workbench" => {
            let Some(index) = state
                .workbenches
                .iter()
                .position(|w| w.name == id || w.id == id)
            else {
                let json = json!({"ok": false, "error": format!("bancada desconhecida '{id}'")});
                return (RouteReply::with_status(400, json), effects);
            };
            match reorder::workbench(index, parent, to, &state.workbenches) {
                Some(done) => {
                    state.workbenches = done.list;
                    effects.push(OrgEffect::PersistWorkbenches);
                    true
                }
                None => false,
            }
        }
        _ => {
            let error = "kind é workspace, project, workbench, store, unstore ou drawer";
            return (RouteReply::err(400, error), effects);
        }
    };
    let json = json!({"ok": ok, "tree": tree_snapshot(state)});
    (
        RouteReply::with_status(status_by_ok(&json, 400), json),
        effects,
    )
}

fn apply_spaces(
    state: &mut OrgState,
    effects: &mut Vec<OrgEffect>,
    moved: Option<Vec<WorkspaceConfig>>,
) -> bool {
    match moved {
        Some(list) => {
            state.workspaces = list;
            effects.push(OrgEffect::SaveWorkspaces);
            true
        }
        None => false,
    }
}

// ── /project/new ───────────────────────────────────────────────────────────

/// `POST /project/new?workspace=<id|nome>&name=<pasta>[&parent=<pasta-mãe>][&git=0]`
/// (`ControlSocket.swift:493`) — o "Novo projeto…" do menu do workspace, sem o
/// formulário (ADR-092). BLOQUEANTE: cria a pasta e roda `git init`.
pub fn project_new(
    state: &OrgState,
    req: &RouteRequest,
    home: &str,
    git: &Git,
) -> (RouteReply, Vec<OrgEffect>) {
    let workspace = req.param("workspace").unwrap_or("");
    let name = req.param("name").unwrap_or("");
    let git_init = req.param("git") != Some("0");

    let Some(space) = state
        .workspaces
        .iter()
        .find(|w| w.id == workspace || w.name == workspace)
    else {
        return (
            RouteReply::err(400, format!("workspace desconhecido '{workspace}'")),
            vec![],
        );
    };
    let base = req
        .param("parent")
        .map_or_else(|| new_project::suggested_parent(space, home), str::to_owned);
    let plan = match new_project::plan(name, &base, space, home, disk_kind) {
        Ok(plan) => plan,
        Err(problem) => return (RouteReply::err(400, problem.message()), vec![]),
    };
    if let Err(error) = new_project::materialize(&plan, git_init, home, git) {
        return (RouteReply::err(400, error.to_string()), vec![]);
    }

    let project = ProjectConfig::for_folder(&plan.path, home);
    let line = format!(
        "projeto \"{}\" {} em {} no workspace \"{}\"{}",
        project.name,
        if plan.create { "criado" } else { "adotado" },
        plan.path,
        space.name,
        if git_init { " (git)" } else { "" }
    );
    let effect = OrgEffect::AddProject {
        workspace_id: space.id.clone(),
        project,
    };
    let mut after = state.clone();
    apply_add_project(&mut after, &effect);
    let json = json!({
        "ok": true, "path": plan.path, "created": plan.create, "tree": tree_snapshot(&after),
    });
    (
        RouteReply::ok(json),
        vec![effect, OrgEffect::SaveWorkspaces, log(line)],
    )
}

/// O que `AddProject` faz no estado: o projeto no fim, e o workspace aberto —
/// recolhido, o projeto novo nasceria escondido.
pub fn apply_add_project(state: &mut OrgState, effect: &OrgEffect) {
    let OrgEffect::AddProject {
        workspace_id,
        project,
    } = effect
    else {
        return;
    };
    if let Some(space) = state.workspaces.iter_mut().find(|w| w.id == *workspace_id) {
        space.projects.push(project.clone());
        space.collapsed = None;
    }
}

// ── /workbench/color ───────────────────────────────────────────────────────

/// `GET /workbench/color?name=<bancada>&color=<cor>` (`ControlSocket.swift:563`)
/// — a paleta (ADR-086); `?show=1` abre a grade na bancada ativa, como o clique
/// na bolinha.
pub fn workbench_color(state: &mut OrgState, req: &RouteRequest) -> (RouteReply, Vec<OrgEffect>) {
    if req.param("show") == Some("1") {
        return (
            RouteReply::ok(json!({"ok": true})),
            vec![OrgEffect::ShowPalette],
        );
    }
    let name = req.param("name").unwrap_or("");
    let raw = req.param("color").unwrap_or("");
    let Some(index) = id_of_name(name, &state.workbenches)
        .and_then(|id| state.workbenches.iter().position(|w| w.id == id))
    else {
        return (
            RouteReply::err(400, format!("bancada desconhecida '{name}'")),
            vec![],
        );
    };
    let Some(color) = WorkbenchColor::named(raw) else {
        let json = json!({
            "ok": false, "error": format!("cor desconhecida '{raw}'"),
            "palette": WorkbenchColor::ALL.iter().map(|c| c.raw()).collect::<Vec<_>>(),
        });
        return (RouteReply::with_status(400, json), vec![]);
    };
    let mut effects = Vec::new();
    if state.workbenches[index].color != Some(color) {
        state.workbenches[index].color = Some(color);
        effects.push(log(format!("bancada \"{name}\": cor {}", color.raw())));
        effects.push(OrgEffect::PersistWorkbenches);
    }
    let json = json!({"ok": true, "workbench": name, "color": color.raw()});
    (RouteReply::ok(json), effects)
}

// ── /tabs ──────────────────────────────────────────────────────────────────

/// O que só a tela sabe da faixa.
#[derive(Debug, Clone, PartialEq)]
pub struct TabsView {
    pub visible: bool,
    pub placement: Value,
    pub inset: f64,
}

impl Default for TabsView {
    fn default() -> Self {
        Self {
            visible: false,
            placement: json!([]),
            inset: -1.0,
        }
    }
}

fn tabs_snapshot(
    state: &OrgState,
    activity: &HashMap<String, ActivitySummary>,
    view: &TabsView,
) -> Map<String, Value> {
    let list = build_tabs(
        &state.open_tabs,
        &state.workbenches,
        state.active_id.as_deref(),
        activity,
    );
    let active = state
        .active_id
        .as_deref()
        .and_then(|id| state.workbenches.iter().find(|w| w.id == id))
        .map_or("", |w| w.name.as_str());
    let Value::Object(map) = json!({
        "open": list.iter().map(|t| t.line()).collect::<Vec<_>>(),
        "active": active,
        "visible": view.visible,
        "placement": view.placement,
        "inset": view.inset,
        "count": list.len(),
    }) else {
        return Map::new();
    };
    map
}

/// `GET /tabs[?close=<bancada>][?move=<bancada>&to=<n>]` (`ControlSocket.swift:579`)
/// — as bancadas abertas, na ordem da faixa, com os badges; `close` fecha a aba
/// sem encerrar a bancada e `move` reordena, como o arrasto. A resposta de
/// `close` e de `move` traz também o retrato da faixa; no choque de chave,
/// vale a da ação.
pub fn tabs(
    state: &mut OrgState,
    req: &RouteRequest,
    activity: &HashMap<String, ActivitySummary>,
    view: &TabsView,
) -> (RouteReply, Vec<OrgEffect>) {
    let to_close = req.param("close").unwrap_or("");
    let to_move = req.param("move").unwrap_or("");
    let mut effects = Vec::new();

    let action: Option<Value> = if !to_move.is_empty() {
        Some(move_tab(state, to_move, req, &mut effects))
    } else if !to_close.is_empty() {
        Some(close_tab(state, to_close, &mut effects))
    } else {
        None
    };

    let mut out = action
        .and_then(|v| v.as_object().cloned())
        .unwrap_or_default();
    for (key, value) in tabs_snapshot(state, activity, view) {
        out.entry(key).or_insert(value);
    }
    let status = if out.get("ok").and_then(Value::as_bool) == Some(false) {
        404
    } else {
        200
    };
    (RouteReply::with_status(status, Value::Object(out)), effects)
}

fn move_tab(
    state: &mut OrgState,
    name: &str,
    req: &RouteRequest,
    effects: &mut Vec<OrgEffect>,
) -> Value {
    let Some(id) = id_of_name(name, &state.workbenches).map(str::to_owned) else {
        return json!({"ok": false, "error": format!("bancada desconhecida '{name}'")});
    };
    let Some(from) = state.open_tabs.iter().position(|t| *t == id) else {
        return json!({"ok": false, "error": format!("'{name}' não está na faixa")});
    };
    let to = req
        .param("to")
        .and_then(|t| t.parse::<i64>().ok())
        .unwrap_or(-1);
    let count = state.open_tabs.len();
    let target = usize::try_from(to).ok().filter(|t| *t < count);
    let Some(target) = target else {
        return json!({"ok": false, "error": format!("posição fora da faixa (0…{})", count - 1)});
    };
    state.open_tabs = moved(&state.open_tabs, from, target);
    effects.push(OrgEffect::ReorderTabs {
        order: state.open_tabs.clone(),
    });
    effects.push(OrgEffect::PersistWorkbenches);
    json!({"ok": true, "moved": name, "to": to})
}

fn close_tab(state: &mut OrgState, name: &str, effects: &mut Vec<OrgEffect>) -> Value {
    let Some(id) = id_of_name(name, &state.workbenches).map(str::to_owned) else {
        return json!({"ok": false, "error": format!("bancada desconhecida '{name}'")});
    };
    if !state.open_tabs.contains(&id) {
        return json!({"ok": false, "error": format!("'{name}' não está na faixa")});
    }
    // Quem entra no lugar é a vizinha da direita, e na falta dela a da esquerda.
    let next = neighbour(&id, &state.open_tabs).map(str::to_owned);
    state.open_tabs.retain(|t| *t != id);
    if state.active_id.as_deref() == Some(id.as_str()) {
        state.active_id = next.clone();
        if let Some(next) = next {
            effects.push(OrgEffect::Activate { id: next });
        }
    }
    effects.push(OrgEffect::CloseTab { id });
    effects.push(OrgEffect::PersistWorkbenches);
    effects.push(log(format!(
        "aba fechada: {name} — a bancada continua de pé"
    )));
    json!({"ok": true, "closed": name})
}

// ── /activate ──────────────────────────────────────────────────────────────

/// `GET /activate?target=<bancada>` (`ControlSocket.swift:771`) — troca a aba
/// ativa.
pub fn activate(state: &OrgState, req: &RouteRequest) -> (RouteReply, Vec<OrgEffect>) {
    let name = req.param("target").unwrap_or("");
    let found = state.workbenches.iter().find(|w| w.name == name);
    let json = json!({
        "ok": found.is_some(), "workspace": name,
        "known": state.workbenches.iter().map(|w| w.name.as_str()).collect::<Vec<_>>(),
    });
    let effects = found
        .map(|w| OrgEffect::Activate { id: w.id.clone() })
        .into_iter()
        .collect();
    (
        RouteReply::with_status(status_by_ok(&json, 404), json),
        effects,
    )
}

// ── /edge ──────────────────────────────────────────────────────────────────

/// `GET /edge?target=ws&from=a&to=b[&direction=->|<-|<->|cycle|none]`
/// (`ControlSocket.swift:802`) — cria a ligação ou troca a direção dela. Sem
/// `direction`, cria como o arrasto cria, com o padrão da casa; `cycle` é
/// exatamente o botão da linha.
pub fn edge(state: &mut OrgState, req: &RouteRequest) -> (RouteReply, Vec<OrgEffect>) {
    let target = req.param("target").unwrap_or("");
    let Some(bench) = state.workbenches.iter_mut().find(|w| w.name == target) else {
        return (
            RouteReply::err(400, format!("bancada desconhecida '{target}'")),
            vec![],
        );
    };
    let (json, outcome) = edges::apply(
        bench,
        req.param("from").unwrap_or(""),
        req.param("to").unwrap_or(""),
        req.param("direction").unwrap_or(""),
    );
    let mut effects: Vec<OrgEffect> = outcome.notes.into_iter().map(log).collect();
    if let Some(text) = outcome.banner {
        effects.push(OrgEffect::Banner { text });
    }
    if outcome.changed {
        effects.push(OrgEffect::PersistWorkbenches);
    }
    (
        RouteReply::with_status(status_by_ok(&json, 400), json),
        effects,
    )
}

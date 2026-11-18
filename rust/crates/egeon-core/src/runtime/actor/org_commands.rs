//! Os comandos de organização do `/ui` (decisão 24) dentro do ator.
//!
//! Onde o Swift tem rota HTTP com a mesma operação (`/move`, `/tabs`,
//! `/activate`, `/workbench/color`, `/edge`), o comando vira a requisição
//! daquela rota e passa pelo handler do `org`: a regra e os textos de erro
//! são um só para a UI, o `egeon` e o `curl`. O que só a tela fazia no Swift
//! vai direto ao modelo.

use std::collections::HashMap;

use serde_json::json;

use super::{Actor, Replier, not_ported};
use crate::commons::ids::{WorkbenchId, WorkbenchName};
use crate::features::edge::model::{EdgeConfig, EdgeLink};
use crate::features::node::model::Frame;
use crate::features::workbench::model::ViewMode as ConfigView;
use crate::features::workspace::multi::default_name;
use crate::features::workspace::new_project::suggested_parent;
use crate::features::workspace::routes::{self as org_routes, OrgEffect, TabsView};
use crate::protocol::handler::{RouteReply, RouteRequest};
use crate::protocol::message::{CommandKind, Reply};
use crate::protocol::org::{Direction, MoveKind, ViewMode};
use crate::protocol::routes::FeatureRoute;

/// A requisição de uma rota do Swift montada a partir de um comando do `/ui`.
pub(super) fn request(path: &str, query: &[(&str, String)]) -> RouteRequest {
    RouteRequest {
        method: "GET".to_owned(),
        target: path.to_owned(),
        path: path.to_owned(),
        query: query
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.clone()))
            .collect(),
        body: Vec::new(),
        origin: None,
    }
}

fn move_kind(kind: MoveKind) -> &'static str {
    match kind {
        MoveKind::Workspace => "workspace",
        MoveKind::Project => "project",
        MoveKind::Workbench => "workbench",
        MoveKind::Store => "store",
        MoveKind::Unstore => "unstore",
        MoveKind::Drawer => "drawer",
    }
}

fn direction(direction: Direction) -> &'static str {
    match direction {
        Direction::Forward => "->",
        Direction::Backward => "<-",
        Direction::Both => "<->",
        Direction::Cycle => "cycle",
        Direction::None => "none",
    }
}

/// A resposta de uma rota vira a do comando: o JSON da rota vai inteiro, e
/// o `ok`/`error` dele é o do comando.
fn reply_of(re: u64, reply: &RouteReply) -> Reply {
    Reply::with(re, &reply.json)
}

impl Actor {
    pub(super) fn org_command(&mut self, re: u64, kind: CommandKind) -> Reply {
        let name = kind.name();
        match kind {
            CommandKind::OpenWorkbench(r) => match self.org.name_of(&r.workbench) {
                Some(_) => {
                    self.apply_org(vec![OrgEffect::Activate {
                        id: r.workbench.to_string(),
                    }]);
                    Reply::ok(re)
                }
                None => unknown(re, &r.workbench),
            },
            CommandKind::ActivateWorkbench(r) => {
                let Some(name) = self.org.name_of(&r.workbench) else {
                    return unknown(re, &r.workbench);
                };
                if !self
                    .org
                    .state
                    .open_tabs
                    .iter()
                    .any(|t| t == r.workbench.as_str())
                {
                    return Reply::err(re, format!("'{name}' não está na faixa"));
                }
                let (reply, effects) = org_routes::activate(
                    &self.org.state,
                    &request("/activate", &[("target", name)]),
                );
                self.apply_org(effects);
                reply_of(re, &reply)
            }
            CommandKind::CloseWorkbench(r) => {
                let Some(name) = self.org.name_of(&r.workbench) else {
                    return unknown(re, &r.workbench);
                };
                self.tabs(re, &[("close", name)])
            }
            CommandKind::MoveTab(t) => {
                let Some(name) = self.org.name_of(&t.workbench) else {
                    return unknown(re, &t.workbench);
                };
                self.tabs(re, &[("move", name), ("to", t.to.to_string())])
            }
            CommandKind::Move(m) => {
                let (reply, effects) =
                    org_routes::move_in_tree(&mut self.org.state, &move_request(&m));
                let ok = reply.json["ok"] == true;
                self.apply_org(effects);
                if ok {
                    Reply::ok(re)
                } else {
                    reply_of(re, &reply)
                }
            }
            CommandKind::PlanMove(m) => {
                // A mesma operação numa cópia: vale o que o `move` aceitaria,
                // sem mexer em nada.
                let mut copy = self.org.state.clone();
                let (reply, _) = org_routes::move_in_tree(&mut copy, &move_request(&m));
                if reply.json["ok"] == true {
                    Reply::with(re, &json!({"lands": {"parent": m.parent, "to": m.to}}))
                } else {
                    reply_of(re, &reply)
                }
            }
            CommandKind::SetWorkbench(s) => {
                let Some(index) = self.org.index_of(&s.workbench) else {
                    return unknown(re, &s.workbench);
                };
                // Tudo validado antes de mexer: erro quer dizer que nada mudou.
                // A cor passa pela rota numa cópia primeiro, para a recusa sair
                // com o texto e a paleta do Swift.
                let color = s.color.map(|color| {
                    let name = self.org.state.workbenches[index].name.clone();
                    request("/workbench/color", &[("name", name), ("color", color)])
                });
                if let Some(req) = &color {
                    let (reply, _) = org_routes::workbench_color(&mut self.org.state.clone(), req);
                    if reply.json["ok"] != true {
                        return reply_of(re, &reply);
                    }
                }
                if let Some(req) = &color {
                    let (_, effects) = org_routes::workbench_color(&mut self.org.state, req);
                    self.apply_org(effects);
                }
                if let Some(view) = s.view {
                    self.org.state.workbenches[index].view = Some(match view {
                        ViewMode::Canvas => ConfigView::Canvas,
                        ViewMode::Chat => ConfigView::Chat,
                    });
                }
                if let Some(typed) = s.name {
                    self.rename(index, &typed);
                }
                self.apply_org(vec![OrgEffect::PersistWorkbenches]);
                Reply::ok(re)
            }
            CommandKind::SetWorkbenchRules(s) => {
                let Some(index) = self.org.index_of(&s.workbench) else {
                    return unknown(re, &s.workbench);
                };
                // Regra em branco é regra nenhuma: o campo vazio do
                // formulário não pode virar um bloco vazio no papel.
                self.org.state.workbenches[index].rules = s.rules.filter(|r| !r.trim().is_empty());
                self.apply_org(vec![OrgEffect::PersistWorkbenches]);
                Reply::ok(re)
            }
            CommandKind::SetWorkspace(s) => {
                let Some(space) = self
                    .org
                    .state
                    .workspaces
                    .iter_mut()
                    .find(|w| w.id == s.workspace.as_str())
                else {
                    return Reply::err(re, format!("workspace desconhecido '{}'", s.workspace));
                };
                if s.icon.is_some() {
                    return Reply::err(re, "trocar o ícone ainda não portado");
                }
                if let Some(name) = s
                    .name
                    .map(|n| n.trim().to_owned())
                    .filter(|n| !n.is_empty())
                {
                    space.name = name;
                }
                if let Some(collapsed) = s.collapsed {
                    space.collapsed = collapsed.then_some(true);
                }
                if let Some(open) = s.stored_open {
                    space.stored_open = open.then_some(true);
                }
                self.apply_org(vec![OrgEffect::SaveWorkspaces]);
                Reply::ok(re)
            }
            CommandKind::SetProject(s) => {
                let Some(project) = self
                    .org
                    .state
                    .workspaces
                    .iter_mut()
                    .flat_map(|w| w.projects.iter_mut())
                    .find(|p| p.id == s.project.as_str())
                else {
                    return Reply::err(re, format!("projeto desconhecido '{}'", s.project));
                };
                if let Some(name) = s
                    .name
                    .map(|n| n.trim().to_owned())
                    .filter(|n| !n.is_empty())
                {
                    project.name = name;
                }
                if let Some(collapsed) = s.collapsed {
                    project.collapsed = collapsed.then_some(true);
                }
                self.apply_org(vec![OrgEffect::SaveWorkspaces]);
                Reply::ok(re)
            }
            CommandKind::Unlink(u) => {
                let Some(index) = self.org.index_of(&u.workbench) else {
                    return unknown(re, &u.workbench);
                };
                let bench = &mut self.org.state.workbenches[index];
                let (from, to) = (u.from.as_str(), u.to.as_str());
                let edges: Vec<EdgeConfig> = bench
                    .edge_list()
                    .iter()
                    .filter(|e| {
                        let forward = e.from == from && e.to == to;
                        let back = e.from == to && e.to == from;
                        !(forward || (u.both && back))
                    })
                    .cloned()
                    .collect();
                bench.edges = Some(edges);
                self.apply_org(vec![OrgEffect::PersistWorkbenches]);
                Reply::ok(re)
            }
            CommandKind::SetEdge(e) => {
                let Some(name) = self.org.name_of(&e.workbench) else {
                    return unknown(re, &e.workbench);
                };
                if let Some(dir) = e.direction {
                    let (reply, effects) = org_routes::edge(
                        &mut self.org.state,
                        &request(
                            "/edge",
                            &[
                                ("target", name),
                                ("from", e.from.to_string()),
                                ("to", e.to.to_string()),
                                ("direction", direction(dir).to_owned()),
                            ],
                        ),
                    );
                    self.apply_org(effects);
                    if reply.json["ok"] != true {
                        return reply_of(re, &reply);
                    }
                }
                if let Some(limit) = e.max_sends
                    && let Some(index) = self.org.index_of(&e.workbench)
                {
                    let bench = &mut self.org.state.workbenches[index];
                    let (a, b) = EdgeLink::pair(e.from.as_str(), e.to.as_str());
                    let Some(link) = EdgeLink::collapse(bench.edge_list())
                        .into_iter()
                        .find(|l| l.a == a && l.b == b)
                    else {
                        return Reply::err(
                            re,
                            format!("não existe ligação entre '{}' e '{}'", e.from, e.to),
                        );
                    };
                    let typed = limit.map(|n| n.to_string()).unwrap_or_default();
                    let outcome = crate::features::canvas::edges::edit_limit(bench, &link, &typed);
                    for note in outcome.notes {
                        crate::log!("{note}");
                    }
                    self.apply_org(vec![OrgEffect::PersistWorkbenches]);
                }
                Reply::ok(re)
            }
            CommandKind::MoveNode(m) => {
                let Some(index) = self.org.index_of(&m.workbench) else {
                    return unknown(re, &m.workbench);
                };
                let Some(node) = self.org.state.workbenches[index]
                    .nodes
                    .iter_mut()
                    .find(|n| n.id == m.node.as_str())
                else {
                    return Reply::err(re, format!("nó desconhecido '{}'", m.node));
                };
                if m.frame.w <= 0.0 || m.frame.h <= 0.0 {
                    return Reply::err(re, "frame sem largura ou altura");
                }
                node.set_frame(Frame {
                    x: m.frame.x,
                    y: m.frame.y,
                    w: m.frame.w,
                    h: m.frame.h,
                });
                self.apply_org(vec![OrgEffect::PersistWorkbenches]);
                Reply::ok(re)
            }
            CommandKind::MultiName(m) => Reply::with(
                re,
                &json!({"name": default_name(&m.folders, &self.org.home)}),
            ),
            CommandKind::SuggestParent(r) => {
                let Some(space) = self
                    .org
                    .state
                    .workspaces
                    .iter()
                    .find(|w| w.id == r.workspace.as_str())
                else {
                    return Reply::err(re, format!("workspace desconhecido '{}'", r.workspace));
                };
                Reply::with(
                    re,
                    &json!({"parent": suggested_parent(space, &self.org.home)}),
                )
            }
            _ => Reply::err(re, format!("{name} ainda não portado")),
        }
    }

    /// As rotas HTTP de organização do Swift, pelos handlers do `org`, com
    /// as chaves e os status de lá.
    pub(super) fn org_route(&mut self, route: FeatureRoute, request: RouteRequest, reply: Replier) {
        let (answer, effects) = match route {
            FeatureRoute::Workspaces => (org_routes::workspaces(&self.org.state), Vec::new()),
            FeatureRoute::Move => org_routes::move_in_tree(&mut self.org.state, &request),
            FeatureRoute::WorkbenchColor => {
                org_routes::workbench_color(&mut self.org.state, &request)
            }
            FeatureRoute::Tabs => org_routes::tabs(
                &mut self.org.state,
                &request,
                &HashMap::new(),
                &TabsView::default(),
            ),
            FeatureRoute::Activate => org_routes::activate(&self.org.state, &request),
            FeatureRoute::Edge => org_routes::edge(&mut self.org.state, &request),
            FeatureRoute::ProjectNew => return self.project_new(request, reply),
            other => return not_ported(other, reply),
        };
        self.apply_org(effects);
        let _ = reply.send(answer);
    }

    /// `/project/new` cria pasta e roda `git init`: sobre uma cópia, fora do
    /// ator, e os efeitos voltam para ele.
    fn project_new(&mut self, request: RouteRequest, reply: Replier) {
        let state = self.org.state.clone();
        let home = self.org.home.clone();
        let git = self.user_git();
        tokio::spawn({
            let inbox = self.inbox.clone();
            async move {
                let done = tokio::task::spawn_blocking(move || {
                    org_routes::project_new(&state, &request, &home, &git)
                })
                .await;
                let Ok((answer, effects)) = done else {
                    let _ = reply.send(RouteReply::err(500, "o novo projeto não terminou"));
                    return;
                };
                let job = move |actor: &mut Actor| {
                    actor.apply_org(effects);
                    let _ = reply.send(answer);
                };
                let _ = inbox.send(super::Msg::Run(Box::new(job))).await;
            }
        });
    }

    fn tabs(&mut self, re: u64, query: &[(&str, String)]) -> Reply {
        let (reply, effects) = org_routes::tabs(
            &mut self.org.state,
            &request("/tabs", query),
            &HashMap::new(),
            &TabsView::default(),
        );
        let ok = reply.json["ok"] != false;
        self.apply_org(effects);
        if ok {
            Reply::ok(re)
        } else {
            reply_of(re, &reply)
        }
    }

    /// `renameWorkbench` do Swift: aparado, vazio ou igual não muda nada, e o
    /// nome sai livre entre os das outras bancadas.
    fn rename(&mut self, index: usize, typed: &str) {
        let current = self.org.state.workbenches[index].name.clone();
        let Ok(typed) = WorkbenchName::new(typed) else {
            return;
        };
        if typed.as_str() == current {
            return;
        }
        let taken: Vec<&str> = self
            .org
            .state
            .workbenches
            .iter()
            .enumerate()
            .filter(|(i, _)| *i != index)
            .map(|(_, w)| w.name.as_str())
            .collect();
        let name = WorkbenchName::available(typed.as_str(), &taken);
        crate::log!("bancada \"{current}\" renomeada para \"{name}\"");
        self.org.state.workbenches[index].name = name.to_string();
    }

    /// Cumpre o que os handlers do `org` pediram e manda o estado novo a quem
    /// assina.
    pub(super) fn apply_org(&mut self, effects: Vec<OrgEffect>) {
        let mut persist = false;
        for effect in effects {
            match effect {
                OrgEffect::SaveWorkspaces
                | OrgEffect::PersistWorkbenches
                | OrgEffect::CloseTab { .. }
                | OrgEffect::ReorderTabs { .. } => persist = true,
                // O `guard index != activeIndex` do Swift: a bancada que já
                // está na frente não muda nada, nem dá o verde por visto.
                OrgEffect::Activate { id }
                    if self.org.state.active_id.as_deref() == Some(id.as_str()) => {}
                OrgEffect::Activate { id } => {
                    // `activate(index)` do Swift: quem não tinha aba ganha uma
                    // no fim da faixa.
                    if !self.org.state.open_tabs.contains(&id) {
                        self.org.state.open_tabs.push(id.clone());
                    }
                    // Montar a bancada sobe os terminais dela, uma vez: trocar
                    // de aba depois não relança ninguém.
                    if !self.org.live.contains(&id) {
                        self.open_terminals(&id);
                    }
                    // Trocar de bancada dá por visto o "terminou" das duas: a
                    // que você abre e a que deixa (main.swift:714-717).
                    let name_of = |id: &str, org: &crate::runtime::org::Org| {
                        org.state
                            .workbenches
                            .iter()
                            .find(|w| w.id == id)
                            .map(|w| w.name.clone())
                    };
                    let previous = self.org.state.active_id.clone();
                    if let Some(name) = previous.as_deref().and_then(|p| name_of(p, &self.org)) {
                        self.dispatch_workbench_opened(&name);
                    }
                    if let Some(name) = name_of(&id, &self.org) {
                        self.dispatch_workbench_opened(&name);
                    }
                    self.org.state.active_id = Some(id);
                    persist = true;
                }
                OrgEffect::AddProject { .. } => {
                    org_routes::apply_add_project(&mut self.org.state, &effect);
                    persist = true;
                }
                OrgEffect::Log { line } => crate::log!("{line}"),
                OrgEffect::Banner { text } => crate::log!("aviso: {text}"),
                OrgEffect::ShowPalette => {}
            }
        }
        if persist {
            self.persist();
        }
        self.publish_org();
    }
}

fn unknown(re: u64, id: &WorkbenchId) -> Reply {
    Reply::err(re, format!("bancada desconhecida '{id}'"))
}

fn move_request(m: &crate::protocol::org::Move) -> RouteRequest {
    let mut query = vec![
        ("kind", move_kind(m.kind).to_owned()),
        ("id", m.item.clone()),
        ("to", m.to.to_string()),
    ];
    if let Some(parent) = &m.parent {
        query.push(("parent", parent.clone()));
    }
    request("/move", &query)
}

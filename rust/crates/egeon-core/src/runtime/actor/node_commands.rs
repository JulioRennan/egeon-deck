//! Dono: `org`. Liga ao ator criar e remover bancada, nó, workspace e projeto, o worktree, o limpar e o set_node (com o relançamento que o Swift faz).
//!
//! Comandos do `/ui` que chegam aqui: create_workbench, remove_workbench, plan_remove_workbench, removal_losses, clear_workbench, worktree, create_node, remove_node, set_node, node_clear, create_workspace, remove_workspace, save_workspace, create_project, add_project, remove_project e multi_project. `None` quer dizer que a
//! resposta sai depois (trabalho fora do ator, pela [`Actor::run_later`]).
//! O core mantém a assinatura; o corpo é do dono.
//!
//! As regras são das features (`node::edit`, `worktree`, `workspace`); aqui só
//! se aplica ao estado e se sobe e derruba terminal.

use std::collections::{BTreeSet, HashMap};
use std::time::Duration;

use serde_json::{Value, json};

use super::{Actor, ClientId, Replier, not_ported};
use crate::commons::ids::{WorkbenchId, WorkbenchName};
use crate::features::agent::claude::catalog as claude_catalog;
use crate::features::agent::model::{AgentProfile, ModelChoice};
use crate::features::agent::model_catalog::ModelCatalog;
use crate::features::canvas::{edges, placement};
use crate::features::edge::EdgeConfig;
use crate::features::node::edit::{self, NewNode, NodePatch};
use crate::features::node::model::{Frame, NodeConfig, NodeKind as ConfigKind};
use crate::features::node::{service as node_service, store as components};
use crate::features::path_text::{abbreviate_tilde, last_component, normalize};
use crate::features::workbench::clock::WorkbenchClocks;
use crate::features::workbench::frames;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workbench::removal::{Removal, RemovalTarget, purge, sweep};
use crate::features::workbench::service::colored_among;
use crate::features::workbench::store as bench_store;
use crate::features::workspace::model::{ProjectConfig, WorkspaceConfig};
use crate::features::workspace::multi::{apply_edit, default_name};
use crate::features::workspace::routes::OrgEffect;
use crate::features::workspace::service::reconcile;
use crate::features::workspace::store as space_store;
use crate::features::workspace::tree::WorkspaceTree;
use crate::features::worktree::removal_plan::{
    BenchWorktree, RemovalContext, involved, multi_roots, payload,
};
use crate::features::worktree::service as worktree_service;
use crate::protocol::handler::{RouteReply, RouteRequest};
use crate::protocol::message::{CommandKind, Reply};
use crate::protocol::org::{
    AddProject, CreateNode, CreateProject, CreateWorkbench, CreateWorkspace, Link, MultiProject,
    NodeKind, NodeRef, RemoveProject, RemoveWorkbench, RemoveWorkspace, SaveWorkspace, SetNode,
    Worktree, WorktreeDestination,
};
use crate::protocol::routes::FeatureRoute;
use crate::runtime::org::screen_id;

pub(super) fn config_kind(kind: NodeKind) -> ConfigKind {
    match kind {
        NodeKind::Shell => ConfigKind::Shell,
        NodeKind::Agent => ConfigKind::Agent,
        NodeKind::Web => ConfigKind::Web,
        NodeKind::Queue => ConfigKind::Queue,
    }
}

pub(super) fn unknown_bench(re: u64, id: &WorkbenchId) -> Reply {
    Reply::err(re, format!("bancada desconhecida '{id}'"))
}

pub(super) fn unknown_node(re: u64, id: &str) -> Reply {
    Reply::err(re, format!("nó desconhecido '{id}'"))
}

impl Actor {
    pub(super) fn node_command(
        &mut self,
        client: ClientId,
        re: u64,
        kind: CommandKind,
    ) -> Option<Reply> {
        Some(match kind {
            CommandKind::CreateWorkbench(c) => return self.create_workbench(client, re, c),
            CommandKind::PlanRemoveWorkbench(r) => return self.plan_remove(client, re, r),
            CommandKind::RemovalLosses(r) => return self.removal_losses(client, re, r),
            CommandKind::RemoveWorkbench(r) => return self.remove_workbench_command(client, re, r),
            CommandKind::Worktree(w) => return self.worktree_command(client, re, w),
            CommandKind::ClearWorkbench(r) => {
                return match self.org.name_of(&r.workbench) {
                    Some(name) => self.clear_workbench_command(client, re, &name),
                    None => Some(unknown_bench(re, &r.workbench)),
                };
            }
            CommandKind::Retry(r) => match self.org.name_of(&r.workbench) {
                None => unknown_bench(re, &r.workbench),
                Some(bench) => match self.retry_node(&format!("{bench}/{}", r.node), r.now) {
                    Ok(()) => Reply::ok(re),
                    Err(error) => Reply::err(re, error),
                },
            },
            CommandKind::OpenNodeFolder(n) => self.open_node_folder(re, &n),
            CommandKind::ResetClock(r) => {
                if self.org.index_of(&r.workbench).is_none() {
                    return Some(unknown_bench(re, &r.workbench));
                }
                self.reset_clock(r.workbench.as_str());
                crate::log!("bancada {}: cronômetro zerado", r.workbench);
                self.publish_org();
                Reply::ok(re)
            }
            CommandKind::Templates => self.templates(re),
            CommandKind::WorktreeInfo(r) => return self.worktree_info(client, re, &r),
            CommandKind::SaveTemplate(s) => self.save_template(re, s),
            CommandKind::WorktreePlan(r) => return self.worktree_plan(client, re, r),
            CommandKind::NodeClear(n) => {
                let target = self
                    .org
                    .name_of(&n.workbench)
                    .map(|b| format!("{b}/{}", n.node));
                match target {
                    None => unknown_bench(re, &n.workbench),
                    Some(target) => match self.node_clear(&target) {
                        None => Reply::ok(re),
                        Some(error) => Reply::err(re, error),
                    },
                }
            }
            CommandKind::CreateWorkspace(c) => self.create_workspace(re, c),
            CommandKind::SaveWorkspace(s) => self.save_workspace(re, s),
            CommandKind::RemoveWorkspace(r) => self.remove_workspace(re, r),
            CommandKind::CreateProject(c) => return self.create_project(client, re, c),
            CommandKind::AddProject(a) => self.add_project(re, a),
            CommandKind::RemoveProject(r) => self.remove_project(re, r),
            CommandKind::MultiProject(m) => self.multi_project(re, m),
            CommandKind::CreateNode(c) => self.create_node(re, c),
            CommandKind::SetNode(s) => self.set_node(re, s),
            CommandKind::NodeForm(f) => self.node_form(re, f),
            CommandKind::NodeFormScreen(s) => self.node_form_screen(re, *s),
            CommandKind::NodeFolder(f) => self.node_folder(re, f),
            CommandKind::ApplyNode(a) => self.apply_node(re, *a),
            CommandKind::Components => self.components(re),
            CommandKind::RemoveNode(r) => self.remove_node(re, r),
            CommandKind::Link(l) => self.link_nodes(re, l),
            other => Reply::err(re, format!("{} ainda não portado", other.name())),
        })
    }

    /// `/worktree`, `/node/clear`, `/workbench/clear` e `/remove`.
    pub(super) fn node_route(
        &mut self,
        route: FeatureRoute,
        request: RouteRequest,
        reply: Replier,
    ) {
        match route {
            FeatureRoute::Remove => self.remove_route(request, reply),
            FeatureRoute::Worktree => self.worktree_route(request, reply),
            FeatureRoute::Model => {
                let answer = self.model_route(&request);
                let _ = reply.send(answer);
            }
            FeatureRoute::WorkbenchClear => {
                let target = request.param("target").unwrap_or("").to_owned();
                self.clear_workbench_route(&target, reply);
            }
            FeatureRoute::NodeClear => {
                let target = request.param("target").unwrap_or("").to_owned();
                let answer = match self.node_clear(&target) {
                    None => RouteReply::ok(json!({"ok": true, "target": target})),
                    Some(error) => {
                        RouteReply::with_status(404, json!({"ok": false, "error": error}))
                    }
                };
                let _ = reply.send(answer);
            }
            other => not_ported(other, reply),
        }
    }

    pub(super) fn profile_of(&self, node: &NodeConfig) -> Option<AgentProfile> {
        node.agent
            .as_ref()
            .and_then(|a| self.org.profiles.get(a))
            .cloned()
    }

    /// Cria um nó: do formulário confirmado, do componente escolhido (que já
    /// traz tipo, agente, comando, pasta e papel) ou do tipo pedido, com o id
    /// livre da bancada. Sobe o terminal se a bancada já está de pé.
    fn create_node(&mut self, re: u64, mut c: CreateNode) -> Reply {
        let Some(index) = self.org.index_of(&c.workbench) else {
            return unknown_bench(re, &c.workbench);
        };
        let formed = c
            .form
            .take()
            .map(|submit| self.form_component(index, *submit, None));
        let bench = &self.org.state.workbenches[index];
        // O arrasto da tela vem como está, ajustado ao mínimo do cartão; sem
        // frame mas com o que está à vista, o primeiro lugar livre ali; sem
        // nada, o nó entra na coluna do layout padrão (`apply_default_frames`).
        let as_frame = |r: crate::protocol::org::Rect| Frame {
            x: r.x,
            y: r.y,
            w: r.w,
            h: r.h,
        };
        let frame = match (c.frame, c.visible) {
            (Some(r), _) => Some(placement::fit(as_frame(r))),
            (None, Some(v)) => {
                let taken: Vec<Frame> = bench.nodes.iter().filter_map(|n| n.frame()).collect();
                Some(placement::spawn(
                    as_frame(v),
                    &taken,
                    placement::TERMINAL_SIZE,
                ))
            }
            (None, None) => None,
        };
        let saved = match (&formed, &c.component) {
            (Some(component), _) => Some(component.clone()),
            (None, Some(name)) => {
                let file = self.config.paths.config(components::FILE);
                let Some(component) = components::component(&file, name) else {
                    return Reply::err(re, format!("componente desconhecido '{name}'"));
                };
                Some(component)
            }
            (None, None) => None,
        };
        let mut node = match saved {
            Some(component) => {
                // O id vem do nome, então o endereço de dispatch fica legível:
                // `deck/revisor`.
                let prefix = crate::commons::ids::NodeId::slug(&component.name);
                let id = edit::next_id(prefix.as_str(), bench);
                let mut node = node_service::instantiate(&component, &id);
                if let Some(frame) = frame {
                    node.set_frame(frame);
                }
                node
            }
            None => edit::new_node(
                config_kind(c.kind),
                NewNode {
                    agent: c.agent,
                    cwd: c.cwd,
                    cmd: c.cmd,
                    url: c.url,
                    frame,
                },
                bench,
            ),
        };
        let profile = self.profile_of(&node);
        edit::prepare_conversation(&mut node, profile.as_ref());

        let id = node.id.clone();
        let name = bench.name.clone();
        crate::log!("bancada {name}: {:?} \"{id}\" criado", node.kind);
        self.org.state.workbenches[index].nodes.push(node.clone());
        if frame.is_none() {
            let window = self.window;
            let bench = &mut self.org.state.workbenches[index];
            for line in frames::apply_default_frames(bench, window) {
                crate::log!("{line}");
            }
            node = bench.nodes.last().cloned().unwrap_or(node);
        }
        if self
            .org
            .live
            .contains(self.org.state.workbenches[index].id.as_str())
        {
            let bench = self.org.state.workbenches[index].clone();
            self.open_terminal(&bench, &node);
        }
        self.apply_org(vec![OrgEffect::PersistWorkbenches]);
        Reply::with(re, &json!({"node": id}))
    }

    /// Aplica o formulário do nó. Nome, comando, agente e pasta definem como o
    /// processo foi lançado: mudá-los reinicia o terminal (não há como
    /// reconfigurar um pty em andamento), e a conversa do agente fica — o CLI
    /// retoma a mesma sessão.
    fn set_node(&mut self, re: u64, s: SetNode) -> Reply {
        let Some(index) = self.org.index_of(&s.workbench) else {
            return unknown_bench(re, &s.workbench);
        };
        let Some(position) = self.org.state.workbenches[index]
            .nodes
            .iter()
            .position(|n| n.id == s.node.as_str())
        else {
            return unknown_node(re, s.node.as_str());
        };
        let patch = NodePatch {
            model: s.model,
            effort: s.effort,
            ultracode: s.ultracode,
            role: s.role,
            rules: s.rules,
            cwd: s.cwd,
            cmd: s.cmd,
            maestro: s.maestro,
        };
        let current = self.org.state.workbenches[index].nodes[position].clone();
        let (updated, restart) = edit::apply_patch(&current, &patch);
        self.org.state.workbenches[index].nodes[position] = updated.clone();

        if restart {
            self.restart_node(index, position, updated);
        }
        self.apply_org(vec![OrgEffect::PersistWorkbenches]);
        Reply::ok(re)
    }

    /// Recomeça o terminal de um nó já gravado em `position`: o processo é
    /// outro, mas a conversa do agente fica — o CLI retoma a mesma sessão. Só
    /// sobe de novo se a bancada está de pé.
    pub(super) fn restart_node(&mut self, index: usize, position: usize, mut updated: NodeConfig) {
        let bench_id = self.org.state.workbenches[index].id.clone();
        if let Some(terminal) = screen_id(&bench_id, &updated.id) {
            let _ = self.close(&terminal);
        }
        let profile = self.profile_of(&updated);
        edit::prepare_conversation(&mut updated, profile.as_ref());
        self.org.state.workbenches[index].nodes[position] = updated.clone();
        if self.org.live.contains(&bench_id) {
            let bench = self.org.state.workbenches[index].clone();
            self.open_terminal(&bench, &updated);
        }
        crate::log!(
            "bancada {}: nó \"{}\" reconfigurado",
            self.org.state.workbenches[index].name,
            updated.id
        );
    }

    /// `GET /model?target=ws/id[&model=…][&effort=…][&ultracode=…]`: o mesmo que
    /// escolher no seletor do cabeçalho. `ultracode` ganha de `effort`, que
    /// ganha de `model`; sem `model`, volta ao padrão do CLI. `effort=default`
    /// volta ao padrão — `effort=` vazio nem chega à query.
    pub(super) fn model_route(&mut self, request: &RouteRequest) -> RouteReply {
        let target = request.param("target").unwrap_or("").to_owned();
        let (choice, field) = if let Some(on) = request.param("ultracode") {
            (
                ModelChoice::Ultracode(matches!(on, "on" | "1" | "true")),
                "ultracode",
            )
        } else if let Some(effort) = request.param("effort") {
            (
                ModelChoice::Effort((effort != "default").then(|| effort.to_owned())),
                "effort",
            )
        } else {
            let model = request.param("model").filter(|m| !m.is_empty());
            (ModelChoice::Model(model.map(str::to_owned)), "model")
        };
        if let Some(error) = self.change_model(&target, &choice) {
            return RouteReply::with_status(404, json!({"ok": false, "error": error}));
        }
        let value = match &choice {
            ModelChoice::Model(v) | ModelChoice::Effort(v) => v.clone(),
            ModelChoice::Ultracode(on) => Some(if *on { "on" } else { "off" }.to_owned()),
        };
        RouteReply::ok(json!({
            "ok": true,
            "target": target,
            field: value.unwrap_or_else(|| "padrão".to_owned()),
        }))
    }

    /// Troca modelo, esforço ou ultracode de um agente e o reinicia se algo
    /// mudou. `Some(erro)` com o texto do Swift quando não dá.
    ///
    /// Desvio: o Swift só achava o nó com a bancada aberta (`shell(at:)`); aqui
    /// a bancada fechada troca também, e só não reabre o terminal.
    fn change_model(&mut self, target: &str, choice: &ModelChoice) -> Option<String> {
        let found = target.split_once('/').and_then(|(bench, node)| {
            Some((
                self.org
                    .state
                    .workbenches
                    .iter()
                    .position(|w| w.name == bench)?,
                node,
            ))
        });
        let Some((index, node_id)) = found else {
            return Some(format!("bancada desconhecida '{target}'"));
        };
        let Some(position) = self.org.state.workbenches[index]
            .nodes
            .iter()
            .position(|n| n.id == node_id)
        else {
            return Some(format!("nó desconhecido '{target}'"));
        };
        let current = self.org.state.workbenches[index].nodes[position].clone();
        let profile = current
            .agent
            .as_ref()
            .and_then(|a| self.org.profiles.get(a))
            .cloned();
        let (true, Some(profile)) = (current.kind == ConfigKind::Agent, profile) else {
            return Some(format!("'{target}' não é um agente"));
        };
        match choice {
            ModelChoice::Model(_) if !profile.offers_models() => {
                return Some(format!("'{target}' não é um agente que aceite modelo"));
            }
            ModelChoice::Effort(_) if !profile.offers_efforts() => {
                return Some(format!("'{target}' não é um agente que aceite esforço"));
            }
            ModelChoice::Ultracode(_) if profile.ultracode.is_none() => {
                return Some(format!("'{target}' não é um agente com ultracode"));
            }
            _ => {}
        }
        let mut updated = current.clone();
        choice.apply(
            &mut updated.model,
            &mut updated.effort,
            &mut updated.ultracode,
        );
        // Modelo novo sem o nível em vigor: o CLI rebaixaria calado, e o slider
        // mostraria um nível que não existe. Volta ao auto, e diz.
        if let (ModelChoice::Model(_), Some(effort)) = (choice, updated.effort.clone())
            && let Some(catalog) = self.model_catalog(&profile)
            && let Some(model) = catalog.model_for(updated.model.as_deref())
            && !model.efforts.contains(&effort)
        {
            crate::log!(
                "bancada {}: {} não tem esforço {effort} — nó \"{}\" volta ao auto",
                self.org.state.workbenches[index].name,
                model.label,
                current.id
            );
            updated.effort = None;
        }
        if updated.model == current.model
            && updated.effort == current.effort
            && updated.ultracode == current.ultracode
        {
            return None;
        }
        self.org.state.workbenches[index].nodes[position] = updated.clone();
        let what = match choice {
            ModelChoice::Model(m) => format!(
                "modelo {} (antes {})",
                m.as_deref().unwrap_or("padrão"),
                current.model.as_deref().unwrap_or("padrão")
            ),
            ModelChoice::Effort(e) => format!(
                "esforço {} (antes {})",
                e.as_deref().unwrap_or("padrão"),
                current.effort.as_deref().unwrap_or("padrão")
            ),
            ModelChoice::Ultracode(on) => {
                format!("ultracode {}", if *on { "ligado" } else { "desligado" })
            }
        };
        crate::log!(
            "bancada {}: nó \"{}\" reiniciado com {what}",
            self.org.state.workbenches[index].name,
            current.id
        );
        self.restart_node(index, position, updated);
        self.apply_org(vec![OrgEffect::PersistWorkbenches]);
        None
    }

    /// O catálogo de modelos do Claude Code, o que o ator já guarda (`detail`).
    pub(super) fn model_catalog(&self, profile: &AgentProfile) -> Option<ModelCatalog> {
        if !claude_catalog::applies_to(profile) {
            return None;
        }
        self.detail.catalog.clone()
    }

    /// O arrasto da porta: liga `from` a `to`. Só terminal tem porta
    /// (`check_link`), e o par já ligado, em qualquer sentido, é ok sem segunda
    /// aresta — o par é uma linha só na tela. `both` liga os dois sentidos de
    /// uma vez: a volta é a que o `EdgeController.add` cria sozinho, e a regra
    /// de alvo vale só para onde o arrasto SOLTA, não para ela.
    fn link_nodes(&mut self, re: u64, l: Link) -> Reply {
        let Some(index) = self.org.index_of(&l.workbench) else {
            return unknown_bench(re, &l.workbench);
        };
        let bench = &mut self.org.state.workbenches[index];
        if let Err(error) = edges::check_link(bench, l.from.as_str(), l.to.as_str()) {
            return Reply::err(re, error);
        }
        if !edges::linkable_from(bench, l.from.as_str()).contains(&l.to.to_string()) {
            return Reply::ok(re);
        }
        let limit = l.max_sends.map(|n| i64::from(n.max(1)));
        let mut list = bench.edge_list().to_vec();
        let mut want = vec![(l.from.to_string(), l.to.to_string())];
        if l.both {
            want.push((l.to.to_string(), l.from.to_string()));
        }
        for (from, to) in want {
            list.push(match limit {
                Some(n) => EdgeConfig::new(from, to, Some(n)),
                None => EdgeConfig::with_default_limit(from, to),
            });
        }
        // O aviso de ciclo é o mesmo do `/edge`: a ligação nova pode fechar uma
        // roda de três nós ou mais.
        let first = list.len() - if l.both { 2 } else { 1 };
        let warning = edges::cycle_warning(&bench.name, &list[first], &list);
        bench.edges = Some(list);
        crate::log!("aresta[{}]: {} → {}", bench.name, l.from, l.to);
        let mut effects = vec![OrgEffect::PersistWorkbenches];
        if let Some((text, note)) = warning {
            crate::log!("{note}");
            effects.push(OrgEffect::Banner {
                workbench: bench.id.clone(),
                text,
            });
        }
        self.apply_org(effects);
        Reply::ok(re)
    }

    /// O ⌘-clique no subtítulo (`NodeView.swift`): a pasta que o card mostra,
    /// inteira, com o app padrão do sistema. O que o sistema faz com ela não
    /// volta: o Swift também não diz nada se o Finder não abrir.
    fn open_node_folder(&mut self, re: u64, n: &crate::protocol::node::NodeTarget) -> Reply {
        let Some(index) = self.org.index_of(&n.workbench) else {
            return unknown_bench(re, &n.workbench);
        };
        let path = match self.org.node_directory(index, n.node.as_str()) {
            Ok(path) => path,
            Err(error) => return Reply::err(re, error),
        };
        crate::log!("nó[{}]: ⌘-clique no subtítulo abre {path}", n.node);
        self.drivers
            .opener
            .open(&crate::ports::opener::OpenTarget::File(path.into()));
        Reply::ok(re)
    }

    /// Tira o nó: derruba o terminal, solta o app que o Egeon abriu para ele
    /// (se era o último a usar) e leva as ligações que apontavam para ele.
    fn remove_node(&mut self, re: u64, r: NodeRef) -> Reply {
        let Some(index) = self.org.index_of(&r.workbench) else {
            return unknown_bench(re, &r.workbench);
        };
        let bench = self.org.state.workbenches[index].clone();
        let Some(node) = bench.nodes.iter().find(|n| n.id == r.node.as_str()) else {
            return unknown_node(re, r.node.as_str());
        };
        let address = bench.address_of(node);
        if let Some(terminal) = screen_id(&bench.id, &node.id) {
            let _ = self.close(&terminal);
        }
        let Some(removed) = edit::remove_node(&mut self.org.state.workbenches[index], &node.id)
        else {
            return unknown_node(re, r.node.as_str());
        };
        if removed.edges > 0 {
            crate::log!(
                "bancada {}: {} ligação(ões) removida(s) junto com \"{}\"",
                bench.name,
                removed.edges,
                node.id
            );
        }
        crate::log!("bancada {}: nó \"{}\" removido", bench.name, node.id);
        let live = self.live_addresses();
        self.processes_release_apps(BTreeSet::from([address]), live);
        self.apply_org(vec![OrgEffect::PersistWorkbenches]);
        Reply::ok(re)
    }

    /// Os endereços dos terminais que seguem de pé.
    fn live_addresses(&self) -> BTreeSet<String> {
        self.nodes
            .values()
            .filter(|n| n.session.is_some())
            .filter_map(|n| n.address.clone())
            .collect()
    }
}

/// O estado do ator que é do `org`: a fila das remoções de bancada, as
/// limpezas em curso e os cronômetros.
///
/// A fila é serial: duas bancadas removidas em seguida que dividem repositório
/// disputariam o `.git/worktrees` do mesmo checkout, e o ator é o único dono
/// desse estado — a próxima só começa quando a anterior volta pelo `Msg::Run`.
#[derive(Default)]
pub(super) struct NodeState {
    /// Remoções à espera da vez; cada uma é o disparo do trabalho de fundo dela.
    pub(super) removals: std::collections::VecDeque<Job>,
    /// Uma remoção está no disco agora.
    pub(super) removal_busy: bool,
    /// Limpezas em curso, por id de bancada.
    pub(super) cleaning: HashMap<String, super::node_clean::Cleaning>,
    /// Os cronômetros de todas as bancadas (`workbenches/<id>/clock.json`).
    pub(super) clocks: Option<WorkbenchClocks>,
}

type Job = Box<dyn FnOnce(&mut Actor) + Send>;

type Then<T> = Box<dyn FnOnce(&mut Actor, T) + Send>;
type Removed = (Vec<BenchWorktree>, Option<Removal>);

/// Roda o trabalho na fila de bloqueantes; pânico dele vira texto de erro em
/// vez de sumir com a resposta.
async fn run_blocking<T: Send + 'static>(
    work: impl FnOnce() -> T + Send + 'static,
) -> Result<T, String> {
    tokio::task::spawn_blocking(work)
        .await
        .map_err(|e| format!("o trabalho em segundo plano falhou: {e}"))
}

impl Actor {
    /// Trabalho que bloqueia (git, disco) fora do ator; o resultado volta como
    /// mensagem e `then` roda no ator — com `Err` quando o trabalho morreu (pânico),
    /// para quem pediu sempre ter resposta e nenhuma marca ficar para trás.
    pub(super) fn blocking<T: Send + 'static>(
        &self,
        work: impl FnOnce() -> T + Send + 'static,
        then: Then<Result<T, String>>,
    ) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let value = run_blocking(work).await;
            let job = move |actor: &mut Actor| then(actor, value);
            let _ = inbox.send(super::Msg::Run(Box::new(job))).await;
        });
    }

    /// Cria a bancada numa pasta (a do projeto, ou a escolhida), com o nome
    /// livre e, se pedido, os nós do template. Bancada de multi-projeto só
    /// nasce em worktree (ADR-065): isso é o comando `worktree`.
    fn create_workbench(&mut self, client: ClientId, re: u64, c: CreateWorkbench) -> Option<Reply> {
        let home = self.org.home.clone();
        let project = c.project.as_ref().and_then(|id| {
            self.org
                .state
                .workspaces
                .iter()
                .find_map(|w| w.project_with_id(id.as_str()))
                .cloned()
        });
        if c.project.is_some() && project.is_none() {
            return Some(Reply::err(
                re,
                format!("projeto desconhecido '{}'", c.project?),
            ));
        }
        let folder = match &project {
            Some(p) => p.url_path(&home),
            None => normalize(&c.path, &home),
        };
        // A pasta de links de um multi-projeto, escolhida à mão, é o mesmo
        // multi-projeto: bancada dele só em worktree.
        let multi = project
            .clone()
            .filter(|p| p.requires_worktree())
            .or_else(|| {
                self.org
                    .state
                    .workspaces
                    .iter()
                    .flat_map(|w| &w.projects)
                    .find(|p| p.requires_worktree() && p.owns(&folder, &home))
                    .cloned()
            });
        if let Some(multi) = multi {
            return Some(Reply::err(
                re,
                format!(
                    "\"{}\" é multi-projeto: a bancada dele só nasce em worktree",
                    multi.name
                ),
            ));
        }
        if folder.is_empty() {
            return Some(Reply::err(re, "pasta da bancada vazia"));
        }

        let file = self.config.paths.config(bench_store::TEMPLATES_FILE);
        let preset = match &c.template {
            Some(name) => match bench_store::template(&file, name) {
                Some(preset) => Some(preset),
                None => return Some(Reply::err(re, format!("template desconhecido '{name}'"))),
            },
            None => None,
        };
        let suggestion = c
            .name
            .as_deref()
            .map(str::trim)
            .filter(|n| !n.is_empty())
            .map_or_else(|| last_component(&folder), str::to_owned);
        let taken: Vec<&str> = self
            .org
            .state
            .workbenches
            .iter()
            .map(|w| w.name.as_str())
            .collect();
        let name = WorkbenchName::available(&suggestion, &taken);
        let mut config = WorkbenchConfig::new(
            name.as_str(),
            abbreviate_tilde(&folder, &home),
            preset.as_ref().map(|p| p.instantiate()).unwrap_or_default(),
        );
        config.template = c.template.clone();
        config.project = c.project.as_ref().map(ToString::to_string);
        // O modo vem do preset: um template desenhado em chat abre em chat.
        config.view = preset.and_then(|p| p.view);
        for node in &mut config.nodes {
            let profile = node.agent.as_ref().and_then(|a| self.org.profiles.get(a));
            edit::prepare_conversation(node, profile);
        }
        let mut config = colored_among(config, &self.org.state.workbenches);
        if let Some(color) = c.color.as_deref() {
            match crate::features::workbench::model::WorkbenchColor::named(color) {
                Some(color) => config.color = Some(color),
                None => return Some(Reply::err(re, format!("cor desconhecida '{color}'"))),
            }
        }

        // Sem projeto dado, o dono é o repositório principal da pasta — git,
        // fora do ator —; com projeto, a conciliação não precisa dele.
        let git = self.user_git();
        let root_of = folder.clone();
        let needs_root = config.project.is_none();
        self.blocking(
            move || {
                needs_root
                    .then(|| worktree_service::main_repo(&git, &root_of))
                    .flatten()
            },
            Box::new(
                move |actor: &mut Actor, root: Result<Option<String>, String>| {
                    let root = match root {
                        Ok(root) => root,
                        Err(error) => {
                            actor.send_reply(client, &Reply::err(re, error));
                            return;
                        }
                    };
                    let id = config.id.clone();
                    let template = config.template.clone();
                    crate::log!(
                        "bancada \"{}\" criada em {}{}",
                        config.name,
                        config.path,
                        template.map_or_else(
                            || " vazia".to_owned(),
                            |t| format!(" a partir do template \"{t}\"")
                        )
                    );
                    actor.org.state.workbenches.push(config);
                    let done = reconcile(
                        &actor.org.state.workspaces,
                        &actor.org.state.workbenches,
                        &actor.org.home,
                        |_| root.clone(),
                    );
                    for note in &done.notes {
                        crate::log!("workspaces: {note}");
                    }
                    actor.org.state.workspaces = done.workspaces;
                    actor.org.state.workbenches = done.workbenches;
                    actor.apply_org(vec![
                        OrgEffect::SaveWorkspaces,
                        OrgEffect::PersistWorkbenches,
                        OrgEffect::Activate { id: id.clone() },
                    ]);
                    actor.send_reply(client, &Reply::with(re, &json!({"workbench": id})));
                },
            ),
        );
        None
    }

    pub(super) fn removal_context(&self, bench: &WorkbenchConfig) -> RemovalContext {
        let is_multi = bench
            .project
            .as_deref()
            .and_then(|id| {
                self.org
                    .state
                    .workspaces
                    .iter()
                    .find_map(|w| w.project_with_id(id))
            })
            .is_some_and(|p| p.is_multi());
        RemovalContext {
            is_multi,
            others: self
                .org
                .state
                .workbenches
                .iter()
                .filter(|w| w.id != bench.id)
                .map(|w| (w.name.clone(), w.url_path(&self.org.home)))
                .collect(),
        }
    }

    fn remove_workbench_command(
        &mut self,
        client: ClientId,
        re: u64,
        r: RemoveWorkbench,
    ) -> Option<Reply> {
        let Some(name) = self.org.name_of(&r.workbench) else {
            return Some(unknown_bench(re, &r.workbench));
        };
        self.start_removal(
            &name,
            r.worktrees,
            Box::new(move |actor, body: Value| {
                let reply = if body["ok"] == false {
                    Reply::err(re, removal_failure(&body))
                } else {
                    Reply::with(re, &body)
                };
                actor.send_reply(client, &reply);
            }),
        );
        None
    }

    /// `GET /remove?target=ws[&worktrees=1]`: remove a bancada, e só com
    /// `worktrees=1` apaga as worktrees dela do disco. O padrão é não apagar.
    pub(super) fn remove_route(&mut self, request: RouteRequest, reply: Replier) {
        let target = request.param("target").unwrap_or("").to_owned();
        let purge = request.param("worktrees") == Some("1");
        self.start_removal(
            &target,
            purge,
            Box::new(move |_, body: Value| {
                let ok = body["ok"].as_bool().unwrap_or(false);
                let _ = reply.send(crate::protocol::handler::RouteReply::with_status(
                    if ok { 200 } else { 400 },
                    body,
                ));
            }),
        );
    }

    /// A remoção em si, com a resposta pelo `finish` no fim.
    ///
    /// O levantamento e a purga são git e disco, na fila serial de fundo. Só
    /// sai da lista se nada resistiu; sobra de pasta não segura a bancada: o
    /// registro já foi, e a faxina vem depois que os processos dela morrerem
    /// (ADR-060).
    fn start_removal(&mut self, name: &str, purge_worktrees: bool, finish: Then<Value>) {
        let Some(bench) = self
            .org
            .state
            .workbenches
            .iter()
            .find(|w| w.name == name)
            .cloned()
        else {
            finish(
                self,
                json!({"ok": false, "error": format!("bancada desconhecida '{name}'")}),
            );
            return;
        };
        if !self.org.removing.insert(bench.id.clone()) {
            finish(
                self,
                json!({"ok": false, "error": "remoção já em curso nesta bancada"}),
            );
            return;
        }
        let context = self.removal_context(&bench);
        let project = bench
            .project
            .as_deref()
            .and_then(|id| {
                self.org
                    .state
                    .workspaces
                    .iter()
                    .find_map(|w| w.project_with_id(id))
            })
            .cloned();
        let (git, home) = (self.user_git(), self.org.home.clone());
        let id = bench.id.clone();
        let bench_name = bench.name.clone();
        let roots = multi_roots(&bench, project.as_ref(), &home);
        self.publish_org();
        let job: Job = Box::new(move |actor: &mut Actor| {
            actor.blocking(
                move || {
                    let worktrees = involved(&git, &bench, &context, &home);
                    let outcome = purge_worktrees.then(|| {
                        let targets: Vec<RemovalTarget> = worktrees
                            .iter()
                            .filter(|w| w.used_by.is_none())
                            .map(|w| RemovalTarget {
                                path: w.path.clone(),
                                label: format!(
                                    "{} · {}",
                                    w.repo,
                                    w.branch.as_deref().unwrap_or("?")
                                ),
                            })
                            .collect();
                        crate::log!(
                            "bancada \"{}\": apagando {} worktree(s) em segundo plano",
                            bench.name,
                            targets.len()
                        );
                        purge(&targets, |path| worktree_service::remove(&git, path))
                    });
                    (worktrees, outcome)
                },
                Box::new(move |actor: &mut Actor, done: Result<Removed, String>| {
                    actor.org.removing.remove(&id);
                    actor.node.removal_busy = false;
                    let (worktrees, outcome) = match done {
                        Ok(done) => done,
                        Err(error) => {
                            actor.publish_org();
                            finish(actor, json!({"ok": false, "error": error}));
                            actor.pump_removal();
                            return;
                        }
                    };
                    let succeeded = outcome.as_ref().is_none_or(|o| o.succeeded());
                    if succeeded {
                        actor.drop_workbench(&id);
                        if let Some(done) = &outcome {
                            actor.sweep_later(done.leftovers.clone(), roots.clone());
                        } else {
                            actor.sweep_later(Vec::new(), roots);
                        }
                    } else {
                        actor.publish_org();
                    }
                    finish(actor, payload(&bench_name, &worktrees, outcome.as_ref()));
                    actor.pump_removal();
                }),
            );
        });
        self.node.removals.push_back(job);
        self.pump_removal();
    }

    /// Começa a próxima remoção da fila, se nenhuma está no disco.
    fn pump_removal(&mut self) {
        if self.node.removal_busy {
            return;
        }
        let Some(job) = self.node.removals.pop_front() else {
            return;
        };
        self.node.removal_busy = true;
        job(self);
    }

    /// A segunda passada nas pastas que o git deixou para trás.
    ///
    /// Depois de a bancada sair: os processos dela acabaram de levar SIGTERM, e
    /// quem ignorou leva SIGKILL meio segundo depois. Antes disso o dev server
    /// ainda estava recriando `.vite` mais rápido do que qualquer um apaga — é
    /// por isso que a faxina não roda junto com o `worktree remove`.
    fn sweep_later(&self, paths: Vec<String>, roots: Vec<std::path::PathBuf>) {
        tokio::spawn(async move {
            let prune = |roots: &[std::path::PathBuf]| {
                for root in roots {
                    if let Some(line) = crate::features::workspace::links::prune_root(root) {
                        crate::log!("{line}");
                    }
                }
            };
            let first = roots.clone();
            let _ = tokio::task::spawn_blocking(move || prune(&first)).await;
            if paths.is_empty() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(1500)).await;
            let _ = tokio::task::spawn_blocking(move || {
                sweep(&paths);
                prune(&roots);
            })
            .await;
        });
    }

    /// Tira a bancada da lista: derruba os terminais, solta os apps que o
    /// Egeon abriu para eles e põe outra na frente (a que ficou no lugar dela).
    fn drop_workbench(&mut self, id: &str) {
        let Some(index) = self.org.state.workbenches.iter().position(|w| w.id == id) else {
            return;
        };
        let bench = self.org.state.workbenches[index].clone();
        let leaving: BTreeSet<String> = bench.nodes.iter().map(|n| bench.address_of(n)).collect();
        for node in &bench.nodes {
            if let Some(terminal) = screen_id(&bench.id, &node.id) {
                let _ = self.close(&terminal);
            }
        }
        self.org.state.workbenches.remove(index);
        self.org.state.open_tabs.retain(|t| t != id);
        self.org.live.remove(id);
        if self.org.state.active_id.as_deref() == Some(id) {
            self.org.state.active_id = None;
        }
        crate::log!("bancada \"{}\" removida", bench.name);
        let live = self.live_addresses();
        self.processes_release_apps(leaving, live);
        let mut effects = vec![OrgEffect::PersistWorkbenches];
        if self.org.state.active_id.is_none()
            && let Some(next) = self
                .org
                .state
                .workbenches
                .get(index.min(self.org.state.workbenches.len().saturating_sub(1)))
        {
            effects.push(OrgEffect::Activate {
                id: next.id.clone(),
            });
        }
        self.apply_org(effects);
    }
}

// ── Workspaces e projetos ──────────────────────────────────────────────────

/// O texto de "A bancada não foi removida" (`purgeAndRemove` do Swift): o que
/// já saiu e o que resistiu. Sem worktree no meio, o erro da remoção.
fn removal_failure(body: &Value) -> String {
    let lines = |key: &str| -> Vec<String> {
        body[key]
            .as_array()
            .map(|list| {
                list.iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect()
            })
            .unwrap_or_default()
    };
    let failed = lines("failed");
    if failed.is_empty() {
        return body["error"]
            .as_str()
            .unwrap_or("remoção falhou")
            .to_owned();
    }
    let removed = lines("removed");
    let done = if removed.is_empty() {
        String::new()
    } else {
        format!("Já apagadas: {}.\n\n", removed.join(", "))
    };
    format!("{done}Não consegui apagar:\n{}", failed.join("\n"))
}

fn blank(re: u64, text: &str) -> Option<Reply> {
    text.trim()
        .is_empty()
        .then(|| Reply::err(re, "Dê um nome ao workspace."))
}

impl Actor {
    fn multi_project_path(&self, id: &str) -> String {
        abbreviate_tilde(
            &self.config.paths.multi_project_dir(id).to_string_lossy(),
            &self.org.home,
        )
    }

    /// A imagem do workspace: `Some(None)` tira, `Some(Some(arquivo))` copia
    /// para a pasta dele, ausente não mexe. Erro de cópia não derruba o resto:
    /// vira texto para a resposta.
    fn set_workspace_icon(
        &self,
        space: &mut WorkspaceConfig,
        icon: &Option<Option<String>>,
    ) -> Option<String> {
        let home = self.config.paths.home();
        match icon {
            None => None,
            Some(None) => {
                space_store::remove_icon(home, space);
                None
            }
            Some(Some(source)) => {
                space_store::install_icon(home, std::path::Path::new(source), space)
                    .err()
                    .map(|e| format!("Não consegui copiar a imagem: {e}"))
            }
        }
    }

    fn create_workspace(&mut self, re: u64, c: CreateWorkspace) -> Reply {
        if let Some(refusal) = blank(re, &c.name) {
            return refusal;
        }
        let mut space = WorkspaceConfig::new(c.name.trim());
        let problem = self.set_workspace_icon(&mut space, &c.icon.map(Some));
        crate::log!("workspace \"{}\" criado", space.name);
        let id = space.id.clone();
        self.org.state.workspaces.push(space);
        self.apply_org(vec![OrgEffect::SaveWorkspaces]);
        match problem {
            Some(error) => Reply::with(re, &json!({"workspace": id, "warning": error})),
            None => Reply::with(re, &json!({"workspace": id})),
        }
    }

    /// O formulário do workspace: nome, imagem, pastas e multi-projetos. Sem
    /// `workspace`, cria. Pasta tirada com bancada dentro fica, e a resposta
    /// diz quais (`refused`) — senão a bancada viraria órfã sem você pedir.
    fn save_workspace(&mut self, re: u64, s: SaveWorkspace) -> Reply {
        if let Some(refusal) = blank(re, &s.name) {
            return refusal;
        }
        let index = match &s.workspace {
            Some(id) => match self
                .org
                .state
                .workspaces
                .iter()
                .position(|w| w.id == id.as_str())
            {
                Some(i) => Some(i),
                None => return Reply::err(re, format!("workspace desconhecido '{id}'")),
            },
            None => None,
        };
        let mut space = index.map_or_else(
            || WorkspaceConfig::new(s.name.trim()),
            |i| self.org.state.workspaces[i].clone(),
        );
        space.name = s.name.trim().to_owned();

        let drafts: Vec<_> = s
            .multis
            .iter()
            .map(|m| crate::features::workspace::multi::MultiProjectDraft {
                id: m.id.as_ref().map(ToString::to_string),
                name: m.name.clone(),
                folders: m.folders.clone(),
            })
            .collect();
        let home = self.org.home.clone();
        let tree = WorkspaceTree::new(&self.org.state.workspaces, &self.org.state.workbenches);
        let outcome = apply_edit(
            &space.projects,
            &s.folders,
            &drafts,
            &home,
            |id| self.multi_project_path(id),
            |project| !tree.indices_in_project(project).is_empty(),
        );
        space.projects = outcome.projects;
        let warning = self.set_workspace_icon(&mut space, &s.icon);

        crate::log!(
            "workspace \"{}\" {} — {} projeto(s)",
            space.name,
            if index.is_some() { "editado" } else { "criado" },
            space.projects.len()
        );
        let id = space.id.clone();
        match index {
            Some(i) => self.org.state.workspaces[i] = space,
            None => self.org.state.workspaces.push(space),
        }
        self.apply_org(vec![OrgEffect::SaveWorkspaces]);
        let saved: Vec<WorkspaceConfig> = self
            .org
            .state
            .workspaces
            .iter()
            .filter(|w| w.id == id)
            .cloned()
            .collect();
        self.sync_multi_links(saved);
        let mut body = json!({"workspace": id, "refused": outcome.refused});
        if let Some(warning) = warning {
            body["warning"] = Value::String(warning);
        }
        Reply::with(re, &body)
    }

    /// Só a organização some; nenhuma pasta é tocada. Com bancada dentro, não.
    fn remove_workspace(&mut self, re: u64, r: RemoveWorkspace) -> Reply {
        let Some(index) = self
            .org
            .state
            .workspaces
            .iter()
            .position(|w| w.id == r.workspace.as_str())
        else {
            return Reply::err(re, format!("workspace desconhecido '{}'", r.workspace));
        };
        let tree = WorkspaceTree::new(&self.org.state.workspaces, &self.org.state.workbenches);
        let members = tree.indices_in_workspace(r.workspace.as_str()).len();
        let name = self.org.state.workspaces[index].name.clone();
        if members > 0 {
            return Reply::err(
                re,
                format!(
                    "\"{name}\" ainda tem {members} bancada(s). Remova as bancadas antes de \
                     remover o workspace."
                ),
            );
        }
        if r.dry_run {
            return Reply::ok(re);
        }
        let mut space = self.org.state.workspaces.remove(index);
        let home = self.config.paths.home();
        space_store::remove_icon(home, &mut space);
        let _ = std::fs::remove_dir_all(space_store::directory(home, &space.id));
        crate::log!("workspace \"{name}\" removido");
        self.apply_org(vec![OrgEffect::SaveWorkspaces]);
        Reply::ok(re)
    }

    /// O "Novo projeto…": cria a pasta, o `git init` e o põe no workspace. É a
    /// rota `/project/new` por dentro: pasta e git, fora do ator.
    fn create_project(&mut self, client: ClientId, re: u64, c: CreateProject) -> Option<Reply> {
        let mut query = vec![
            ("workspace", c.workspace.to_string()),
            ("name", c.name),
            ("git", if c.git { "1" } else { "0" }.to_owned()),
        ];
        if let Some(parent) = c.parent {
            query.push(("parent", parent));
        }
        let request = crate::protocol::handler::RouteRequest {
            method: "POST".to_owned(),
            target: "/project/new".to_owned(),
            path: "/project/new".to_owned(),
            query: query.into_iter().map(|(k, v)| (k.to_owned(), v)).collect(),
            body: Vec::new(),
            origin: None,
        };
        let state = self.org.state.clone();
        let (home, git) = (self.org.home.clone(), self.user_git());
        self.blocking(
            move || crate::features::workspace::routes::project_new(&state, &request, &home, &git),
            Box::new(
                move |actor: &mut Actor, done: Result<(RouteReply, Vec<OrgEffect>), String>| {
                    let (answer, effects) = match done {
                        Ok(done) => done,
                        Err(error) => {
                            actor.send_reply(client, &Reply::err(re, error));
                            return;
                        }
                    };
                    actor.apply_org(effects);
                    let mut body = answer.json;
                    if let Some(map) = body.as_object_mut() {
                        // O estado novo chega pelo tópico.
                        map.remove("tree");
                    }
                    actor.send_reply(client, &Reply::with(re, &body));
                },
            ),
        );
        None
    }

    /// Uma pasta que já existe vira projeto do workspace, à vista (workspace
    /// recolhido abre).
    fn add_project(&mut self, re: u64, a: AddProject) -> Reply {
        let home = self.org.home.clone();
        let Some(index) = self
            .org
            .state
            .workspaces
            .iter()
            .position(|w| w.id == a.workspace.as_str())
        else {
            return Reply::err(re, format!("workspace desconhecido '{}'", a.workspace));
        };
        let folder = normalize(&a.path, &home);
        if !std::path::Path::new(&folder).is_dir() {
            return Reply::err(
                re,
                format!("A pasta {} não existe.", abbreviate_tilde(&folder, &home)),
            );
        }
        let space = &mut self.org.state.workspaces[index];
        if let Some(existing) = space.project_owning(&folder, &home) {
            return Reply::err(
                re,
                format!(
                    "Essa pasta já é o projeto \"{}\" deste workspace.",
                    existing.name
                ),
            );
        }
        let mut project = ProjectConfig::for_folder(&folder, &home);
        if let Some(name) = a.name.as_deref().map(str::trim).filter(|n| !n.is_empty()) {
            project.name = name.to_owned();
        }
        let id = project.id.clone();
        crate::log!(
            "projeto \"{}\" adotado em {} no workspace \"{}\"",
            project.name,
            project.path,
            space.name
        );
        space.projects.push(project);
        space.collapsed = None;
        self.apply_org(vec![OrgEffect::SaveWorkspaces]);
        Reply::with(re, &json!({"project": id}))
    }

    /// Tira o projeto do workspace; a pasta não é tocada. Com bancada dentro,
    /// não.
    fn remove_project(&mut self, re: u64, r: RemoveProject) -> Reply {
        let Some((w, p)) = self
            .org
            .state
            .workspaces
            .iter()
            .enumerate()
            .find_map(|(w, space)| {
                space
                    .projects
                    .iter()
                    .position(|p| p.id == r.project.as_str())
                    .map(|p| (w, p))
            })
        else {
            return Reply::err(re, format!("projeto desconhecido '{}'", r.project));
        };
        let tree = WorkspaceTree::new(&self.org.state.workspaces, &self.org.state.workbenches);
        let members = tree.indices_in_project(r.project.as_str()).len();
        let name = self.org.state.workspaces[w].projects[p].name.clone();
        if members > 0 {
            return Reply::err(
                re,
                format!(
                    "\"{name}\" ainda tem {members} bancada(s). Remova as bancadas antes de \
                     tirar o projeto do workspace."
                ),
            );
        }
        if r.dry_run {
            return Reply::ok(re);
        }
        let space = &mut self.org.state.workspaces[w];
        space.projects.remove(p);
        crate::log!("projeto \"{name}\" tirado do workspace \"{}\"", space.name);
        self.apply_org(vec![OrgEffect::SaveWorkspaces]);
        Reply::ok(re)
    }

    /// Um multi-projeto: projetos de pasta DESTE workspace, juntos por id numa
    /// pasta de links (ADR-065). Nome vazio é o das pastas.
    fn multi_project(&mut self, re: u64, m: MultiProject) -> Reply {
        let home = self.org.home.clone();
        let Some(index) = self
            .org
            .state
            .workspaces
            .iter()
            .position(|w| w.id == m.workspace.as_str())
        else {
            return Reply::err(re, format!("workspace desconhecido '{}'", m.workspace));
        };
        let space = &self.org.state.workspaces[index];
        let mut folders = Vec::new();
        let mut members = Vec::new();
        for id in &m.members {
            match space.project_with_id(id.as_str()).filter(|p| !p.is_multi()) {
                Some(p) => {
                    folders.push(p.path.clone());
                    members.push(p.id.clone());
                }
                None => return Reply::err(re, format!("projeto de pasta desconhecido '{id}'")),
            }
        }
        if members.is_empty() {
            return Reply::err(re, "Escolha ao menos uma pasta.");
        }
        let name = match m.name.trim() {
            "" => default_name(&folders, &home),
            given => given.to_owned(),
        };
        let id = crate::features::workbench::model::new_id();
        let mut project = ProjectConfig::new(name, self.multi_project_path(&id));
        project.id = id.clone();
        project.members = Some(members);
        self.org.state.workspaces[index].projects.push(project);
        self.apply_org(vec![OrgEffect::SaveWorkspaces]);
        let space = self.org.state.workspaces[index].clone();
        self.sync_multi_links(vec![space]);
        Reply::with(re, &json!({"project": id}))
    }
}

// ── Worktree, cópia do não versionado e links do multi-projeto ─────────────

use crate::features::worktree::duplicate::Target;
use crate::features::worktree::from_folder;
use crate::features::worktree::merge;
use crate::features::worktree::routes::{
    FormChoice, OrgSnapshot, WorktreeEffect, worktree_with as worktree_route,
};

impl Actor {
    /// O comando `worktree` do `/ui` é a rota `/worktree` por dentro: a mesma
    /// regra e os mesmos textos de erro para a UI, o `egeon` e o `curl`.
    fn worktree_command(&mut self, client: ClientId, re: u64, w: Worktree) -> Option<Reply> {
        let Some(workbench) = w.workbench.clone() else {
            return self.worktree_from_folder(client, re, w);
        };
        let Some(name) = self.org.name_of(&workbench) else {
            return Some(unknown_bench(re, &workbench));
        };
        // `bancada/nó` na rota: só aquele terminal é reapontado.
        let name = match &w.node {
            Some(node) => format!("{name}/{node}"),
            None => name,
        };
        let choice = match self.form_choice(&w) {
            Ok(choice) => choice,
            Err(error) => return Some(Reply::err(re, error)),
        };
        // Na rota, `nodes` de bancada multi-projeto são os repositórios.
        let nodes: Vec<String> = w
            .nodes
            .iter()
            .map(|(id, branch)| format!("{id}:{branch}"))
            .chain(
                w.repos
                    .iter()
                    .map(|(repo, branch)| format!("{repo}:{branch}")),
            )
            .collect();
        let mut query = vec![("target", name), ("branch", w.branch)];
        if !nodes.is_empty() {
            query.push(("nodes", nodes.join(",")));
        }
        let request = RouteRequest {
            method: "GET".to_owned(),
            target: "/worktree".to_owned(),
            path: "/worktree".to_owned(),
            query: query.into_iter().map(|(k, v)| (k.to_owned(), v)).collect(),
            body: Vec::new(),
            origin: None,
        };
        self.start_worktree(
            request,
            choice,
            Box::new(move |actor, answer: RouteReply| {
                actor.send_reply(client, &Reply::with(re, &actor.worktree_answer(answer)));
            }),
        );
        None
    }

    /// Bancada nova numa worktree de uma pasta, sem bancada de origem
    /// (`createWorkbenchFromWorktree`): o repositório vem de `path` ou da pasta
    /// do `project`.
    fn worktree_from_folder(&mut self, client: ClientId, re: u64, w: Worktree) -> Option<Reply> {
        if w.destination == WorktreeDestination::MoveCurrent {
            return Some(Reply::err(re, "não há bancada para mover"));
        }
        if w.path.is_none() && w.project.is_none() {
            return Some(Reply::err(re, "pede a pasta do repositório"));
        }
        let choice = match self.form_choice(&w) {
            Ok(choice) => choice,
            Err(error) => return Some(Reply::err(re, error)),
        };
        let (path, project, branch, repos) =
            (w.path, w.project.map(|p| p.to_string()), w.branch, w.repos);
        self.run_worktree(
            move |snapshot, home, git, links| {
                from_folder::from_folder(
                    git,
                    snapshot,
                    from_folder::Source {
                        path: path.as_deref(),
                        project: project.as_deref(),
                    },
                    from_folder::Branches {
                        branch: &branch,
                        repos: &repos,
                    },
                    choice.template.as_ref(),
                    home,
                    &|target, link| links.symlink(target, link),
                )
            },
            Box::new(move |actor, answer: RouteReply| {
                actor.send_reply(client, &Reply::with(re, &actor.worktree_answer(answer)));
            }),
        );
        None
    }

    /// As escolhas do formulário: para onde vai a worktree e de que template a
    /// bancada nova nasce.
    fn form_choice(&self, w: &Worktree) -> Result<FormChoice, String> {
        // No Swift o template só existe no formulário sem origem, que só cria
        // bancada nova; mover a bancada atual para uma worktree não tem molde.
        if w.destination == WorktreeDestination::MoveCurrent && w.template.is_some() {
            return Err("template só vale para bancada nova".to_owned());
        }
        let template = match &w.template {
            Some(name) => {
                let file = self.config.paths.config(bench_store::TEMPLATES_FILE);
                let Some(preset) = bench_store::template(&file, name) else {
                    return Err(format!("template desconhecido '{name}'"));
                };
                Some((name.clone(), preset))
            }
            None => None,
        };
        Ok(FormChoice {
            destination: match w.destination {
                WorktreeDestination::NewWorkbench => Target::NewWorkbench,
                WorktreeDestination::MoveCurrent => Target::MoveCurrent,
            },
            template,
        })
    }

    /// A resposta do comando traz o id da bancada (`{workbench}`); a rota HTTP
    /// fala o nome, como o Swift. O nome some da lista só se a rota falhou.
    fn worktree_answer(&self, answer: RouteReply) -> Value {
        let mut json = answer.json;
        let id = json
            .get("workbench")
            .and_then(Value::as_str)
            .and_then(|name| self.org.state.workbenches.iter().find(|w| w.name == name))
            .map(|w| w.id.clone());
        if let (Some(id), Some(object)) = (id, json.as_object_mut()) {
            object.insert("workbench".to_owned(), Value::String(id));
        }
        // Multi-projeto em que nenhum repositório aceitou: o "Nenhuma worktree
        // foi criada" do Swift lista o motivo de cada um.
        if json["ok"] == false && json.get("error").is_none() {
            let failed = json["failed"]
                .as_array()
                .map(|list| {
                    list.iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join("\n")
                })
                .unwrap_or_default();
            if let (false, Some(object)) = (failed.is_empty(), json.as_object_mut()) {
                object.insert("error".to_owned(), Value::String(failed));
            }
        }
        json
    }

    /// `GET /worktree?target=ws[/id]&branch=X[&nodes=back:fix/api]`.
    pub(super) fn worktree_route(&mut self, request: RouteRequest, reply: Replier) {
        self.start_worktree(
            request,
            FormChoice::default(),
            Box::new(move |_, answer: RouteReply| {
                let _ = reply.send(answer);
            }),
        );
    }

    /// Git e cópia de arquivos levam de segundos a minutos: sobre uma cópia da
    /// organização, fora do ator; a bancada nova (ou o nó reapontado) volta
    /// como efeito e entra no ator, que então a ativa, grava e copia o que o git
    /// não versiona.
    fn start_worktree(
        &mut self,
        request: RouteRequest,
        choice: FormChoice,
        finish: Then<RouteReply>,
    ) {
        self.run_worktree(
            move |snapshot, home, git, links| {
                worktree_route(
                    &request,
                    snapshot,
                    home,
                    git,
                    &|target, link| links.symlink(target, link),
                    &choice,
                )
            },
            finish,
        );
    }

    /// Roda o trabalho de git fora do ator sobre uma cópia da organização, aplica
    /// os efeitos que ele devolve e responde.
    fn run_worktree(
        &mut self,
        work: impl FnOnce(
            &OrgSnapshot,
            &str,
            &crate::features::worktree::Git,
            &dyn crate::ports::links::FileLinks,
        ) -> (RouteReply, Vec<WorktreeEffect>)
        + Send
        + 'static,
        finish: Then<RouteReply>,
    ) {
        let snapshot = OrgSnapshot {
            workbenches: self.org.state.workbenches.clone(),
            workspaces: self.org.state.workspaces.clone(),
        };
        let (home, git, links) = (
            self.org.home.clone(),
            self.user_git(),
            self.drivers.links.clone(),
        );
        self.blocking(
            move || work(&snapshot, &home, &git, links.as_ref()),
            Box::new(
                move |actor: &mut Actor,
                      done: Result<(RouteReply, Vec<WorktreeEffect>), String>| {
                    let (answer, effects) = match done {
                        Ok(done) => done,
                        Err(error) => {
                            finish(actor, RouteReply::err(500, error));
                            return;
                        }
                    };
                    for effect in effects {
                        actor.apply_worktree(effect);
                    }
                    finish(actor, answer);
                },
            ),
        );
    }

    fn apply_worktree(&mut self, effect: WorktreeEffect) {
        match effect {
            WorktreeEffect::AddWorkbench { config, copies } => {
                let id = config.id.clone();
                self.org.state.workbenches.push(config);
                let done = reconcile(
                    &self.org.state.workspaces,
                    &self.org.state.workbenches,
                    &self.org.home,
                    |_| None,
                );
                self.org.state.workspaces = done.workspaces;
                self.org.state.workbenches = done.workbenches;
                self.apply_org(vec![
                    OrgEffect::SaveWorkspaces,
                    OrgEffect::PersistWorkbenches,
                    OrgEffect::Activate { id: id.clone() },
                ]);
                self.copy_unversioned(&id, copies);
            }
            WorktreeEffect::RepointNode {
                workbench_id,
                node,
                copies,
            } => {
                let Some(index) = self
                    .org
                    .state
                    .workbenches
                    .iter()
                    .position(|w| w.id == workbench_id)
                else {
                    return;
                };
                let Some(position) = self.org.state.workbenches[index]
                    .nodes
                    .iter()
                    .position(|n| n.id == node.id)
                else {
                    return;
                };
                // Só a pasta nova entra: o nó de agora guarda o que foi editado
                // enquanto o git rodava.
                let mut node =
                    merge::repoint_live(&self.org.state.workbenches[index].nodes[position], &node);
                let profile = self.profile_of(&node);
                edit::prepare_conversation(&mut node, profile.as_ref());
                // Um pty não muda de diretório depois de aberto: o terminal é
                // refeito, no mesmo lugar do canvas (o frame vai no nó).
                if let Some(terminal) = screen_id(&workbench_id, &node.id) {
                    let _ = self.close(&terminal);
                }
                self.org.state.workbenches[index].nodes[position] = node.clone();
                if self.org.live.contains(&workbench_id) {
                    let bench = self.org.state.workbenches[index].clone();
                    self.open_terminal(&bench, &node);
                }
                self.apply_org(vec![OrgEffect::PersistWorkbenches]);
                self.copy_unversioned(&workbench_id, copies);
            }
            WorktreeEffect::MoveWorkbench { config, copies } => {
                let Some(index) = self
                    .org
                    .state
                    .workbenches
                    .iter()
                    .position(|w| w.id == config.id)
                else {
                    return;
                };
                // O canvas inteiro é refeito: um pty não muda de diretório
                // depois de aberto, e reconstruir reaproveita o caminho de
                // sempre em vez de um segundo, quase igual, só para esta situação.
                for node in self.org.state.workbenches[index].nodes.clone() {
                    if let Some(terminal) = screen_id(&config.id, &node.id) {
                        let _ = self.close(&terminal);
                    }
                }
                let live = self.org.live.contains(&config.id);
                let id = config.id.clone();
                self.org.state.workbenches[index] =
                    merge::move_live(&self.org.state.workbenches[index], &config);
                for position in 0..self.org.state.workbenches[index].nodes.len() {
                    let mut node = self.org.state.workbenches[index].nodes[position].clone();
                    let profile = self.profile_of(&node);
                    edit::prepare_conversation(&mut node, profile.as_ref());
                    self.org.state.workbenches[index].nodes[position] = node;
                }
                if live {
                    self.open_terminals(&id);
                }
                self.apply_org(vec![
                    OrgEffect::PersistWorkbenches,
                    OrgEffect::Activate { id },
                ]);
                self.copy_unversioned(&config.id, copies);
            }
        }
    }

    /// Deixa cada pasta de multi-projeto com um link por repositório. Na carga
    /// e depois de salvar o workspace: a pasta é derivada, e é refeita a cada
    /// arranque.
    pub(super) fn sync_multi_links(&mut self, workspaces: Vec<WorkspaceConfig>) {
        if !workspaces
            .iter()
            .flat_map(|w| &w.projects)
            .any(|p| p.is_multi())
        {
            return;
        }
        let (home, links) = (self.org.home.clone(), self.drivers.links.clone());
        self.blocking(
            move || {
                crate::features::workspace::links::sync_all(&workspaces, &home, &|target, link| {
                    links.symlink(target, link)
                })
            },
            Box::new(|_, done: Result<Vec<String>, String>| match done {
                Ok(lines) => lines.iter().for_each(|l| crate::log!("{l}")),
                Err(error) => crate::log!("multi-projeto: os links não foram refeitos — {error}"),
            }),
        );
    }
}

// ── Limpar ─────────────────────────────────────────────────────────────────

impl Actor {
    /// O botão de limpar do card: manda o `clear` do perfil pela fila do
    /// Dispatcher, como um prompt seu — terminal ocupado recebe quando ficar
    /// livre, e a TUI não descarta o texto no meio de um redraw. Responde no
    /// disparo. `Some(erro)` quando não deu.
    pub(super) fn node_clear(&mut self, target: &str) -> Option<String> {
        let (bench, node) = split_target(target);
        let found = self.org.state.workbenches.iter().find_map(|b| {
            let node = b
                .nodes
                .iter()
                .find(|n| Some(n.id.as_str()) == node && n.kind == ConfigKind::Agent)?;
            (Some(b.name.as_str()) == bench).then(|| (b.id.clone(), node.clone()))
        });
        let Some((bench_id, node)) = found else {
            return Some(format!("agente desconhecido '{target}'"));
        };
        let Some(command) = self
            .profile_of(&node)
            .and_then(|p| p.clear)
            .filter(|c| !c.is_empty())
        else {
            return Some(format!("o CLI de '{target}' não declara comando de limpar"));
        };
        self.dispatch_chat_send(&bench_id, &node.id, &command).err()
    }
}

/// `bancada/nó` pelo primeiro `/`; sem nó, só a bancada.
fn split_target(target: &str) -> (Option<&str>, Option<&str>) {
    match target.split_once('/') {
        Some((bench, node)) if !bench.is_empty() && !node.is_empty() => (Some(bench), Some(node)),
        _ => (None, None),
    }
}

#[cfg(test)]
mod tests {
    use super::run_blocking;

    #[tokio::test]
    async fn pânico_do_trabalho_vira_erro_e_nao_silencio() {
        let ok = run_blocking(|| 7).await;
        assert_eq!(ok, Ok(7));
        let broken = run_blocking(|| -> u8 { panic!("git morreu") }).await;
        let error = broken.unwrap_err();
        assert!(
            error.starts_with("o trabalho em segundo plano falhou"),
            "{error}"
        );
    }
}

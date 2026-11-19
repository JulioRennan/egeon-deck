//! Dono: `dispatch`. Liga ao ator o [`Coordination`] (envio entre agentes,
//! permissões, atividade, maestro) e as rotas /targets, /conversation,
//! /permission*, /activity, /retry, /message, /maestro*, /peers, /status e
//! /dispatch.
//!
//! O core mantém a assinatura destas funções, que o `actor.rs` chama; o
//! corpo é do dono. A regra mora nas features (`dispatch`, `permission`,
//! `maestro`); aqui só se monta o mundo que elas leem e se executa o que
//! devolvem.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;
use std::time::SystemTime;

use serde_json::{Value, json};

use super::{Actor, Node, Replier, not_ported};
use crate::commons::clock::local_offset_secs;
use crate::commons::ids::NodeId;
use crate::features::activity::model::Activity;
use crate::features::agent::claude::catalog as claude_catalog;
use crate::features::agent::claude::transcript::{MODEL_TAIL_BYTES, last_model_at};
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::ModelCatalog;
use crate::features::agent::store::Profiles;
use crate::features::chat::runtime::Source as ChatSource;
use crate::features::dispatch::coordination::Links;
use crate::features::dispatch::coordination::{Coordination, Outward, World};
use crate::features::dispatch::marker::{
    LastMarker, MARKER_TAIL_BYTES, MarkerConfig, last_marker_at,
};
use crate::features::dispatch::profile::TargetProfile;
use crate::features::dispatch::request::DispatchRequest;
use crate::features::dispatch::routes as dispatch;
use crate::features::dispatch::{Dispatcher, Surface};
use crate::features::maestro::controller::{MaestroEffect, MaestroWiring};
use crate::features::maestro::planner::MaestroContext;
use crate::features::maestro::routes as maestro;
use crate::features::node::model::NodeConfig;
use crate::features::node::model::NodeKind;
use crate::features::permission::routes as permission;
use crate::features::terminal::model::peek_lines;
use crate::features::trace::routes::{NodeIdentities, NodeIdentity, TraceRoutes};
use crate::features::trace::store::TraceLog;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workspace::model::WorkspaceConfig;
use crate::log;
use crate::ports::notifier::{Notice, SoundError};
use crate::protocol::handler::{RouteReply, RouteRequest};
use crate::protocol::routes::FeatureRoute;
use crate::runtime::org::screen_id;

/// O estado do dispatch dentro do ator.
#[derive(Default)]
pub(super) struct DispatchState {
    /// A fila de prompts lê a atividade e envia "de você" por aqui.
    pub(super) coordination: Coordination,
    /// Os terminais de nó já registrados no Dispatcher: id do terminal →
    /// `bancada/nó` e a geração que foi registrada.
    registered: HashMap<NodeId, (String, u64)>,
}

/// O que o chat lê do dispatch (o `ChatHost` do `chat_commands`). Leitura só:
/// o `OrgHost` empresta o `DispatchState` junto da organização.
impl DispatchState {
    /// A atividade do terminal `bancada/nó`.
    pub(super) fn activity(&self, address: &str) -> Option<Activity> {
        self.coordination
            .dispatcher
            .target(address)
            .map(|t| t.activity().clone())
    }

    /// O transcript que o gancho `/conversation` relatou para o nó e o início
    /// do turno em curso (`chat.liveSource` do Swift).
    pub(super) fn source(&self, bench: &WorkbenchConfig, node: &str) -> Option<ChatSource> {
        let config = bench.nodes.iter().find(|n| n.id == node)?;
        let path = config.transcript.as_deref().filter(|p| !p.is_empty())?;
        let address = format!("{}/{node}", bench.name);
        Some(ChatSource {
            path: path.into(),
            not_before: self
                .coordination
                .dispatcher
                .target(&address)
                .and_then(|t| t.turn_started_at()),
        })
    }

    /// Os pedidos de permissão em aberto da bancada para a bandeja do chat —
    /// todos, empilhados como no Swift, no formato do `GET /permissions`.
    pub(super) fn permissions(&self, bench: &WorkbenchConfig, now: SystemTime) -> Vec<Value> {
        self.coordination
            .desk
            .pending_at(&bench.name, now)
            .into_iter()
            .map(|ask| {
                let questions: Vec<Value> = ask
                    .questions()
                    .into_iter()
                    .map(|q| json!({"question": q.question, "options": q.options, "multiSelect": q.multi_select}))
                    .collect();
                json!({
                    "id": ask.id, "address": ask.address, "tool": ask.tool,
                    "summary": ask.summary, "detail": ask.detail.clone().unwrap_or_default(),
                    "always": ask.can_always_allow(), "questions": questions,
                })
            })
            .collect()
    }
}

/// O que as features leem do ator, emprestado só enquanto a chamada dura.
/// A tela do terminal é lida já pronta, porque o `rows_text` pede `&mut`.
struct View<'a> {
    screens: HashMap<String, Vec<String>>,
    running: HashSet<String>,
    workbenches: &'a [WorkbenchConfig],
    workspaces: &'a [WorkspaceConfig],
    profiles: &'a Profiles,
    authorized: bool,
    app_active: bool,
    focused: Option<&'a str>,
    home: &'a str,
    data: &'a Path,
    activities: HashMap<String, Activity>,
}

impl Surface for View<'_> {
    fn running(&self, address: &str) -> bool {
        self.running.contains(address)
    }

    /// Você está olhando para ESTE terminal: o app na frente e o foco do
    /// teclado nele (`isFocused` do Swift), como a UI diz pelo `ui_focus`.
    fn focused(&self, address: &str) -> bool {
        self.app_active && self.focused == Some(address)
    }

    fn peek(&self, address: &str, lines: usize) -> Vec<String> {
        self.screens
            .get(address)
            .map(|rows| peek_lines(rows.clone(), lines))
            .unwrap_or_default()
    }

    /// Síncrono, dentro do ator: a cauda é de 512 KiB e o `Stop` relê no
    /// máximo sete vezes. Se pesar, sai por `run_later`.
    fn last_marker(&self, transcript: &Path, marker: &MarkerConfig) -> Option<LastMarker> {
        last_marker_at(transcript, marker, MARKER_TAIL_BYTES)
    }
}

impl World for View<'_> {
    fn workbench(&self, name: &str) -> Option<WorkbenchConfig> {
        self.workbenches.iter().find(|b| b.name == name).cloned()
    }

    /// Na frente, a borda já diz tudo: a notificação não sai.
    fn app_active(&self) -> bool {
        self.app_active
    }

    fn notifier_authorized(&self) -> bool {
        self.authorized
    }
}

impl MaestroWiring for View<'_> {
    fn bench(&self, name: &str) -> Option<WorkbenchConfig> {
        World::workbench(self, name)
    }

    /// Como o `makeMaestro` do Swift: pedido de permissão parado é turno em
    /// curso; shell "trabalhando" é só log correndo e vai com o segundo plano.
    fn context(&self, bench: &WorkbenchConfig, caller: &str) -> MaestroContext<'_> {
        let mut context = MaestroContext::new(caller, self.profiles.clone(), self.home);
        let data = self.data.to_path_buf();
        context.catalog = Box::new(move |profile| catalog(&data, profile));
        let state = |id: &str| self.activities.get(&format!("{}/{id}", bench.name));
        let shells: HashSet<&str> = bench
            .nodes
            .iter()
            .filter(|n| n.kind == NodeKind::Shell)
            .map(|n| n.id.as_str())
            .collect();
        for node in &bench.nodes {
            let id = node.id.as_str();
            match state(id) {
                Some(Activity::Working | Activity::Asking) if shells.contains(id) => {
                    context.background.insert(id.to_owned());
                }
                Some(Activity::Working | Activity::Asking) => {
                    context.working.insert(id.to_owned());
                }
                Some(Activity::Background | Activity::Awaiting(_)) => {
                    context.background.insert(id.to_owned());
                }
                _ => {}
            }
        }
        let suggested = bench
            .project
            .as_deref()
            .and_then(|project| {
                self.workspaces
                    .iter()
                    .find(|w| w.projects.iter().any(|p| p.id == project))
            })
            .and_then(|w| w.last_configs.clone())
            .unwrap_or_default();
        context.suggested_config = Box::new(move |cli| suggested.get(cli).cloned());
        context
    }

    fn activity(&self, address: &str) -> Option<Activity> {
        self.activities.get(address).cloned()
    }

    fn profiles(&self) -> BTreeMap<String, AgentProfile> {
        self.profiles.clone()
    }

    fn catalog(&self, profile: &AgentProfile) -> Option<ModelCatalog> {
        catalog(self.data, profile)
    }

    fn home(&self) -> String {
        self.home.to_owned()
    }
}

/// O catálogo de modelos do Claude Code, do cache que a feature `agent` grava.
fn catalog(data: &Path, profile: &AgentProfile) -> Option<ModelCatalog> {
    if !claude_catalog::applies_to(profile) {
        return None;
    }
    claude_catalog::load_cache(&claude_catalog::cache_file(data)).map(|c| c.catalog)
}

impl Actor {
    pub(super) fn dispatch_route(
        &mut self,
        route: FeatureRoute,
        request: RouteRequest,
        reply: Replier,
    ) {
        use FeatureRoute::*;
        let now = SystemTime::now();
        let handled = match route {
            Targets => self.with_coordination(|c, w| dispatch::targets(c, &request, now, w)),
            Conversation => {
                self.with_coordination(|c, w| dispatch::conversation(c, &request, now, w))
            }
            PermissionAnswer => {
                self.with_coordination(|c, w| permission::answer(c, &request, now, w))
            }
            Permissions => self.with_coordination(|c, w| permission::list(c, &request, now, w)),
            PermissionOpen => self.with_coordination(|c, w| permission::open(c, &request, now, w)),
            PermissionPoll => self.with_coordination(|c, w| permission::poll(c, &request, now, w)),
            Activity => self.with_coordination(|c, w| dispatch::activity(c, &request, now, w)),
            Retry => self.with_coordination(|c, w| dispatch::retry(c, &request, now, w)),
            Message => self.with_coordination(|c, w| dispatch::message(c, &request, now, w)),
            Maestro => self.with_coordination(|c, w| maestro::maestro(c, &request, now, w, w)),
            Peers => self.with_coordination(|c, w| dispatch::peers(c, &request, now, w)),
            Dispatch => self.with_coordination(|c, w| dispatch::dispatch(c, &request, now, w)),
            MaestroGuide => (self.set_maestro(&request), Vec::new()),
            Status => return self.status(&request, reply),
            Peek => (self.peek(&request), Vec::new()),
            other => return not_ported(other, reply),
        };
        let (answer, out) = handled;
        let _ = reply.send(answer);
        self.dispatch_apply(out);
    }

    /// O laço de 250 ms. Antes de tudo, os terminais de nó que nasceram ou
    /// morreram desde o último tique entram e saem do Dispatcher.
    pub(super) fn dispatch_tick(&mut self, now: SystemTime) {
        self.dispatch_sync(now);
        let out = self.with_coordination(|c, w| ((), c.tick(now, w))).1;
        self.dispatch_apply(out);
    }

    /// Depois de a tela receber os bytes de `node`.
    ///
    /// O terminal que acabou de subir escreve (o prompt do shell, o banner da
    /// TUI) antes do tique que o registraria: sem registrar aqui, essa saída
    /// se perdia, o alvo nunca "via saída" e nunca ficava pronto para receber.
    pub(super) fn dispatch_output(&mut self, node: &NodeId, now: SystemTime) {
        let Some((address, generation)) = self
            .nodes
            .get(node)
            .and_then(|n| Some((n.address.clone()?, n.generation)))
        else {
            return;
        };
        match self.dispatch.registered.get(node) {
            Some(seen) if *seen == (address.clone(), generation) => {}
            Some((old, _)) => {
                let old = old.clone();
                self.dispatch.registered.remove(node);
                let out = self
                    .with_coordination(|c, w| ((), c.unregister(&old, now, w)))
                    .1;
                self.dispatch_apply(out);
                self.dispatch_register(node, now);
            }
            None => self.dispatch_register(node, now),
        }
        self.with_screens(Some(&address), |c, w| {
            c.output(&address, now, w);
            ((), Vec::new())
        });
    }

    /// Tira o Coordination do ator enquanto a feature roda, para o mundo
    /// poder emprestar o resto do estado.
    fn with_coordination<T>(
        &mut self,
        run: impl FnOnce(&mut Coordination, &View<'_>) -> (T, Vec<Outward>),
    ) -> (T, Vec<Outward>) {
        self.with_screens(None, run)
    }

    /// Como `with_coordination`, mas lendo só a tela de `only` quando dado:
    /// a saída do pty chega a cada pedaço de bytes, e montar a tela de todos
    /// os nós ali é trabalho à toa.
    fn with_screens<T>(
        &mut self,
        only: Option<&str>,
        run: impl FnOnce(&mut Coordination, &View<'_>) -> (T, Vec<Outward>),
    ) -> (T, Vec<Outward>) {
        let mut coordination = std::mem::take(&mut self.dispatch.coordination);
        let activities = coordination
            .dispatcher
            .addresses()
            .into_iter()
            .filter_map(|a| {
                let activity = coordination.dispatcher.target(&a)?.activity().clone();
                Some((a, activity))
            })
            .collect();
        let mut screens = HashMap::new();
        let mut running = HashSet::new();
        for node in self.nodes.values_mut() {
            let Some(address) = node.address.clone() else {
                continue;
            };
            if node.session.is_some() && node.info.alive {
                running.insert(address.clone());
            }
            if only.is_none_or(|o| o == address) {
                screens.insert(address, node.screen.rows_text());
            }
        }
        let view = View {
            screens,
            running,
            workbenches: &self.org.state.workbenches,
            workspaces: &self.org.state.workspaces,
            profiles: &self.org.profiles,
            authorized: self.drivers.notifier.authorized(),
            app_active: self.app_active,
            focused: self.focused.as_deref(),
            home: &self.org.home,
            data: self.config.paths.home(),
            activities,
        };
        let result = run(&mut coordination, &view);
        self.dispatch.coordination = coordination;
        result
    }

    /// Registra os terminais de nó novos e tira os que saíram.
    fn dispatch_sync(&mut self, now: SystemTime) {
        let live: HashMap<NodeId, (String, u64)> = self
            .nodes
            .iter()
            .filter_map(|(id, node)| Some((id.clone(), (node.address.clone()?, node.generation))))
            .collect();
        // Saiu, ou subiu de novo (outra geração): o alvo velho sai. O Swift
        // cria um `Target` novo a cada `makeNode`.
        let gone: Vec<(NodeId, String)> = self
            .dispatch
            .registered
            .iter()
            .filter(|(id, seen)| live.get(*id) != Some(*seen))
            .map(|(id, (address, _))| (id.clone(), address.clone()))
            .collect();
        for (id, address) in gone {
            self.dispatch.registered.remove(&id);
            let out = self
                .with_coordination(|c, w| ((), c.unregister(&address, now, w)))
                .1;
            self.dispatch_apply(out);
        }
        let fresh: Vec<NodeId> = live
            .into_keys()
            .filter(|id| !self.dispatch.registered.contains_key(id))
            .collect();
        for id in fresh {
            self.dispatch_register(&id, now);
        }
    }

    /// Põe no Dispatcher o terminal de nó `id`. Fala por gancho quem subiu com
    /// os argumentos de relato (`LaunchPlan.hooked`, `main.swift:2763`).
    fn dispatch_register(&mut self, id: &NodeId, now: SystemTime) {
        let Some((address, generation, hooked)) = self
            .nodes
            .get(id)
            .and_then(|n| Some((n.address.clone()?, n.generation, n.hooked)))
        else {
            return;
        };
        let target = self
            .agent_profile(&address)
            .as_ref()
            .map(TargetProfile::from_agent);
        self.dispatch
            .coordination
            .register(address.clone(), target, hooked, now);
        self.dispatch
            .registered
            .insert(id.clone(), (address, generation));
    }

    /// O papel de quem não tem flag de system prompt vai como primeira
    /// mensagem (`TerminalNode.swift:326`): o alvo entra agora, sem esperar o
    /// tique, e o texto espera na fila até a TUI ficar pronta.
    pub(super) fn dispatch_enqueue_role(&mut self, address: &str, prompt: String) {
        let now = SystemTime::now();
        let pending = self.dispatch.registered.values().any(|(a, _)| a == address);
        if !pending {
            let id = self
                .nodes
                .iter()
                .find(|(_, n)| n.address.as_deref() == Some(address))
                .map(|(id, _)| id.clone());
            if let Some(id) = id {
                self.dispatch_register(&id, now);
            }
        }
        let size = prompt.chars().count();
        if self
            .dispatch
            .coordination
            .dispatcher
            .enqueue(address, prompt)
        {
            log!("terminal[{address}]: papel enfileirado ({size} caracteres)");
        }
    }

    /// Você digitou no terminal `node` — o `input` e o `paste` do `/ui`, nunca
    /// a injeção. Qual tecla chega ao pty (o ⌘ dos atalhos não chega) a UI
    /// decide (`reachesPty`); aqui a tecla que chegou fecha o pedido de
    /// permissão, cancela a nova tentativa e zera a cadeia (`userTyped`).
    pub(super) fn dispatch_user_typed(&mut self, node: &NodeId) {
        let Some((address, _)) = self.dispatch.registered.get(node).cloned() else {
            return;
        };
        let now = SystemTime::now();
        let out = self
            .with_coordination(|c, w| ((), c.user_typed(&address, now, w)))
            .1;
        self.dispatch_apply(out);
    }

    /// A bancada `name` ficou na frente (ou saiu dela): o "terminou" dos
    /// terminais dela já foi visto (`main.swift:714`).
    pub(super) fn dispatch_workbench_opened(&mut self, name: &str) {
        self.dispatch.coordination.workbench_opened(name);
    }

    /// O perfil do agente do nó, pelo `agent` do `NodeConfig`. Shell é `None`.
    fn agent_profile(&mut self, address: &str) -> Option<AgentProfile> {
        let (bench, node) = address.split_once('/')?;
        let config = self
            .org
            .state
            .workbenches
            .iter()
            .find(|b| b.name == bench)?
            .nodes
            .iter()
            .find(|n| n.id == node)?
            .clone();
        if config.kind != NodeKind::Agent {
            return None;
        }
        let key = config.agent?;
        self.org.profiles.get(&key).cloned()
    }

    /// O terminal de nó com este endereço.
    fn node_at(&self, address: &str) -> Option<(&NodeId, &Node)> {
        self.nodes
            .iter()
            .find(|(_, n)| n.address.as_deref() == Some(address))
    }

    /// Executa o que as features devolveram.
    fn dispatch_apply(&mut self, out: Vec<Outward>) {
        for effect in out {
            match effect {
                Outward::Write { address, bytes } => {
                    let Some(id) = self.node_at(&address).map(|(id, _)| id.clone()) else {
                        continue;
                    };
                    if let Err(error) = self.write(&id, &bytes) {
                        log!("dispatch[{address}]: escrita falhou — {error}");
                    }
                }
                Outward::Conversation {
                    address,
                    id,
                    transcript,
                } => self.record_conversation(&address, &id, transcript.as_deref()),
                Outward::Maestro(effect) => self.maestro_apply(effect),
                Outward::Notify(n) => self.drivers.notifier.post(Notice {
                    identifier: n.identifier,
                    title: n.title,
                    body: n.body,
                    workbench: n.workbench,
                    node: n.node,
                }),
                Outward::Sound { name, volume } => {
                    if let Err(error) = self.drivers.notifier.play_sound(&name, volume) {
                        log!("atenção: {error} — veja os nomes em /System/Library/Sounds");
                        // Nome errado não cala o certo pela janela de 1,5s.
                        if matches!(error, SoundError::Unknown(_)) {
                            self.dispatch.coordination.sound_failed();
                        }
                    }
                }
                Outward::Withdraw { identifier } => self.drivers.notifier.withdraw(&identifier),
                // Depois das releituras do `Stop`: a resposta inteira já está no
                // transcript quando o histórico a lê (`AppControl.turnEnded`).
                Outward::TurnEnded { address, .. } => self.chat_turn_ended(&address),
            }
        }
    }

    /// `AppControl.recordConversation`: o transcript é conferido mesmo com a
    /// conversa igual — depois de um rebuild o id volta do arquivo e o
    /// caminho não.
    fn record_conversation(&mut self, address: &str, id: &str, transcript: Option<&str>) {
        let Some((bench, node)) = address.split_once('/') else {
            return;
        };
        let Some(config) = self
            .org
            .state
            .workbenches
            .iter_mut()
            .find(|b| b.name == bench)
            .and_then(|b| b.nodes.iter_mut().find(|n| n.id == node))
        else {
            return;
        };
        let mut changed = false;
        if let Some(transcript) = transcript.filter(|t| !t.is_empty())
            && config.transcript.as_deref() != Some(transcript)
        {
            config.transcript = Some(transcript.to_owned());
            changed = true;
        }
        if config.conversation_id.as_deref() != Some(id) {
            let before = config
                .conversation_id
                .clone()
                .unwrap_or_else(|| "nenhuma".to_owned());
            config.conversation_id = Some(id.to_owned());
            config.conversation_started = Some(true);
            changed = true;
            log!("conversa[{address}]: {before} → {id}");
        }
        if changed {
            self.persist();
        }
    }

    /// O que o maestro mandou mudar. Montar, reerguer e tirar terminal da tela
    /// é da fiação dos nós (core); aqui fica a bancada gravada e a trilha.
    fn maestro_apply(&mut self, effect: MaestroEffect) {
        match effect {
            MaestroEffect::Commit(next) => {
                if let Some(slot) = self
                    .org
                    .state
                    .workbenches
                    .iter_mut()
                    .find(|b| b.id == next.id)
                {
                    *slot = next;
                }
            }
            MaestroEffect::Persist => self.persist(),
            MaestroEffect::Trace { address, text } => self.maestro_trace(address, text),
            // A bancada gravada já é a nova (`Commit` vem antes): subir é
            // abrir os terminais que faltam; reiniciar é tirar e subir de novo.
            MaestroEffect::Spawn { bench, .. } => self.maestro_open(&bench),
            MaestroEffect::Restart { bench, node } => {
                self.maestro_close(&bench, &node);
                self.maestro_open(&bench);
            }
            MaestroEffect::Dispose { bench, node } => self.maestro_close(&bench, &node),
            MaestroEffect::RedrawEdges { .. } | MaestroEffect::Arrange { .. } => self.publish_org(),
            MaestroEffect::PermissionAnswered { .. } => {}
        }
    }

    /// A linha do maestro na trilha da bancada, carimbada como ele, como o
    /// `wiring.trace` do Swift. Grava em disco: fora do ator.
    fn maestro_trace(&mut self, address: String, text: String) {
        let Some((bench, node)) = address.split_once('/') else {
            return;
        };
        let Some(workbench) = self.org.state.workbenches.iter().find(|b| b.name == bench) else {
            return;
        };
        let Some(config) = workbench.nodes.iter().find(|n| n.id == node).cloned() else {
            return;
        };
        let profile = config
            .agent
            .as_ref()
            .and_then(|k| self.org.profiles.get(k))
            .cloned();
        let workbench_id = workbench.id.clone();
        let dir = self.config.paths.workbenches_dir();
        let home = std::path::PathBuf::from(&self.org.home);
        tokio::task::spawn_blocking(move || {
            let identity = NodeIdentity {
                workbench_id,
                cli: profile
                    .as_ref()
                    .map(|p| p.display_name.clone())
                    .or_else(|| config.agent.clone()),
                model: literal_model(&config, profile.as_ref(), &home),
                conversation: config.conversation_id.clone(),
            };
            let routes = TraceRoutes {
                log: TraceLog::new(dir, Arc::new(local_offset_secs)),
                identities: Box::new(One(address.clone(), identity)),
            };
            if routes.record(&address, &text, SystemTime::now()).is_none() {
                log!("trilha[{address}]: não gravou — {text}");
            }
        });
    }

    fn bench_id(&self, name: &str) -> Option<String> {
        self.org
            .state
            .workbenches
            .iter()
            .find(|b| b.name == name)
            .map(|b| b.id.clone())
    }

    fn maestro_open(&mut self, bench: &str) {
        if let Some(id) = self.bench_id(bench) {
            self.open_terminals(&id);
        }
    }

    fn maestro_close(&mut self, bench: &str, node: &str) {
        let Some(id) = self.bench_id(bench).and_then(|b| screen_id(&b, node)) else {
            return;
        };
        if self.nodes.contains_key(&id)
            && let Err(error) = self.close(&id)
        {
            log!("maestro[{bench}/{node}]: não fechou — {error}");
        }
    }

    /// `GET /maestro?target=<bancada/nó>&on=1|0` — liga o maestro de fora, como
    /// o checkbox do formulário. De dentro de um terminal seria um agente se
    /// promovendo (ADR-066).
    fn set_maestro(&mut self, request: &RouteRequest) -> RouteReply {
        if request.origin.is_some() {
            return RouteReply::err(
                400,
                "só o usuário liga o maestro — de dentro de um terminal, não",
            );
        }
        let target = request.param("target").unwrap_or_default().to_owned();
        let on = request.param("on") != Some("0");
        let refused = (|| {
            // O split do Swift descarta a peça vazia: "deck/" não tem nó.
            let (bench, node) = target
                .split_once('/')
                .filter(|(b, n)| !b.is_empty() && !n.is_empty())
                .ok_or("bancada desconhecida")?;
            let config = self
                .org
                .state
                .workbenches
                .iter_mut()
                .find(|b| b.name == bench)
                .ok_or("bancada desconhecida")?;
            let name = config.name.clone();
            let node = config
                .nodes
                .iter_mut()
                .find(|n| n.id == node)
                .ok_or("nó desconhecido")?;
            if node.kind != NodeKind::Agent {
                return Err("não é um agente");
            }
            if node.is_maestro() != on {
                node.maestro = on.then_some(true);
                let id = node.id.clone();
                log!(
                    "bancada {name}: nó \"{id}\" {}",
                    if on {
                        "virou maestro"
                    } else {
                        "deixou de ser maestro"
                    }
                );
                return Ok(Some((name, id)));
            }
            Ok(None)
        })();
        match refused {
            Ok(changed) => {
                // Como o detach/makeNode do Swift: o maestro sobe de novo com a
                // guia e as ligações implícitas no system prompt.
                if let Some((bench, node)) = changed {
                    self.persist();
                    self.maestro_close(&bench, &node);
                    self.maestro_open(&bench);
                    self.publish_org();
                }
                RouteReply::ok(json!({"ok": true, "target": target, "maestro": on}))
            }
            Err("não é um agente") => RouteReply::err(400, format!("'{target}' não é um agente")),
            Err(kind) => RouteReply::err(400, format!("{kind} '{target}'")),
        }
    }

    /// O que você mandou pelo chat (`chat.send` do Swift): `from: nil` de
    /// propósito — quem manda é VOCÊ, e as guardas de cadeia só valem entre
    /// agentes. `Err` traz o texto do erro para o chat mostrar.
    pub(super) fn dispatch_chat_send(
        &mut self,
        workbench_id: &str,
        node: &str,
        text: &str,
    ) -> Result<(), String> {
        let Some(name) = self
            .org
            .state
            .workbenches
            .iter()
            .find(|b| b.id == workbench_id)
            .map(|b| b.name.clone())
        else {
            return Err("bancada sumiu".to_owned());
        };
        let mut request = DispatchRequest::new(format!("{name}/{node}"));
        request.text = Some(text.to_owned());
        self.with_coordination(|c, w| {
            let sent = c.dispatcher.dispatch(&request, None, &Links(w));
            (sent.map(|_| ()).map_err(|e| e.to_string()), Vec::new())
        })
        .0
    }

    /// O botão da bandeja do chat (`permission_answer` do `/ui`): o mesmo
    /// caminho do `POST /permission/answer` — `answer`, `choice` da pergunta
    /// única ou `answers` do AskUserQuestion com várias. `Err` traz o texto do
    /// erro da rota.
    pub(super) fn dispatch_permission_answer(
        &mut self,
        answer: &crate::protocol::chat::PermissionAnswer,
    ) -> Result<(), String> {
        use crate::protocol::chat::PermissionChoice;
        let mut query = HashMap::from([("id".to_owned(), answer.request.clone())]);
        if let Some(choice) = &answer.answer {
            let raw = match choice {
                PermissionChoice::Allow => "allow",
                PermissionChoice::Always => "always",
                PermissionChoice::Deny => "deny",
            };
            query.insert("answer".to_owned(), raw.to_owned());
        }
        if let Some(choice) = &answer.choice {
            query.insert("choice".to_owned(), choice.clone());
        }
        let body = answer
            .answers
            .as_ref()
            .map(|answers| json!({ "answers": answers }).to_string().into_bytes())
            .unwrap_or_default();
        let request = RouteRequest {
            method: "POST".to_owned(),
            target: "/permission/answer".to_owned(),
            path: "/permission/answer".to_owned(),
            query,
            body,
            origin: None,
        };
        let now = SystemTime::now();
        let (reply, out) = self.with_coordination(|c, w| permission::answer(c, &request, now, w));
        self.dispatch_apply(out);
        if reply.status == 200 {
            Ok(())
        } else {
            Err(reply.json["error"]
                .as_str()
                .unwrap_or("resposta recusada")
                .to_owned())
        }
    }

    /// O comando `retry` do `/ui`: a mesma rota `/retry`, para o card dizer
    /// "tentar agora" ou "cancelar tentativa" sem HTTP.
    pub(super) fn retry_node(&mut self, address: &str, now_flag: bool) -> Result<(), String> {
        let mut query = HashMap::from([("target".to_owned(), address.to_owned())]);
        if now_flag {
            query.insert("now".to_owned(), "1".to_owned());
        }
        let request = RouteRequest {
            method: "POST".to_owned(),
            target: "/retry".to_owned(),
            path: "/retry".to_owned(),
            query,
            body: Vec::new(),
            origin: None,
        };
        let now = SystemTime::now();
        let (reply, out) = self.with_coordination(|c, w| dispatch::retry(c, &request, now, w));
        self.dispatch_apply(out);
        if reply.status == 200 {
            Ok(())
        } else {
            Err(reply.json["error"]
                .as_str()
                .unwrap_or("tentativa recusada")
                .to_owned())
        }
    }

    /// `GET /peek?target=<bancada/id>[&lines=n]` — `ControlSocket.swift:744`:
    /// o que o terminal realmente exibe. De dentro de um terminal, só de
    /// vizinho; o id de terminal (`t1`, `1a2b3c4d.b`) vale como reserva para
    /// quem chama de fora.
    fn peek(&mut self, request: &RouteRequest) -> RouteReply {
        let target = request
            .param("target")
            .or_else(|| request.param("id"))
            .unwrap_or_default()
            .to_owned();
        let count = request
            .param("lines")
            .and_then(|n| n.parse::<i64>().ok())
            .unwrap_or(20)
            .clamp(1, 200) as usize;
        let origin = request
            .origin
            .clone()
            .filter(|o| self.dispatch.coordination.dispatcher.target(o).is_some());
        let (resolved, allowed) = self
            .with_coordination(|c, w| {
                let peers: Vec<String> = origin
                    .as_deref()
                    .map(|o| c.dispatcher.peers(o, &Links(w)))
                    .unwrap_or_default()
                    .into_iter()
                    .map(|p| p.address)
                    .collect();
                let resolved = origin
                    .as_deref()
                    .and_then(|o| c.dispatcher.resolve(&target, o))
                    .unwrap_or_else(|| target.clone());
                let allowed = Dispatcher::may_peek(&resolved, origin.as_deref(), &peers);
                ((resolved, allowed), Vec::new())
            })
            .0;
        if !allowed {
            return RouteReply::err(
                403,
                format!("não existe ligação de você para '{target}' — desenhe a aresta no canvas"),
            );
        }
        let node = self
            .nodes
            .values_mut()
            .find(|n| n.address.as_deref() == Some(resolved.as_str()));
        let node = match node {
            Some(node) => Some(node),
            None => NodeId::new(resolved.as_str())
                .ok()
                .and_then(|id| self.nodes.get_mut(&id)),
        };
        let Some(node) = node else {
            return RouteReply::err(404, format!("alvo desconhecido '{target}'"));
        };
        let lines = peek_lines(node.screen.rows_text(), count);
        RouteReply::ok(json!({"target": target, "lines": lines}))
    }

    /// `GET /status` — este terminal, do ponto de vista do app. Quem você é
    /// vem antes de como você está.
    ///
    /// O modelo literal lê a cauda do transcript (até 256 KiB): o payload sai
    /// montado do ator, a leitura vai a um `spawn_blocking` e a resposta segue
    /// pelo `reply` quando ela voltar.
    fn status(&mut self, request: &RouteRequest, reply: Replier) {
        let Some(origin) = request
            .origin
            .clone()
            .filter(|o| self.dispatch.coordination.dispatcher.target(o).is_some())
        else {
            let _ = reply.send(RouteReply::ok(
                json!({"detail": "esta conexão não veio de um terminal"}),
            ));
            return;
        };
        let (pending, peers) = self
            .with_coordination(|c, w| (c.status(&origin, w), Vec::new()))
            .0
            .unwrap_or((0, 0));
        let mut payload = json!({"address": origin, "pending": pending, "peers": peers});
        let mut identity = None;
        let (bench, node) = origin.split_once('/').unwrap_or((origin.as_str(), ""));
        if let Some(map) = payload.as_object_mut() {
            map.insert("workbench".into(), json!(bench));
            let config = self
                .org
                .state
                .workbenches
                .iter()
                .find(|b| b.name == bench)
                .and_then(|b| b.nodes.iter().find(|n| n.id == node))
                .cloned();
            if let Some(config) = config {
                if let Some(role) = config.effective_prompt() {
                    map.insert("role".into(), json!(role));
                }
                if config.is_maestro() {
                    map.insert("maestro".into(), json!(true));
                }
                // `nodeIdentity` do Swift: o CLI pelo nome do perfil (ou a
                // chave) e o modelo literal; o que não se sabe some da resposta.
                let profile = config
                    .agent
                    .as_ref()
                    .and_then(|k| self.org.profiles.get(k))
                    .cloned();
                let cli = profile
                    .as_ref()
                    .map(|p| p.display_name.clone())
                    .or_else(|| config.agent.clone());
                if let Some(cli) = cli {
                    map.insert("cli".into(), json!(cli));
                }
                identity = Some((config, profile));
            }
        }
        let Some((config, profile)) = identity else {
            let _ = reply.send(RouteReply::ok(payload));
            return;
        };
        let home = std::path::PathBuf::from(&self.org.home);
        tokio::spawn(async move {
            let model = tokio::task::spawn_blocking(move || {
                literal_model(&config, profile.as_ref(), &home)
            })
            .await
            .ok()
            .flatten();
            if let (Some(model), Some(map)) = (model, payload.as_object_mut()) {
                map.insert("model".into(), json!(model));
            }
            let _ = reply.send(RouteReply::ok(payload));
        });
    }
}

/// A identidade de um nó só, já montada.
struct One(String, NodeIdentity);

impl NodeIdentities for One {
    fn identity(&self, address: &str) -> Option<NodeIdentity> {
        (address == self.0).then(|| self.1.clone())
    }
}

/// `literalModel` do `main.swift`: o nome que o transcript diz; sem
/// transcript, o do `settings.json` do CLI, mas só se o nó está no padrão —
/// com modelo escolhido ele diz o que o CLI usaria sem a flag. A cópia única:
/// o `/status` daqui e a trilha (`trace_commands`) usam esta. Lê o fim do
/// transcript: bloqueia.
pub(super) fn literal_model(
    node: &NodeConfig,
    profile: Option<&AgentProfile>,
    user_home: &Path,
) -> Option<String> {
    if let Some(path) = node.transcript.as_deref().filter(|p| !p.is_empty())
        && let Some(model) = last_model_at(Path::new(path), None, MODEL_TAIL_BYTES)
    {
        return Some(model);
    }
    if node.model.is_some() {
        return None;
    }
    profile?.default_model_name(node.config.as_deref(), user_home)
}

#[cfg(test)]
mod tests {
    use std::time::SystemTime;

    use super::super::processes_commands::support::{Rig, request};
    use crate::features::agent::model::AgentProfile;
    use crate::features::edge::model::EdgeConfig;
    use crate::features::node::model::{NodeConfig, NodeKind};
    use crate::features::workbench::model::WorkbenchConfig;
    use crate::protocol::routes::FeatureRoute;
    use crate::runtime::org::screen_id;

    /// A bancada "deck" com os agentes `a` e `b` (perfil "fake") e o shell
    /// `sh`, de pé e registrados no Dispatcher.
    fn deck() -> (Rig, String) {
        let mut rig = Rig::new();
        let agent = |id: &str| {
            let mut n = NodeConfig::new(NodeKind::Agent, id);
            n.agent = Some("fake".into());
            n
        };
        let mut b = agent("b");
        b.model = Some("opus".into());
        let bench = WorkbenchConfig::new(
            "deck",
            rig.dir.path().to_string_lossy(),
            vec![agent("a"), b, NodeConfig::new(NodeKind::Shell, "sh")],
        );
        let mut bench = bench;
        bench.edges = Some(vec![
            EdgeConfig::with_default_limit("a", "b"),
            EdgeConfig::with_default_limit("b", "a"),
        ]);
        let id = bench.id.clone();
        rig.actor.org.state.workbenches.push(bench);
        rig.actor
            .org
            .profiles
            .insert("fake".into(), AgentProfile::new("Fake", &["/bin/zsh"]));
        rig.actor.open_terminals(&id);
        rig.actor.dispatch_tick(SystemTime::now());
        (rig, id)
    }

    fn generation(rig: &Rig, bench: &str, node: &str) -> u64 {
        let id = screen_id(bench, node).unwrap();
        rig.actor.nodes[&id].generation
    }

    #[tokio::test]
    async fn os_terminais_de_no_entram_no_dispatcher() {
        let (mut rig, _) = deck();
        let reply = rig
            .call(FeatureRoute::Targets, request("GET", "/targets", None))
            .await;
        assert_eq!(
            reply.json["targets"],
            serde_json::json!(["deck/a", "deck/b", "deck/sh"])
        );
    }

    /// `main.swift:3127`: virar maestro troca a flag, grava e reergue o nó —
    /// o system prompt passa a levar a guia e as ligações implícitas.
    #[tokio::test]
    async fn ligar_o_maestro_reergue_o_no() {
        let (mut rig, bench) = deck();
        let before = generation(&rig, &bench, "a");
        let reply = rig
            .call(
                FeatureRoute::MaestroGuide,
                request("GET", "/maestro?target=deck/a&on=1", None),
            )
            .await;
        assert_eq!(reply.status, 200, "{}", reply.json);
        assert_eq!(
            reply.json,
            serde_json::json!({"ok": true, "target": "deck/a", "maestro": true})
        );
        assert!(rig.actor.org.state.workbenches[0].nodes[0].is_maestro());
        assert!(generation(&rig, &bench, "a") > before, "o nó subiu de novo");

        // Já é maestro: nada muda, nada reergue.
        let again = generation(&rig, &bench, "a");
        rig.call(
            FeatureRoute::MaestroGuide,
            request("GET", "/maestro?target=deck/a&on=1", None),
        )
        .await;
        assert_eq!(generation(&rig, &bench, "a"), again);
    }

    #[tokio::test]
    async fn ligar_o_maestro_recusa_como_o_swift() {
        let (mut rig, _) = deck();
        let mut call = async |target: &str, origin: Option<&str>| {
            let reply = rig
                .call(
                    FeatureRoute::MaestroGuide,
                    request("GET", &format!("/maestro?target={target}&on=1"), origin),
                )
                .await;
            (
                reply.status,
                reply.json["error"].as_str().unwrap_or("").to_owned(),
            )
        };
        assert_eq!(
            call("deck/a", Some("deck/b")).await,
            (
                400,
                "só o usuário liga o maestro — de dentro de um terminal, não".into()
            )
        );
        assert_eq!(
            call("deck/", None).await,
            (400, "bancada desconhecida 'deck/'".into())
        );
        assert_eq!(
            call("outra/a", None).await,
            (400, "bancada desconhecida 'outra/a'".into())
        );
        assert_eq!(
            call("deck/zz", None).await,
            (400, "nó desconhecido 'deck/zz'".into())
        );
        assert_eq!(
            call("deck/sh", None).await,
            (400, "'deck/sh' não é um agente".into())
        );
    }

    /// `nodeIdentity`: com modelo escolhido e sem transcript, o modelo
    /// literal não se sabe e a chave some; o CLI é o nome do perfil.
    #[tokio::test]
    async fn status_traz_quem_voce_e_sem_inventar_modelo() {
        let (mut rig, _) = deck();
        let reply = rig
            .call(
                FeatureRoute::Status,
                request("GET", "/status", Some("deck/b")),
            )
            .await;
        assert_eq!(reply.json["address"], "deck/b");
        assert_eq!(reply.json["workbench"], "deck");
        assert_eq!(reply.json["cli"], "Fake");
        assert_eq!(reply.json["pending"], 0);
        assert!(reply.json.get("model").is_none(), "{}", reply.json);
        let shell = rig
            .call(
                FeatureRoute::Status,
                request("GET", "/status", Some("deck/sh")),
            )
            .await;
        assert!(shell.json.get("cli").is_none(), "{}", shell.json);
        let you = rig
            .call(FeatureRoute::Status, request("GET", "/status", None))
            .await;
        assert_eq!(you.json["detail"], "esta conexão não veio de um terminal");
    }

    /// A linha do maestro vai para a trilha da bancada, carimbada como ele.
    #[tokio::test]
    async fn trilha_do_maestro_grava_no_arquivo_da_bancada() {
        let (mut rig, bench) = deck();
        rig.actor
            .maestro_trace("deck/a".into(), "maestro aplicou: +dev".into());
        rig.settle().await;
        let file = rig.data.join("workbenches").join(&bench).join("trace.md");
        // A gravação sai num `spawn_blocking`: com a suíte inteira em
        // paralelo ela pode demorar, e o arquivo nasce com o cabeçalho antes
        // da entrada. Espera a linha, não o arquivo.
        let mut text = String::new();
        for _ in 0..250 {
            text = std::fs::read_to_string(&file).unwrap_or_default();
            if text.contains("maestro aplicou: +dev") {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
        }
        assert!(text.contains("maestro aplicou: +dev"), "{file:?}: {text}");
        assert!(
            text.contains("· a\nFake"),
            "carimbado como o maestro: {text}"
        );
    }

    /// Direto ao `dispatch_route`: a tabela do core ainda manda o `/peek` ao
    /// `org` até trocar a rota.
    async fn peek(rig: &mut Rig, query: &str, origin: Option<&str>) -> (u16, serde_json::Value) {
        let (tx, mut rx) = tokio::sync::oneshot::channel();
        let req = request("GET", &format!("/peek?{query}"), origin);
        rig.actor.dispatch_route(FeatureRoute::Peek, req, tx);
        let reply = rig.pump(&mut rx).await;
        (reply.status, reply.json)
    }

    /// `ControlSocket.swift:744`: de fora vale qualquer alvo, pelo endereço
    /// ou pelo id do terminal; de dentro, só vizinho — e o id curto resolve
    /// na mesma bancada.
    #[tokio::test]
    async fn peek_pelo_endereco_e_so_de_vizinho() {
        let (mut rig, bench) = deck();
        let (status, body) = peek(&mut rig, "target=deck/sh&lines=3", None).await;
        assert_eq!(status, 200, "{body}");
        assert_eq!(body["target"], "deck/sh");
        assert!(body["lines"].is_array());
        let (status, body) = peek(&mut rig, &format!("id={bench}.b"), None).await;
        assert_eq!(
            (status, body["target"].clone()),
            (200, serde_json::json!(format!("{bench}.b")))
        );

        let (status, _) = peek(&mut rig, "target=b", Some("deck/a")).await;
        assert_eq!(status, 200, "vizinho pelo id curto");
        let (status, _) = peek(&mut rig, "target=deck/a", Some("deck/a")).await;
        assert_eq!(status, 200, "a si mesmo");
        let (status, body) = peek(&mut rig, "target=sh", Some("deck/a")).await;
        assert_eq!(status, 403);
        assert_eq!(
            body["error"],
            "não existe ligação de você para 'sh' — desenhe a aresta no canvas"
        );
        let (status, _) = peek(&mut rig, &format!("id={bench}.b"), Some("deck/a")).await;
        assert_eq!(status, 403, "de dentro, o id de terminal não fura a aresta");
        let (status, body) = peek(&mut rig, "target=deck/zz", None).await;
        assert_eq!(
            (status, body["error"].clone()),
            (404, serde_json::json!("alvo desconhecido 'deck/zz'"))
        );
    }

    /// O papel de quem não tem flag de system prompt entra na fila já, sem
    /// esperar o tique.
    #[tokio::test]
    async fn papel_enfileirado_registra_o_alvo_na_hora() {
        let (mut rig, bench) = deck();
        rig.actor.dispatch.registered.clear();
        rig.actor.dispatch.coordination = Default::default();
        rig.actor
            .dispatch_enqueue_role("deck/a", "Você revisa.".into());
        let target = rig.actor.dispatch.coordination.dispatcher.target("deck/a");
        assert_eq!(target.map(|t| t.pending()), Some(1));
        assert!(
            rig.actor
                .dispatch
                .registered
                .contains_key(&screen_id(&bench, "a").unwrap())
        );
        let _ = &mut rig;
    }

    /// Reerguido (outra geração), o nó volta ao Dispatcher como alvo novo.
    #[tokio::test]
    async fn no_reerguido_entra_de_novo() {
        let (mut rig, bench) = deck();
        rig.actor
            .dispatch
            .coordination
            .dispatcher
            .enqueue("deck/a", "texto".into());
        rig.actor.maestro_close("deck", "a");
        rig.actor.maestro_open("deck");
        rig.actor.dispatch_tick(SystemTime::now());
        let target = rig.actor.dispatch.coordination.dispatcher.target("deck/a");
        assert_eq!(
            target.map(|t| t.pending()),
            Some(0),
            "o alvo novo nasce sem fila"
        );
        let id = screen_id(&bench, "a").unwrap();
        assert_eq!(
            rig.actor.dispatch.registered[&id].1,
            rig.actor.nodes[&id].generation
        );
    }

    /// `main.swift:714`: abrir a bancada dá por visto o "terminou" dela.
    #[tokio::test]
    async fn abrir_a_bancada_apaga_o_verde() {
        use crate::features::activity::model::Activity;
        let (mut rig, _) = deck();
        for query in ["event=prompt", "event=stop&last=[[ED:ok]]"] {
            rig.call(
                FeatureRoute::Activity,
                request("POST", &format!("/activity?{query}"), Some("deck/b")),
            )
            .await;
        }
        let activity = |rig: &Rig| {
            rig.actor
                .dispatch
                .coordination
                .dispatcher
                .target("deck/b")
                .map(|t| t.activity().clone())
        };
        assert_eq!(activity(&rig), Some(Activity::Waiting));
        rig.actor.dispatch_workbench_opened("deck");
        assert_eq!(activity(&rig), Some(Activity::Ready));
    }

    /// O chat lê do dispatch a atividade, o transcript do turno e a bandeja; e
    /// o que você manda pelo chat entra sem guarda de cadeia.
    #[tokio::test]
    async fn o_chat_le_e_entrega_pelo_dispatch() {
        use crate::features::activity::model::Activity;
        let (mut rig, bench) = deck();
        let now = SystemTime::now();
        assert_eq!(
            rig.actor.dispatch.activity("deck/a"),
            Some(Activity::Starting)
        );
        assert_eq!(rig.actor.dispatch.activity("deck/zz"), None);

        rig.actor
            .dispatch_chat_send(&bench, "a", "oi do chat")
            .unwrap();
        let target = rig.actor.dispatch.coordination.dispatcher.target("deck/a");
        assert_eq!(target.map(|t| t.pending()), Some(1));
        assert_eq!(
            rig.actor.dispatch_chat_send("nada", "a", "x"),
            Err("bancada sumiu".to_owned())
        );
        assert!(
            rig.actor
                .dispatch_chat_send(&bench, "zz", "x")
                .unwrap_err()
                .starts_with("alvo desconhecido 'deck/zz'")
        );

        let workbench = rig.actor.org.state.workbenches[0].clone();
        assert!(
            rig.actor.dispatch.source(&workbench, "a").is_none(),
            "sem transcript"
        );
        rig.actor
            .record_conversation("deck/a", "conv-1", Some("/tmp/t.jsonl"));
        let workbench = rig.actor.org.state.workbenches[0].clone();
        let source = rig.actor.dispatch.source(&workbench, "a").unwrap();
        assert_eq!(source.path, std::path::PathBuf::from("/tmp/t.jsonl"));

        assert!(rig.actor.dispatch.permissions(&workbench, now).is_empty());
        for (address, command) in [("deck/b", "ls"), ("deck/a", "pwd")] {
            rig.actor
                .dispatch
                .coordination
                .desk
                .open_ask(
                    address,
                    &serde_json::json!({"tool_name": "Bash", "tool_input": {"command": command}}),
                    now,
                )
                .unwrap();
        }
        // Dois agentes pedindo ao mesmo tempo: os dois vão à bandeja.
        let tray = rig.actor.dispatch.permissions(&workbench, now);
        let shown: Vec<_> = tray
            .iter()
            .map(|t| (t["address"].clone(), t["summary"].clone()))
            .collect();
        assert_eq!(
            shown,
            [
                (serde_json::json!("deck/b"), serde_json::json!("ls")),
                (serde_json::json!("deck/a"), serde_json::json!("pwd")),
            ]
        );
    }

    /// A saída que chega antes do tique registra o alvo na hora: o shell que
    /// só escreveu o prompt ao subir fica pronto e recebe em ~1 s, como no
    /// Swift (`idleWindow` 1,0 s e aquecimento 0 sem perfil).
    #[tokio::test]
    async fn saida_antes_do_tique_registra_e_o_shell_quieto_recebe() {
        let (mut rig, bench) = deck();
        rig.actor.dispatch.registered.clear();
        rig.actor.dispatch.coordination = Default::default();
        let sh = screen_id(&bench, "sh").unwrap();
        let start = SystemTime::now();
        rig.actor.dispatch_output(&sh, start);
        assert!(rig.actor.dispatch.registered.contains_key(&sh));
        rig.actor
            .dispatch
            .coordination
            .dispatcher
            .enqueue("deck/sh", "echo oi".into());
        let later = start + std::time::Duration::from_millis(1100);
        rig.actor.dispatch_tick(later);
        let target = rig.actor.dispatch.coordination.dispatcher.target("deck/sh");
        assert_eq!(
            target.map(|t| t.pending()),
            Some(0),
            "entregue ao shell quieto"
        );
    }

    /// A tecla sua fecha o pedido de permissão em aberto e zera a cadeia: o
    /// que o terminal fizer depois nasce de você (`userTyped` do Swift).
    #[tokio::test]
    async fn digitar_no_terminal_fecha_a_permissao_e_zera_a_cadeia() {
        let (mut rig, bench) = deck();
        let now = SystemTime::now();
        rig.actor
            .dispatch
            .coordination
            .desk
            .open_ask("deck/a", &serde_json::json!({"tool_name": "Bash"}), now)
            .unwrap();
        rig.actor
            .dispatch_user_typed(&screen_id(&bench, "a").unwrap());
        assert!(rig.actor.dispatch.coordination.desk.open(now).is_empty());
    }

    async fn hook(rig: &mut Rig, address: &str, query: &str) {
        rig.call(
            FeatureRoute::Activity,
            request("POST", &format!("/activity?{query}"), Some(address)),
        )
        .await;
    }

    fn header(rig: &Rig, address: &str) -> (Option<String>, Option<String>, Option<String>, bool) {
        let activity = rig
            .actor
            .dispatch
            .activity(address)
            .expect("alvo registrado");
        let view = crate::runtime::org::activity_view(&activity, 0, 0);
        (view.label, view.glyph, view.tone, view.needs_attention)
    }

    /// `ActivityTests.testBackgroundIsAnHourglassWithoutAlarm`: o `[[ED:wait]]`
    /// com trabalho de fundo vira ampulheta, sem cor de parada e sem alarme.
    #[tokio::test]
    async fn segundo_plano_e_ampulheta_sem_alarme() {
        let (mut rig, _) = deck();
        hook(&mut rig, "deck/a", "event=prompt").await;
        hook(
            &mut rig,
            "deck/a",
            "event=stop&bg=1&last=rodando%0A[[ED:wait]]",
        )
        .await;
        let s = |t: &str| Some(t.to_owned());
        assert_eq!(
            header(&rig, "deck/a"),
            (s("em segundo plano"), s("hourglass"), None, false)
        );
    }

    /// `ActivityTests.testAwaitingNamesThePeers`: quem acionou um vizinho fica
    /// na ampulheta com o nome dele, sem cor de parada.
    #[tokio::test]
    async fn aguardando_diz_o_nome_dos_vizinhos() {
        let (mut rig, _) = deck();
        hook(&mut rig, "deck/a", "event=prompt").await;
        let mut send = request("POST", "/message?target=b", Some("deck/a"));
        send.body = b"revisa".to_vec();
        let sent = rig.call(FeatureRoute::Message, send).await;
        assert_eq!(sent.status, 200, "{}", sent.json);
        hook(&mut rig, "deck/a", "event=stop&last=[[ED:ok]]").await;
        let s = |t: &str| Some(t.to_owned());
        assert_eq!(
            header(&rig, "deck/a"),
            (s("aguardando b"), s("hourglass"), None, false)
        );
        let two = crate::runtime::org::activity_view(
            &crate::features::activity::model::Activity::Awaiting(vec![
                "back".into(),
                "front".into(),
            ]),
            0,
            0,
        );
        assert_eq!(two.label, s("aguardando back, front"));
        assert_eq!(two.tone, None);
    }

    fn chat_answer(
        request: &str,
        answer: Option<crate::protocol::chat::PermissionChoice>,
        choice: Option<&str>,
        answers: Option<&[(&str, &[&str])]>,
    ) -> crate::protocol::chat::PermissionAnswer {
        crate::protocol::chat::PermissionAnswer {
            workbench: crate::commons::ids::WorkbenchId::generate(),
            request: request.to_owned(),
            answer,
            choice: choice.map(str::to_owned),
            answers: answers.map(|list| {
                list.iter()
                    .map(|(q, picked)| {
                        (
                            (*q).to_owned(),
                            picked.iter().map(|p| (*p).to_owned()).collect(),
                        )
                    })
                    .collect()
            }),
        }
    }

    /// A bandeja do chat responde pelo mesmo caminho do `/permission/answer`:
    /// botão, escolha da pergunta única e várias perguntas de uma vez.
    #[tokio::test]
    async fn a_bandeja_do_chat_responde_como_a_rota() {
        use crate::features::permission::service::PermissionState;
        use crate::protocol::chat::PermissionChoice;
        let (mut rig, _) = deck();
        let now = SystemTime::now();
        let bash = rig
            .actor
            .dispatch
            .coordination
            .desk
            .open_ask("deck/a", &serde_json::json!({"tool_name": "Bash"}), now)
            .unwrap();
        rig.actor
            .dispatch_permission_answer(&chat_answer(
                &bash.id,
                Some(PermissionChoice::Deny),
                None,
                None,
            ))
            .unwrap();
        assert!(matches!(
            rig.actor.dispatch.coordination.desk.state(&bash.id, now),
            PermissionState::Answered(_)
        ));

        let questions = serde_json::json!({"tool_name": "AskUserQuestion", "tool_input": {"questions": [
            {"question": "Qual banco?", "options": [{"label": "Postgres"}, {"label": "SQLite"}]},
            {"question": "Quais testes?", "multiSelect": true,
             "options": [{"label": "unidade"}, {"label": "contrato"}]}]}});
        let many = rig
            .actor
            .dispatch
            .coordination
            .desk
            .open_ask("deck/b", &questions, now)
            .unwrap();
        let picked: &[(&str, &[&str])] = &[
            ("Qual banco?", &["Postgres"]),
            ("Quais testes?", &["unidade", "contrato"]),
        ];
        rig.actor
            .dispatch_permission_answer(&chat_answer(&many.id, None, None, Some(picked)))
            .unwrap();
        let reply = rig.actor.dispatch.coordination.desk.poll(&many.id, now);
        assert_eq!(
            reply["output"]["hookSpecificOutput"]["decision"]["updatedInput"]["answers"],
            serde_json::json!({"Qual banco?": "Postgres", "Quais testes?": "unidade, contrato"})
        );

        let single = serde_json::json!({"tool_name": "AskUserQuestion", "tool_input": {"questions": [
            {"question": "Segue?", "options": [{"label": "Sim"}, {"label": "Não"}]}]}});
        let one = rig
            .actor
            .dispatch
            .coordination
            .desk
            .open_ask("deck/b", &single, now)
            .unwrap();
        assert_eq!(
            rig.actor
                .dispatch_permission_answer(&chat_answer(&one.id, None, Some("Talvez"), None)),
            Err(format!(
                "pedido {} já acabou, ou escolha fora das opções",
                one.id
            ))
        );
        rig.actor
            .dispatch_permission_answer(&chat_answer(&one.id, None, Some("Sim"), None))
            .unwrap();
        assert_eq!(
            rig.actor.dispatch_permission_answer(&chat_answer(
                "zz",
                Some(PermissionChoice::Allow),
                None,
                None
            )),
            Err("pedido zz já acabou, ou escolha fora das opções".to_owned())
        );
    }

    /// Com o app na frente e o foco no nó, a parada não vira notificação — a
    /// borda já diz tudo; e o foco é dele só com o app na frente.
    #[tokio::test]
    async fn no_focado_com_o_app_na_frente_nao_notifica() {
        use crate::features::dispatch::Hook;
        use crate::features::dispatch::Surface;
        use crate::features::dispatch::coordination::Outward;
        use crate::features::dispatch::marker::HookEvent;
        let (mut rig, _) = deck();
        let now = SystemTime::now();
        let ask = |rig: &mut Rig| {
            rig.actor
                .with_coordination(|c, w| {
                    c.hook("deck/a", Hook::new(HookEvent::Prompt), now, w);
                    (
                        (),
                        c.hook("deck/a", Hook::new(HookEvent::Ask), now, w)
                            .unwrap_or_default(),
                    )
                })
                .1
        };
        let notified = |out: &[Outward]| out.iter().any(|o| matches!(o, Outward::Notify(_)));
        assert!(notified(&ask(&mut rig)), "no fundo, a pergunta notifica");

        rig.actor.app_active = true;
        rig.actor.focused = Some("deck/a".into());
        rig.actor
            .dispatch_user_typed(&screen_id(&rig.actor.org.state.workbenches[0].id, "a").unwrap());
        assert!(!notified(&ask(&mut rig)), "na frente, só a borda");
        let focus = |rig: &mut Rig| {
            rig.actor
                .with_coordination(|_, w| (w.focused("deck/a"), Vec::new()))
                .0
        };
        assert!(focus(&mut rig));
        rig.actor.app_active = false;
        assert!(!focus(&mut rig), "app no fundo: ninguém está olhando");
    }

    /// O modelo literal sai do transcript, lido fora do ator: a resposta do
    /// `/status` chega depois, com ele.
    #[tokio::test]
    async fn status_le_o_modelo_do_transcript_fora_do_ator() {
        let (mut rig, _) = deck();
        let transcript = rig.dir.path().join("a.jsonl");
        std::fs::write(
            &transcript,
            r#"{"type":"assistant","message":{"model":"claude-fable-5","content":[{"type":"text","text":"x"}]}}"#,
        )
        .unwrap();
        rig.actor
            .record_conversation("deck/a", "c1", transcript.to_str());
        let reply = rig
            .call(
                FeatureRoute::Status,
                request("GET", "/status", Some("deck/a")),
            )
            .await;
        assert_eq!(reply.json["model"], "claude-fable-5", "{}", reply.json);
        assert_eq!(reply.json["cli"], "Fake");
    }
}

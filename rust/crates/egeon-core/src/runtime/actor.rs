//! O ator: único dono dos nós de terminal e dos clientes do `/ui`.
//!
//! Ninguém mais toca no estado. Leitores de pty e conexões só mandam
//! [`Msg`]; o ator responde por `oneshot` (HTTP) ou pela fila do cliente
//! (`/ui`), e nunca espera em ninguém — fila de cliente cheia não trava os
//! outros terminais.

mod access;
mod activity_watch;
mod app_commands;
mod bench_forms;
mod bench_removal;
mod chat_commands;
mod chat_queue;
mod dispatch_commands;
mod exists;
mod launch;
mod menu_commands;
mod node_clean;
mod node_commands;
mod node_detail;
mod node_form;
mod notices;

pub use node_detail::{WEB_PROFILES, load_web_profiles};
mod org_commands;
mod processes_commands;
mod processes_ui;
mod queue_commands;
mod terminal_commands;
mod trace_commands;
mod trust_commands;
mod ui_requests;
mod update_commands;
mod worktree_copy;

/// Onde a resposta de uma rota HTTP vai: quem bloqueia a leva para fora do
/// ator e responde depois.
pub type Replier = oneshot::Sender<HttpReply>;

/// Rota do Swift que ainda não tem handler ligado.
pub(super) fn not_ported(route: FeatureRoute, reply: Replier) {
    let _ = reply.send(HttpReply::err(
        501,
        format!("{route:?} ainda não portada no app novo"),
    ));
}

use crate::features::activity::model::ActivitySummary;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use serde_json::{Value, json};
use tokio::sync::{mpsc, oneshot, watch};

use super::org::Org;
use super::{Config, Drivers, Snapshot};
use crate::commons::ids::WorkbenchId;
use crate::features::chat::runtime::Complete;
use crate::features::processes::{mark, tree};
use crate::features::terminal::model::{LAUNCH_SHELL, TERM, launch_args, paste_bytes};
use crate::features::terminal::peer::owner;
use crate::ports::procs::ProcessDriver;
use crate::ports::pty::{PtyEvent, PtyExit, PtySession, PtySignal, PtySize, PtySpec};
use crate::ports::screen::Screen;
use crate::protocol::handler::RouteRequest;
use crate::protocol::message::{
    Command, CommandKind, CreateTerminal, Event, EventBody, NodeId, Reply, TerminalInfo, Topic,
    to_line,
};
use crate::protocol::node::UsageState;
use crate::protocol::org::{NodesState, WorkspacesState};
use crate::protocol::routes::{FeatureRoute, Route};
use crate::protocol::screen::{Scroll, Size};

/// Tamanho de um terminal quando o pedido não diz.
pub(super) const DEFAULT_SIZE: Size = Size { cols: 80, rows: 24 };

/// Quanto o ator junta de mensagens já na fila antes de mandar os quadros:
/// sob saída pesada, um quadro por lote em vez de um por pedaço de bytes.
const BATCH: usize = 256;

/// Linhas na fila de cada cliente do `/ui`. Cheia, o cliente perde deltas e
/// recebe a tela inteira quando houver espaço.
pub const CLIENT_QUEUE: usize = 256;

/// O passo do relógio das features — o `TICK` do dispatch, 250 ms.
pub const TICK: Duration = Duration::from_millis(250);

/// Do SIGHUP ao SIGKILL ao fechar um terminal: o zsh sai no HUP, e um
/// programa que o ignora não segura o nó.
const KILL_GRACE: Duration = Duration::from_millis(500);

/// Do SIGTERM nos descendentes ao SIGKILL em quem o ignorou, ao remover um
/// nó: o mesmo de `ProcessScanner.terminateTree`.
const TREE_GRACE: Duration = Duration::from_secs(2);

pub type ClientId = u64;

/// Uma linha já serializada, dividida entre os clientes do mesmo tópico.
pub type WireLine = Arc<[u8]>;

/// Resposta a uma rota HTTP: status e corpo JSON.
pub type HttpReply = crate::protocol::handler::RouteReply;

pub enum Msg {
    Http {
        route: Route,
        /// O pid do par e os pais dele: é por eles que se sabe de qual
        /// terminal veio o pedido.
        caller: Vec<u32>,
        reply: oneshot::Sender<HttpReply>,
    },
    /// Trabalho que voltou de fora do ator (disco, git, rede) para ser
    /// aplicado no estado. É como os arquivos das features devolvem o
    /// resultado de um `spawn_blocking` sem acrescentar variantes aqui.
    Run(Box<dyn FnOnce(&mut Actor) + Send>),
    /// O relógio das features, a cada [`TICK`].
    Tick,
    /// Cliente novo do `/ui`. `queue` e `alive` ficam só com o ator: largá-los
    /// é o que fecha a conexão.
    UiOpen {
        queue: mpsc::Sender<WireLine>,
        alive: oneshot::Sender<()>,
        reply: oneshot::Sender<ClientId>,
    },
    /// Resposta pronta para um cliente — o erro de uma linha que a conexão
    /// não conseguiu ler como comando.
    UiReply {
        client: ClientId,
        reply: Reply,
    },
    UiCommand {
        client: ClientId,
        command: Command,
    },
    UiClose {
        client: ClientId,
    },
    Pty {
        node: NodeId,
        generation: u64,
        event: PtyEvent,
    },
    Shutdown {
        done: oneshot::Sender<()>,
    },
}

struct Node {
    info: TerminalInfo,
    /// `bancada/nó` quando o terminal é de um nó de bancada; os terminais
    /// soltos do marco 1 não têm.
    address: Option<String>,
    /// Quando o processo subiu: o modelo do transcript só vale de linha
    /// posterior (o `since: launched` do Swift), senão a troca de modelo, que
    /// reinicia e mantém a conversa, mostraria o modelo velho.
    launched: SystemTime,
    /// O agente subiu com os ganchos de relato (`LaunchPlan.hooked`): binário
    /// próprio, flag de system prompt e os argumentos de relato. Shell e
    /// terminal solto, não.
    hooked: bool,
    /// Distingue o nó de um outro com o mesmo id que venha depois: evento do
    /// pty antigo, ainda na fila, não cai no novo.
    generation: u64,
    session: Option<Box<dyn PtySession>>,
    screen: Box<dyn Screen>,
    /// Mudou desde o último quadro mandado.
    dirty: bool,
}

struct Client {
    queue: mpsc::Sender<WireLine>,
    /// Cai junto com o cliente; a conexão espera nele para fechar.
    _alive: oneshot::Sender<()>,
    topics: HashSet<Topic>,
    /// Telas que este cliente tem de receber inteiras: ele perdeu um delta com
    /// a fila cheia.
    resync: HashSet<NodeId>,
}

pub struct Actor {
    config: Config,
    drivers: Drivers,
    inbox: mpsc::Sender<Msg>,
    nodes: BTreeMap<NodeId, Node>,
    clients: HashMap<ClientId, Client>,
    next_node: u64,
    next_client: ClientId,
    next_generation: u64,
    org: Org,
    node: node_commands::NodeState,
    saver: Option<watch::Sender<Option<Arc<Snapshot>>>>,
    saves: u64,
    dispatch: dispatch_commands::DispatchState,
    chat: chat_commands::ChatState,
    ui_requests: ui_requests::UiRequests,
    detail: node_detail::DetailState,
    exists: exists::ExistsState,
    activity_watch: activity_watch::ActivityWatch,
    /// O app está na frente (decisão 33); sem a UI dizer, não está.
    pub(super) app_active: bool,
    /// O terminal com o foco, como `bancada/nó`.
    pub(super) focused: Option<String>,
    /// O tamanho do canvas que a UI mandou no `ui_focus`.
    pub(super) window: Option<(f64, f64)>,
    // O `cli` liga o corpo; até lá o campo só existe.
    #[allow(dead_code)]
    processes: processes_commands::ProcessesState,
    // O `cli` liga o corpo; até lá o campo só existe.
    #[allow(dead_code)]
    trace: trace_commands::TraceState,
    // O `cli` liga o corpo; até lá o campo só existe.
    #[allow(dead_code)]
    queue: queue_commands::QueueState,
    // O `cli` liga o corpo; até lá o campo só existe.
    #[allow(dead_code)]
    update: update_commands::UpdateState,
}

impl Actor {
    pub fn new(config: Config, drivers: Drivers, inbox: mpsc::Sender<Msg>) -> Self {
        Self {
            config,
            drivers,
            inbox,
            nodes: BTreeMap::new(),
            clients: HashMap::new(),
            next_node: 1,
            next_client: 1,
            next_generation: 1,
            org: Org::default(),
            node: node_commands::NodeState::default(),
            saver: None,
            saves: 0,
            dispatch: dispatch_commands::DispatchState::default(),
            chat: chat_commands::ChatState::default(),
            ui_requests: ui_requests::UiRequests::default(),
            detail: node_detail::DetailState::default(),
            exists: exists::ExistsState::default(),
            activity_watch: activity_watch::ActivityWatch::default(),
            app_active: false,
            focused: None,
            window: None,
            processes: processes_commands::ProcessesState::default(),
            trace: trace_commands::TraceState::default(),
            queue: queue_commands::QueueState::default(),
            update: update_commands::UpdateState::default(),
        }
    }

    /// Quem grava as bancadas no disco, fora do ator.
    pub fn with_saver(mut self, saver: watch::Sender<Option<Arc<Snapshot>>>) -> Self {
        self.saver = Some(saver);
        self
    }

    /// Manda o retrato de agora ao gravador. Não espera: o gravador fica com o
    /// mais novo.
    fn persist(&mut self) {
        self.org.record_tab_order();
        let Some(saver) = &self.saver else { return };
        self.saves += 1;
        saver.send_replace(Some(Arc::new(Snapshot {
            seq: self.saves,
            workspaces: self.org.state.workspaces.clone(),
            workbenches: self.org.state.workbenches.clone(),
        })));
    }

    /// As bancadas carregadas na partida.
    pub fn with_org(mut self, mut org: Org) -> Self {
        self.detail.web_profiles = std::mem::take(&mut org.web_profiles);
        self.org = org;
        self
    }

    pub async fn run(mut self, mut rx: mpsc::Receiver<Msg>) {
        let ticker = self.inbox.clone();
        let ticking = tokio::spawn(async move {
            let mut every = tokio::time::interval(TICK);
            every.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            loop {
                every.tick().await;
                // Fila cheia: o próximo tique vem logo, e esperar aqui seria
                // segurar o relógio de todo mundo atrás de um `cat` gigante.
                if let Err(mpsc::error::TrySendError::Closed(_)) = ticker.try_send(Msg::Tick) {
                    return;
                }
            }
        });
        // Como o Swift ao abrir: a bancada da frente sobe já; as outras abas,
        // quando forem ativadas.
        if let Some(active) = self.org.state.active_id.clone() {
            self.open_terminals(&active);
        }
        // A pasta de links de todo multi-projeto é refeita a cada arranque,
        // como o `MultiProjectLinks.syncAll` do Swift.
        let workspaces = self.org.state.workspaces.clone();
        self.sync_multi_links(workspaces);
        self.serve_inbox(&mut rx).await;
        ticking.abort();
    }

    async fn serve_inbox(&mut self, rx: &mut mpsc::Receiver<Msg>) {
        while let Some(msg) = rx.recv().await {
            if self.handle(msg) {
                return;
            }
            // O que já está na fila entra no mesmo lote: sem espera nenhuma
            // quando está quieto, e um quadro só quando está chovendo saída.
            for _ in 0..BATCH {
                match rx.try_recv() {
                    Ok(msg) => {
                        if self.handle(msg) {
                            return;
                        }
                    }
                    Err(_) => break,
                }
            }
            self.flush();
        }
    }

    /// O terminal de onde a conexão partiu, como o `Dispatcher.target(callingOn:)`
    /// do Swift: o primeiro da cadeia do pid do par que é o shell de um nó
    /// com endereço. `None` é você — o chat, um `curl`, um teste.
    fn origin_of(&self, caller: &[u32]) -> Option<String> {
        let shells: HashMap<u32, &str> = self
            .nodes
            .values()
            .filter_map(|n| Some((n.session.as_ref()?.pid(), n.address.as_deref()?)))
            .collect();
        let first = *caller.first()?;
        let next = |pid: u32| {
            let at = caller.iter().position(|p| *p == pid)?;
            caller.get(at + 1).copied()
        };
        let owner = owner(first, |pid| shells.contains_key(&pid), next)?;
        shells.get(&owner).map(|a| (*a).to_owned())
    }

    /// Entrega a rota do Swift ao arquivo do dono. A resposta pode sair
    /// depois: quem bloqueia leva `reply` para fora e responde quando
    /// terminar, voltando ao ator por [`Msg::Run`].
    fn feature_route(&mut self, route: FeatureRoute, request: RouteRequest, reply: Replier) {
        use FeatureRoute::*;
        match route {
            Targets | Conversation | PermissionAnswer | Permissions | PermissionOpen
            | PermissionPoll | Activity | Retry | Message | Maestro | MaestroGuide | Peers
            | Status | Peek | Dispatch => self.dispatch_route(route, request, reply),
            Trace => self.trace_route(route, request, reply),
            Worktree | NodeClear | WorkbenchClear | Remove | Model => {
                self.node_route(route, request, reply);
            }
            Layout | Sidebar | Geometry | Shot => self.ui_route(route, request, reply),
            Tasks | Task | Queue => self.queue_route(route, request, reply),
            Apps | ProcessesReap | ProcessesKill | Processes => {
                self.processes_route(route, request, reply);
            }
            Update => self.update_route(route, request, reply),
            Chat if request.param("newqueue") == Some("1") => {
                self.chat_new_queue_route(&request);
                self.chat_route(route, request, reply);
            }
            ChatClear | Compose | Chat | Usage => self.chat_route(route, request, reply),
            ProjectNew | Move | WorkbenchColor | Tabs | Workspaces | Activate | Edge | About => {
                self.org_route(route, request, reply);
            }
        }
    }

    /// O relógio de cada feature, na ordem em que o Swift os teria: quem
    /// injeta primeiro, a fila depois.
    fn tick(&mut self, now: SystemTime) {
        self.dispatch_tick(now);
        self.queue_tick(now);
        self.processes_tick(now);
        self.update_tick(now);
        self.chat_tick(now);
        self.node_tick(now);
        self.detail_tick(now);
        self.exists_tick(now);
        self.activity_tick();
    }

    /// O git do usuário, com o PATH que os terminais recebem.
    pub(super) fn user_git(&self) -> crate::features::worktree::git::Git {
        let env = crate::features::terminal::environment::for_child(
            &*self.drivers.pty,
            &self.config.paths.cli_dir(),
            &mark::inherited(),
        )
        .into_iter()
        .map(|(k, v)| (k.into(), v.into()))
        .collect();
        crate::features::worktree::git::Git::new(env)
    }

    /// Devolve `true` quando é para parar.
    pub(super) fn handle(&mut self, msg: Msg) -> bool {
        match msg {
            Msg::Http {
                route: Route::Feature { route, mut request },
                caller,
                reply,
            } => {
                request.origin = self.origin_of(&caller);
                self.feature_route(route, request, reply);
            }
            Msg::Http { route, reply, .. } => {
                let _ = reply.send(self.http(route));
            }
            Msg::Run(job) => job(self),
            Msg::Tick => self.tick(SystemTime::now()),
            Msg::UiOpen {
                queue,
                alive,
                reply,
            } => {
                let id = self.next_client;
                self.next_client += 1;
                self.clients.insert(
                    id,
                    Client {
                        queue,
                        _alive: alive,
                        topics: HashSet::new(),
                        resync: HashSet::new(),
                    },
                );
                let _ = reply.send(id);
            }
            Msg::UiCommand { client, command } => self.command(client, command),
            Msg::UiReply { client, reply } => self.send_reply(client, &reply),
            Msg::UiClose { client } => {
                self.clients.remove(&client);
            }
            Msg::Pty {
                node,
                generation,
                event: PtyEvent::Output(bytes),
            } => self.output(node, generation, &bytes),
            Msg::Pty {
                node,
                generation,
                event: PtyEvent::Exited(exit),
            } => self.exited(node, generation, exit),
            Msg::Shutdown { done } => {
                // O `applicationWillTerminate` da atualização: a troca do app
                // agendada sai antes de os terminais caírem.
                self.update_shutdown();
                self.flush_clocks();
                let sessions = self.shutdown();
                let procs = self.drivers.procs.clone();
                tokio::spawn(async move {
                    shut_down(sessions, procs).await;
                    let _ = done.send(());
                });
                return true;
            }
        }
        false
    }

    fn http(&mut self, route: Route) -> HttpReply {
        match route {
            Route::About => HttpReply::ok(json!({
                "ok": true,
                "version": self.config.version,
                "build": self.config.build,
            })),
            Route::ListTerminals => HttpReply::ok(json!({"terminals": self.infos()})),
            Route::CreateTerminal(spec) => match self.create(spec) {
                Ok(info) => {
                    let mut body = json!({"ok": true});
                    merge(&mut body, &info);
                    HttpReply::ok(body)
                }
                Err(err) => HttpReply::err(err.status(), err.to_string()),
            },
            Route::Input { node, bytes } => match self.write(&node, &bytes) {
                Ok(()) => HttpReply::ok(json!({"ok": true})),
                Err(err) => HttpReply::err(err.status(), err.to_string()),
            },
            // O upgrade é tratado na conexão; aqui não chega.
            Route::Ui => HttpReply::err(400, "o canal /ui não é rota de pedido e resposta"),
            // As do Swift vão por `feature_route`, com a origem; aqui não chegam.
            Route::Feature { route, .. } => {
                HttpReply::err(500, format!("{route:?} sem quem atenda"))
            }
        }
    }

    fn command(&mut self, client: ClientId, command: Command) {
        let re = command.id;
        let reply = match command.kind {
            CommandKind::Subscribe { topic } => {
                return self.subscribe(client, re, topic);
            }
            CommandKind::Unsubscribe { topic } => {
                if let Some(c) = self.clients.get_mut(&client) {
                    c.topics.remove(&topic);
                }
                Reply::ok(re)
            }
            CommandKind::CreateTerminal(spec) => match self.create(spec) {
                Ok(info) => Reply::with(re, &info),
                Err(err) => Reply::err(re, err.to_string()),
            },
            CommandKind::Input { node, text } => {
                // Digitado na UI, não injetado: o dispatch conta como você.
                self.dispatch_user_typed(&node);
                let outcome = self.write(&node, text.as_bytes());
                self.result(re, outcome)
            }
            CommandKind::Paste { node, text } => {
                self.dispatch_user_typed(&node);
                let bytes = match self.nodes.get(&node) {
                    Some(n) => paste_bytes(&text, n.screen.bracketed_paste()),
                    None => Vec::new(),
                };
                let outcome = self.write(&node, &bytes);
                self.result(re, outcome)
            }
            CommandKind::Key { node, press } => {
                self.dispatch_user_typed(&node);
                let bytes = match self.nodes.get_mut(&node) {
                    Some(n) => n.screen.encode_key(&press),
                    None => Vec::new(),
                };
                let outcome = self.write(&node, &bytes);
                self.result(re, outcome)
            }
            CommandKind::Resize { node, cols, rows } => {
                let outcome = self.resize(&node, Size { cols, rows });
                self.result(re, outcome)
            }
            CommandKind::ListTerminals => Reply::with(re, &json!({"terminals": self.infos()})),
            CommandKind::CloseTerminal { node } => {
                let outcome = self.close(&node);
                self.result(re, outcome)
            }
            kind @ (CommandKind::ChatSnapshot(_)
            | CommandKind::ChatStep(_)
            | CommandKind::ChatMore(_)
            | CommandKind::ChatClear(_)
            | CommandKind::ChatSend(_)) => match self.chat_command(client, re, kind) {
                Some(reply) => reply,
                // A resposta sai quando o trabalho fora do ator terminar.
                None => return,
            },
            kind @ (CommandKind::QueueAdd(_)
            | CommandKind::QueueUpdate(_)
            | CommandKind::QueueRemove(_)
            | CommandKind::QueueMove(_)
            | CommandKind::QueueToggleDone(_)
            | CommandKind::QueueReopen(_)
            | CommandKind::QueueSend(_)
            | CommandKind::QueueReply(_)
            | CommandKind::QueueSet(_)
            | CommandKind::QueueClearDone(_)
            | CommandKind::QueueAttach(_)
            | CommandKind::QueueDetach(_)) => self.queue_command(re, kind),
            CommandKind::QueueOpenImage(open) => self.queue_open_image(re, &open),
            CommandKind::UiReply(answer) => self.ui_reply(re, answer),
            CommandKind::ChatNewQueue(c) => self.chat_new_queue(client, re, c),
            CommandKind::AccessOpenSettings(r) => self.access_open_settings(re, &r),
            CommandKind::AccessAskAgain(r) => match self.access_ask_again(client, re, &r) {
                Some(reply) => reply,
                None => return,
            },
            // O mesmo caminho do `POST /permission/answer` (US-301).
            CommandKind::PermissionAnswer(answer) => match self.dispatch_permission_answer(&answer)
            {
                Ok(()) => Reply::ok(re),
                Err(error) => Reply::err(re, error),
            },
            kind @ (CommandKind::Processes
            | CommandKind::ProcessesReap(_)
            | CommandKind::ProcessesKill(_)) => match self.processes_ui(client, re, kind) {
                Some(reply) => reply,
                None => return,
            },
            kind @ (CommandKind::EffortMove(_)
            | CommandKind::EffortToggleAuto(_)
            | CommandKind::EffortSettle(_)
            | CommandKind::WebNavigate(_)
            | CommandKind::WebNavigated(_)
            | CommandKind::WebSetProfile(_)) => match self.detail_command(client, re, kind) {
                Some(reply) => reply,
                None => return,
            },
            CommandKind::UiFocus(f) => {
                self.app_active = f.app_active;
                if let Some(size) = f.window {
                    self.window = Some((size.w, size.h));
                }
                self.focused = f.node.and_then(|n| {
                    let name = self.org.name_of(&n.workbench)?;
                    Some(format!("{name}/{}", n.node))
                });
                Reply::ok(re)
            }
            kind @ (CommandKind::CreateWorkbench(_)
            | CommandKind::RemoveWorkbench(_)
            | CommandKind::PlanRemoveWorkbench(_)
            | CommandKind::RemovalLosses(_)
            | CommandKind::ClearWorkbench(_)
            | CommandKind::ResetClock(_)
            | CommandKind::Worktree(_)
            | CommandKind::CreateNode(_)
            | CommandKind::RemoveNode(_)
            | CommandKind::SetNode(_)
            | CommandKind::NodeForm(_)
            | CommandKind::NodeFormScreen(_)
            | CommandKind::NodeFolder(_)
            | CommandKind::ApplyNode(_)
            | CommandKind::Components
            | CommandKind::Link(_)
            | CommandKind::NodeClear(_)
            | CommandKind::Retry(_)
            | CommandKind::OpenNodeFolder(_)
            | CommandKind::CreateWorkspace(_)
            | CommandKind::RemoveWorkspace(_)
            | CommandKind::SaveWorkspace(_)
            | CommandKind::CreateProject(_)
            | CommandKind::AddProject(_)
            | CommandKind::RemoveProject(_)
            | CommandKind::MultiProject(_)
            | CommandKind::Templates
            | CommandKind::WorktreeInfo(_)
            | CommandKind::WorktreePlan(_)
            | CommandKind::SaveTemplate(_)) => match self.node_command(client, re, kind) {
                Some(reply) => reply,
                None => return,
            },
            kind @ (CommandKind::Scroll(_)
            | CommandKind::Pointer(_)
            | CommandKind::SelectAll(_)
            | CommandKind::Copy(_)
            | CommandKind::ClipboardReply(_)
            | CommandKind::LinkHover(_)
            | CommandKind::Drop(_)) => match self.terminal_command(client, re, kind) {
                Some(reply) => reply,
                None => return,
            },
            CommandKind::ChatComplete(c) => {
                let request = Complete {
                    workbench: c.workbench.to_string(),
                    text: c.text,
                    caret: c.caret,
                    to: c.to.map(|n| n.to_string()),
                    search: c.search,
                };
                match self.chat_complete(client, re, request) {
                    Some(reply) => reply,
                    None => return,
                }
            }
            kind @ (CommandKind::UpdateMenu
            | CommandKind::UpdateAnswer(_)
            | CommandKind::UpdateAuto(_)
            | CommandKind::ReaperEnabled(_)) => self.app_command(re, kind),
            CommandKind::CopyTargets => self.copy_targets(re),
            CommandKind::OpenUrl(open) => self.open_url(re, open),
            other => self.org_command(re, other),
        };
        self.send_reply(client, &reply);
    }

    fn result(&self, re: u64, outcome: Result<(), NodeError>) -> Reply {
        match outcome {
            Ok(()) => Reply::ok(re),
            Err(err) => Reply::err(re, err.to_string()),
        }
    }

    fn subscribe(&mut self, client: ClientId, re: u64, topic: Topic) {
        let snapshot = match &topic {
            Topic::Terminals => Event {
                topic: topic.clone(),
                body: EventBody::Terminals {
                    terminals: self.infos(),
                },
            },
            Topic::Usage(id) => match self.usage_event(id) {
                Some(event) => event,
                None => {
                    let reply = Reply::err(re, format!("bancada desconhecida '{id}'"));
                    self.send_reply(client, &reply);
                    return;
                }
            },
            // Agente, web e fila têm estado por dentro; o shell não.
            Topic::Node(bench, node) => match self.node_event(bench, node) {
                Some(event) => event,
                None => {
                    let error = match self.config_of(bench, node) {
                        None => format!("nó desconhecido '{bench}/{node}'"),
                        Some(_) => format!("o nó '{node}' não tem estado por dentro"),
                    };
                    let reply = Reply::err(re, error);
                    self.send_reply(client, &reply);
                    return;
                }
            },
            // O `reset` do chat sai para quem assina, e o cliente novo tem de
            // estar na lista antes: a resposta vai primeiro, o estado depois.
            Topic::Chat(id) => {
                if let Some(c) = self.clients.get_mut(&client) {
                    c.topics.insert(topic.clone());
                }
                if self.org.index_of(id).is_none() {
                    if let Some(c) = self.clients.get_mut(&client) {
                        c.topics.remove(&topic);
                    }
                    let reply = Reply::err(re, format!("bancada desconhecida '{id}'"));
                    self.send_reply(client, &reply);
                    return;
                }
                self.send_reply(client, &Reply::ok(re));
                if !self.chat_subscribe(id) {
                    crate::log!("chat[{id}]: assinatura sem estado");
                }
                return;
            }
            Topic::App => self.app_snapshot(),
            Topic::Workspaces => Event {
                topic: topic.clone(),
                body: EventBody::Workspaces(self.workspaces_state()),
            },
            Topic::Nodes(id) => {
                self.queue_sync();
                let state = self
                    .org
                    .index_of(id)
                    .and_then(|index| self.nodes_state(index));
                let Some(state) = state else {
                    let reply = Reply::err(re, format!("bancada desconhecida '{id}'"));
                    self.send_reply(client, &reply);
                    return;
                };
                Event {
                    topic: topic.clone(),
                    body: EventBody::Nodes(state),
                }
            }
            Topic::Screen(id) => {
                let first = !self.clients.values().any(|c| c.topics.contains(&topic));
                let Some(node) = self.nodes.get_mut(id) else {
                    let reply = Reply::err(re, NodeError::Unknown(id.clone()).to_string());
                    self.send_reply(client, &reply);
                    return;
                };
                let frame = node.screen.full_frame();
                if first {
                    // Ninguém assinava: o sujo acumulado até aqui já está no
                    // quadro inteiro, e o próximo delta começa do zero.
                    let _ = node.screen.take_delta();
                    node.dirty = false;
                }
                Event {
                    topic: topic.clone(),
                    body: EventBody::Screen(frame),
                }
            }
        };
        if let Some(c) = self.clients.get_mut(&client) {
            c.topics.insert(topic.clone());
            if let Topic::Screen(id) = &topic {
                c.resync.remove(id);
            }
        }
        self.send_reply(client, &Reply::ok(re));
        if let Some(line) = encode(&snapshot) {
            self.push(client, line, false);
        }
        match topic {
            Topic::App => self.ui_app_subscribed(),
            Topic::Node(bench, node) => self.probe_node(bench, node),
            _ => {}
        }
    }

    fn send_reply(&mut self, client: ClientId, reply: &Reply) {
        if let Some(line) = encode(reply) {
            self.push(client, line, false);
        }
    }

    /// Põe a linha na fila do cliente sem esperar. Resposta ou evento que não
    /// cabe derruba o cliente — ele perderia o fio da conversa; delta de tela
    /// que não cabe vira tela inteira depois (`droppable`).
    fn push(&mut self, client: ClientId, line: WireLine, droppable: bool) -> bool {
        let Some(c) = self.clients.get(&client) else {
            return false;
        };
        match c.queue.try_send(line) {
            Ok(()) => true,
            Err(mpsc::error::TrySendError::Full(_)) if droppable => false,
            Err(_) => {
                crate::log!("ui: cliente {client} não lê a fila; desligado");
                self.clients.remove(&client);
                false
            }
        }
    }

    fn publish_terminals(&mut self) {
        let event = Event {
            topic: Topic::Terminals,
            body: EventBody::Terminals {
                terminals: self.infos(),
            },
        };
        self.publish(&event);
    }

    /// A árvore com o que só o ator sabe: a atividade de cada bancada (do
    /// dispatch) e o cronômetro dela (do `org`).
    fn workspaces_state(&mut self) -> WorkspacesState {
        let summaries = self.dispatch.coordination.dispatcher.activity_summary();
        self.workspaces_state_with(&summaries)
    }

    fn workspaces_state_with(
        &mut self,
        summaries: &BTreeMap<String, ActivitySummary>,
    ) -> WorkspacesState {
        let ids: Vec<String> = self
            .org
            .state
            .workbenches
            .iter()
            .map(|w| w.id.clone())
            .collect();
        let clocks: HashMap<String, _> = ids
            .into_iter()
            .map(|id| {
                let clock = self.clock_of(&id);
                (id, clock)
            })
            .collect();
        self.org.workspaces_state(SystemTime::now(), |bench| {
            (
                summaries.get(&bench.name).copied(),
                clocks.get(&bench.id).cloned(),
            )
        })
    }

    /// Os nós da bancada. As filas têm de estar criadas (`queue_sync`): quem
    /// chama com `&mut self` sincroniza antes.
    fn nodes_state(&self, index: usize) -> Option<NodesState> {
        let dispatcher = &self.dispatch.coordination.dispatcher;
        let mut state = self.org.nodes_state(
            index,
            |id| self.nodes.get(id).is_some_and(|n| n.session.is_some()),
            |address| {
                dispatcher
                    .target(address)
                    .map(|t| (t.activity().clone(), t.pending()))
            },
            crate::commons::clock::local_offset_secs(SystemTime::now()),
        )?;
        // O subtítulo do card da fila é o resumo dela, que só o ator sabe.
        for node in &mut state.nodes {
            if node.kind == crate::protocol::org::NodeKind::Queue {
                node.subtitle = self
                    .queue
                    .subtitle(state.workbench.as_str(), node.id.as_str());
            }
        }
        Some(state)
    }

    /// O estado novo da organização a quem assina: a árvore e os nós de cada
    /// bancada assinada. Só monta o que alguém está olhando.
    pub(super) fn publish_org(&mut self) {
        self.queue_sync();
        let watched: HashSet<Topic> = self
            .clients
            .values()
            .flat_map(|c| c.topics.iter().cloned())
            .filter(|t| matches!(t, Topic::Workspaces | Topic::Nodes(_) | Topic::Node(..)))
            .collect();
        for topic in watched {
            let body = match &topic {
                Topic::Workspaces => {
                    // Só a publicação para todos conta como "já foi à tela": o
                    // retrato de quem acabou de assinar vai só para ele, e
                    // gravá-lo faria o relógio achar que os outros já têm a
                    // árvore nova.
                    let summaries = self.dispatch.coordination.dispatcher.activity_summary();
                    self.activity_watch.published = summaries.clone();
                    EventBody::Workspaces(self.workspaces_state_with(&summaries))
                }
                Topic::Nodes(id) => {
                    let Some(state) = self.org.index_of(id).and_then(|i| self.nodes_state(i))
                    else {
                        continue;
                    };
                    EventBody::Nodes(state)
                }
                // O nó por dentro também muda com a organização (modelo,
                // conversa, URL).
                Topic::Node(bench, node) => {
                    if let Some(event) = self.node_event(bench, node) {
                        self.publish(&event);
                    }
                    continue;
                }
                _ => continue,
            };
            self.publish(&Event { topic, body });
        }
    }

    fn usage_event(&mut self, id: &WorkbenchId) -> Option<Event> {
        let (pill, panel) = self.usage_state(id.as_str())?;
        Some(Event {
            topic: Topic::Usage(id.clone()),
            body: EventBody::Usage(Box::new(UsageState {
                workbench: id.clone(),
                pill,
                panel,
            })),
        })
    }

    /// O consumo novo a quem assina a bancada: quem relê o `UsageStore`
    /// chama (o chat-rs, a cada refresh).
    pub(super) fn publish_usage(&mut self, id: &WorkbenchId) {
        let topic = Topic::Usage(id.clone());
        if !self.clients.values().any(|c| c.topics.contains(&topic)) {
            return;
        }
        if let Some(event) = self.usage_event(id) {
            self.publish(&event);
        }
    }

    /// Manda o estado inteiro de um tópico a quem o assina.
    fn publish(&mut self, event: &Event) {
        let Some(line) = encode(event) else { return };
        let targets: Vec<ClientId> = self
            .clients
            .iter()
            .filter(|(_, c)| c.topics.contains(&event.topic))
            .map(|(id, _)| *id)
            .collect();
        for client in targets {
            self.push(client, line.clone(), false);
        }
    }

    /// Manda os quadros das telas que mudaram a quem as assina.
    pub(super) fn flush(&mut self) {
        let mut sends: Vec<(ClientId, NodeId, WireLine, bool)> = Vec::new();
        for (id, node) in &mut self.nodes {
            let topic = Topic::Screen(id.clone());
            let watchers: Vec<(ClientId, bool)> = self
                .clients
                .iter()
                .filter(|(_, c)| c.topics.contains(&topic))
                .map(|(cid, c)| (*cid, c.resync.contains(id)))
                .collect();
            if watchers.is_empty() {
                continue;
            }
            let screen_line = |frame| {
                encode(&Event {
                    topic: topic.clone(),
                    body: EventBody::Screen(frame),
                })
            };
            let delta_line = if node.dirty {
                node.dirty = false;
                node.screen.take_delta().and_then(screen_line)
            } else {
                None
            };
            let full_line = if watchers.iter().any(|(_, resync)| *resync) {
                screen_line(node.screen.full_frame())
            } else {
                None
            };
            for (cid, resync) in watchers {
                let line = if resync { &full_line } else { &delta_line };
                if let Some(line) = line {
                    sends.push((cid, id.clone(), line.clone(), resync));
                }
            }
        }
        for (cid, id, line, was_resync) in sends {
            let delivered = self.push(cid, line, true);
            if let Some(c) = self.clients.get_mut(&cid) {
                if delivered && was_resync {
                    c.resync.remove(&id);
                } else if !delivered {
                    c.resync.insert(id);
                }
            }
        }
    }

    fn infos(&self) -> Vec<TerminalInfo> {
        self.nodes.values().map(|n| n.info.clone()).collect()
    }

    fn create(&mut self, spec: CreateTerminal) -> Result<TerminalInfo, NodeError> {
        let cwd = spec
            .cwd
            .filter(|c| !c.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| self.config.default_cwd.clone());
        let size = Size {
            cols: spec.cols.unwrap_or(DEFAULT_SIZE.cols),
            rows: spec.rows.unwrap_or(DEFAULT_SIZE.rows),
        };
        if size.cols == 0 || size.rows == 0 {
            return Err(NodeError::BadSize(size));
        }
        // A procedência herdada sai: quem marca é o terminal que vai lançar
        // (ProcessMark.inherited no Swift, ADR-083).
        let mut env = self.base_environment();
        env.retain(|(k, _)| k != "TERM");
        env.push(("TERM".to_owned(), TERM.to_owned()));

        let command = spec.command.filter(|c| !c.trim().is_empty());
        let id = self.fresh_id();
        self.spawn_terminal(id, None, &cwd, command, env, size)
    }

    /// O ambiente-base de todo filho: o do app sem as `CLAUDE_CODE*` e sem a
    /// procedência herdada, com o `egeon` na frente do `PATH`.
    pub(super) fn base_environment(&self) -> Vec<(String, String)> {
        crate::features::terminal::environment::for_child(
            &*self.drivers.pty,
            &self.config.paths.cli_dir(),
            &mark::inherited(),
        )
    }

    /// Lança o processo atrás de um pty e guarda o nó. A linha é sempre
    /// `zsh -lc "cd '<cwd>'; clear; <command>"`: o `cd` vai só na linha, como
    /// no Swift — uma pasta que sumiu não impede o nó de subir, e o erro do
    /// `cd` aparece na tela.
    pub(super) fn spawn_terminal(
        &mut self,
        id: NodeId,
        address: Option<String>,
        cwd: &std::path::Path,
        command: Option<String>,
        env: Vec<(String, String)>,
        size: Size,
    ) -> Result<TerminalInfo, NodeError> {
        if size.cols == 0 || size.rows == 0 {
            return Err(NodeError::BadSize(size));
        }
        let screen = self
            .drivers
            .screens
            .create(size)
            .map_err(|e| NodeError::Screen(e.to_string()))?;
        let child = self
            .drivers
            .pty
            .spawn(PtySpec {
                program: PathBuf::from(LAUNCH_SHELL),
                args: launch_args(cwd, command.as_deref()),
                env,
                cwd: None,
                size: PtySize {
                    cols: size.cols,
                    rows: size.rows,
                },
            })
            .map_err(|e| NodeError::Spawn(e.to_string()))?;
        let generation = self.next_generation;
        self.next_generation += 1;
        let info = TerminalInfo {
            id: id.clone(),
            cwd: cwd.to_string_lossy().into_owned(),
            command,
            pid: child.session.pid(),
            cols: size.cols,
            rows: size.rows,
            alive: true,
            exit_code: None,
        };
        tokio::spawn(forward(
            id.clone(),
            generation,
            child.events,
            self.inbox.clone(),
        ));
        self.nodes.insert(
            id,
            Node {
                info: info.clone(),
                address,
                launched: SystemTime::now(),
                hooked: false,
                generation,
                session: Some(child.session),
                screen,
                dirty: false,
            },
        );
        self.publish_terminals();
        Ok(info)
    }

    fn fresh_id(&mut self) -> NodeId {
        loop {
            let n = self.next_node;
            self.next_node += 1;
            if let Ok(id) = NodeId::new(format!("t{n}"))
                && !self.nodes.contains_key(&id)
            {
                return id;
            }
        }
    }

    /// Entrada do usuário ou injeção: a vista desce ao fim antes, como o
    /// `ensureCaretIsVisible` do `TerminalView.send` no SwiftTerm.
    pub(super) fn write(&mut self, node: &NodeId, bytes: &[u8]) -> Result<(), NodeError> {
        if let Some(n) = self.nodes.get_mut(node) {
            n.screen.scroll(Scroll::Bottom);
            n.dirty = true;
        }
        self.write_raw(node, bytes)
    }

    /// Bytes que não rolam a vista: o relatório de mouse vai direto ao
    /// programa, como no SwiftTerm.
    pub(super) fn write_raw(&self, node: &NodeId, bytes: &[u8]) -> Result<(), NodeError> {
        let n = self
            .nodes
            .get(node)
            .ok_or_else(|| NodeError::Unknown(node.clone()))?;
        let session = n
            .session
            .as_ref()
            .ok_or_else(|| NodeError::Exited(node.clone()))?;
        if bytes.is_empty() {
            return Ok(());
        }
        session
            .write(bytes)
            .map_err(|e| NodeError::Pty(e.to_string()))
    }

    fn resize(&mut self, id: &NodeId, size: Size) -> Result<(), NodeError> {
        if size.cols == 0 || size.rows == 0 {
            return Err(NodeError::BadSize(size));
        }
        let node = self
            .nodes
            .get_mut(id)
            .ok_or_else(|| NodeError::Unknown(id.clone()))?;
        if node.info.size() == size {
            return Ok(());
        }
        node.screen
            .resize(size)
            .map_err(|e| NodeError::Screen(e.to_string()))?;
        if let Some(session) = &node.session {
            session
                .resize(PtySize {
                    cols: size.cols,
                    rows: size.rows,
                })
                .map_err(|e| NodeError::Pty(e.to_string()))?;
        }
        node.info.cols = size.cols;
        node.info.rows = size.rows;
        node.dirty = true;
        self.publish_terminals();
        Ok(())
    }

    fn close(&mut self, id: &NodeId) -> Result<(), NodeError> {
        let node = self
            .nodes
            .remove(id)
            .ok_or_else(|| NodeError::Unknown(id.clone()))?;
        if let Some(session) = node.session {
            let reason = format!("terminal {id} removido");
            tokio::spawn(remove(session, self.drivers.procs.clone(), reason));
        }
        for c in self.clients.values_mut() {
            c.topics.remove(&Topic::Screen(id.clone()));
            c.resync.remove(id);
        }
        self.publish_terminals();
        Ok(())
    }

    fn live(&mut self, id: &NodeId, generation: u64) -> Option<&mut Node> {
        self.nodes
            .get_mut(id)
            .filter(|n| n.generation == generation)
    }

    fn output(&mut self, id: NodeId, generation: u64, bytes: &[u8]) {
        let Some(node) = self.live(&id, generation) else {
            return;
        };
        node.screen.feed(bytes);
        node.dirty = true;
        let answer = node.screen.take_responses();
        if !answer.is_empty()
            && let Some(session) = &node.session
            && let Err(err) = session.write(&answer)
        {
            crate::log!("terminal[{id}]: resposta ao programa perdida: {err}");
        }
        // Depois da tela: o sino e o OSC 52 que o programa mandou, e o
        // marcador que o dispatch lê.
        self.screen_effects(&id);
        self.dispatch_output(&id, SystemTime::now());
    }

    fn exited(&mut self, id: NodeId, generation: u64, exit: PtyExit) {
        let Some(node) = self.live(&id, generation) else {
            return;
        };
        node.info.alive = false;
        node.info.exit_code = Some(match exit {
            PtyExit::Code(code) => code,
            // Como o shell conta: 128 + o sinal.
            PtyExit::Signal(sig) => 128 + sig,
        });
        node.session = None;
        self.publish_terminals();
    }

    /// Larga os clientes e entrega as sessões vivas para serem encerradas.
    fn shutdown(&mut self) -> Vec<Box<dyn PtySession>> {
        self.clients.clear();
        std::mem::take(&mut self.nodes)
            .into_values()
            .filter_map(|n| n.session)
            .collect()
    }
}

/// O que um nó devolve de erro; a rota traduz em status.
#[derive(Debug, thiserror::Error)]
pub enum NodeError {
    #[error("terminal desconhecido '{0}'")]
    Unknown(NodeId),
    #[error("o processo de '{0}' já terminou")]
    Exited(NodeId),
    #[error("tamanho inválido: {}×{}", .0.cols, .0.rows)]
    BadSize(Size),
    #[error("a tela recusou: {0}")]
    Screen(String),
    #[error("não foi possível lançar o terminal: {0}")]
    Spawn(String),
    #[error("pty: {0}")]
    Pty(String),
}

impl NodeError {
    fn status(&self) -> u16 {
        match self {
            Self::Unknown(_) => 404,
            Self::Exited(_) => 409,
            Self::BadSize(_) => 400,
            Self::Screen(_) | Self::Spawn(_) | Self::Pty(_) => 500,
        }
    }
}

fn encode<T: serde::Serialize>(msg: &T) -> Option<WireLine> {
    match to_line(msg) {
        Ok(bytes) => Some(bytes.into()),
        Err(err) => {
            crate::log!("ui: mensagem sem serializar: {err}");
            None
        }
    }
}

fn merge<T: serde::Serialize>(target: &mut Value, extra: &T) {
    if let (Value::Object(into), Ok(Value::Object(from))) = (target, serde_json::to_value(extra)) {
        into.extend(from);
    }
}

/// Leva os eventos de um pty ao ator. Esperar no `send` é de propósito: com a
/// fila do ator cheia, o leitor do pty para de ler e o programa espera, em vez
/// de a memória crescer.
async fn forward(
    node: NodeId,
    generation: u64,
    mut events: mpsc::Receiver<PtyEvent>,
    inbox: mpsc::Sender<Msg>,
) {
    while let Some(event) = events.recv().await {
        let msg = Msg::Pty {
            node: node.clone(),
            generation,
            event,
        };
        if inbox.send(msg).await.is_err() {
            return;
        }
    }
}

/// Como `TerminalNode.prepareForRemoval`: a árvore antes do shell. Morto
/// ele, os filhos já são do launchd e não se sabe mais de qual nó eram — e
/// sem isso um trabalho do zsh que ignora o HUP, ou um comando que o Bash de
/// um agente pôs noutro grupo, sobrevive ao nó.
async fn remove(session: Box<dyn PtySession>, procs: Arc<dyn ProcessDriver>, reason: String) {
    let pid = session.pid();
    let _ =
        tokio::task::spawn_blocking(move || tree::terminate_tree(procs, pid, TREE_GRACE, &reason))
            .await;
    hang_up_all(vec![session]).await;
}

/// O mesmo de [`remove`] para todos, com uma diferença: o SIGKILL em quem
/// ignorou o SIGTERM sai daqui, e não da thread que `terminate_tree` deixa
/// esperando, que morreria junto com o processo, que sai logo depois.
///
/// Divergência do Swift: o `applicationWillTerminate` de lá não mexe em
/// processo nenhum, e o trabalho do zsh que ignora o HUP sobrevivia ao app.
/// Aqui o core é o processo que a UI encerra (decisão 21), e fechar o app
/// promete fechar os terminais inteiros.
async fn shut_down(sessions: Vec<Box<dyn PtySession>>, procs: Arc<dyn ProcessDriver>) {
    let mut reading = Vec::new();
    for session in &sessions {
        let pid = session.pid();
        let procs = procs.clone();
        reading.push(tokio::task::spawn_blocking(move || {
            tree::terminate_tree(procs, pid, Duration::ZERO, "app encerrando")
        }));
    }
    let mut victims = Vec::new();
    for read in reading {
        victims.extend(read.await.unwrap_or_default());
    }
    hang_up_all(sessions).await;
    if !victims.is_empty() {
        let _ = tokio::task::spawn_blocking(move || {
            tree::kill_stubborn(&*procs, &victims, "app encerrando");
        })
        .await;
    }
}

/// HUP primeiro, e o KILL ao grupo só depois de um tempo: o zsh interativo põe
/// cada trabalho num grupo próprio, e é o HUP que ele repassa a eles — o KILL
/// direto mataria o shell e deixaria os trabalhos de pé.
async fn hang_up_all(sessions: Vec<Box<dyn PtySession>>) {
    if sessions.is_empty() {
        return;
    }
    for session in &sessions {
        let _ = session.signal(PtySignal::Hangup);
        // O `process.terminate()` do Swift (TerminalNode.swift:386): o SIGTERM
        // na raiz, antes da espera, para quem o respeita sair por conta
        // própria (um agente grava a conversa ao sair).
        let _ = session.signal(PtySignal::Terminate);
    }
    tokio::time::sleep(KILL_GRACE).await;
    // Grupo que já morreu devolve erro, e está tudo bem.
    for session in &sessions {
        let _ = session.signal(PtySignal::Kill);
    }
}

//! O chat dentro do runtime (decisão 29): o que o ator faz com a thread, sem o
//! ator. Esta é a parte que não conhece `Actor`: fala com ele por [`ChatHost`] e
//! devolve [`Out`] — respostas, linhas do canal `/ui` e **jobs** de disco.
//!
//! # Disco nunca no ator
//!
//! Tudo que lê ou grava arquivo é um job de dados puros ([`ChatJob`]): o ator o
//! cria, o runtime o roda em `spawn_blocking` ([`ChatJob::run`]) e devolve o
//! [`ChatDone`] ao ator, que chama [`ChatRuntime::done`]. Entre os dois só há
//! estado em memória.
//!
//! - [`RefreshJob`]: o `chat.jsonl` (só se mudou) e a cauda ao vivo do transcript
//!   de cada agente que trabalha;
//! - [`RecordJob`]: no `Stop`, o último turno do transcript vai para o histórico;
//! - [`ArchiveJob`]: "limpar a conversa";
//! - [`UsageJob`]: o consumo, a cada ~8 s e no `Stop`;
//! - [`CompleteJob`]: a lista de `/` de um agente (varre pastas).
//!
//! # O vigia
//!
//! Sem port de arquivo alterado: o ator chama [`ChatRuntime::tick`] a cada 300 ms
//! e, enquanto algum agente do chat trabalha, o job compara tamanho e data do
//! transcript — o que o Swift também fazia (e limitava a 0,3 s por leitura).

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use serde_json::{Value, json};

use super::model::{ChatRecord, ChatTurn};
use super::parsers::{mention, slash};
use super::routes::{ChatEffect, ChatRoutes};
use super::store::{self, ChatHistory};
use super::thread::{ChatParticipant, QueueInfo};
use super::time::Offset;
use super::view::{ChatUpdate, ThreadInput};
use crate::features::activity::model::Activity;
use crate::features::agent::claude::command_registry::CommandRegistry;
use crate::features::agent::claude::slash_catalog;
use crate::features::agent::claude::transcript::{self, Context, LIVE_TAIL_BYTES, LiveTurn};
use crate::features::agent::model::AgentProfile;
use crate::features::agent::slash::{SlashCommand, SlashSource};
use crate::features::node::model::NodeConfig;
use crate::features::queue::chat::ChatQueue;
use crate::features::usage::ledger::UsageLedger;
use crate::features::usage::store::{Source as UsageSource, UsageStore};
use crate::features::usage::{PriceTable, routes::UsageRoutes};

/// De quanto em quanto tempo a cauda ao vivo é relida, no máximo.
pub const LIVE_EVERY: Duration = Duration::from_millis(300);
/// Quanto o turno ao vivo fica na tela depois do `Stop`, esperando o histórico
/// trazer o gravado.
pub const LIVE_LINGER: Duration = Duration::from_secs(20);
/// De quanto em quanto tempo o consumo é relido.
pub const USAGE_EVERY: Duration = Duration::from_secs(8);

// ---------------------------------------------------------------------------
// O que o runtime pergunta ao ator
// ---------------------------------------------------------------------------

/// Uma bancada como o chat a vê.
#[derive(Debug, Clone)]
pub struct BenchInfo {
    pub id: String,
    pub name: String,
    /// `canvas` ou `chat`.
    pub mode: String,
    pub nodes: Vec<NodeConfig>,
}

/// Onde mora a conversa de um agente: o transcript que o gancho `/conversation`
/// relatou e o instante do último `prompt` (turno mais velho que isso não é o
/// em curso).
#[derive(Debug, Clone, PartialEq)]
pub struct Source {
    pub path: PathBuf,
    pub not_before: Option<SystemTime>,
}

/// O carimbo de um turno gravado.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Identity {
    pub conversation: Option<String>,
    pub cli: Option<String>,
    pub model: Option<String>,
}

/// Do que a lista de `/` de um agente é feita.
#[derive(Debug, Clone)]
pub struct SlashInputs {
    pub profile: AgentProfile,
    pub node_config: Option<String>,
    pub cwd: PathBuf,
    pub transcript: Option<PathBuf>,
    pub binary: Option<CommandRegistry>,
    pub home: PathBuf,
}

/// O que o ator entrega ao chat. Só leituras de memória — nada de disco.
pub trait ChatHost {
    fn benches(&self) -> Vec<BenchInfo>;
    fn activity(&self, address: &str) -> Option<Activity>;
    fn source(&self, workbench: &str, node: &str) -> Option<Source>;
    fn identity(&self, workbench: &str, node: &str) -> Identity;
    /// O pedido de permissão em aberto da bancada, para a bandeja.
    fn permission(&self, workbench: &str) -> Option<Value>;
    fn slash(&self, workbench: &str, node: &str) -> Option<SlashInputs>;
    /// A tabela de preços em vigor.
    fn prices(&self) -> PriceTable;
    /// As filas da bancada, para a seção FILAS da coluna. Sem filas por padrão.
    fn queues(&self, _workbench: &str) -> Vec<ChatQueue> {
        Vec::new()
    }
}

// ---------------------------------------------------------------------------
// O que o runtime devolve ao ator
// ---------------------------------------------------------------------------

/// A resposta de um comando ou rota, pelo `token` que o ator deu.
#[derive(Debug, Clone, PartialEq)]
pub enum Answer {
    Ok(Value),
    Err { status: u16, message: String },
}

impl Answer {
    fn err(status: u16, message: impl Into<String>) -> Answer {
        Answer::Err {
            status,
            message: message.into(),
        }
    }
}

/// Uma mensagem a entregar a um agente; depois de entregue o ator chama
/// [`ChatRuntime::sent`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Delivery {
    pub workbench: String,
    pub node: String,
    pub text: String,
}

#[derive(Debug, Default)]
pub struct Out {
    /// `(token, resposta)`.
    pub replies: Vec<(u64, Answer)>,
    /// `(tópico, linha NDJSON)` para quem assina o tópico.
    pub publish: Vec<(String, String)>,
    pub deliveries: Vec<Delivery>,
    pub jobs: Vec<(u64, ChatJob)>,
    /// As bancadas cujo registro de consumo mudou: o ator publica o painel.
    pub usage: Vec<String>,
}

impl Out {
    fn publish_update(&mut self, update: &ChatUpdate) {
        if let Ok(mut line) = serde_json::to_string(update) {
            line.push('\n');
            self.publish.push((update.topic.clone(), line));
        }
    }

    fn effects(&mut self, effects: Vec<ChatEffect>, rebuild: &mut BTreeSet<String>) {
        for effect in effects {
            match effect {
                ChatEffect::Ui(update) => self.publish_update(&update),
                ChatEffect::Rebuild { workbench } => {
                    rebuild.insert(workbench);
                }
                ChatEffect::Send {
                    workbench,
                    target,
                    text,
                } => self.deliveries.push(Delivery {
                    workbench,
                    node: target,
                    text,
                }),
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Jobs
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Stamp {
    pub size: u64,
    pub modified: SystemTime,
}

fn stamp_of(path: &std::path::Path) -> Option<Stamp> {
    let meta = fs::metadata(path).ok()?;
    Some(Stamp {
        size: meta.len(),
        modified: meta.modified().ok()?,
    })
}

#[derive(Debug, Clone)]
struct LiveRead {
    node: String,
    path: PathBuf,
    not_before: Option<SystemTime>,
    from: u64,
    cached: Option<Stamp>,
}

#[derive(Debug)]
pub struct RefreshJob {
    workbench: String,
    history: PathBuf,
    history_stamp: Option<Stamp>,
    lives: Vec<LiveRead>,
    prices: PriceTable,
    now: SystemTime,
}

#[derive(Debug)]
pub struct LiveDone {
    node: String,
    stamp: Option<Stamp>,
    /// `None` com `unchanged`: o arquivo é o mesmo, vale o que se tinha.
    live: Option<LiveTurn>,
    unchanged: bool,
}

#[derive(Debug)]
pub struct RefreshResult {
    workbench: String,
    history: Option<(Option<Stamp>, Vec<ChatRecord>)>,
    lives: Vec<LiveDone>,
}

impl RefreshJob {
    fn run(self) -> RefreshResult {
        let history = {
            let now = stamp_of(&self.history);
            if now.is_some() && now == self.history_stamp {
                None
            } else {
                Some((now, store::read(&self.history)))
            }
        };
        let ctx = Context {
            now: self.now,
            prices: &self.prices,
        };
        let lives = self
            .lives
            .into_iter()
            .map(|read| {
                let stamp = stamp_of(&read.path);
                if stamp.is_some() && stamp == read.cached {
                    return LiveDone {
                        node: read.node,
                        stamp,
                        live: None,
                        unchanged: true,
                    };
                }
                // A partir do prompt do turno já conhecido: só o turno em curso é
                // relido, não os 4 MB de cauda.
                let live = transcript::live_turn(
                    &read.path,
                    read.not_before,
                    read.from,
                    LIVE_TAIL_BYTES,
                    &ctx,
                );
                LiveDone {
                    node: read.node,
                    stamp,
                    live,
                    unchanged: false,
                }
            })
            .collect();
        RefreshResult {
            workbench: self.workbench,
            history,
            lives,
        }
    }
}

/// No `Stop`: o último turno do transcript vira uma linha do histórico. A leitura
/// chega a MB, por isso é job.
#[derive(Debug)]
pub struct RecordJob {
    workbench: String,
    workbenches_dir: PathBuf,
    clock_offset: Offset,
    node: String,
    identity: Identity,
    transcript: PathBuf,
    not_before: Option<SystemTime>,
    prices: PriceTable,
    now: SystemTime,
}

impl RecordJob {
    fn run(self) -> bool {
        let ctx = Context {
            now: self.now,
            prices: &self.prices,
        };
        // Só o Claude Code grava transcript hoje; outro CLI entra pelo leitor do
        // perfil dele, quando existir.
        let Some(turn) = transcript::last_turn(
            &self.transcript,
            self.not_before,
            transcript::LAST_TURN_TAIL_BYTES,
            &ctx,
        ) else {
            return false;
        };
        let record = ChatRecord {
            node: self.node,
            conversation: self.identity.conversation,
            cli: self.identity.cli,
            model: self.identity.model,
            turn,
        };
        let mut history = ChatHistory::new(self.workbenches_dir, self.clock_offset);
        history.append(&record, &self.workbench);
        true
    }
}

#[derive(Debug)]
pub struct ArchiveJob {
    workbench: String,
    name: String,
    workbenches_dir: PathBuf,
    clock_offset: Offset,
    now: SystemTime,
}

#[derive(Debug)]
pub struct UsageJob {
    store: UsageStore,
    sources: BTreeMap<String, Vec<UsageSource>>,
    prices: PriceTable,
}

#[derive(Debug)]
pub struct CompleteJob {
    inputs: SlashInputs,
    query: String,
    search: String,
    range: (usize, usize),
}

#[derive(Debug)]
pub enum ChatJob {
    Refresh(RefreshJob),
    Record(RecordJob),
    Archive(ArchiveJob),
    Usage(UsageJob),
    Complete(Box<CompleteJob>),
    /// Um job que sempre dá pânico, para provar que o runtime se recompõe.
    #[cfg(test)]
    Boom,
}

#[derive(Debug)]
pub enum ChatDone {
    Refresh(RefreshResult),
    Record {
        workbench: String,
        wrote: bool,
    },
    Archive {
        workbench: String,
        name: String,
        archived: Option<PathBuf>,
    },
    Usage {
        store: UsageStore,
        changed: BTreeMap<String, UsageLedger>,
    },
    Complete {
        items: Vec<SlashCommand>,
        range: (usize, usize),
    },
}

/// O que um job era, guardado antes de ele rodar: se o job morrer (pânico no
/// `spawn_blocking`), é com isto que o runtime se recompõe — ninguém fica
/// esperando, e a bancada não fica presa em "lendo".
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JobKind {
    Refresh {
        workbench: String,
    },
    Record,
    Archive,
    Usage,
    Complete,
    #[cfg(test)]
    Boom,
}

impl ChatJob {
    pub fn kind(&self) -> JobKind {
        match self {
            ChatJob::Refresh(job) => JobKind::Refresh {
                workbench: job.workbench.clone(),
            },
            ChatJob::Record(_) => JobKind::Record,
            ChatJob::Archive(_) => JobKind::Archive,
            ChatJob::Usage(_) => JobKind::Usage,
            ChatJob::Complete(_) => JobKind::Complete,
            #[cfg(test)]
            ChatJob::Boom => JobKind::Boom,
        }
    }

    /// Bloqueante (disco): o runtime chama de `spawn_blocking`.
    pub fn run(self) -> ChatDone {
        match self {
            ChatJob::Refresh(job) => ChatDone::Refresh(job.run()),
            ChatJob::Record(job) => {
                let workbench = job.workbench.clone();
                ChatDone::Record {
                    wrote: job.run(),
                    workbench,
                }
            }
            ChatJob::Archive(job) => {
                let mut history = ChatHistory::new(job.workbenches_dir, job.clock_offset);
                let archived = history.archive(&job.workbench, job.now);
                ChatDone::Archive {
                    workbench: job.workbench,
                    name: job.name,
                    archived,
                }
            }
            ChatJob::Usage(mut job) => {
                let changed = job.store.refresh(&job.sources, &job.prices);
                ChatDone::Usage {
                    store: job.store,
                    changed,
                }
            }
            #[cfg(test)]
            ChatJob::Boom => panic!("job de mentira"),
            ChatJob::Complete(job) => {
                let all = slash_catalog::commands_for_profile(
                    &job.inputs.profile,
                    job.inputs.node_config.as_deref(),
                    &job.inputs.cwd,
                    job.inputs.transcript.as_deref(),
                    job.inputs.binary.as_ref(),
                    &job.inputs.home,
                )
                .unwrap_or_default();
                let found =
                    SlashCommand::searching(&SlashCommand::matching(&all, &job.query), &job.search);
                ChatDone::Complete {
                    items: found,
                    range: job.range,
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// O runtime
// ---------------------------------------------------------------------------

struct HistoryCache {
    stamp: Option<Stamp>,
    records: Vec<ChatRecord>,
}

struct LiveEntry {
    stamp: Option<Stamp>,
    live: Option<LiveTurn>,
    read_at: SystemTime,
}

/// O que `chat_complete` pede (decisão 29): o texto da caixa e o cursor, em UTF-16.
/// O gatilho — `@` no meio do texto ou `/` no começo — e a consulta saem do texto,
/// pelos mesmos leitores do composer do Swift.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Complete {
    pub workbench: String,
    pub text: String,
    pub caret: usize,
    /// O agente cuja lista de `/` se quer; sem ele, o foco.
    pub to: Option<String>,
    /// A barra de busca da lista de `/`.
    pub search: Option<String>,
}

fn complete_answer(items: &[Value], range: (usize, usize)) -> Value {
    json!({"items": items, "range": [range.0, range.1]})
}

fn slash_item(command: &SlashCommand) -> Value {
    // Com apelidos o nome vem com eles, como a lista do Swift.
    let label = if command.aliases.is_empty() {
        command.name.clone()
    } else {
        format!("{} ({})", command.name, command.aliases.join(", "))
    };
    json!({"label": label, "insert": format!("/{} ", command.name),
           "detail": command.detail, "kind": source_name(&command.source)})
}

pub struct ChatRuntime {
    routes: ChatRoutes,
    usage: Option<UsageStore>,
    usage_dirs: (PathBuf, PathBuf),
    usage_routes: UsageRoutes,
    usage_flying: bool,
    usage_at: Option<SystemTime>,
    workbenches_dir: PathBuf,
    clock_offset: Offset,
    histories: BTreeMap<String, HistoryCache>,
    lives: BTreeMap<(String, String), LiveEntry>,
    refreshed: BTreeMap<String, SystemTime>,
    flying: BTreeSet<String>,
    dirty: BTreeSet<String>,
}

impl ChatRuntime {
    /// `workbenches_dir` é `<home>/workbenches`; `clock_offset`, o fuso do nome dos
    /// arquivos arquivados; `usage`, o registro de consumo já aberto.
    pub fn new(workbenches_dir: PathBuf, clock_offset: Offset, usage: UsageStore) -> ChatRuntime {
        ChatRuntime {
            routes: ChatRoutes::new(ChatHistory::new(workbenches_dir.clone(), clock_offset)),
            usage_routes: UsageRoutes {
                ledgers: BTreeMap::new(),
                prices: PriceTable::from_built_in(),
                workbenches: Vec::new(),
            },
            usage_dirs: usage.dirs(),
            usage: Some(usage),
            usage_flying: false,
            usage_at: None,
            workbenches_dir,
            clock_offset,
            histories: BTreeMap::new(),
            lives: BTreeMap::new(),
            refreshed: BTreeMap::new(),
            flying: BTreeSet::new(),
            dirty: BTreeSet::new(),
        }
    }

    pub fn routes(&self) -> &ChatRoutes {
        &self.routes
    }

    pub fn routes_mut(&mut self) -> &mut ChatRoutes {
        &mut self.routes
    }

    /// O agente a que a fila nova da bancada nasce ligada; `None` sem agente.
    pub fn new_queue_agent(&self, workbench: &str) -> Option<String> {
        self.routes.new_queue_agent(workbench)
    }

    pub fn usage_routes(&mut self) -> &mut UsageRoutes {
        &mut self.usage_routes
    }

    /// Alinha o que o chat guarda com o que o ator tem agora: as bancadas, a barra
    /// de participantes e a bandeja. Memória pura; devolve o que mudou.
    pub fn sync(&mut self, host: &dyn ChatHost, out: &mut Out) {
        let benches = host.benches();
        let known: BTreeSet<String> = benches.iter().map(|b| b.id.clone()).collect();
        for gone in self
            .routes
            .ids()
            .filter(|id| !known.contains(*id))
            .map(str::to_owned)
            .collect::<Vec<_>>()
        {
            self.routes.forget(&gone);
            self.histories.remove(&gone);
            self.lives.retain(|(wb, _), _| wb != &gone);
        }
        self.usage_routes.workbenches = benches
            .iter()
            .map(|b| (b.id.clone(), b.name.clone()))
            .collect();
        for bench in &benches {
            self.routes.register(&bench.id, &bench.name, &bench.mode);
            let participants = ChatParticipant::from_nodes(&bench.nodes, &bench.name, |address| {
                host.activity(address)
            });
            let before = self.routes.participants(&bench.id).to_vec();
            if before != participants {
                self.dirty.insert(bench.id.clone());
            }
            let effects = self.routes.set_participants(&bench.id, participants);
            let permission = self
                .routes
                .set_permission(&bench.id, host.permission(&bench.id));
            let queues: Vec<QueueInfo> =
                host.queues(&bench.id).iter().map(QueueInfo::from).collect();
            let queues = self.routes.set_queues(&bench.id, queues);
            let mut rebuild = BTreeSet::new();
            out.effects(effects, &mut rebuild);
            out.effects(queues, &mut rebuild);
            out.effects(permission, &mut rebuild);
        }
    }

    /// A UI assinou `chat/<id>`: o `reset` com tudo, e uma leitura para trazer o
    /// histórico se ainda não está na memória. `None` é bancada desconhecida.
    pub fn subscribe(
        &mut self,
        host: &dyn ChatHost,
        workbench: &str,
        now: SystemTime,
    ) -> Option<Out> {
        let mut out = Out::default();
        self.sync(host, &mut out);
        self.routes.view(workbench)?;
        self.dirty.insert(workbench.to_owned());
        self.settle(host, now, &mut out);
        let update = self.routes.reset_update(workbench)?;
        // O assinante recebe só o reset, não os eventos de sync acima — que eram
        // para quem já assinava.
        out.publish.retain(|(topic, _)| *topic != update.topic);
        out.publish_update(&update);
        self.plan_refresh(host, workbench, now, &mut out);
        Some(out)
    }

    /// `chat_snapshot`.
    pub fn snapshot(&self, workbench: &str) -> Option<Value> {
        self.routes.snapshot_of(workbench)
    }

    /// `chat_step`.
    pub fn step(
        &mut self,
        host: &dyn ChatHost,
        workbench: &str,
        block: &str,
        now: SystemTime,
    ) -> Out {
        let mut out = Out::default();
        let effects = self.routes.step(workbench, block);
        self.apply_effects(host, effects, now, &mut out);
        out
    }

    /// `chat_more`: o usuário rolou até o topo.
    pub fn more(&mut self, host: &dyn ChatHost, workbench: &str, now: SystemTime) -> Out {
        let mut out = Out::default();
        let effects = self.routes.more(workbench);
        self.apply_effects(host, effects, now, &mut out);
        out
    }

    /// Os efeitos que um handler de rota devolveu (`/chat`, `/compose`): remonta o
    /// que pediram, publica o que for do canal e devolve as entregas.
    pub fn effects(
        &mut self,
        host: &dyn ChatHost,
        effects: Vec<ChatEffect>,
        now: SystemTime,
    ) -> Out {
        let mut out = Out::default();
        self.apply_effects(host, effects, now, &mut out);
        out
    }

    /// `chat_send`: devolve as entregas; o ator as faz e chama [`ChatRuntime::sent`].
    pub fn send(&mut self, workbench: &str, to: &[String], text: &str) -> Out {
        let mut out = Out::default();
        let effects = self.routes.send(workbench, to, text);
        let mut rebuild = BTreeSet::new();
        out.effects(effects, &mut rebuild);
        out
    }

    /// O ator entregou: o eco entra na thread até o transcript confirmar.
    pub fn sent(
        &mut self,
        host: &dyn ChatHost,
        workbench: &str,
        node: &str,
        text: &str,
        now: SystemTime,
    ) -> Out {
        let known: BTreeSet<String> = self.known_turns(workbench, node);
        self.routes.sent(workbench, text, node, now, known);
        self.dirty.insert(workbench.to_owned());
        let mut out = Out::default();
        self.settle(host, now, &mut out);
        out
    }

    /// `chat_clear` e `/chat/clear`: arquivar a conversa corrente. A resposta sai
    /// quando o job termina (`token`).
    pub fn clear(&mut self, token: u64, by_name: bool, who: &str, now: SystemTime) -> Out {
        let mut out = Out::default();
        let bench = self
            .routes
            .bench_ids()
            .find(|(id, name)| if by_name { *name == who } else { *id == who })
            .map(|(id, name)| (id.to_owned(), name.to_owned()));
        let Some((id, name)) = bench else {
            let message = format!("bancada desconhecida '{who}'");
            out.replies.push((token, Answer::err(404, message)));
            return out;
        };
        out.jobs.push((
            token,
            ChatJob::Archive(ArchiveJob {
                workbench: id,
                name,
                workbenches_dir: self.workbenches_dir.clone(),
                clock_offset: self.clock_offset,
                now,
            }),
        ));
        out
    }

    /// Arquiva a conversa corrente da bancada, pelo caminho do `clearWorkbench`
    /// (que não passa pelo chat): devolve para onde foi, ou `None` se estava
    /// vazia. Faz disco — chame de onde bloquear for aceitável, ou use
    /// [`ChatRuntime::clear`], que vira job.
    pub fn archive_now(&self, workbench: &str, now: SystemTime) -> Option<PathBuf> {
        ChatHistory::new(self.workbenches_dir.clone(), self.clock_offset).archive(workbench, now)
    }

    /// O `clearedHistory()` do Swift: o eco local, o turno ao vivo e o que estava
    /// aberto vão embora, e a UI vê a thread esvaziar.
    pub fn cleared(&mut self, workbench: &str) -> Out {
        let mut out = Out::default();
        self.histories.remove(workbench);
        self.lives.retain(|(wb, _), _| wb != workbench);
        let effects = self.routes.cleared(workbench);
        let mut want = BTreeSet::new();
        out.effects(effects, &mut want);
        out
    }

    /// `chat_complete{workbench, text, caret}` → `{items:[{label, insert, detail?,
    /// kind}], range:[ini, fim]}`; `range` é o trecho do texto que a escolha
    /// substitui. `@` responde na hora; `/` varre pastas e vira job. Sem gatilho
    /// no cursor, a lista vem vazia.
    pub fn complete(&mut self, host: &dyn ChatHost, token: u64, request: &Complete) -> Out {
        let mut out = Out::default();
        let Some(participants) = self
            .routes
            .view(&request.workbench)
            .map(|_| self.routes.participants(&request.workbench).to_vec())
        else {
            let message = format!("bancada desconhecida '{}'", request.workbench);
            out.replies.push((token, Answer::err(404, message)));
            return out;
        };
        let alive: Vec<&ChatParticipant> = participants
            .iter()
            .filter(|p| p.is_agent && p.activity != Activity::Dead)
            .collect();
        let empty = Answer::Ok(complete_answer(&[], (request.caret, request.caret)));

        // O `/` vale só no começo da mensagem e até o primeiro espaço.
        if let Some(query) = slash::active_query(&request.text, request.caret) {
            let end = request
                .text
                .split(char::is_whitespace)
                .next()
                .map_or(0, |w| w.encode_utf16().count());
            let range = (0, end);
            let target = request
                .to
                .clone()
                .or_else(|| self.routes.focused(&request.workbench))
                .or_else(|| alive.first().map(|p| p.id.clone()));
            let inputs = target.and_then(|node| host.slash(&request.workbench, &node));
            match inputs {
                Some(inputs) => out.jobs.push((
                    token,
                    ChatJob::Complete(Box::new(CompleteJob {
                        inputs,
                        query,
                        search: request.search.clone().unwrap_or_default().trim().to_owned(),
                        range,
                    })),
                )),
                // Terminal sem lista de `/` (outro CLI): vazio, como o Swift.
                None => out
                    .replies
                    .push((token, Answer::Ok(complete_answer(&[], range)))),
            }
            return out;
        }
        if let Some(active) = mention::active_mention(&request.text, request.caret) {
            let names: Vec<String> = alive.iter().map(|p| p.id.clone()).collect();
            let items: Vec<Value> = mention::candidates(&names, &active.query)
                .into_iter()
                .map(|name| {
                    let address = alive
                        .iter()
                        .find(|p| p.id == name)
                        .map(|p| p.address.clone())
                        .unwrap_or_default();
                    json!({"label": format!("@{name}"), "insert": format!("@{name} "),
                           "detail": address, "kind": "agent"})
                })
                .collect();
            let range = (
                active.range.location,
                active.range.location + active.range.length,
            );
            out.replies
                .push((token, Answer::Ok(complete_answer(&items, range))));
            return out;
        }
        out.replies.push((token, empty));
        out
    }

    /// O `Stop` de um agente: grava o turno e relê o consumo.
    pub fn turn_ended(&mut self, host: &dyn ChatHost, address: &str, now: SystemTime) -> Out {
        let mut out = Out::default();
        let Some((workbench, node)) = address.split_once('/') else {
            return out;
        };
        let Some(bench) = host.benches().into_iter().find(|b| b.name == workbench) else {
            return out;
        };
        if !bench
            .nodes
            .iter()
            .any(|n| n.id == node && n.kind == crate::features::node::model::NodeKind::Agent)
        {
            return out;
        }
        if let Some(source) = host.source(&bench.id, node) {
            out.jobs.push((
                0,
                ChatJob::Record(RecordJob {
                    workbench: bench.id.clone(),
                    workbenches_dir: self.workbenches_dir.clone(),
                    clock_offset: self.clock_offset,
                    node: node.to_owned(),
                    identity: host.identity(&bench.id, node),
                    transcript: source.path,
                    not_before: source.not_before,
                    prices: host.prices(),
                    now,
                }),
            ));
        }
        self.plan_usage(host, now, true, &mut out);
        out
    }

    /// O relógio de 300 ms do runtime: remonta o que mudou (sem disco), e relê a
    /// cauda enquanto algum agente trabalha.
    pub fn tick(&mut self, host: &dyn ChatHost, now: SystemTime) -> Out {
        let mut out = Out::default();
        self.sync(host, &mut out);
        let chat_benches: Vec<BenchInfo> = host
            .benches()
            .into_iter()
            .filter(|b| b.mode == "chat")
            .collect();
        for bench in &chat_benches {
            let working =
                self.routes.participants(&bench.id).iter().any(|p| {
                    p.is_agent && matches!(p.activity, Activity::Working | Activity::Asking)
                });
            let due = self
                .refreshed
                .get(&bench.id)
                .is_none_or(|at| now.duration_since(*at).unwrap_or_default() >= LIVE_EVERY);
            if working && due {
                self.plan_refresh(host, &bench.id, now, &mut out);
            }
        }
        self.settle(host, now, &mut out);
        self.plan_usage(host, now, false, &mut out);
        out
    }

    /// A rota `/usage`.
    pub fn usage_route(
        &mut self,
        host: &dyn ChatHost,
        req: &crate::protocol::handler::RouteRequest,
        now: SystemTime,
    ) -> (
        crate::protocol::handler::RouteReply,
        Vec<crate::features::usage::routes::UsageEffect>,
    ) {
        let mut sink = Out::default();
        self.sync(host, &mut sink);
        self.usage_routes.prices = host.prices();
        crate::features::usage::routes::usage(&mut self.usage_routes, req, now)
    }

    /// A pílula e o painel de uma bancada, do que o registro tem na memória agora —
    /// o ator publica isto a cada refresh do consumo. `None` se a bancada não existe.
    pub fn usage_state(
        &mut self,
        host: &dyn ChatHost,
        workbench: &str,
    ) -> Option<(
        crate::features::usage::panel::Pill,
        crate::features::usage::panel::Panel,
    )> {
        use crate::features::usage::{panel, store::pricing_file};
        let mut sink = Out::default();
        self.sync(host, &mut sink);
        self.usage_routes.prices = host.prices();
        let name = self
            .usage_routes
            .workbenches
            .iter()
            .find(|(id, _)| id == workbench)
            .map(|(_, name)| name.clone())?;
        let ledger = self
            .usage_routes
            .ledgers
            .get(workbench)
            .cloned()
            .unwrap_or_default();
        let prices = &self.usage_routes.prices;
        let (home, user_home) = &self.usage_dirs;
        Some((
            panel::pill(&ledger, prices),
            panel::panel(
                &format!("Consumo · {name}"),
                &ledger,
                prices,
                &pricing_file(home),
                user_home,
            ),
        ))
    }

    /// O job morreu (pânico): quem esperava recebe um erro, a bancada volta a ser
    /// lida e o consumo ganha um registro novo — um nó com problema não trava a
    /// bancada.
    pub fn failed(
        &mut self,
        host: &dyn ChatHost,
        token: u64,
        kind: &JobKind,
        now: SystemTime,
    ) -> Out {
        let mut out = Out::default();
        match kind {
            JobKind::Refresh { workbench } => {
                self.flying.remove(workbench);
                // O que já está na memória segue valendo; o próximo tique tenta de novo.
                self.dirty.insert(workbench.clone());
                self.refreshed.remove(workbench);
                self.settle(host, now, &mut out);
            }
            JobKind::Archive | JobKind::Complete => out.replies.push((
                token,
                Answer::err(500, "o trabalho de disco do chat não terminou"),
            )),
            JobKind::Usage => {
                self.usage_flying = false;
                let (home, user_home) = self.usage_dirs.clone();
                self.usage = Some(UsageStore::new(home, user_home));
            }
            JobKind::Record => {}
            #[cfg(test)]
            JobKind::Boom => {}
        }
        out
    }

    /// Um job terminou. `token` é o que o ator guardou para responder.
    pub fn done(
        &mut self,
        host: &dyn ChatHost,
        token: u64,
        done: ChatDone,
        now: SystemTime,
    ) -> Out {
        let mut out = Out::default();
        match done {
            ChatDone::Refresh(result) => self.refreshed_with(host, result, now, &mut out),
            ChatDone::Record { workbench, wrote } => {
                if wrote {
                    // O histórico mudou em disco: relê.
                    self.histories.remove(&workbench);
                    self.plan_refresh(host, &workbench, now, &mut out);
                }
            }
            ChatDone::Archive {
                workbench,
                name,
                archived,
            } => {
                let effects = self.routes.cleared(&workbench);
                self.histories.remove(&workbench);
                self.lives.retain(|(wb, _), _| wb != &workbench);
                let mut want = BTreeSet::new();
                out.effects(effects, &mut want);
                let body = match &archived {
                    Some(path) => {
                        json!({"ok": true, "workbench": name, "archived": path.to_string_lossy()})
                    }
                    None => {
                        json!({"ok": true, "workbench": name, "archived": Value::Null, "detail": "conversa já estava vazia"})
                    }
                };
                out.replies.push((token, Answer::Ok(body)));
            }
            ChatDone::Usage { store, changed } => {
                self.usage_flying = false;
                for (id, ledger) in &changed {
                    self.usage_routes.ledgers.insert(id.clone(), ledger.clone());
                    out.usage.push(id.clone());
                }
                self.usage = Some(store);
            }
            ChatDone::Complete { items, range } => {
                let list: Vec<Value> = items.iter().map(slash_item).collect();
                out.replies
                    .push((token, Answer::Ok(complete_answer(&list, range))));
            }
        }
        out
    }

    // ---- por dentro -------------------------------------------------------

    fn known_turns(&self, workbench: &str, node: &str) -> BTreeSet<String> {
        let mut ids: BTreeSet<String> = self
            .histories
            .get(workbench)
            .map(|h| {
                h.records
                    .iter()
                    .filter(|r| r.node == node)
                    .map(|r| r.turn.id.clone())
                    .collect()
            })
            .unwrap_or_default();
        if let Some(live) = self
            .lives
            .get(&(workbench.to_owned(), node.to_owned()))
            .and_then(|l| l.live.as_ref())
        {
            ids.insert(live.turn.id.clone());
        }
        ids
    }

    fn apply_effects(
        &mut self,
        host: &dyn ChatHost,
        effects: Vec<ChatEffect>,
        now: SystemTime,
        out: &mut Out,
    ) {
        let mut rebuild = BTreeSet::new();
        out.effects(effects, &mut rebuild);
        self.dirty.extend(rebuild);
        self.settle(host, now, out);
    }

    /// Remonta, em memória, as bancadas sujas.
    fn settle(&mut self, host: &dyn ChatHost, now: SystemTime, out: &mut Out) {
        let dirty: Vec<String> = std::mem::take(&mut self.dirty).into_iter().collect();
        let prices = host.prices();
        for workbench in dirty {
            let participants = self.routes.participants(&workbench).to_vec();
            let records: Vec<ChatRecord> = self
                .histories
                .get(&workbench)
                .map(|h| h.records.clone())
                .unwrap_or_default();
            let recorded: BTreeSet<(String, String)> = records
                .iter()
                .map(|r| (r.node.clone(), r.turn.id.clone()))
                .collect();
            // O turno ao vivo vale enquanto o agente trabalha; depois do `Stop`,
            // até o histórico trazer o gravado (ou 20 s).
            let mut live: BTreeMap<String, LiveTurn> = BTreeMap::new();
            let mut stale: Vec<(String, String)> = Vec::new();
            for ((wb, node), entry) in &self.lives {
                if wb != &workbench {
                    continue;
                }
                let Some(turn) = &entry.live else { continue };
                let working = participants.iter().any(|p| {
                    &p.id == node && matches!(p.activity, Activity::Working | Activity::Asking)
                });
                if working {
                    live.insert(node.clone(), turn.clone());
                    continue;
                }
                let waited = now.duration_since(entry.read_at).unwrap_or_default();
                if recorded.contains(&(node.clone(), turn.turn.id.clone())) || waited > LIVE_LINGER
                {
                    stale.push((wb.clone(), node.clone()));
                } else {
                    live.insert(node.clone(), turn.clone());
                }
            }
            for key in stale {
                self.lives.remove(&key);
            }
            if let Some(view) = self.routes.view_mut(&workbench)
                && let Some(update) = view.rebuild(&ThreadInput {
                    participants: &participants,
                    records: &records,
                    live: &live,
                    prices: &prices,
                })
            {
                out.publish_update(&update);
            }
        }
    }

    fn plan_refresh(
        &mut self,
        host: &dyn ChatHost,
        workbench: &str,
        now: SystemTime,
        out: &mut Out,
    ) {
        if self.flying.contains(workbench) {
            self.dirty.insert(workbench.to_owned());
            return;
        }
        if !host.benches().iter().any(|b| b.id == workbench) {
            return;
        }
        let participants = self.routes.participants(workbench).to_vec();
        let mut lives = Vec::new();
        for p in participants
            .iter()
            .filter(|p| p.is_agent && matches!(p.activity, Activity::Working | Activity::Asking))
        {
            let Some(source) = host.source(workbench, &p.id) else {
                continue;
            };
            let cached = self.lives.get(&(workbench.to_owned(), p.id.clone()));
            // Leu há menos de 300 ms: o próximo tique relê.
            if cached
                .is_some_and(|c| now.duration_since(c.read_at).unwrap_or_default() < LIVE_EVERY)
            {
                continue;
            }
            lives.push(LiveRead {
                node: p.id.clone(),
                path: source.path,
                not_before: source.not_before,
                from: cached
                    .and_then(|c| c.live.as_ref())
                    .map_or(0, |l| l.prompt_offset),
                cached: cached.and_then(|c| c.stamp),
            });
        }
        let history_stamp = self.histories.get(workbench).and_then(|h| h.stamp);
        let history_known = self.histories.contains_key(workbench);
        self.refreshed.insert(workbench.to_owned(), now);
        self.flying.insert(workbench.to_owned());
        out.jobs.push((
            0,
            ChatJob::Refresh(RefreshJob {
                workbench: workbench.to_owned(),
                history: self
                    .workbenches_dir
                    .join(workbench)
                    .join(store::CURRENT_NAME),
                history_stamp: if history_known { history_stamp } else { None },
                lives,
                prices: host.prices(),
                now,
            }),
        ));
    }

    fn refreshed_with(
        &mut self,
        host: &dyn ChatHost,
        result: RefreshResult,
        now: SystemTime,
        out: &mut Out,
    ) {
        let workbench = result.workbench;
        self.flying.remove(&workbench);
        if let Some((stamp, records)) = result.history {
            self.histories
                .insert(workbench.clone(), HistoryCache { stamp, records });
        }
        for done in result.lives {
            let key = (workbench.clone(), done.node);
            if done.unchanged {
                if let Some(entry) = self.lives.get_mut(&key) {
                    entry.read_at = now;
                }
                continue;
            }
            self.lives.insert(
                key,
                LiveEntry {
                    stamp: done.stamp,
                    live: done.live,
                    read_at: now,
                },
            );
        }
        self.dirty.insert(workbench);
        self.settle(host, now, out);
    }

    fn plan_usage(&mut self, host: &dyn ChatHost, now: SystemTime, force: bool, out: &mut Out) {
        if self.usage_flying {
            return;
        }
        let due = self
            .usage_at
            .is_none_or(|at| now.duration_since(at).unwrap_or_default() >= USAGE_EVERY);
        if !(force || due) {
            return;
        }
        let Some(store) = self.usage.take() else {
            return;
        };
        let mut sources: BTreeMap<String, Vec<UsageSource>> = BTreeMap::new();
        for bench in host.benches() {
            for node in bench
                .nodes
                .iter()
                .filter(|n| n.kind == crate::features::node::model::NodeKind::Agent)
            {
                if let Some(source) = host.source(&bench.id, &node.id) {
                    sources
                        .entry(bench.id.clone())
                        .or_default()
                        .push(UsageSource {
                            node: node.id.clone(),
                            transcript: source.path,
                        });
                }
            }
        }
        self.usage_flying = true;
        self.usage_at = Some(now);
        out.jobs.push((
            0,
            ChatJob::Usage(UsageJob {
                store,
                sources,
                prices: host.prices(),
            }),
        ));
    }
}

fn source_name(source: &SlashSource) -> String {
    match source {
        SlashSource::Builtin => "builtin".to_owned(),
        SlashSource::Bundled => "bundled".to_owned(),
        SlashSource::User => "user".to_owned(),
        SlashSource::Project => "project".to_owned(),
        SlashSource::Plugin(name) => format!("plugin:{name}"),
    }
}

/// Os turnos que o runtime guarda de um agente (para os testes e a rota).
pub fn turns_of(records: &[ChatRecord], node: &str) -> Vec<ChatTurn> {
    records
        .iter()
        .filter(|r| r.node == node)
        .map(|r| r.turn.clone())
        .collect()
}

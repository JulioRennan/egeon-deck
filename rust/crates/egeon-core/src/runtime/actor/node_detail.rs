//! O nó por dentro no ator (decisão 31): o retrato de `node/<wb>/<nó>` para
//! agente e web, o estado do dial de esforço de cada agente, e os comandos
//! do dial e do nó web. A fila é do `cli` (`queue_node_event`).

use std::collections::{BTreeMap, HashMap, HashSet};
use std::time::{Duration, SystemTime};

use super::{Actor, ClientId};
use crate::commons::ids::{NodeId, WorkbenchId};
use crate::features::agent::claude::catalog::{self, CatalogMemo};
use crate::features::agent::claude::transcript::{context_tokens_at, last_model_at};
use crate::features::agent::effort_dial::EffortDialState;
use crate::features::agent::model_catalog::ModelCatalog;
use crate::features::node::model::{NodeConfig, NodeKind};
use crate::features::workspace::routes::OrgEffect;
use crate::protocol::message::{CommandKind, Event, EventBody, Reply, Topic};
use crate::protocol::node::NodeDetail;
use crate::protocol::org::{NodeKind as WireKind, SetNode};
use crate::runtime::node_view::{
    DEFAULT_WEB_PROFILE, Reading, agent_detail, dial_for, effective_model, normalize_url,
    web_detail,
};

/// O que o ator guarda do nó por dentro.
#[derive(Default)]
pub(super) struct DetailState {
    /// O dial de cada agente (por endereço) e o modelo para o qual foi
    /// montado: modelo novo, níveis novos.
    dials: HashMap<String, (Option<String>, EffortDialState)>,
    /// `web-profiles.json`: nome → UUID do armazenamento do navegador.
    pub(super) web_profiles: BTreeMap<String, String>,
    /// O catálogo de modelos do CLI, quando já foi lido.
    pub(super) catalog: Option<ModelCatalog>,
    /// O cache do catálogo e as releituras do binário em curso.
    memo: Option<CatalogMemo>,
    /// O último modelo e contexto de cada agente, lidos do transcript.
    pub(super) readings: HashMap<String, Reading>,
    /// Leituras do transcript em curso, para não empilhar.
    reading: HashSet<String>,
    last_probe: Option<SystemTime>,
    last_catalog: Option<SystemTime>,
}

/// O transcript é lido no máximo a cada 2 s, como o `ModelRow` do Swift:
/// é leitura de arquivo, e o relógio do ator anda de 250 em 250 ms.
const PROBE_EVERY: Duration = Duration::from_secs(2);
/// O carimbo do binário do CLI é conferido a cada 30 s: o Claude Code se
/// atualiza com o app aberto, e o catálogo novo vale para quem já está na tela.
const CATALOG_EVERY: Duration = Duration::from_secs(30);
/// Quanto do fim do transcript se lê para achar o último modelo e o contexto.
const TAIL_BYTES: u64 = 512 * 1024;

impl Actor {
    pub(super) fn config_of(
        &self,
        bench: &WorkbenchId,
        node: &NodeId,
    ) -> Option<(String, NodeConfig)> {
        let bench = self
            .org
            .state
            .workbenches
            .iter()
            .find(|w| w.id == bench.as_str())?;
        let config = bench.nodes.iter().find(|n| n.id == node.as_str())?.clone();
        Some((bench.address_of(&config), config))
    }

    /// O retrato do nó; `None` quando o nó não existe ou é um shell.
    pub(super) fn node_event(&mut self, bench: &WorkbenchId, node: &NodeId) -> Option<Event> {
        if let Some(event) = self.queue_node_event(bench, node) {
            return Some(event);
        }
        let (address, config) = self.config_of(bench, node)?;
        let (kind, agent, web) = match config.kind {
            NodeKind::Agent => {
                let profile = self.org.profiles.get(config.agent.as_ref()?)?.clone();
                let reading = self
                    .detail
                    .readings
                    .get(&address)
                    .cloned()
                    .unwrap_or_default();
                let catalog = self.detail.catalog.as_ref();
                let model = effective_model(catalog, &config, &reading).map(|m| m.id.clone());
                let rebuild = self
                    .detail
                    .dials
                    .get(&address)
                    .is_none_or(|(built, _)| *built != model);
                if rebuild {
                    let fresh = dial_for(
                        &profile,
                        &config,
                        effective_model(catalog, &config, &reading),
                    );
                    self.detail.dials.insert(address.clone(), (model, fresh));
                }
                let dial = &self.detail.dials.get(&address)?.1;
                let detail = agent_detail(
                    &profile,
                    &config,
                    dial,
                    self.detail.catalog.as_ref(),
                    &reading,
                );
                (WireKind::Agent, Some(detail), None)
            }
            NodeKind::Web => {
                let profile = config
                    .profile
                    .clone()
                    .unwrap_or_else(|| DEFAULT_WEB_PROFILE.to_owned());
                let id = self.web_profile_id(&profile);
                let detail = web_detail(&config, &self.detail.web_profiles, id);
                (WireKind::Web, None, Some(detail))
            }
            NodeKind::Shell | NodeKind::Queue => return None,
        };
        Some(Event {
            topic: Topic::Node(bench.clone(), node.clone()),
            body: EventBody::Node(Box::new(NodeDetail {
                workbench: bench.clone(),
                node: node.clone(),
                kind,
                agent,
                queue: None,
                web,
            })),
        })
    }

    /// O UUID do perfil, criado e gravado na primeira vez, como o
    /// `WebProfileStore.identifier(for:)` do Swift.
    fn web_profile_id(&mut self, profile: &str) -> String {
        if let Some(id) = self.detail.web_profiles.get(profile) {
            return id.clone();
        }
        let id = uuid::Uuid::new_v4().hyphenated().to_string().to_uppercase();
        self.detail
            .web_profiles
            .insert(profile.to_owned(), id.clone());
        crate::log!("web: perfil \"{profile}\" criado ({id})");
        let file = self.config.paths.config(WEB_PROFILES);
        let all = self.detail.web_profiles.clone();
        tokio::task::spawn_blocking(move || save_web_profiles(&file, &all));
        id
    }

    /// Os comandos do nó por dentro: o dial e o nó web.
    pub(super) fn detail_command(
        &mut self,
        client: ClientId,
        re: u64,
        kind: CommandKind,
    ) -> Option<Reply> {
        let (bench, node) = match &kind {
            CommandKind::EffortMove(m) => (m.workbench.clone(), m.node.clone()),
            CommandKind::EffortToggleAuto(t) | CommandKind::EffortSettle(t) => {
                (t.workbench.clone(), t.node.clone())
            }
            CommandKind::WebNavigate(w) => (w.workbench.clone(), w.node.clone()),
            CommandKind::WebNavigated(w) => (w.workbench.clone(), w.node.clone()),
            CommandKind::WebSetProfile(w) => (w.workbench.clone(), w.node.clone()),
            other => return Some(Reply::err(re, format!("{} não é do nó", other.name()))),
        };
        let Some((address, _)) = self.config_of(&bench, &node) else {
            return Some(Reply::err(re, format!("nó desconhecido '{node}'")));
        };
        // O dial precisa existir antes de mexer: o retrato o monta.
        let _ = self.node_event(&bench, &node);
        match kind {
            CommandKind::EffortMove(m) => {
                if let Some((_, dial)) = self.detail.dials.get_mut(&address) {
                    dial.move_to(i64::try_from(m.index).unwrap_or(i64::MAX));
                }
            }
            CommandKind::EffortToggleAuto(_) => {
                if let Some((_, dial)) = self.detail.dials.get_mut(&address) {
                    dial.toggle_auto();
                }
            }
            CommandKind::EffortSettle(_) => {
                let settled = self
                    .detail
                    .dials
                    .get_mut(&address)
                    .and_then(|(_, dial)| dial.settle());
                // Assentou: é o set_node{effort}, com o reinício que o Swift faz.
                if let Some(value) = settled {
                    let set = SetNode {
                        workbench: bench.clone(),
                        node: node.clone(),
                        model: None,
                        effort: Some(value),
                        ultracode: None,
                        role: None,
                        rules: None,
                        cwd: None,
                        cmd: None,
                        maestro: None,
                    };
                    let reply = self.node_command(client, re, CommandKind::SetNode(set));
                    self.publish_node(&bench, &node);
                    return reply;
                }
            }
            CommandKind::WebNavigate(w) => {
                let Some(url) = normalize_url(&w.typed) else {
                    return Some(Reply::err(re, "endereço vazio"));
                };
                self.set_web(&bench, &node, |n| n.url = Some(url));
            }
            CommandKind::WebNavigated(w) => {
                self.set_web(&bench, &node, |n| n.url = Some(w.url));
            }
            CommandKind::WebSetProfile(w) => {
                let profile = w.profile.trim().to_owned();
                if profile.is_empty() {
                    return Some(Reply::err(re, "perfil sem nome"));
                }
                let _ = self.web_profile_id(&profile);
                self.set_web(&bench, &node, |n| n.profile = Some(profile));
            }
            _ => {}
        }
        self.publish_node(&bench, &node);
        Some(Reply::ok(re))
    }

    /// Muda o nó web e grava a bancada (`main.swift:3969`).
    fn set_web(
        &mut self,
        bench: &WorkbenchId,
        node: &NodeId,
        change: impl FnOnce(&mut NodeConfig),
    ) {
        let Some(config) = self
            .org
            .state
            .workbenches
            .iter_mut()
            .find(|w| w.id == bench.as_str())
            .and_then(|w| w.nodes.iter_mut().find(|n| n.id == node.as_str()))
        else {
            return;
        };
        let before = config.clone();
        change(config);
        if *config != before {
            self.apply_org(vec![OrgEffect::PersistWorkbenches]);
        }
    }

    /// O relógio do nó por dentro: o catálogo de vez em quando, e o
    /// transcript dos agentes que alguém está olhando.
    pub(super) fn detail_tick(&mut self, now: SystemTime) {
        let due = |last: Option<SystemTime>, every: Duration| {
            last.is_none_or(|l| now.duration_since(l).is_ok_and(|d| d >= every))
        };
        if due(self.detail.last_catalog, CATALOG_EVERY) {
            self.detail.last_catalog = Some(now);
            self.refresh_catalog();
        }
        if due(self.detail.last_probe, PROBE_EVERY) {
            self.detail.last_probe = Some(now);
            self.probe_transcripts();
        }
    }

    /// O cache do catálogo do binário do Claude; releitura, quando o binário
    /// mudou, fora do ator.
    fn refresh_catalog(&mut self) {
        let Some(profile) = self.org.profiles.values().find(|p| catalog::applies_to(p)) else {
            return;
        };
        let Some(name) = profile.command.first().cloned() else {
            return;
        };
        let path = self
            .base_environment()
            .into_iter()
            .find(|(k, _)| k == "PATH")
            .map(|(_, v)| v)
            .unwrap_or_default();
        let file = catalog::cache_file(self.config.paths.home());
        let executable = self.drivers.is_executable;
        let memo = self
            .detail
            .memo
            .get_or_insert_with(|| CatalogMemo::new(executable));
        let (cache, refresh) = memo.cache(&file, &name, &path);
        let current = cache.map(|c| c.catalog.clone());
        let changed = current != self.detail.catalog;
        self.detail.catalog = current;
        if changed {
            self.publish_org();
        }
        let Some(refresh) = refresh else { return };
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let job = refresh.clone();
            let read =
                tokio::task::spawn_blocking(move || catalog::read_binary(&job.binary, job.stamp))
                    .await
                    .unwrap_or(None);
            let apply = move |actor: &mut Actor| {
                let file = catalog::cache_file(actor.config.paths.home());
                if let Some(memo) = actor.detail.memo.as_mut() {
                    let stored = memo.store(&file, &refresh, read).cloned();
                    if stored.is_some() {
                        actor.detail.catalog = stored;
                        actor.publish_org();
                    }
                }
            };
            let _ = inbox.send(super::Msg::Run(Box::new(apply))).await;
        });
    }

    /// O último modelo e o contexto de cada agente assinado, do transcript.
    fn probe_transcripts(&mut self) {
        let watched: Vec<(WorkbenchId, NodeId)> = self
            .clients
            .values()
            .flat_map(|c| c.topics.iter())
            .filter_map(|t| match t {
                Topic::Node(bench, node) => Some((bench.clone(), node.clone())),
                _ => None,
            })
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        for (bench, node) in watched {
            self.probe_node(bench, node);
        }
    }

    /// Lê o transcript e o padrão da config de um nó de agente, fora do ator.
    /// Também roda no `subscribe`, para o primeiro retrato não esperar o
    /// tique (o `refresh(force: true)` do `ModelRow` do Swift).
    pub(super) fn probe_node(&mut self, bench: WorkbenchId, node: NodeId) {
        let Some((address, config)) = self.config_of(&bench, &node) else {
            return;
        };
        if config.kind != NodeKind::Agent {
            return;
        }
        // Sem transcript (antes do primeiro turno) o nó também entra: o
        // título vem do padrão da config (main.swift:3692-3709).
        let path = config.transcript.clone();
        if !self.detail.reading.insert(address.clone()) {
            return;
        }
        let since = crate::runtime::org::screen_id(bench.as_str(), node.as_str())
            .and_then(|id| self.nodes.get(&id))
            .map(|n| n.launched);
        let profile = config
            .agent
            .as_ref()
            .and_then(|a| self.org.profiles.get(a))
            .cloned();
        let config_dir = config.config.clone();
        let home = self.config.default_cwd.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let file = path.map(std::path::PathBuf::from);
            let read = tokio::task::spawn_blocking(move || Reading {
                // Sem terminal no ar não há subida para comparar: linha
                // nenhuma do transcript diz o modelo em uso.
                model: since.and_then(|since| {
                    file.as_deref()
                        .and_then(|f| last_model_at(f, Some(since), TAIL_BYTES))
                }),
                tokens: file
                    .as_deref()
                    .and_then(|f| context_tokens_at(f, TAIL_BYTES)),
                // O `settings.json` da config em uso: lido aqui, fora do
                // ator, junto com o transcript.
                default_model: profile
                    .and_then(|p| p.default_model_name(config_dir.as_deref(), &home)),
            })
            .await
            .unwrap_or_default();
            let apply = move |actor: &mut Actor| {
                actor.detail.reading.remove(&address);
                if actor.detail.readings.get(&address) != Some(&read) {
                    actor.detail.readings.insert(address, read);
                    actor.publish_node(&bench, &node);
                }
            };
            let _ = inbox.send(super::Msg::Run(Box::new(apply))).await;
        });
    }

    /// O retrato novo a quem assina o nó.
    pub(super) fn publish_node(&mut self, bench: &WorkbenchId, node: &NodeId) {
        let topic = Topic::Node(bench.clone(), node.clone());
        if !self.clients.values().any(|c| c.topics.contains(&topic)) {
            return;
        }
        if let Some(event) = self.node_event(bench, node) {
            self.publish(&event);
        }
    }
}

pub const WEB_PROFILES: &str = "web-profiles.json";

/// `web-profiles.json`: nome → UUID. Arquivo que não abre é mapa vazio, como
/// no Swift. Bloqueia: chamar fora do ator.
pub fn load_web_profiles(file: &std::path::Path) -> BTreeMap<String, String> {
    std::fs::read(file)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

fn save_web_profiles(file: &std::path::Path, all: &BTreeMap<String, String>) {
    if let Some(parent) = file.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    match serde_json::to_vec_pretty(all) {
        Ok(bytes) => {
            if let Err(err) = std::fs::write(file, bytes) {
                crate::log!("web: não deu para gravar {} — {err}", file.display());
            }
        }
        Err(err) => crate::log!("web: perfis sem serializar — {err}"),
    }
}

//! Dono: `chat-rs`. Liga ao ator o tópico chat/<id>, a cauda do transcript e as rotas /chat/clear, /compose, /chat e /usage.
//!
//! A lógica está em `features::chat::runtime`, que não conhece o [`Actor`]; aqui
//! só a fiação: o [`ChatHost`] que lê a organização, o roteamento das respostas
//! (HTTP ou `/ui`), a publicação das linhas do canal e os jobs de disco, que
//! saem por `tokio::spawn` + `spawn_blocking` e voltam por `Msg::Run`.
//!
//! O que ainda não existe no ator e entra nos pontos marcados com `dispatch`:
//! a atividade de cada terminal, a conversa que o gancho relatou (de onde vem a
//! cauda ao vivo), o pedido de permissão da bandeja e a entrega do `chat_send`.
//! Sem eles o chat monta a thread só do histórico gravado.

use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::time::SystemTime;

use serde_json::Value;

use super::super::org::Org;
use super::dispatch_commands::DispatchState;
use super::{Actor, ClientId, Replier, WireLine, not_ported};
use crate::commons::ids::WorkbenchId;
use crate::features::activity::model::Activity;
use crate::features::agent::claude::command_registry::CommandRegistry;
use crate::features::chat::routes::{chat_compose, chat_get};
use crate::features::chat::runtime::{
    Answer, BenchInfo, ChatDone, ChatHost, ChatJob, ChatRuntime, Complete, Identity, JobKind, Out,
    SlashInputs, Source,
};
use crate::features::node::model::NodeKind;
use crate::features::queue::chat::ChatQueue;
use crate::features::usage::PriceTable;
use crate::features::usage::panel::{Panel, Pill};
use crate::features::usage::store::{PriceMemo, UsageStore};
use crate::features::workbench::model::WorkbenchConfig;
use crate::protocol::handler::{RouteReply, RouteRequest};
use crate::protocol::message::{CommandKind, Reply, Topic};
use crate::protocol::routes::FeatureRoute;

/// Quem espera a resposta de um job.
enum Waiter {
    Http(Replier),
    Ui { client: ClientId, re: u64 },
}

/// O estado do chat no ator: o runtime (criado no primeiro uso, porque precisa da
/// pasta de dados) e quem espera cada job.
#[derive(Default)]
pub(super) struct ChatState {
    runtime: Option<ChatRuntime>,
    waiting: HashMap<u64, Waiter>,
    next_token: u64,
    prices: PriceMemo,
}

/// O que o chat lê do ator: a organização, o dispatch (atividade, conversa e
/// bandeja de permissão) e o `/` lido do binário do CLI.
struct OrgHost<'a> {
    org: &'a Org,
    dispatch: &'a DispatchState,
    commands: Option<&'a CommandRegistry>,
    /// As filas de cada bancada, já lidas do ator: o host só empresta `&self`.
    queues: BTreeMap<String, Vec<ChatQueue>>,
    prices: PriceTable,
    now: SystemTime,
}

impl OrgHost<'_> {
    fn bench(&self, id: &str) -> Option<&WorkbenchConfig> {
        self.org.state.workbenches.iter().find(|b| b.id == id)
    }
}

impl ChatHost for OrgHost<'_> {
    fn benches(&self) -> Vec<BenchInfo> {
        self.org
            .state
            .workbenches
            .iter()
            .map(|b| BenchInfo {
                id: b.id.clone(),
                name: b.name.clone(),
                mode: b.view_mode().raw().to_owned(),
                nodes: b.nodes.clone(),
            })
            .collect()
    }

    fn activity(&self, address: &str) -> Option<Activity> {
        self.dispatch.activity(address)
    }

    /// O transcript que o gancho `/conversation` relatou, e o início do turno.
    fn source(&self, workbench: &str, node: &str) -> Option<Source> {
        self.dispatch.source(self.bench(workbench)?, node)
    }

    fn identity(&self, workbench: &str, node: &str) -> Identity {
        let found = self
            .org
            .state
            .workbenches
            .iter()
            .find(|b| b.id == workbench)
            .and_then(|b| {
                b.nodes
                    .iter()
                    .find(|n| n.id == node && n.kind == NodeKind::Agent)
            });
        Identity {
            conversation: found.and_then(|n| n.conversation_id.clone()),
            cli: found.and_then(|n| n.agent.clone()),
            model: found.and_then(|n| n.model.clone()),
        }
    }

    fn queues(&self, workbench: &str) -> Vec<ChatQueue> {
        self.queues.get(workbench).cloned().unwrap_or_default()
    }

    /// Os pedidos de permissão abertos da bancada, para a bandeja.
    fn permissions(&self, workbench: &str) -> Vec<Value> {
        self.bench(workbench)
            .map(|bench| self.dispatch.permissions(bench, self.now))
            .unwrap_or_default()
    }

    /// Como o `chat.slashCommands` do Swift: o perfil do agente, a config que
    /// o nó escolheu, a pasta em que ele roda e o transcript dele.
    fn slash(&self, workbench: &str, node: &str) -> Option<SlashInputs> {
        let bench = self.bench(workbench)?;
        let config = bench.nodes.iter().find(|n| n.id == node)?;
        let profile = self.org.profiles.get(config.agent.as_ref()?)?;
        Some(SlashInputs {
            profile: profile.clone(),
            node_config: config.config.clone(),
            cwd: PathBuf::from(bench.directory(config, &self.org.home).path),
            transcript: config.transcript.as_ref().map(PathBuf::from),
            binary: self.commands.cloned(),
            home: PathBuf::from(&self.org.home),
        })
    }

    fn prices(&self) -> PriceTable {
        self.prices.clone()
    }
}

impl Actor {
    pub(super) fn chat_route(
        &mut self,
        route: FeatureRoute,
        request: RouteRequest,
        reply: Replier,
    ) {
        let now = SystemTime::now();
        match route {
            FeatureRoute::ChatClear => {
                let name = request.param("target").unwrap_or("").to_owned();
                let token = self.chat_wait(Waiter::Http(reply));
                let out = self.chat_with(|rt, _| rt.clear(token, true, &name, now));
                self.chat_out(out);
            }
            FeatureRoute::Compose => {
                let (answer, effects) =
                    self.chat_with_host(|rt, _| chat_compose(rt.routes_mut(), &request, now));
                let out = self.chat_with(|rt, host| rt.effects(host, effects, now));
                let _ = reply.send(answer);
                self.chat_out(out);
            }
            FeatureRoute::Chat => {
                let (answer, effects) =
                    self.chat_with_host(|rt, _| chat_get(rt.routes_mut(), &request, now));
                let out = self.chat_with(|rt, host| rt.effects(host, effects, now));
                let _ = reply.send(answer);
                self.chat_out(out);
            }
            FeatureRoute::Usage => {
                let (answer, _show_panel) =
                    self.chat_with_host(|rt, host| rt.usage_route(host, &request, now));
                let _ = reply.send(answer);
            }
            other => not_ported(other, reply),
        }
    }

    pub(super) fn chat_tick(&mut self, now: SystemTime) {
        if self.chat.runtime.is_none() {
            return;
        }
        let out = self.chat_with(|rt, host| rt.tick(host, now));
        self.chat_out(out);
    }

    /// A UI assinou `chat/<id>`. `false` é bancada desconhecida. O `reset` sai
    /// para quem assina o tópico, o novo cliente inclusive — por isso o tópico
    /// já tem de estar na lista dele.
    pub(super) fn chat_subscribe(&mut self, workbench: &WorkbenchId) -> bool {
        let now = SystemTime::now();
        let id = workbench.to_string();
        let out = self.chat_with(|rt, host| rt.subscribe(host, &id, now));
        match out {
            Some(out) => {
                self.chat_out(out);
                true
            }
            None => false,
        }
    }

    /// `chat_snapshot`, `chat_step`, `chat_more`, `chat_clear` e `chat_send`. A
    /// resposta de `chat_clear` sai depois do job: `None` quer dizer "já está a
    /// caminho". O `permission_answer` é do dispatch.
    pub(super) fn chat_command(
        &mut self,
        client: ClientId,
        re: u64,
        kind: CommandKind,
    ) -> Option<Reply> {
        let now = SystemTime::now();
        match kind {
            CommandKind::ChatSnapshot(r) => {
                let id = r.workbench.to_string();
                self.chat_with(|rt, host| {
                    let mut sink = Out::default();
                    rt.sync(host, &mut sink);
                    Some(match rt.snapshot(&id) {
                        Some(snapshot) => Reply::with(re, &snapshot),
                        None => Reply::err(re, format!("bancada desconhecida '{id}'")),
                    })
                })
            }
            CommandKind::ChatStep(s) => {
                let id = s.workbench.to_string();
                let out = self.chat_with(|rt, host| rt.step(host, &id, &s.block, now));
                self.chat_out(out);
                Some(Reply::ok(re))
            }
            CommandKind::ChatMore(r) => {
                let id = r.workbench.to_string();
                let out = self.chat_with(|rt, host| rt.more(host, &id, now));
                self.chat_out(out);
                Some(Reply::ok(re))
            }
            CommandKind::ChatClear(r) => {
                let id = r.workbench.to_string();
                let token = self.chat_wait(Waiter::Ui { client, re });
                let out = self.chat_with(|rt, _| rt.clear(token, false, &id, now));
                self.chat_out(out);
                None
            }
            CommandKind::ChatSend(s) => {
                let id = s.workbench.to_string();
                let to: Vec<String> = s.to.iter().map(ToString::to_string).collect();
                let out = self.chat_with(|rt, _| rt.send(&id, &to, &s.text));
                self.chat_out(out);
                Some(Reply::ok(re))
            }
            _ => None,
        }
    }

    /// `chat_complete{workbench, text, caret, to?, search?}`: o core monta o
    /// [`Complete`] a partir do `ChatComplete` do protocolo. `@` responde na hora;
    /// `/` volta do job.
    pub(super) fn chat_complete(
        &mut self,
        client: ClientId,
        re: u64,
        request: Complete,
    ) -> Option<Reply> {
        let token = self.chat_wait(Waiter::Ui { client, re });
        let out = self.chat_with(|rt, host| rt.complete(host, token, &request));
        self.chat_out(out);
        None
    }

    /// O `Stop` de um agente (efeito `TurnEnded` do dispatch): grava o turno no
    /// histórico e relê o consumo, ambos em job. `address` é `bancada/nó`.
    // Sem chamador até o dispatch ligar o efeito `TurnEnded`; quem ligar tira o allow.
    #[allow(dead_code)]
    pub(super) fn chat_turn_ended(&mut self, address: &str) {
        let now = SystemTime::now();
        let out = self.chat_with(|rt, host| rt.turn_ended(host, address, now));
        self.chat_out(out);
    }

    /// Arquiva o `chat.jsonl` da bancada (o `ChatHistory.archive` do Swift) para o
    /// `clear_workbench`, que não passa pelo chat. Faz disco no ator, como o
    /// `rename` do Swift na fila serial: se o org preferir fora do ator, chame de
    /// dentro do job dele.
    pub(super) fn chat_archive(
        &mut self,
        workbench_id: &str,
        now: SystemTime,
    ) -> Option<std::path::PathBuf> {
        self.chat_with(|rt, _| rt.archive_now(workbench_id, now))
    }

    /// O `clearedHistory()` do Swift: esvazia o eco local e o turno ao vivo, e a
    /// UI vê a thread esvaziar.
    pub(super) fn chat_cleared(&mut self, workbench_id: &str) {
        let out = self.chat_with(|rt, _| rt.cleared(workbench_id));
        self.chat_out(out);
    }

    /// Um job terminou; o ator o recebe por `Msg::Run`.
    fn chat_done(&mut self, token: u64, done: ChatDone) {
        let now = SystemTime::now();
        let out = self.chat_with(|rt, host| rt.done(host, token, done, now));
        self.chat_out(out);
    }

    fn chat_wait(&mut self, waiter: Waiter) -> u64 {
        self.chat.next_token += 1;
        let token = self.chat.next_token;
        self.chat.waiting.insert(token, waiter);
        token
    }

    /// O agente a que a fila nova da bancada nasce ligada: o que está em foco e,
    /// se o foco não é um agente, o primeiro. `None` sem agente — a fila nasce solta.
    pub(super) fn chat_new_queue_agent(&self, workbench: &str) -> Option<String> {
        self.chat
            .runtime
            .as_ref()
            .and_then(|rt| rt.new_queue_agent(workbench))
    }

    /// O consumo de uma bancada, já formatado, para o core publicar em
    /// `workbench/<id>/usage` a cada refresh do registro.
    pub(super) fn usage_state(&mut self, workbench_id: &str) -> Option<(Pill, Panel)> {
        self.chat_with_host(|rt, host| rt.usage_state(host, workbench_id))
    }

    fn chat_with_host<R>(&mut self, f: impl FnOnce(&mut ChatRuntime, &dyn ChatHost) -> R) -> R {
        self.chat_with(f)
    }

    fn chat_with<R>(&mut self, f: impl FnOnce(&mut ChatRuntime, &dyn ChatHost) -> R) -> R {
        // As filas pedem `&mut self` (sincronizam os controladores): lidas antes
        // de emprestar o runtime e a organização ao host.
        let ids: Vec<String> = self
            .org
            .state
            .workbenches
            .iter()
            .map(|b| b.id.clone())
            .collect();
        let queues: BTreeMap<String, Vec<ChatQueue>> = ids
            .into_iter()
            .map(|id| {
                let list = self.queue_chat_queues(&id);
                (id, list)
            })
            .collect();
        // O runtime e a organização são campos distintos: um empresta o outro.
        let home = self.config.paths.home().to_path_buf();
        let user_home = std::path::PathBuf::from(&self.org.home);
        let runtime = self.chat.runtime.get_or_insert_with(|| {
            ChatRuntime::new(
                home.join("workbenches"),
                crate::commons::clock::local_offset_secs,
                UsageStore::new(home.clone(), user_home),
            )
        });
        let catalog = self
            .detail
            .catalog
            .as_ref()
            .and_then(|c| c.prices.clone())
            .unwrap_or_default();
        let prices = self.chat.prices.table(&home, &catalog).clone();
        let host = OrgHost {
            org: &self.org,
            dispatch: &self.dispatch,
            commands: self.detail.commands(),
            queues,
            prices,
            now: SystemTime::now(),
        };
        f(runtime, &host)
    }

    /// Faz o que o runtime pediu: responde, publica no canal e dispara os jobs.
    fn chat_out(&mut self, out: Out) {
        for (token, answer) in out.replies {
            self.chat_reply(token, answer);
        }
        for (topic, line) in out.publish {
            let Some(id) = topic.strip_prefix("chat/") else {
                continue;
            };
            let Ok(id) = WorkbenchId::new(id) else {
                continue;
            };
            let wanted = Topic::Chat(id);
            let line: WireLine = line.into_bytes().into();
            let targets: Vec<ClientId> = self
                .clients
                .iter()
                .filter(|(_, c)| c.topics.contains(&wanted))
                .map(|(id, _)| *id)
                .collect();
            for client in targets {
                self.push(client, line.clone(), false);
            }
        }
        for delivery in out.deliveries {
            // `from: nil` como o `chat.send` do Swift: quem manda é o usuário, e as
            // guardas de cadeia só valem entre agentes. Entregue, o eco entra na
            // thread até o transcript confirmar.
            match self.dispatch_chat_send(&delivery.workbench, &delivery.node, &delivery.text) {
                Ok(()) => {
                    let now = SystemTime::now();
                    let echo = self.chat_with(|rt, host| {
                        rt.sent(
                            host,
                            &delivery.workbench,
                            &delivery.node,
                            &delivery.text,
                            now,
                        )
                    });
                    self.chat_out(echo);
                }
                Err(error) => crate::log!(
                    "chat: envio para {}/{} falhou: {error}",
                    delivery.workbench,
                    delivery.node
                ),
            }
        }
        for id in out.usage {
            if let Ok(id) = WorkbenchId::new(&id) {
                self.publish_usage(&id);
            }
        }
        for (token, job) in out.jobs {
            self.chat_spawn(token, job);
        }
    }

    fn chat_reply(&mut self, token: u64, answer: Answer) {
        let Some(waiter) = self.chat.waiting.remove(&token) else {
            return;
        };
        match waiter {
            Waiter::Http(reply) => {
                let _ = reply.send(match answer {
                    Answer::Ok(json) => RouteReply::ok(json),
                    Answer::Err { status, message } => RouteReply::err(status, message),
                });
            }
            Waiter::Ui { client, re } => {
                let reply = match answer {
                    Answer::Ok(json) => Reply::with(re, &json),
                    Answer::Err { message, .. } => Reply::err(re, message),
                };
                self.send_reply(client, &reply);
            }
        }
    }

    /// O job vai para `spawn_blocking` e o resultado volta ao ator por `Msg::Run`.
    fn chat_spawn(&mut self, token: u64, job: ChatJob) {
        let inbox = self.inbox.clone();
        let kind = job.kind();
        tokio::spawn(async move {
            let run: Box<dyn FnOnce(&mut Actor) + Send> =
                match tokio::task::spawn_blocking(move || job.run()).await {
                    Ok(done) => Box::new(move |actor: &mut Actor| actor.chat_done(token, done)),
                    // O job deu pânico: o ator recebe o aviso, responde a quem
                    // esperava e destrava a bancada — nada fica esperando para sempre.
                    Err(_) => {
                        crate::log!("chat: job de disco não terminou ({kind:?})");
                        Box::new(move |actor: &mut Actor| actor.chat_failed(token, &kind))
                    }
                };
            let _ = inbox.send(super::Msg::Run(run)).await;
        });
    }

    /// O job morreu: ver [`ChatRuntime::failed`].
    fn chat_failed(&mut self, token: u64, kind: &JobKind) {
        let now = SystemTime::now();
        let out = self.chat_with(|rt, host| rt.failed(host, token, kind, now));
        self.chat_out(out);
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;

    use super::super::processes_commands::support::Rig;
    use crate::features::agent::claude::profile::claude_code;
    use crate::features::agent::claude::slash_catalog;
    use crate::features::node::model::{NodeConfig, NodeKind};
    use crate::features::workbench::model::WorkbenchConfig;

    #[tokio::test]
    async fn a_barra_do_chat_le_o_catalogo_do_agente() {
        let mut rig = Rig::new();
        let root = rig.dir.path().to_path_buf();
        let repo = root.join("deck");
        fs::create_dir_all(repo.join(".claude/commands")).unwrap();
        fs::write(
            repo.join(".claude/commands/deploy.md"),
            "---\ndescription: sobe o app\n---\n",
        )
        .unwrap();
        let config = root.join("claude-x");
        fs::create_dir_all(config.join("commands")).unwrap();
        fs::write(config.join("commands/meu.md"), "do usuário\n").unwrap();
        // O home do teste: nada de varrer o `~/.claude` de verdade.
        rig.actor.org.home = root.to_string_lossy().into_owned();
        rig.actor
            .org
            .profiles
            .insert("claude".into(), claude_code());
        let mut agent = NodeConfig::new(NodeKind::Agent, "dev");
        agent.agent = Some("claude".into());
        agent.config = Some(config.to_string_lossy().into_owned());
        agent.transcript = Some("/nao/existe.jsonl".into());
        let shell = NodeConfig::new(NodeKind::Shell, "sh");
        let bench =
            WorkbenchConfig::new("deck", repo.to_string_lossy().as_ref(), vec![agent, shell]);
        let id = bench.id.clone();
        rig.actor.org.state.workbenches.push(bench);

        let (inputs, of_shell) = rig
            .actor
            .chat_with(|_, host| (host.slash(&id, "dev"), host.slash(&id, "sh")));
        assert!(of_shell.is_none(), "shell não tem `/`");
        let inputs = inputs.expect("o agente tem `/`");
        assert_eq!(inputs.cwd, repo);
        assert_eq!(inputs.node_config, agent_config(&config));
        assert_eq!(
            inputs.transcript.as_deref(),
            Some(Path::new("/nao/existe.jsonl"))
        );
        assert!(inputs.binary.is_none(), "o binário ainda não foi lido");

        let names: Vec<String> = slash_catalog::commands_for_profile(
            &inputs.profile,
            inputs.node_config.as_deref(),
            &inputs.cwd,
            inputs.transcript.as_deref(),
            inputs.binary.as_ref(),
            &inputs.home,
        )
        .expect("perfil do Claude Code")
        .into_iter()
        .map(|c| c.name)
        .collect();
        for name in ["deploy", "meu", "clear"] {
            assert!(names.iter().any(|n| n == name), "falta /{name}: {names:?}");
        }
    }

    fn agent_config(config: &Path) -> Option<String> {
        Some(config.to_string_lossy().into_owned())
    }
}

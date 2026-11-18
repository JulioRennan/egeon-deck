//! Dono: `cli`. Liga ao ator as filas de prompts e as rotas /tasks, /task e /queue.
//!
//! Cada nó de fila da bancada tem um [`QueueController`], criado quando
//! preciso a partir do `Org`. O mundo da fila (as arestas, a atividade do
//! alvo, o envio) vem do `Org` e do `Dispatcher`, emprestados só durante a
//! chamada. As filas gravam o `queue.json` na hora, no ator, como o Swift
//! fazia na thread principal: são arquivos de poucos KB.
//!
//! Desvio do Swift: as rotas enxergam toda bancada do `Org`, e não só as de
//! canvas carregado (`shells[id]`). Para o agente não muda nada, que sempre
//! está numa bancada aberta; pelo `curl` dá para mexer na fila de uma bancada
//! fechada, e a tarefa mandada a um alvo que não está de pé fica na fila.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::path::Path;
use std::time::SystemTime;

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::{Value, json};

use super::{Actor, Replier, not_ported};
use crate::commons::ids::{NodeId, WorkbenchId};
use crate::features::activity::model::Activity;
use crate::features::chat::time::format_iso;
use crate::features::dispatch::request::DispatchRequest;
use crate::features::dispatch::service::{Dispatcher, Topology};
use crate::features::edge::model::EdgeConfig;
use crate::features::node::model::NodeKind;
use crate::features::queue::chat::ChatQueue;
use crate::features::queue::model::{MessageKind, QueueItem, Status};
use crate::features::queue::routes::{self, QueueDirectory, QueueEffect, TaskQueues};
use crate::features::queue::service::{Linked, QueueController, QueueHost, TICK_EVERY};
use crate::features::queue::store::{IMAGE_EXTENSIONS, QueueStore, is_image_file};
use crate::features::workbench::model::WorkbenchConfig;
use crate::protocol::handler::RouteRequest;
use crate::protocol::message::{CommandKind, Event, EventBody, Reply, Topic};
use crate::protocol::node::{
    NodeDetail, NodeEffect, QueueDetail, QueueItemView, QueueMessage as MessageView, QueueStatus,
    QueueTarget,
};
use crate::protocol::org::NodeKind as WireKind;
use crate::protocol::routes::FeatureRoute;

/// Uma fila é do nó de fila de uma bancada: (id da bancada, id do nó).
type Key = (String, String);

/// O estado das filas dentro do ator.
#[derive(Default)]
pub(super) struct QueueState {
    queues: BTreeMap<Key, QueueController>,
    /// A próxima batida de 1 s das filas.
    next_tick: Option<SystemTime>,
}

impl QueueState {
    /// As filas de uma bancada para a coluna FILAS do chat, em ordem de id
    /// do nó. Só as que o ator já criou: quem lê fora de `queue_chat_queues`
    /// precisa ter sincronizado antes.
    pub(super) fn chat_queues(&self, bench_id: &str) -> Vec<ChatQueue> {
        self.queues
            .iter()
            .filter(|((bench, _), _)| bench == bench_id)
            .map(|((_, node), controller)| ChatQueue::new(node.clone(), controller.queue()))
            .collect()
    }
}

/// Os nós a que a fila `queue_node` está ligada: as arestas que saem dela,
/// para agente ou terminal comum (`linked` do `queueController` do Swift).
fn linked(bench: &WorkbenchConfig, queue_node: &str) -> Vec<Linked> {
    bench
        .edge_list()
        .iter()
        .filter(|edge| edge.from == queue_node)
        .filter_map(|edge| {
            let node = bench.nodes.iter().find(|n| n.id == edge.to)?;
            matches!(node.kind, NodeKind::Agent | NodeKind::Shell).then(|| Linked {
                id: node.id.clone(),
                label: node.id.clone(),
                // Agente lê o rodapé com os comandos da tarefa; shell o
                // executaria.
                agent: node.kind == NodeKind::Agent,
            })
        })
        .collect()
}

fn queue_nodes(bench: &WorkbenchConfig) -> impl Iterator<Item = &str> {
    bench
        .nodes
        .iter()
        .filter(|n| n.kind == NodeKind::Queue)
        .map(|n| n.id.as_str())
}

/// O mundo de uma fila: as arestas lidas do modelo e o `Dispatcher` do ator.
struct ActorHost<'a> {
    bench_name: String,
    linked: Vec<Linked>,
    dispatcher: &'a mut Dispatcher,
}

/// Sem arestas: quem manda "de você" não passa pelas guardas de cadeia.
struct NoTopology;

impl Topology for NoTopology {
    fn edges(&self, _workbench: &str) -> Vec<EdgeConfig> {
        Vec::new()
    }
}

impl QueueHost for ActorHost<'_> {
    fn linked(&self) -> Vec<Linked> {
        self.linked.clone()
    }

    fn activity(&self, node: &str) -> Option<Activity> {
        let address = format!("{}/{node}", self.bench_name);
        self.dispatcher
            .target(&address)
            .map(|t| t.activity().clone())
    }

    /// "Quem manda é você": a fila só guardou o que você anotou.
    fn dispatch(&mut self, node: &str, text: &str, images: &[String]) -> Result<(), String> {
        let request = DispatchRequest {
            target: format!("{}/{node}", self.bench_name),
            text: Some(text.to_owned()),
            images: (!images.is_empty()).then(|| images.to_vec()),
            ..DispatchRequest::default()
        };
        self.dispatcher
            .dispatch(&request, None, &NoTopology)
            .map(|_| ())
            .map_err(|error| error.to_string())
    }
}

/// As filas que mandam para um agente (`queues(reaching:)` do `main.swift`).
struct Reaching<'a> {
    benches: &'a [WorkbenchConfig],
    queues: &'a mut BTreeMap<Key, QueueController>,
}

impl TaskQueues for Reaching<'_> {
    fn reaching(&mut self, address: &str) -> Vec<&mut QueueController> {
        let Some((bench_name, node)) = address.split_once('/') else {
            return Vec::new();
        };
        let Some(bench) = self.benches.iter().find(|b| b.name == bench_name) else {
            return Vec::new();
        };
        // Na ordem dos nós da bancada, como o Swift.
        let wanted: Vec<Key> = queue_nodes(bench)
            .filter(|queue| linked(bench, queue).iter().any(|l| l.id == node))
            .map(|queue| (bench.id.clone(), queue.to_owned()))
            .collect();
        let mut by_key: BTreeMap<&Key, &mut QueueController> = self.queues.iter_mut().collect();
        wanted.iter().filter_map(|key| by_key.remove(key)).collect()
    }
}

/// A fila de um nó pelo endereço `bancada/nó`, com o mundo dela.
struct Directory<'a> {
    benches: &'a [WorkbenchConfig],
    queues: &'a mut BTreeMap<Key, QueueController>,
    dispatcher: &'a mut Dispatcher,
}

impl QueueDirectory for Directory<'_> {
    fn with_queue(
        &mut self,
        address: &str,
        run: &mut dyn FnMut(&mut QueueController, &mut dyn QueueHost) -> Value,
    ) -> Option<Value> {
        let (bench_name, node) = address.split_once('/')?;
        let bench = self.benches.iter().find(|b| b.name == bench_name)?;
        queue_nodes(bench).find(|n| *n == node)?;
        let controller = self.queues.get_mut(&(bench.id.clone(), node.to_owned()))?;
        let mut host = ActorHost {
            bench_name: bench.name.clone(),
            linked: linked(bench, node),
            dispatcher: &mut *self.dispatcher,
        };
        Some(run(controller, &mut host))
    }
}

/// A fila de um nó pelo id da bancada e do nó, com o mundo dela emprestado só
/// durante a chamada.
fn with_queue<R>(
    benches: &[WorkbenchConfig],
    queues: &mut BTreeMap<Key, QueueController>,
    dispatcher: &mut Dispatcher,
    workbench: &WorkbenchId,
    node: &NodeId,
    run: impl FnOnce(&mut QueueController, &mut dyn QueueHost) -> R,
) -> Option<R> {
    let bench = benches.iter().find(|b| b.id == workbench.as_str())?;
    queue_nodes(bench).find(|n| *n == node.as_str())?;
    let controller = queues.get_mut(&(bench.id.clone(), node.to_string()))?;
    let mut host = ActorHost {
        bench_name: bench.name.clone(),
        linked: linked(bench, node.as_str()),
        dispatcher,
    };
    Some(run(controller, &mut host))
}

/// O nome da mensagem da thread no fio, como o Swift a grava.
fn message_kind(kind: MessageKind) -> &'static str {
    match kind {
        MessageKind::Question => "question",
        MessageKind::Note => "note",
        MessageKind::Done => "done",
        MessageKind::Reply => "reply",
    }
}

fn item_view(item: &QueueItem) -> QueueItemView {
    QueueItemView {
        id: item.id.clone(),
        text: item.text.clone(),
        images: item.images.clone(),
        status: match item.status {
            Status::Pending => QueueStatus::Pending,
            Status::Sent => QueueStatus::Sent,
            Status::Done => QueueStatus::Done,
        },
        sent_to: item.sent_to.as_deref().and_then(|n| NodeId::new(n).ok()),
        sent_at: item.sent_at.map(format_iso),
        thread: item
            .thread
            .iter()
            .map(|m| MessageView {
                // Você é o que não tem autor, e a UI o mostra assim.
                author: m.author.clone().unwrap_or_else(|| "você".to_owned()),
                kind: message_kind(m.kind).to_owned(),
                text: m.text.clone(),
                at: format_iso(m.at),
            })
            .collect(),
        awaiting: item.awaiting,
        locked: item.is_locked(),
        empty: item.is_empty(),
    }
}

/// O estado da fila como o card a desenha. O destino é o que vale (o escolhido,
/// ou o primeiro ligado), e o `blocker` é o aviso de quando ela não pode andar.
fn queue_detail(queue: &QueueController, host: &dyn QueueHost) -> QueueDetail {
    let linked = host.linked();
    let ids: Vec<String> = linked.iter().map(|l| l.id.clone()).collect();
    let destination = queue
        .queue()
        .destination(&ids)
        .and_then(|d| NodeId::new(d).ok());
    // O texto da coluna FILAS vem do mesmo `ChatQueue` que o chat usa.
    let chat = ChatQueue::new(String::new(), queue.queue());
    QueueDetail {
        items: queue.queue().items.iter().map(item_view).collect(),
        auto: queue.queue().auto,
        target: destination.clone(),
        destination,
        pending: queue.queue().pending_count(),
        asking: chat.asking,
        summary: chat.summary(),
        subtitle: queue.queue().pending_summary(),
        image_extensions: IMAGE_EXTENSIONS.map(str::to_owned).to_vec(),
        targets: linked
            .iter()
            .filter_map(|l| {
                Some(QueueTarget {
                    id: NodeId::new(l.id.clone()).ok()?,
                    label: l.label.clone(),
                })
            })
            .collect(),
        blocker: queue.blocker(host).map(|e| e.to_string()),
        // Onde os prints moram: a UI lê `<images_dir>/<nome>`.
        images_dir: queue.store().folder().to_string_lossy().into_owned(),
    }
}

/// A bancada e o nó de um comando da fila.
fn command_target(kind: &CommandKind) -> Option<(&WorkbenchId, &NodeId)> {
    Some(match kind {
        CommandKind::QueueAdd(c) => (&c.workbench, &c.node),
        CommandKind::QueueUpdate(c) | CommandKind::QueueReply(c) => (&c.workbench, &c.node),
        CommandKind::QueueRemove(c)
        | CommandKind::QueueToggleDone(c)
        | CommandKind::QueueReopen(c) => (&c.workbench, &c.node),
        CommandKind::QueueMove(c) => (&c.workbench, &c.node),
        CommandKind::QueueSend(c) => (&c.workbench, &c.node),
        CommandKind::QueueSet(c) => (&c.workbench, &c.node),
        CommandKind::QueueClearDone(c) => (&c.workbench, &c.node),
        CommandKind::QueueAttach(c) => (&c.workbench, &c.node),
        CommandKind::QueueDetach(c) => (&c.workbench, &c.node),
        _ => return None,
    })
}

/// Um comando da fila. `Ok(Some(id))` é o item que o `queue_add` criou.
fn run_command(
    queue: &mut QueueController,
    host: &mut dyn QueueHost,
    kind: CommandKind,
    now: SystemTime,
) -> Result<Option<String>, String> {
    let fail = |e: crate::features::queue::QueueError| e.to_string();
    match kind {
        CommandKind::QueueAdd(c) => {
            return Ok(Some(queue.add(&c.text, Vec::new(), c.after.as_deref()).id));
        }
        CommandKind::QueueUpdate(c) => queue.update(&c.item, &c.text),
        CommandKind::QueueRemove(c) => queue.remove(&c.item),
        CommandKind::QueueMove(c) => queue.move_to(&c.item, c.to),
        CommandKind::QueueToggleDone(c) => queue.toggle_done(&c.item, now),
        CommandKind::QueueReopen(c) => queue.reopen(&c.item),
        CommandKind::QueueSend(c) => match c.item {
            Some(item) => queue.send(&item, host, now).map_err(fail)?,
            None => queue.send_next(host, now).map_err(fail)?,
        },
        CommandKind::QueueReply(c) => queue.reply(&c.item, &c.text, host, now).map_err(fail)?,
        CommandKind::QueueSet(c) => {
            if let Some(auto) = c.auto {
                queue.set_auto(auto, host, now);
            }
            if let Some(target) = c.target {
                queue.set_target(target.as_str());
            }
        }
        CommandKind::QueueClearDone(_) => queue.clear_done(),
        CommandKind::QueueAttach(c) => {
            // Um arquivo (arrastado) ou o PNG de um print colado, em base64:
            // os dois vão para a pasta da fila, onde o item os guarda.
            let name = match (c.path, c.png) {
                (Some(path), _) if !is_image_file(Path::new(&path)) => {
                    return Err(format!(
                        "só imagem se anexa ({})",
                        IMAGE_EXTENSIONS.join(", ")
                    ));
                }
                (Some(path), _) => queue.store().import_image(Path::new(&path)),
                (None, Some(png)) => {
                    let bytes = STANDARD
                        .decode(png.trim())
                        .map_err(|_| "a imagem colada não é base64".to_owned())?;
                    queue.store().save_image(&bytes)
                }
                (None, None) => return Err("sem arquivo nem imagem para anexar".to_owned()),
            };
            let name = name.ok_or_else(|| "não consegui guardar a imagem".to_owned())?;
            let id = queue
                .attach_to(name, c.item.as_deref(), c.open.as_deref())
                .ok_or_else(|| {
                    "a tarefa não existe ou já foi enviada: o print não foi anexado".to_owned()
                })?;
            return Ok(Some(id));
        }
        CommandKind::QueueDetach(c) => queue.detach(&c.image, &c.item),
        other => return Err(format!("{} não é da fila", other.name())),
    }
    Ok(None)
}

impl Actor {
    /// Põe e tira controladores para casar com os nós de fila das bancadas.
    fn queue_sync(&mut self) {
        let wanted: BTreeSet<Key> = self
            .org
            .state
            .workbenches
            .iter()
            .flat_map(|b| queue_nodes(b).map(|n| (b.id.clone(), n.to_owned())))
            .collect();
        self.queue.queues.retain(|key, _| wanted.contains(key));
        let workbenches = self.config.paths.workbenches_dir();
        for key in wanted {
            self.queue.queues.entry(key.clone()).or_insert_with(|| {
                QueueController::new(
                    QueueStore::for_node(&workbenches, &key.0, &key.1),
                    key.1.clone(),
                )
            });
        }
    }

    /// As filas da bancada para o chat, na ordem dos nós dela. Sincroniza
    /// antes: uma fila recém-criada já aparece, sem esperar o tique.
    pub(super) fn queue_chat_queues(&mut self, bench_id: &str) -> Vec<ChatQueue> {
        self.queue_sync();
        let mut queues = self.queue.chat_queues(bench_id);
        if let Some(bench) = self.org.state.workbenches.iter().find(|b| b.id == bench_id) {
            queues.sort_by_key(|q| {
                bench
                    .nodes
                    .iter()
                    .position(|n| n.id == q.id)
                    .unwrap_or(usize::MAX)
            });
        }
        queues
    }

    pub(super) fn queue_route(
        &mut self,
        route: FeatureRoute,
        request: RouteRequest,
        reply: Replier,
    ) {
        let now = SystemTime::now();
        self.queue_sync();
        let benches = &self.org.state.workbenches;
        let mut effects = Vec::new();
        // Só `/task` e `/queue` bem-sucedidos mexem na fila; `/tasks` só lê e a
        // fila desconhecida (404) não tem o que mostrar.
        let mut mutated = false;
        let answer = match route {
            FeatureRoute::Tasks => routes::tasks(
                &mut Reaching {
                    benches,
                    queues: &mut self.queue.queues,
                },
                &request,
                now,
            ),
            FeatureRoute::Task => {
                let answer = routes::task(
                    &mut Reaching {
                        benches,
                        queues: &mut self.queue.queues,
                    },
                    &request,
                    now,
                );
                mutated = answer.status == 200;
                answer
            }
            FeatureRoute::Queue => {
                let (answer, queue_effects) = routes::queue(
                    &mut Directory {
                        benches,
                        queues: &mut self.queue.queues,
                        dispatcher: &mut self.dispatch.coordination.dispatcher,
                    },
                    &request,
                    now,
                );
                effects = queue_effects;
                mutated = answer.status == 200;
                answer
            }
            other => return not_ported(other, reply),
        };
        let _ = reply.send(answer);
        for effect in effects {
            self.queue_effect(effect);
        }
        // O `egeon` e o agente mexeram na fila: quem a olha vê o estado novo.
        if mutated {
            self.queue_publish(None);
        }
    }

    /// `open=` e `draft=` da rota `/queue` são efeitos no tópico do nó (decisão
    /// 31): a UI abre a tarefa e põe o rascunho no card.
    fn queue_effect(&mut self, effect: QueueEffect) {
        let (address, body) = match effect {
            QueueEffect::OpenItem { address, item } => (address, NodeEffect::OpenItem { item }),
            QueueEffect::SetDraft { address, text } => (address, NodeEffect::Draft { text }),
        };
        let topic = address.split_once('/').and_then(|(bench, node)| {
            let id = self
                .org
                .state
                .workbenches
                .iter()
                .find(|b| b.name == bench)?
                .id
                .clone();
            Some(Topic::Node(
                WorkbenchId::new(id).ok()?,
                NodeId::new(node).ok()?,
            ))
        });
        match topic {
            Some(topic) => self.publish(&Event {
                topic,
                body: EventBody::NodeEffect(body),
            }),
            None => crate::log!("fila[{address}]: efeito sem bancada conhecida"),
        }
    }

    /// Os comandos `queue_*` do `/ui` (decisão 31): o `/queue` do Swift em
    /// comandos. A resposta do `queue_add` leva o `item` novo; o estado novo da
    /// fila sai a quem assina o nó.
    pub(super) fn queue_command(&mut self, re: u64, kind: CommandKind) -> Reply {
        self.queue_sync();
        let now = SystemTime::now();
        let Some((workbench, node)) = command_target(&kind).map(|(w, n)| (w.clone(), n.clone()))
        else {
            return Reply::err(re, format!("{} não é da fila", kind.name()));
        };
        let outcome = with_queue(
            &self.org.state.workbenches,
            &mut self.queue.queues,
            &mut self.dispatch.coordination.dispatcher,
            &workbench,
            &node,
            |queue, host| run_command(queue, host, kind, now),
        );
        // Comando que deu erro não mudou nada: não há estado novo a publicar.
        if matches!(outcome, Some(Ok(_))) {
            self.queue_publish(Some((&workbench, &node)));
        }
        match outcome {
            None => Reply::err(re, format!("fila desconhecida '{workbench}/{node}'")),
            Some(Err(error)) => Reply::err(re, error),
            Some(Ok(Some(item))) => Reply::with(re, &json!({"item": item})),
            Some(Ok(None)) => Reply::ok(re),
        }
    }

    /// O estado de um nó de fila, para a assinatura do tópico do nó. `None`
    /// quando o nó não é uma fila.
    pub(super) fn queue_node_event(
        &mut self,
        workbench: &WorkbenchId,
        node: &NodeId,
    ) -> Option<Event> {
        self.queue_sync();
        let detail = with_queue(
            &self.org.state.workbenches,
            &mut self.queue.queues,
            &mut self.dispatch.coordination.dispatcher,
            workbench,
            node,
            |queue, host| queue_detail(queue, host),
        )?;
        Some(Event {
            topic: Topic::Node(workbench.clone(), node.clone()),
            body: EventBody::Node(Box::new(NodeDetail {
                workbench: workbench.clone(),
                node: node.clone(),
                kind: WireKind::Queue,
                agent: None,
                queue: Some(detail),
                web: None,
            })),
        })
    }

    /// O estado novo das filas a quem assina o tópico do nó delas; com
    /// `only`, só o da fila que mudou (um comando mexe numa só).
    fn queue_publish(&mut self, only: Option<(&WorkbenchId, &NodeId)>) {
        let watched: HashSet<(WorkbenchId, NodeId)> = self
            .clients
            .values()
            .flat_map(|c| c.topics.iter())
            .filter_map(|t| match t {
                Topic::Node(workbench, node)
                    if only.is_none_or(|(w, n)| w == workbench && n == node) =>
                {
                    Some((workbench.clone(), node.clone()))
                }
                _ => None,
            })
            .collect();
        for (workbench, node) in watched {
            if let Some(event) = self.queue_node_event(&workbench, &node) {
                self.publish(&event);
            }
        }
    }

    /// A batida de 1 s das filas: fecha o item cujo turno acabou e, no
    /// automático, manda o próximo. Só as de bancada com terminal de pé: sem
    /// ele o envio não teria para onde ir.
    pub(super) fn queue_tick(&mut self, now: SystemTime) {
        if self.queue.next_tick.is_some_and(|at| now < at) {
            return;
        }
        self.queue.next_tick = Some(now + TICK_EVERY);
        self.queue_sync();
        let keys: Vec<Key> = self.queue.queues.keys().cloned().collect();
        let mut changed = false;
        for key in keys {
            let Some(bench) = self
                .org
                .state
                .workbenches
                .iter()
                .find(|b| b.id == key.0 && self.org.live.contains(&b.id))
            else {
                continue;
            };
            let mut host = ActorHost {
                bench_name: bench.name.clone(),
                linked: linked(bench, &key.1),
                dispatcher: &mut self.dispatch.coordination.dispatcher,
            };
            if let Some(controller) = self.queue.queues.get_mut(&key) {
                controller.tick(&mut host, now);
                changed |= controller.take_changed();
            }
        }
        if changed {
            self.queue_publish(None);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::time::SystemTime;

    use serde_json::{Value, json};

    use super::super::processes_commands::support::{Rig, request};
    use crate::features::edge::model::EdgeConfig;
    use crate::features::node::model::{NodeConfig, NodeKind};
    use crate::features::workbench::model::WorkbenchConfig;
    use crate::protocol::routes::FeatureRoute;

    /// A bancada "deck": a fila "fila" ligada ao agente "dev", que está de pé
    /// no Dispatcher.
    fn rig_with_deck() -> (Rig, String) {
        let mut rig = Rig::new();
        let queue = NodeConfig::new(NodeKind::Queue, "fila");
        let agent = NodeConfig::new(NodeKind::Agent, "dev");
        let mut bench = WorkbenchConfig::new("deck", "/tmp/deck", vec![queue, agent]);
        bench.edges = Some(vec![EdgeConfig::new("fila", "dev", None)]);
        let id = bench.id.clone();
        rig.actor.org.state.workbenches.push(bench);
        rig.actor.org.live.insert(id.clone());
        rig.actor
            .dispatch
            .coordination
            .register("deck/dev", None, false, SystemTime::now());
        (rig, id)
    }

    async fn queue(rig: &mut Rig, target: &str) -> (u16, Value) {
        let reply = rig
            .call(FeatureRoute::Queue, request("GET", target, None))
            .await;
        (reply.status, reply.json)
    }

    fn pending(rig: &Rig) -> usize {
        rig.actor
            .dispatch
            .coordination
            .dispatcher
            .target("deck/dev")
            .map_or(0, |t| t.pending())
    }

    #[tokio::test]
    async fn as_filas_da_bancada_vao_para_o_chat_na_ordem_dos_nos() {
        let mut rig = Rig::new();
        let nodes = vec![
            NodeConfig::new(NodeKind::Queue, "zeta"),
            NodeConfig::new(NodeKind::Agent, "dev"),
            NodeConfig::new(NodeKind::Queue, "alfa"),
        ];
        let bench = WorkbenchConfig::new("deck", "/tmp/deck", nodes);
        let id = bench.id.clone();
        rig.actor.org.state.workbenches.push(bench);
        rig.actor.org.live.insert(id.clone());
        assert_eq!(
            queue(&mut rig, "/queue?target=deck/zeta&add=a").await.0,
            200
        );

        let list = rig.actor.queue_chat_queues(&id);
        let ids: Vec<&str> = list.iter().map(|q| q.id.as_str()).collect();
        assert_eq!(ids, ["zeta", "alfa"], "a ordem dos nós, não a do id");
        assert_eq!((list[0].pending, list[1].pending), (1, 0));
        assert!(!list[0].asking && list[0].working_with.is_none());
        // Por id, sem a bancada à mão (o `QueueState` não conhece a ordem).
        let by_id: Vec<String> = rig
            .actor
            .queue
            .chat_queues(&id)
            .into_iter()
            .map(|q| q.id)
            .collect();
        assert_eq!(by_id, ["alfa", "zeta"]);
        // Bancada que não existe, ou sem fila: nenhuma.
        assert!(rig.actor.queue_chat_queues("outra").is_empty());
    }

    #[tokio::test]
    async fn fila_que_nao_existe_e_404_com_o_alvo() {
        let (mut rig, _) = rig_with_deck();
        let (status, body) = queue(&mut rig, "/queue?target=deck/nada").await;
        assert_eq!(status, 404);
        assert_eq!(
            body,
            json!({"ok": false, "error": "fila desconhecida 'deck/nada'"})
        );
        // Nó que existe mas não é fila também não vale.
        assert_eq!(queue(&mut rig, "/queue?target=deck/dev").await.0, 404);
    }

    #[tokio::test]
    async fn anota_a_tarefa_grava_no_disco_da_bancada_e_mostra_o_destino() {
        let (mut rig, id) = rig_with_deck();
        let (status, body) = queue(&mut rig, "/queue?target=deck/fila&add=conserta").await;
        assert_eq!(status, 200);
        assert!(body["added"].is_string());
        assert_eq!(body["destination"], "dev");
        assert_eq!(body["targets"], json!(["dev"]));
        assert_eq!(body["items"][0]["status"], "pending");
        let file = rig
            .data
            .join("workbenches")
            .join(&id)
            .join("queues/fila/queue.json");
        let saved: Value = serde_json::from_slice(&std::fs::read(file).unwrap()).unwrap();
        assert_eq!(saved["items"][0]["text"], "conserta");
    }

    #[tokio::test]
    async fn enviar_enfileira_no_alvo_de_pe_e_marca_a_tarefa() {
        let (mut rig, _) = rig_with_deck();
        queue(&mut rig, "/queue?target=deck/fila&add=primeira").await;
        let (_, sent) = queue(&mut rig, "/queue?target=deck/fila&send=next").await;
        assert_eq!(sent["error"], "");
        assert_eq!(sent["items"][0]["status"], "sent");
        assert_eq!(sent["items"][0]["sentTo"], "dev");
        // Foi ao Dispatcher "de você", sem guardas de cadeia.
        assert_eq!(pending(&rig), 1);

        // Sem mais nada pendente, o erro é o do Swift.
        let (_, none) = queue(&mut rig, "/queue?target=deck/fila&send=next").await;
        assert_eq!(none["error"], "nada pendente");
    }

    #[tokio::test]
    async fn alvo_que_nao_esta_de_pe_nao_perde_a_tarefa() {
        let (mut rig, _) = rig_with_deck();
        rig.actor
            .dispatch
            .coordination
            .dispatcher
            .unregister("deck/dev", SystemTime::now());
        queue(&mut rig, "/queue?target=deck/fila&add=primeira").await;
        let (_, sent) = queue(&mut rig, "/queue?target=deck/fila&send=next").await;
        assert!(
            sent["error"]
                .as_str()
                .unwrap()
                .starts_with("alvo desconhecido")
        );
        assert_eq!(sent["items"][0]["status"], "pending");
    }

    #[tokio::test]
    async fn o_agente_ve_e_marca_as_tarefas_das_filas_ligadas_a_ele() {
        let (mut rig, _) = rig_with_deck();
        let (_, added) = queue(&mut rig, "/queue?target=deck/fila&add=toast").await;
        let id = added["items"][0]["id"].as_str().unwrap().to_lowercase();
        let short = &id[..6];

        let denied = rig
            .call(FeatureRoute::Tasks, request("GET", "/tasks", None))
            .await;
        assert_eq!(denied.status, 403);

        let tasks = rig
            .call(
                FeatureRoute::Tasks,
                request("GET", "/tasks", Some("deck/dev")),
            )
            .await;
        assert_eq!(tasks.json["tasks"][0]["id"], short);
        assert_eq!(tasks.json["tasks"][0]["fila"], "fila");

        let done = rig
            .call(
                FeatureRoute::Task,
                request(
                    "POST",
                    &format!("/task?action=done&id={short}"),
                    Some("deck/dev"),
                ),
            )
            .await;
        assert_eq!((done.status, done.json), (200, json!({"ok": true})));
        let (_, now) = queue(&mut rig, "/queue?target=deck/fila").await;
        assert_eq!(now["items"][0]["status"], "done");

        // Quem nenhuma fila alcança é recusado com a frase do Swift.
        let alone = rig
            .call(
                FeatureRoute::Task,
                request("POST", "/task?action=done&id=abcdef", Some("deck/outro")),
            )
            .await;
        assert_eq!(alone.status, 400);
        assert_eq!(alone.json["error"], "nenhuma fila está ligada a você");
    }

    // O agente recém-registrado ainda está iniciando: livre é só "esperando
    // prompt". O automático não manda por cima, e o tique de 1 s também não.
    // (Que manda quando ele fica livre está nos testes da feature `queue`.)
    #[tokio::test]
    async fn o_automatico_espera_o_agente_ficar_livre() {
        let (mut rig, _) = rig_with_deck();
        queue(&mut rig, "/queue?target=deck/fila&add=um").await;
        queue(&mut rig, "/queue?target=deck/fila&add=dois").await;
        let (_, on) = queue(&mut rig, "/queue?target=deck/fila&auto=1").await;
        assert_eq!(on["auto"], true);
        assert_eq!(on["items"][0]["status"], "pending");
        assert_eq!(pending(&rig), 0);
        let t0 = SystemTime::now();
        rig.actor.queue_tick(t0);
        rig.actor.queue_tick(t0 + std::time::Duration::from_secs(2));
        let (_, still) = queue(&mut rig, "/queue?target=deck/fila").await;
        assert_eq!(still["items"][0]["status"], "pending");
        assert_eq!(pending(&rig), 0);
        // O manual manda mesmo assim: é decisão sua.
        let (_, sent) = queue(&mut rig, "/queue?target=deck/fila&send=next").await;
        assert_eq!(sent["items"][0]["status"], "sent");
        assert_eq!(pending(&rig), 1);
    }

    // Decisão 31: `open=` e `draft=` da rota viram efeito no tópico do nó,
    // para quem assina o card da fila.
    #[tokio::test]
    async fn open_e_draft_viram_efeito_no_topico_do_no() {
        use std::collections::HashSet;

        use crate::commons::ids::{NodeId, WorkbenchId};
        use crate::protocol::message::Topic;

        let (mut rig, id) = rig_with_deck();
        let topic = Topic::Node(
            WorkbenchId::new(id.clone()).unwrap(),
            NodeId::new("fila").unwrap(),
        );
        let (line_tx, mut lines) = tokio::sync::mpsc::channel(8);
        let (alive, _kept) = tokio::sync::oneshot::channel();
        rig.actor.clients.insert(
            1,
            super::super::Client {
                queue: line_tx,
                _alive: alive,
                topics: HashSet::from([topic]),
                resync: HashSet::new(),
            },
        );
        let (status, body) = queue(
            &mut rig,
            "/queue?target=deck/fila&open=a1b2c3&draft=rascunho",
        )
        .await;
        assert_eq!(status, 200);
        assert!(body["items"].is_array());

        let mut got = Vec::new();
        while let Ok(line) = lines.try_recv() {
            got.push(serde_json::from_slice::<Value>(&line).unwrap());
        }
        // Os efeitos primeiro, e depois o estado novo da fila a quem a assina.
        let (effects, states): (Vec<_>, Vec<_>) = got
            .into_iter()
            .partition(|line| line.get("effect").is_some());
        assert_eq!(states.len(), 1);
        assert_eq!(states[0]["kind"], "queue");
        assert_eq!(
            effects,
            [
                json!({"effect": "open_item", "item": "a1b2c3", "topic": format!("node/{id}/fila")}),
                json!({"effect": "draft", "text": "rascunho", "topic": format!("node/{id}/fila")}),
            ]
        );
        // Fila que não existe não manda efeito a ninguém.
        queue(&mut rig, "/queue?target=deck/nada&open=x").await;
        assert!(lines.try_recv().is_err());
    }

    // ---- Os comandos `queue_*` do /ui e o estado do nó (decisão 31)

    use std::collections::HashSet;

    use base64::Engine;

    use crate::commons::ids::{NodeId, WorkbenchId};
    use crate::protocol::message::{CommandKind, Reply, Topic};
    use crate::protocol::node::*;

    struct Fila {
        rig: Rig,
        wb: WorkbenchId,
        node: NodeId,
    }

    fn fila() -> Fila {
        let (rig, id) = rig_with_deck();
        Fila {
            rig,
            wb: WorkbenchId::new(id).unwrap(),
            node: NodeId::new("fila").unwrap(),
        }
    }

    impl Fila {
        fn run(&mut self, kind: CommandKind) -> Value {
            let reply: Reply = self.rig.actor.queue_command(7, kind);
            serde_json::to_value(reply).unwrap()
        }

        fn add(&mut self, text: &str) -> String {
            let reply = self.run(CommandKind::QueueAdd(QueueAdd {
                workbench: self.wb.clone(),
                node: self.node.clone(),
                text: text.into(),
                after: None,
            }));
            reply["item"].as_str().expect("sem item").to_owned()
        }

        fn item(&self, id: &str) -> QueueItemRef {
            QueueItemRef {
                workbench: self.wb.clone(),
                node: self.node.clone(),
                item: id.into(),
            }
        }

        fn text(&self, id: &str, text: &str) -> QueueItemText {
            QueueItemText {
                workbench: self.wb.clone(),
                node: self.node.clone(),
                item: id.into(),
                text: text.into(),
            }
        }

        fn detail(&mut self) -> QueueDetail {
            let event = self
                .rig
                .actor
                .queue_node_event(&self.wb, &self.node)
                .expect("não é uma fila");
            match event.body {
                crate::protocol::message::EventBody::Node(d) => d.queue.expect("sem fila"),
                other => panic!("{other:?}"),
            }
        }
    }

    #[test]
    fn add_responde_o_item_novo_e_o_estado_mostra_o_destino() {
        let mut f = fila();
        let id = f.add("roda os testes");
        let reply = f.run(CommandKind::QueueAdd(QueueAdd {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            text: "depois".into(),
            after: None,
        }));
        assert_eq!(reply["ok"], true);
        assert_ne!(reply["item"], id.as_str());
        let detail = f.detail();
        assert_eq!(detail.items.len(), 2);
        assert_eq!(detail.items[0].id, id);
        assert_eq!(detail.items[0].status, QueueStatus::Pending);
        assert!(!detail.auto);
        assert_eq!(detail.target.unwrap().as_str(), "dev");
        assert_eq!(detail.targets.len(), 1);
        assert_eq!(detail.targets[0].label, "dev");
        assert_eq!(detail.blocker, None);
    }

    #[test]
    fn add_depois_de_um_item_entra_logo_abaixo() {
        let mut f = fila();
        let a = f.add("a");
        f.add("c");
        f.run(CommandKind::QueueAdd(QueueAdd {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            text: "b".into(),
            after: Some(a),
        }));
        let texts: Vec<String> = f.detail().items.into_iter().map(|i| i.text).collect();
        assert_eq!(texts, ["a", "b", "c"]);
    }

    #[test]
    fn editar_mover_marcar_reabrir_remover_e_limpar() {
        let mut f = fila();
        let (a, b, c) = (f.add("a"), f.add("b"), f.add("c"));
        f.run(CommandKind::QueueUpdate(f.text(&a, "a2")));
        f.run(CommandKind::QueueMove(QueueMove {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            item: c.clone(),
            to: 0,
        }));
        let d = f.detail();
        assert_eq!(
            d.items.iter().map(|i| i.text.as_str()).collect::<Vec<_>>(),
            ["c", "a2", "b"]
        );

        f.run(CommandKind::QueueToggleDone(f.item(&a)));
        assert_eq!(f.detail().items[1].status, QueueStatus::Done);
        f.run(CommandKind::QueueReopen(f.item(&a)));
        assert_eq!(f.detail().items[1].status, QueueStatus::Pending);

        f.run(CommandKind::QueueToggleDone(f.item(&b)));
        f.run(CommandKind::QueueClearDone(NodeTarget {
            workbench: f.wb.clone(),
            node: f.node.clone(),
        }));
        assert_eq!(f.detail().items.len(), 2);
        f.run(CommandKind::QueueRemove(f.item(&c)));
        assert_eq!(f.detail().items.len(), 1);
    }

    #[test]
    fn enviar_manda_o_item_ou_o_proximo_e_o_erro_e_o_do_swift() {
        let mut f = fila();
        let a = f.add("primeira");
        f.add("segunda");
        let send = |f: &mut Fila, item: Option<String>| {
            f.run(CommandKind::QueueSend(QueueSend {
                workbench: f.wb.clone(),
                node: f.node.clone(),
                item,
            }))
        };
        assert_eq!(send(&mut f, Some(a.clone()))["ok"], true);
        let d = f.detail();
        assert_eq!(d.items[0].status, QueueStatus::Sent);
        assert_eq!(d.items[0].sent_to.as_ref().unwrap().as_str(), "dev");
        assert!(d.items[0].sent_at.as_ref().unwrap().ends_with('Z'));
        assert_eq!(pending(&f.rig), 1);
        // Já enviada: continua pela thread.
        let again = send(&mut f, Some(a));
        assert_eq!(again["ok"], false);
        assert_eq!(
            again["error"],
            "esta tarefa já foi enviada: continue pela thread"
        );
        // Sem item, o próximo pendente; depois dele, nada.
        assert_eq!(send(&mut f, None)["ok"], true);
        let none = send(&mut f, None);
        assert_eq!(none["error"], "nada pendente");
    }

    #[test]
    fn responder_na_thread_aparece_como_voce_e_o_agente_com_o_nome_dele() {
        let mut f = fila();
        let a = f.add("pergunta");
        f.run(CommandKind::QueueSend(QueueSend {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            item: Some(a.clone()),
        }));
        let short: String = a.to_lowercase().chars().take(6).collect();
        let now = std::time::SystemTime::now();
        f.rig
            .actor
            .queue
            .queues
            .values_mut()
            .next()
            .unwrap()
            .agent("dev", "ask", &short, "posso?", now)
            .unwrap();
        let d = f.detail();
        assert!(d.items[0].awaiting);
        // A pergunta passa na frente de tudo na coluna FILAS.
        assert_eq!((d.asking, d.summary.as_str()), (true, "? pergunta"));
        let reply = f.run(CommandKind::QueueReply(f.text(&a, "pode")));
        assert_eq!(reply["ok"], true);
        let d = f.detail();
        assert!(!d.items[0].awaiting);
        assert!(!d.asking);
        let thread: Vec<(&str, &str, &str)> = d.items[0]
            .thread
            .iter()
            .map(|m| (m.author.as_str(), m.kind.as_str(), m.text.as_str()))
            .collect();
        assert_eq!(
            thread,
            [("dev", "question", "posso?"), ("você", "reply", "pode")]
        );
    }

    #[test]
    fn queue_set_liga_o_automatico_e_escolhe_o_destino() {
        let mut f = fila();
        f.run(CommandKind::QueueSet(QueueSet {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            auto: Some(true),
            target: Some(NodeId::new("dev").unwrap()),
        }));
        let d = f.detail();
        assert!(d.auto);
        assert_eq!(d.target.unwrap().as_str(), "dev");
    }

    // O que a UI só mostra: o destino com a regra do Swift, o resumo do nó, a
    // trava por item e as extensões de imagem.
    #[test]
    fn o_estado_manda_pronto_destino_pendentes_resumo_e_trava() {
        let mut f = fila();
        let d = f.detail();
        assert_eq!(d.pending, 0);
        assert_eq!(d.subtitle, "nada pendente");
        assert_eq!(
            d.image_extensions,
            ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
        );

        // A tarefa em branco é a que você está escrevendo: não conta.
        f.add("");
        assert_eq!(f.detail().pending, 0);
        let a = f.add("primeira");
        f.add("segunda");
        let d = f.detail();
        assert_eq!((d.pending, d.subtitle.as_str()), (2, "2 pendentes"));
        assert!(d.items.iter().all(|i| !i.locked));

        f.run(CommandKind::QueueSend(QueueSend {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            item: Some(a.clone()),
        }));
        let d = f.detail();
        assert_eq!((d.pending, d.subtitle.as_str()), (1, "1 pendente"));
        let locked: Vec<(&str, bool)> = d
            .items
            .iter()
            .filter(|i| !i.text.is_empty())
            .map(|i| (i.text.as_str(), i.locked))
            .collect();
        assert_eq!(locked, [("primeira", true), ("segunda", false)]);
    }

    #[test]
    fn o_destino_cai_no_primeiro_ligado_quando_o_escolhido_nao_esta_mais() {
        let mut f = fila();
        assert_eq!(f.detail().destination.unwrap().as_str(), "dev");
        // Alvo que não é um nó ligado: o `target` da fila vale só enquanto
        // está ligado; o destino segue o primeiro.
        f.run(CommandKind::QueueSet(QueueSet {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            auto: None,
            target: Some(NodeId::new("sumiu").unwrap()),
        }));
        let d = f.detail();
        assert_eq!(d.destination.as_ref().unwrap().as_str(), "dev");
        assert_eq!(d.destination, d.target);
    }

    // O texto da coluna FILAS vem pronto, igual ao do chat, e o estado diz se
    // alguém pergunta e quais tarefas estão em branco.
    #[test]
    fn o_estado_manda_o_texto_da_coluna_filas_a_pergunta_e_as_em_branco() {
        let mut f = fila();
        let d = f.detail();
        assert_eq!((d.asking, d.summary.as_str()), (false, "nada pendente"));
        assert_eq!(d.subtitle, "nada pendente");
        let blank = f.add("");
        let a = f.add("primeira");
        f.add("segunda");
        let d = f.detail();
        assert_eq!(d.summary, "2 pendentes");
        assert_eq!(d.subtitle, "2 pendentes");
        let empties: Vec<bool> = d.items.iter().map(|i| i.empty).collect();
        assert_eq!(empties, [true, false, false]);
        assert_eq!(d.items[0].id, blank);

        // Enviada, a fila "está com" o agente; o subtítulo do nó não muda de
        // forma, o texto da coluna ganha o "com".
        f.run(CommandKind::QueueSend(QueueSend {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            item: Some(a.clone()),
        }));
        let d = f.detail();
        assert_eq!(d.summary, "1 pendente · com dev");
        assert_eq!(d.subtitle, "1 pendente");
        assert!(!d.asking);
    }

    #[test]
    fn print_sem_tarefa_dita_vai_para_a_aberta_ou_cria_uma_nova() {
        let mut f = fila();
        let open = f.add("aberta");
        let sent = f.add("enviada");
        f.run(CommandKind::QueueSend(QueueSend {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            item: Some(sent.clone()),
        }));
        let shot = |f: &mut Fila, open: Option<&str>| {
            let png = base64::engine::general_purpose::STANDARD.encode([7, 7]);
            f.run(CommandKind::QueueAttach(QueueAttach {
                workbench: f.wb.clone(),
                node: f.node.clone(),
                item: None,
                open: open.map(str::to_owned),
                path: None,
                png: Some(png),
            }))
        };
        // Na aberta (e não enviada): o print entra nela, e a resposta diz qual.
        let reply = shot(&mut f, Some(&open));
        assert_eq!(reply["ok"], true);
        assert_eq!(reply["item"], open.as_str());
        let d = f.detail();
        assert_eq!(
            d.items.iter().find(|i| i.id == open).unwrap().images.len(),
            1
        );
        let before = d.items.len();

        // Aberta que já foi enviada não recebe: nasce uma tarefa em branco.
        let reply = shot(&mut f, Some(&sent));
        let created = reply["item"].as_str().unwrap().to_owned();
        assert_ne!(created, sent);
        let d = f.detail();
        assert_eq!(d.items.len(), before + 1);
        let new = d.items.iter().find(|i| i.id == created).unwrap();
        // Em branco, mas com o print: já não é `empty`.
        assert!(new.text.is_empty() && new.images.len() == 1 && !new.empty && !new.locked);
        assert!(
            d.items
                .iter()
                .find(|i| i.id == sent)
                .unwrap()
                .images
                .is_empty()
        );

        // Com a tarefa dita mas sumida ou já enviada: erro, e nada anexado
        // nem criado.
        let count = f.detail().items.len();
        for item in ["fantasma", sent.as_str()] {
            let png = base64::engine::general_purpose::STANDARD.encode([7, 7]);
            let reply = f.run(CommandKind::QueueAttach(QueueAttach {
                workbench: f.wb.clone(),
                node: f.node.clone(),
                item: Some(item.to_owned()),
                open: None,
                path: None,
                png: Some(png),
            }));
            assert_eq!(reply["ok"], false, "{item}");
            assert_eq!(
                reply["error"],
                "a tarefa não existe ou já foi enviada: o print não foi anexado"
            );
        }
        assert_eq!(f.detail().items.len(), count);
        assert!(
            f.detail()
                .items
                .iter()
                .find(|i| i.id == sent)
                .unwrap()
                .images
                .is_empty()
        );

        // Sem aberta nenhuma, ou uma que sumiu: também nasce uma nova.
        for open in [None, Some("fantasma")] {
            let before = f.detail().items.len();
            let created = shot(&mut f, open)["item"].as_str().unwrap().to_owned();
            let d = f.detail();
            assert_eq!(d.items.len(), before + 1, "{open:?}");
            assert_eq!(d.items.last().unwrap().id, created);
        }
    }

    #[test]
    fn so_imagem_se_anexa_por_arquivo() {
        let mut f = fila();
        let a = f.add("com anexo");
        let attach = |f: &mut Fila, name: &str| {
            let source = f.rig.dir.path().join(name);
            std::fs::write(&source, [1]).unwrap();
            f.run(CommandKind::QueueAttach(QueueAttach {
                workbench: f.wb.clone(),
                node: f.node.clone(),
                item: Some(a.clone()),
                open: None,
                path: Some(source.to_string_lossy().into_owned()),
                png: None,
            }))
        };
        for name in ["nota.txt", "semextensao", "foto.png.zip"] {
            let reply = attach(&mut f, name);
            assert_eq!(reply["ok"], false, "{name}");
            assert_eq!(
                reply["error"],
                "só imagem se anexa (png, jpg, jpeg, gif, webp, heic, tiff, bmp)"
            );
        }
        assert!(f.detail().items[0].images.is_empty());
        for name in ["a.JPG", "b.Heic", "c.webp"] {
            assert_eq!(attach(&mut f, name)["ok"], true, "{name}");
        }
        assert_eq!(f.detail().items[0].images.len(), 3);
    }

    #[test]
    fn anexar_arquivo_ou_print_colado_e_tirar() {
        let mut f = fila();
        let a = f.add("com print");
        let source = f.rig.dir.path().join("tela.PNG");
        std::fs::write(&source, [1, 2, 3]).unwrap();
        let attach = |f: &mut Fila, path: Option<String>, png: Option<String>| {
            f.run(CommandKind::QueueAttach(QueueAttach {
                workbench: f.wb.clone(),
                node: f.node.clone(),
                item: Some(a.clone()),
                open: None,
                path,
                png,
            }))
        };
        assert_eq!(
            attach(&mut f, Some(source.to_string_lossy().into_owned()), None)["ok"],
            true
        );
        let pasted = base64::engine::general_purpose::STANDARD.encode([9, 9, 9]);
        assert_eq!(attach(&mut f, None, Some(pasted))["ok"], true);
        let images = f.detail().items[0].images.clone();
        assert_eq!(images.len(), 2);
        assert!(
            images[0].ends_with(".png"),
            "extensão em minúscula: {images:?}"
        );
        let folder = f
            .rig
            .data
            .join("workbenches")
            .join(f.wb.as_str())
            .join("queues/fila");
        assert_eq!(std::fs::read(folder.join(&images[0])).unwrap(), [1, 2, 3]);
        assert_eq!(std::fs::read(folder.join(&images[1])).unwrap(), [9, 9, 9]);

        // Sem arquivo e sem imagem, ou base64 ruim: erro, e nada se perde.
        assert_eq!(
            attach(&mut f, None, None)["error"],
            "sem arquivo nem imagem para anexar"
        );
        assert_eq!(
            attach(&mut f, None, Some("%%%".into()))["error"],
            "a imagem colada não é base64"
        );
        assert_eq!(f.detail().items[0].images.len(), 2);

        let reply = f.run(CommandKind::QueueDetach(QueueDetach {
            workbench: f.wb.clone(),
            node: f.node.clone(),
            item: a.clone(),
            image: images[0].clone(),
        }));
        assert_eq!(reply["ok"], true);
        assert_eq!(f.detail().items[0].images, [images[1].clone()]);
        assert!(!folder.join(&images[0]).exists());
    }

    #[test]
    fn sem_alvo_ligado_o_estado_traz_o_aviso() {
        let mut f = fila();
        f.rig.actor.org.state.workbenches[0].edges = Some(Vec::new());
        let d = f.detail();
        assert_eq!(d.target, None);
        assert!(d.targets.is_empty());
        assert_eq!(
            d.blocker.as_deref(),
            Some("Ligue a fila a um agente: arraste o + da borda até ele.")
        );
    }

    #[test]
    fn fila_ou_nome_que_nao_existe_e_erro_e_nao_e_fila() {
        let mut f = fila();
        let reply = f.run(CommandKind::QueueRemove(QueueItemRef {
            workbench: f.wb.clone(),
            node: NodeId::new("nada").unwrap(),
            item: "x".into(),
        }));
        assert_eq!(reply["ok"], false);
        assert_eq!(reply["error"], format!("fila desconhecida '{}/nada'", f.wb));
        // O agente não é uma fila: sem estado de fila para ele.
        assert!(
            f.rig
                .actor
                .queue_node_event(&f.wb, &NodeId::new("dev").unwrap())
                .is_none()
        );
        // Comando que não é da fila.
        let reply = f.rig.actor.queue_command(8, CommandKind::ListTerminals);
        assert_eq!(
            serde_json::to_value(reply).unwrap()["error"],
            "list_terminals não é da fila"
        );
    }

    #[test]
    fn quem_assina_o_no_recebe_o_estado_a_cada_comando() {
        let mut f = fila();
        let topic = Topic::Node(f.wb.clone(), f.node.clone());
        let (line_tx, mut lines) = tokio::sync::mpsc::channel(8);
        let (alive, _closed) = tokio::sync::oneshot::channel();
        f.rig.actor.clients.insert(
            1,
            super::super::Client {
                queue: line_tx,
                _alive: alive,
                topics: HashSet::from([topic]),
                resync: HashSet::new(),
            },
        );
        f.add("uma");
        let line = lines.try_recv().expect("o estado não foi publicado");
        let event: Value = serde_json::from_slice(&line).unwrap();
        assert_eq!(event["kind"], "queue");
        assert_eq!(event["topic"], format!("node/{}/fila", f.wb));
        assert_eq!(event["queue"]["items"][0]["text"], "uma");
        assert_eq!(event["queue"]["targets"][0]["id"], "dev");
    }

    // ---- De ponta a ponta pelo `/ui`: assinar, comandar e receber o estado

    #[tokio::test]
    async fn pelo_ui_assina_a_fila_adiciona_envia_e_recebe_o_estado_a_cada_passo() {
        use super::super::processes_commands::support::{drain, send, ui};

        let (mut rig, id) = rig_with_deck();
        let mut client = ui(&mut rig).await;
        let topic = format!("node/{id}/fila");
        let base = json!({"workbench": id, "node": "fila"});
        let cmd = |n: u64, name: &str, extra: Value| {
            let mut c = base.clone();
            c["id"] = json!(n);
            c["cmd"] = json!(name);
            for (k, v) in extra.as_object().cloned().unwrap_or_default() {
                c[k] = v;
            }
            c
        };

        // Assinar: a resposta vem antes e logo depois o estado inteiro da fila.
        send(
            &mut rig,
            &client,
            json!({"id": 1, "cmd": "subscribe", "topic": topic}),
        );
        let got = drain(&mut client);
        assert_eq!(got[0], json!({"re": 1, "ok": true}));
        assert_eq!(got[1]["kind"], "queue");
        assert_eq!(got[1]["topic"], topic);
        assert_eq!(got[1]["queue"]["items"], json!([]));
        assert_eq!(got[1]["queue"]["target"], "dev");
        assert_eq!(
            got[1]["queue"]["targets"],
            json!([{"id": "dev", "label": "dev"}])
        );

        // queue_add: responde o item novo e o estado novo sai a quem assina.
        send(
            &mut rig,
            &client,
            cmd(2, "queue_add", json!({"text": "roda os testes"})),
        );
        let got = drain(&mut client);
        let reply = got.iter().find(|l| l["re"] == 2).expect("sem resposta");
        let item = reply["item"].as_str().expect("sem item").to_owned();
        let state = got
            .iter()
            .find(|l| l["kind"] == "queue")
            .expect("sem estado");
        assert_eq!(state["queue"]["items"][0]["id"], item.as_str());
        assert_eq!(state["queue"]["items"][0]["text"], "roda os testes");
        assert_eq!(state["queue"]["items"][0]["status"], "pending");

        // queue_send: o item vai ao agente, e o estado mostra para quem.
        send(
            &mut rig,
            &client,
            cmd(3, "queue_send", json!({"item": item})),
        );
        let got = drain(&mut client);
        assert_eq!(
            got.iter().find(|l| l["re"] == 3).unwrap(),
            &json!({"re": 3, "ok": true})
        );
        let state = got.iter().find(|l| l["kind"] == "queue").unwrap();
        assert_eq!(state["queue"]["items"][0]["status"], "sent");
        assert_eq!(state["queue"]["items"][0]["sent_to"], "dev");
        assert_eq!(pending(&rig), 1);

        // Erro de regra volta como resposta de erro, sem estado novo.
        send(&mut rig, &client, cmd(4, "queue_send", json!({})));
        let got = drain(&mut client);
        assert_eq!(
            got,
            [json!({"re": 4, "ok": false, "error": "nada pendente"})]
        );

        // Fila que não existe.
        send(
            &mut rig,
            &client,
            json!({"id": 5, "cmd": "queue_clear_done", "workbench": id, "node": "nada"}),
        );
        let got = drain(&mut client);
        assert_eq!(got[0]["ok"], false);
        assert_eq!(got[0]["error"], format!("fila desconhecida '{id}/nada'"));
    }

    #[tokio::test]
    async fn pelo_ui_assinar_um_no_que_nao_e_fila_diz_que_nao_tem_estado_por_dentro() {
        use super::super::processes_commands::support::{drain, send, ui};

        let (mut rig, id) = rig_with_deck();
        let mut client = ui(&mut rig).await;
        send(
            &mut rig,
            &client,
            json!({"id": 1, "cmd": "subscribe", "topic": format!("node/{id}/dev")}),
        );
        assert_eq!(
            drain(&mut client),
            [json!({"re": 1, "ok": false, "error": "o nó 'dev' não tem estado por dentro"})]
        );
    }
}

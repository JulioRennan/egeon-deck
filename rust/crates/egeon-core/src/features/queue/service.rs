//! O que a fila de um nó faz: guardar, editar, mandar e, no automático, andar
//! sozinha a cada fim de turno do agente.
//!
//! Dona da fila DESTE nó e do arquivo dela — o `workbenches.json` não guarda
//! item nenhum. O resto chega pelo [`QueueHost`]: quem está ligado (as arestas
//! são da bancada), o estado do agente e o envio (do despacho). É o que deixa o
//! teste rodar sem tela e sem terminal. A hora vem por parâmetro; quem chama a
//! batida (`tick`) a cada segundo é o core.

use std::collections::HashMap;
use std::time::SystemTime;

use serde_json::{Map, Value, json};

use super::error::QueueError;
use super::model::{MessageKind, PromptQueue, QueueItem, QueueMessage, Status};
use super::runner::QueueRunner;
use super::store::QueueStore;
use crate::features::activity::model::Activity;
use crate::features::dispatch::request::TAG;

/// De quanto em quanto o core deve chamar [`QueueController::tick`].
pub const TICK_EVERY: std::time::Duration = std::time::Duration::from_secs(1);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Linked {
    pub id: String,
    pub label: String,
    /// Agente lê o rodapé com os comandos da tarefa; shell o executaria.
    pub agent: bool,
}

impl Linked {
    pub fn agent(id: &str) -> Self {
        Linked {
            id: id.to_owned(),
            label: id.to_owned(),
            agent: true,
        }
    }
}

/// O mundo de fora da fila.
pub trait QueueHost {
    /// Os nós ligados a esta fila por aresta, na ordem das arestas.
    fn linked(&self) -> Vec<Linked>;
    fn activity(&self, node: &str) -> Option<Activity>;
    /// Manda texto e imagens (caminho absoluto) ao nó. O erro é o texto que o
    /// usuário lê.
    fn dispatch(&mut self, node: &str, text: &str, images: &[String]) -> Result<(), String>;
}

pub struct QueueController {
    queue: PromptQueue,
    store: QueueStore,
    /// O nome do nó, que o agente vê no rodapé da tarefa.
    name: String,
    /// Viu o agente trabalhando depois do último envio — ver `QueueRunner`.
    saw_work: bool,
    /// Os ligados na última batida: aresta criada ou apagada no canvas muda o
    /// seletor sem ninguém avisar a fila.
    last_linked: Option<Vec<Linked>>,
    /// A fila mudou desde a última [`take_changed`](Self::take_changed): a
    /// view redesenha.
    changed: bool,
}

impl QueueController {
    pub fn new(store: QueueStore, name: impl Into<String>) -> Self {
        let queue = store.load();
        QueueController {
            queue,
            store,
            name: name.into(),
            saw_work: false,
            last_linked: None,
            changed: false,
        }
    }

    pub fn queue(&self) -> &PromptQueue {
        &self.queue
    }

    pub fn store(&self) -> &QueueStore {
        &self.store
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    /// Diz se a fila mudou desde a última vez que perguntaram, e zera.
    pub fn take_changed(&mut self) -> bool {
        std::mem::take(&mut self.changed)
    }

    pub fn destination(&self, host: &dyn QueueHost) -> Option<String> {
        let ids: Vec<String> = host.linked().into_iter().map(|l| l.id).collect();
        self.queue.destination(&ids).map(str::to_owned)
    }

    /// Por que não dá para mandar agora, ou `None`.
    pub fn blocker(&self, host: &dyn QueueHost) -> Option<QueueError> {
        self.destination(host)
            .is_none()
            .then_some(QueueError::NoDestination)
    }

    // ---- Edição

    /// Tarefa nova no fim, ou logo depois de `after` — o Enter no título de
    /// uma tarefa aberta cria a próxima ali, como no Things. Vazia é
    /// permitida: ela nasce para você escrever, e some se ficar vazia
    /// ([`drop_if_empty`](Self::drop_if_empty)).
    pub fn add(&mut self, text: &str, images: Vec<String>, after: Option<&str>) -> QueueItem {
        let item = QueueItem::new(text, images);
        match after.and_then(|id| self.queue.index_of(id)) {
            Some(index) => self.queue.items.insert(index + 1, item.clone()),
            None => self.queue.items.push(item.clone()),
        }
        self.changed();
        item
    }

    pub fn update(&mut self, id: &str, text: &str) {
        let Some(index) = self.queue.index_of(id) else {
            return;
        };
        let item = &mut self.queue.items[index];
        if item.is_locked() || item.text == text {
            return;
        }
        item.text = text.to_owned();
        self.changed();
    }

    /// O print que chega sem tarefa dita: vai para a aberta na UI, se ainda
    /// existe e não foi enviada (`QueueNode.performDragOperation`); senão cria
    /// uma tarefa em branco no fim. Com `item`, vai para ele — e se ele sumiu
    /// ou já foi enviado, a imagem é descartada e a resposta é `None`, para
    /// ninguém achar que o anexo entrou. Devolve a tarefa que ficou com a
    /// imagem.
    pub fn attach_to(
        &mut self,
        image: String,
        item: Option<&str>,
        open: Option<&str>,
    ) -> Option<String> {
        let usable = |queue: &Self, id: &str| {
            queue
                .queue
                .index_of(id)
                .is_some_and(|i| !queue.queue.items[i].is_locked())
        };
        let id = match (item, open) {
            (Some(id), _) if usable(self, id) => id.to_owned(),
            (Some(_), _) => {
                self.store.remove_images(&[image]);
                return None;
            }
            (None, Some(id)) if usable(self, id) => id.to_owned(),
            (None, _) => self.add("", Vec::new(), None).id,
        };
        self.attach(vec![image], &id);
        Some(id)
    }

    pub fn attach(&mut self, images: Vec<String>, id: &str) {
        let target = self
            .queue
            .index_of(id)
            .filter(|&i| !self.queue.items[i].is_locked() && !images.is_empty());
        let Some(index) = target else {
            // Quem salvou o print aqui não tem mais onde pô-lo.
            self.store.remove_images(&images);
            return;
        };
        self.queue.items[index].images.extend(images);
        self.changed();
    }

    pub fn detach(&mut self, image: &str, id: &str) {
        let Some(index) = self
            .queue
            .index_of(id)
            .filter(|&i| !self.queue.items[i].is_locked())
        else {
            return;
        };
        crate::log!("fila: print {image} tirado da tarefa {}", short(id));
        self.queue.items[index].images.retain(|i| i != image);
        self.store.remove_images(&[image.to_owned()]);
        self.changed();
    }

    /// A tarefa recolhida sem nada escrito não fica na lista.
    pub fn drop_if_empty(&mut self, id: &str) {
        if self
            .queue
            .index_of(id)
            .is_some_and(|i| self.queue.items[i].is_empty())
        {
            self.remove(id);
        }
    }

    /// O checkbox: feito vira pendente, e o resto vira feito — à mão, sem
    /// mandar nada (o problema que você resolveu sozinho).
    pub fn toggle_done(&mut self, id: &str, now: SystemTime) {
        let Some(index) = self.queue.index_of(id) else {
            return;
        };
        if self.queue.items[index].status == Status::Done {
            self.reopen(id);
            return;
        }
        self.queue.items[index].status = Status::Done;
        self.queue.items[index].done_at = Some(now);
        self.changed();
    }

    /// Tarefa com o agente não sai da lista: ele ainda pode marcá-la e
    /// perguntar.
    pub fn remove(&mut self, id: &str) {
        let Some(index) = self
            .queue
            .index_of(id)
            .filter(|&i| self.queue.items[i].status != Status::Sent)
        else {
            return;
        };
        crate::log!(
            "fila: tarefa {} apagada ({} print(s))",
            short(id),
            self.queue.items[index].images.len()
        );
        self.store.remove_images(&self.queue.items[index].images);
        self.queue.items.remove(index);
        self.changed();
    }

    pub fn move_by(&mut self, id: &str, offset: isize) {
        self.queue.move_by(id, offset);
        self.changed();
    }

    pub fn move_to(&mut self, id: &str, index: usize) {
        let before: Vec<String> = self.queue.items.iter().map(|i| i.id.clone()).collect();
        self.queue.move_to(id, index);
        if self.queue.items.iter().map(|i| &i.id).ne(before.iter()) {
            self.changed();
        }
    }

    /// Volta para pendente a que você marcou à mão. A que já foi a um agente
    /// não volta: quem a reabre é a resposta na thread.
    pub fn reopen(&mut self, id: &str) {
        let Some(index) = self
            .queue
            .index_of(id)
            .filter(|&i| !self.queue.items[i].is_locked())
        else {
            return;
        };
        let item = &mut self.queue.items[index];
        item.status = Status::Pending;
        item.sent_at = None;
        item.sent_to = None;
        item.done_at = None;
        self.changed();
    }

    /// Tira da lista o que já foi, com as imagens.
    pub fn clear_done(&mut self) {
        let images: Vec<String> = self
            .queue
            .items
            .iter()
            .filter(|i| i.status == Status::Done)
            .flat_map(|i| i.images.clone())
            .collect();
        let before = self.queue.items.len();
        self.queue.items.retain(|i| i.status != Status::Done);
        if self.queue.items.len() == before {
            return;
        }
        self.store.remove_images(&images);
        self.changed();
    }

    pub fn set_auto(&mut self, on: bool, host: &mut dyn QueueHost, now: SystemTime) {
        if self.queue.auto == on {
            return;
        }
        self.queue.auto = on;
        self.changed();
        if on {
            self.tick(host, now);
        }
    }

    pub fn set_target(&mut self, id: &str) {
        if self.queue.target.as_deref() == Some(id) {
            return;
        }
        self.queue.target = Some(id.to_owned());
        self.changed();
    }

    // ---- Envio

    /// Manda o item agora. Se outro ainda estava em andamento, ele é dado por
    /// encerrado: mandar por cima é decisão sua de seguir em frente, e a fila
    /// só acompanha um turno por vez.
    pub fn send(
        &mut self,
        id: &str,
        host: &mut dyn QueueHost,
        now: SystemTime,
    ) -> Result<(), QueueError> {
        let destination = self.destination(host).ok_or(QueueError::NoDestination)?;
        let index = self.queue.index_of(id).ok_or(QueueError::NoItem)?;
        let item = self.queue.items[index].clone();
        if item.is_locked() {
            return Err(QueueError::AlreadySent);
        }
        if item.is_empty() {
            return Err(QueueError::EmptyTask);
        }
        let agent = host
            .linked()
            .iter()
            .find(|l| l.id == destination)
            .is_some_and(|l| l.agent);
        // Comentário seu feito antes de mandar segue junto: é parte do pedido.
        let comments = item
            .thread
            .iter()
            .filter(|m| m.author.is_none())
            .map(|m| m.text.as_str());
        let body = std::iter::once(item.prompt())
            .chain(comments)
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join("\n\n");
        let text = if agent {
            format!("{body}\n\n{}", self.footer(&item))
        } else {
            body
        };
        let images: Vec<String> = item
            .images
            .iter()
            .map(|i| self.store.url_of(i).to_string_lossy().into_owned())
            .collect();
        if let Err(error) = host.dispatch(&destination, &text, &images) {
            crate::log!("fila: envio para {destination} falhou — {error}");
            return Err(QueueError::Dispatch(error));
        }
        let open = self
            .queue
            .in_flight()
            .filter(|c| c.id != id)
            .and_then(|c| self.queue.index_of(&c.id));
        if let Some(open) = open {
            self.queue.items[open].status = Status::Done;
            self.queue.items[open].done_at = Some(now);
        }
        let sent = &mut self.queue.items[index];
        sent.status = Status::Sent;
        sent.sent_to = Some(destination.clone());
        sent.sent_at = Some(now);
        sent.done_at = None;
        sent.awaiting = false;
        self.saw_work = false;
        crate::log!(
            "fila: item {} enviado para {destination} ({} imagem(ns), {} pendente(s))",
            short(id),
            item.images.len(),
            self.queue.pending_count()
        );
        self.changed();
        Ok(())
    }

    /// O que vai embaixo da tarefa: de onde ela veio e como o agente fala de
    /// volta com ela. Sem isso ele não sabe que a tarefa existe fora do prompt.
    pub fn footer(&self, item: &QueueItem) -> String {
        let short = item.short_id();
        format!(
            "{TAG} tarefa {short} da fila {}. Ao concluir: `egeon task done {short}`. \
             Para perguntar algo sobre ela: `egeon task ask {short}` com a pergunta no stdin — \
             a pergunta aparece na tarefa e a resposta volta para você.",
            self.name
        )
    }

    pub fn send_next(
        &mut self,
        host: &mut dyn QueueHost,
        now: SystemTime,
    ) -> Result<(), QueueError> {
        let next = self
            .queue
            .next_pending()
            .map(|i| i.id.clone())
            .ok_or(QueueError::NothingPending)?;
        self.send(&next, host, now)
    }

    // ---- Agente

    /// O que o agente vê com `egeon tasks`: as tarefas desta fila, curtas.
    pub fn tasks(&self) -> Vec<Value> {
        self.queue
            .items
            .iter()
            .filter(|i| !i.is_empty())
            .map(|item| {
                let mut out = Map::new();
                out.insert("id".into(), json!(item.short_id()));
                out.insert("text".into(), json!(item.text));
                out.insert("status".into(), json!(status_name(item.status)));
                out.insert("fila".into(), json!(self.name));
                if item.awaiting {
                    out.insert("awaiting".into(), json!(true));
                }
                if !item.thread.is_empty() {
                    let thread: Vec<Value> = item
                        .thread
                        .iter()
                        .map(|m| {
                            json!({
                                "from": m.author.as_deref().unwrap_or("você"),
                                "kind": kind_name(m.kind),
                                "text": m.text,
                            })
                        })
                        .collect();
                    out.insert("thread".into(), Value::Array(thread));
                }
                Value::Object(out)
            })
            .collect()
    }

    /// O agente mexeu na tarefa: `done`, `ask` ou `note`.
    pub fn agent(
        &mut self,
        author: &str,
        action: &str,
        typed: &str,
        text: &str,
        now: SystemTime,
    ) -> Result<(), QueueError> {
        let index = self
            .queue
            .index_matching(typed)
            .ok_or_else(|| QueueError::NoSuchTask {
                typed: typed.to_owned(),
                queue: self.name.clone(),
            })?;
        let text = text.trim();
        let message = |kind| QueueMessage {
            author: Some(author.to_owned()),
            kind,
            text: text.to_owned(),
            at: now,
        };
        let item = &mut self.queue.items[index];
        match action {
            "done" => {
                item.status = Status::Done;
                item.done_at = Some(now);
                item.awaiting = false;
                item.thread.push(message(MessageKind::Done));
                self.saw_work = false;
            }
            "ask" => {
                if text.is_empty() {
                    return Err(QueueError::EmptyQuestion);
                }
                item.awaiting = true;
                item.thread.push(message(MessageKind::Question));
            }
            "note" => {
                if text.is_empty() {
                    return Err(QueueError::EmptyNote);
                }
                item.thread.push(message(MessageKind::Note));
            }
            other => return Err(QueueError::UnknownAction(other.to_owned())),
        }
        crate::log!(
            "fila: {author} → {action} na tarefa {}",
            self.queue.items[index].short_id()
        );
        self.changed();
        Ok(())
    }

    /// Você escreveu na thread. Tarefa que já foi a um agente leva a resposta
    /// a ele — com a primeira linha, para ele saber do que se trata; a que
    /// ainda não foi só guarda o comentário, que segue junto quando ela for.
    pub fn reply(
        &mut self,
        id: &str,
        text: &str,
        host: &mut dyn QueueHost,
        now: SystemTime,
    ) -> Result<(), QueueError> {
        let text = text.trim();
        let Some(index) = self.queue.index_of(id).filter(|_| !text.is_empty()) else {
            return Ok(());
        };
        let item = self.queue.items[index].clone();
        if let Some(agent) = &item.sent_to {
            let prompt = format!(
                "Sobre a tarefa {} “{}” da fila {}:\n\n{text}",
                item.short_id(),
                item.headline(),
                self.name
            );
            host.dispatch(agent, &prompt, &[])
                .map_err(QueueError::Dispatch)?;
            self.queue.items[index].status = Status::Sent;
            self.queue.items[index].done_at = None;
            self.saw_work = false;
        }
        let item = &mut self.queue.items[index];
        item.awaiting = false;
        item.thread.push(QueueMessage {
            author: None,
            kind: MessageKind::Reply,
            text: text.to_owned(),
            at: now,
        });
        self.changed();
        Ok(())
    }

    /// Uma batida: fecha o item cujo turno acabou e, no automático, manda o
    /// próximo.
    pub fn tick(&mut self, host: &mut dyn QueueHost, now: SystemTime) {
        let current = host.linked();
        if self
            .last_linked
            .as_ref()
            .is_some_and(|last| *last != current)
        {
            self.changed = true;
        }
        let ids: Vec<String> = current.iter().map(|l| l.id.clone()).collect();
        self.last_linked = Some(current);
        let Some(destination) = self.queue.destination(&ids).map(str::to_owned) else {
            return;
        };
        let state = host.activity(&destination);
        if state.as_ref().is_some_and(QueueRunner::is_busy) {
            self.saw_work = true;
        }
        let step = QueueRunner::step(&self.queue, state.as_ref(), self.saw_work, now);
        if let Some(finished) = step.finish
            && let Some(index) = self.queue.index_of(&finished)
        {
            self.queue.items[index].status = Status::Done;
            self.queue.items[index].done_at = Some(now);
            self.saw_work = false;
            crate::log!(
                "fila: item {} concluído por {destination}",
                short(&finished)
            );
            self.changed();
        }
        if let Some(next) = step.send {
            let _ = self.send(&next, host, now);
        }
    }

    fn changed(&mut self) {
        self.store.save(&self.queue);
        self.changed = true;
    }

    /// A fila como dados, para a rota `/queue`.
    pub fn snapshot(&self, host: &dyn QueueHost) -> Value {
        let targets: Vec<String> = host.linked().into_iter().map(|l| l.id).collect();
        let items: Vec<Value> = self
            .queue
            .items
            .iter()
            .map(|item| {
                json!({
                    "id": item.id,
                    "text": item.text,
                    "images": item.images.len(),
                    "status": status_name(item.status),
                    "sentTo": item.sent_to.as_deref().unwrap_or(""),
                })
            })
            .collect();
        json!({
            "auto": self.queue.auto,
            "destination": self.queue.destination(&targets).unwrap_or(""),
            "targets": targets,
            "items": items,
        })
    }

    /// A rota `GET /queue?target=…`: aplica os parâmetros na ordem do Swift e
    /// devolve o que fez, junto com [`snapshot`](Self::snapshot).
    ///
    /// `open` e `draft` mexem no estado de tela do card, que não é daqui: o
    /// core os repassa à UI.
    pub fn control(
        &mut self,
        query: &HashMap<String, String>,
        host: &mut dyn QueueHost,
        now: SystemTime,
    ) -> Value {
        let mut result = Map::new();
        if let Some(text) = query.get("add") {
            let images = query
                .get("image")
                .and_then(|path| self.store.import_image(std::path::Path::new(path)))
                .into_iter()
                .collect();
            let added = self.add(text, images, None);
            result.insert("added".into(), json!(added.id));
        }
        if let Some(id) = query.get("done") {
            self.toggle_done(id, now);
        }
        if let Some(id) = query.get("remove") {
            self.remove(id);
        }
        if let Some(id) = query.get("reply") {
            let text = query.get("text").map_or("", String::as_str);
            let error = self.reply(id, text, host, now).err();
            result.insert(
                "error".into(),
                json!(error.map(|e| e.to_string()).unwrap_or_default()),
            );
        }
        if let Some(auto) = query.get("auto") {
            self.set_auto(auto == "1", host, now);
        }
        if let Some(target) = query.get("to") {
            self.set_target(target);
        }
        if let Some(id) = query.get("send") {
            let sent = if id == "next" {
                self.send_next(host, now)
            } else {
                self.send(id, host, now)
            };
            result.insert(
                "error".into(),
                json!(sent.err().map(|e| e.to_string()).unwrap_or_default()),
            );
        }
        if query.get("clear").is_some_and(|c| c == "done") {
            self.clear_done();
        }
        if let Value::Object(snapshot) = self.snapshot(host) {
            for (key, value) in snapshot {
                result.entry(key).or_insert(value);
            }
        }
        Value::Object(result)
    }
}

fn short(id: &str) -> String {
    id.chars().take(8).collect()
}

fn status_name(status: Status) -> &'static str {
    match status {
        Status::Pending => "pending",
        Status::Sent => "sent",
        Status::Done => "done",
    }
}

fn kind_name(kind: MessageKind) -> &'static str {
    match kind {
        MessageKind::Question => "question",
        MessageKind::Note => "note",
        MessageKind::Done => "done",
        MessageKind::Reply => "reply",
    }
}

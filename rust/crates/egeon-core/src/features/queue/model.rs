//! A fila e as tarefas, no formato do `queue.json` do Swift.

use std::time::SystemTime;

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use unicode_segmentation::UnicodeSegmentation;

use crate::features::chat::time::{format_iso, parse_iso};

/// Foundation grava a data em segundos inteiros (`.iso8601`), sem a fração que
/// o chat usa.
fn format_secs(at: SystemTime) -> String {
    let full = format_iso(at);
    // `2026-08-25T17:00:00.250Z` → `2026-08-25T17:00:00Z`.
    format!("{}Z", &full[..full.len() - 5])
}

mod iso_secs {
    use super::*;

    pub fn serialize<S: Serializer>(at: &SystemTime, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&format_secs(*at))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<SystemTime, D::Error> {
        let raw = String::deserialize(d)?;
        parse(&raw).ok_or_else(|| serde::de::Error::custom(format!("data inválida: {raw}")))
    }
}

/// O `.iso8601` do Foundation só aceita `T` e `Z` em maiúsculas.
fn parse(raw: &str) -> Option<SystemTime> {
    if raw.contains(['t', 'z']) {
        return None;
    }
    parse_iso(raw)
}

mod iso_secs_opt {
    use super::*;

    pub fn serialize<S: Serializer>(at: &Option<SystemTime>, s: S) -> Result<S::Ok, S::Error> {
        match at {
            Some(at) => s.serialize_str(&format_secs(*at)),
            None => s.serialize_none(),
        }
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Option<SystemTime>, D::Error> {
        match Option::<String>::deserialize(d)? {
            None => Ok(None),
            Some(raw) => parse(&raw)
                .map(Some)
                .ok_or_else(|| serde::de::Error::custom(format!("data inválida: {raw}"))),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MessageKind {
    /// O agente perguntou e espera você.
    Question,
    /// O agente comentou — andamento, achado, o que fez.
    Note,
    /// O agente marcou a tarefa como feita.
    Done,
    /// Você, respondendo ou comentando.
    Reply,
}

/// Uma mensagem na thread de uma tarefa — do agente ou sua.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueMessage {
    /// O nó do agente; `None` é você.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    pub kind: MessageKind,
    pub text: String,
    #[serde(with = "iso_secs")]
    pub at: SystemTime,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    /// Anotado, ainda não foi.
    Pending,
    /// Entregue ao agente, e o turno dele ainda não fechou.
    Sent,
    /// O agente fechou o turno em que recebeu este item.
    Done,
}

/// Uma tarefa da fila: um texto corrido e os prints — juntos, o prompt — e a
/// thread do que o agente e você disseram sobre ela.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(from = "RawItem", rename_all = "camelCase")]
pub struct QueueItem {
    pub id: String,
    /// Um texto só, como numa nota: não há título separado do corpo.
    pub text: String,
    /// Nomes dos arquivos na pasta da fila — relativos, para a pasta da
    /// bancada mudar de lugar sem quebrar nada.
    pub images: Vec<String>,
    pub status: Status,
    /// O nó que recebeu, e quando.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sent_to: Option<String>,
    #[serde(with = "iso_secs_opt", skip_serializing_if = "Option::is_none")]
    pub sent_at: Option<SystemTime>,
    #[serde(with = "iso_secs_opt", skip_serializing_if = "Option::is_none")]
    pub done_at: Option<SystemTime>,
    pub thread: Vec<QueueMessage>,
    /// O agente perguntou e você ainda não respondeu: a fila não anda.
    pub awaiting: bool,
}

/// Como a tarefa chega do disco. Thread e pergunta chegaram depois das
/// tarefas, e a v1.7 gravava título e notas em vez de um texto só: arquivo
/// antigo não pode perder a tarefa por falta de chave.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawItem {
    id: String,
    text: Option<String>,
    title: Option<String>,
    notes: Option<String>,
    images: Option<Vec<String>>,
    status: Option<Status>,
    sent_to: Option<String>,
    #[serde(default, with = "iso_secs_opt")]
    sent_at: Option<SystemTime>,
    #[serde(default, with = "iso_secs_opt")]
    done_at: Option<SystemTime>,
    thread: Option<Vec<QueueMessage>>,
    awaiting: Option<bool>,
}

impl From<RawItem> for QueueItem {
    fn from(raw: RawItem) -> Self {
        // Título e notas antigos viram o texto, com a linha em branco que o
        // prompt já levava.
        let text = raw.text.unwrap_or_else(|| {
            [raw.title, raw.notes]
                .into_iter()
                .flatten()
                .filter(|part| !part.is_empty())
                .collect::<Vec<_>>()
                .join("\n\n")
        });
        QueueItem {
            id: raw.id,
            text,
            images: raw.images.unwrap_or_default(),
            status: raw.status.unwrap_or(Status::Pending),
            sent_to: raw.sent_to,
            sent_at: raw.sent_at,
            done_at: raw.done_at,
            thread: raw.thread.unwrap_or_default(),
            awaiting: raw.awaiting.unwrap_or(false),
        }
    }
}

impl QueueItem {
    /// Tarefa nova, pendente, com id próprio.
    pub fn new(text: impl Into<String>, images: Vec<String>) -> Self {
        Self::with_id(
            uuid::Uuid::new_v4().to_string().to_uppercase(),
            text,
            images,
            Status::Pending,
        )
    }

    pub fn with_id(
        id: impl Into<String>,
        text: impl Into<String>,
        images: Vec<String>,
        status: Status,
    ) -> Self {
        QueueItem {
            id: id.into(),
            text: text.into(),
            images,
            status,
            sent_to: None,
            sent_at: None,
            done_at: None,
            thread: Vec::new(),
            awaiting: false,
        }
    }

    /// O id curto que o agente digita (`egeon task done 3f9a2c`).
    pub fn short_id(&self) -> String {
        self.id.to_lowercase().chars().take(6).collect()
    }

    /// Já foi a um agente: o texto e os prints são o registro do que foi
    /// pedido, e a partir daqui a conversa segue pela thread.
    pub fn is_locked(&self) -> bool {
        self.sent_at.is_some()
    }

    /// O que o agente recebe.
    pub fn prompt(&self) -> &str {
        self.text.trim()
    }

    /// A primeira linha, curta: como a resposta na thread diz de que tarefa
    /// fala.
    pub fn headline(&self) -> String {
        let line = self
            .prompt()
            .split(['\n', '\r'])
            .find(|l| !l.is_empty())
            .unwrap_or("");
        // Por grafema, como o `count` e o `prefix` do Swift: o corte não
        // parte um caractere composto.
        if line.graphemes(true).count() > 60 {
            let mut cut: String = line.graphemes(true).take(60).collect();
            cut.push('…');
            cut
        } else {
            line.to_owned()
        }
    }

    /// Sem texto e sem imagem não há o que mandar.
    pub fn is_empty(&self) -> bool {
        self.prompt().is_empty() && self.images.is_empty()
    }
}

/// A fila de um nó: os itens na ordem de envio, o modo automático e para quem.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PromptQueue {
    // `items` e `auto` são obrigatórios: o `Codable` sintetizado do Swift
    // recusa o arquivo sem eles e a fila abre vazia.
    pub items: Vec<QueueItem>,
    /// Manda o próximo sozinha quando o agente fecha o turno.
    pub auto: bool,
    /// O destino escolhido entre os nós ligados por aresta. `None`, ou um que
    /// não está mais ligado, cai no primeiro ligado.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<String>,
}

impl PromptQueue {
    pub fn in_flight(&self) -> Option<&QueueItem> {
        self.items.iter().find(|i| i.status == Status::Sent)
    }

    /// A tarefa ainda em branco é a que você está escrevendo, não a próxima.
    pub fn next_pending(&self) -> Option<&QueueItem> {
        self.items
            .iter()
            .find(|i| i.status == Status::Pending && !i.is_empty())
    }

    /// O subtítulo do nó de fila.
    pub fn pending_summary(&self) -> String {
        match self.pending_count() {
            0 => "nada pendente".to_owned(),
            1 => "1 pendente".to_owned(),
            n => format!("{n} pendentes"),
        }
    }

    pub fn pending_count(&self) -> usize {
        self.items
            .iter()
            .filter(|i| i.status == Status::Pending && !i.is_empty())
            .count()
    }

    pub fn destination<'a>(&'a self, linked: &'a [String]) -> Option<&'a str> {
        match &self.target {
            Some(target) if linked.contains(target) => Some(target),
            _ => linked.first().map(String::as_str),
        }
    }

    pub fn index_of(&self, id: &str) -> Option<usize> {
        self.items.iter().position(|i| i.id == id)
    }

    /// A tarefa pelo id que o agente digitou: o curto ou o inteiro, sem caixa.
    pub fn index_matching(&self, typed: &str) -> Option<usize> {
        let key = typed
            .to_lowercase()
            .trim_matches(|c: char| c.is_whitespace() && c != '\n' && c != '\r')
            .to_owned();
        if key.chars().count() < 4 {
            return None;
        }
        let mut found = self
            .items
            .iter()
            .enumerate()
            .filter(|(_, item)| item.id.to_lowercase().starts_with(&key))
            .map(|(index, _)| index);
        match (found.next(), found.next()) {
            (Some(index), None) => Some(index),
            _ => None,
        }
    }

    /// Leva o item para a posição `index` da lista SEM ele — a conta que o
    /// arrasto faz, contando só as linhas que ficaram no lugar.
    pub fn move_to(&mut self, id: &str, index: usize) {
        let Some(from) = self.index_of(id) else {
            return;
        };
        let item = self.items.remove(from);
        self.items.insert(index.min(self.items.len()), item);
    }

    /// Sobe ou desce um item, sem sair da lista.
    pub fn move_by(&mut self, id: &str, offset: isize) {
        let Some(from) = self.index_of(id) else {
            return;
        };
        let last = self.items.len() as isize - 1;
        let to = (from as isize + offset).clamp(0, last) as usize;
        if to != from {
            let item = self.items.remove(from);
            self.items.insert(to, item);
        }
    }
}

//! A thread da bancada: cruza os transcripts de todos os agentes por tempo e
//! marca as citações, no jeito do WhatsApp.

use std::collections::{BTreeMap, BTreeSet};
use std::time::SystemTime;

use serde::{Deserialize, Serialize};

use super::model::ChatTurn;
use super::time::{iso, swift_double, unix_f64};
use crate::commons::ids::NodeId;
use crate::features::activity::model::Activity;
use crate::features::dispatch::failure::MAX_ATTEMPTS;
use crate::features::node::model::{NodeConfig, NodeKind};
use crate::features::queue::chat::ChatQueue;

/// Um participante do modo chat: agente ou shell da bancada, como estado puro.
/// O web fica de fora — não é endereçável e não tem conversa.
#[derive(Debug, Clone, PartialEq)]
pub struct ChatParticipant {
    pub id: String,
    /// `bancada/id` — o endereço que o Dispatcher entende.
    pub address: String,
    pub is_agent: bool,
    /// O que aparece embaixo do nome: papel do agente ou comando do shell.
    pub role: Option<String>,
    pub activity: Activity,
    /// O terminal que a UI assina em `screen/<id>`: o chat mostra o shell em
    /// foco no lugar da thread.
    pub screen: Option<String>,
}

/// O participante como a linha o mostra. Sem `activity`: ela muda a cada turno de
/// todo mundo e a linha não a mostra — com ela, cada mudança de estado faria
/// todas as linhas do agente parecerem outras.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Who {
    pub id: String,
    pub address: String,
    pub is_agent: bool,
    pub role: Option<String>,
}

/// O participante para a barra de quem está na conversa (op `participants` do
/// canal): o mesmo da linha mais o estado, que é o que a barra mostra — ocupado,
/// esperando, morto.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParticipantInfo {
    pub id: String,
    pub address: String,
    pub is_agent: bool,
    pub role: Option<String>,
    /// O nome do caso de `Activity` em minúsculas (`working`, `waiting`, `dead`…).
    pub activity: String,
    /// A cor do estado (`green`, `orange` ou `red`); ausente nos demais — a UI
    /// não mapeia nome em cor.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tone: Option<String>,
    /// Interrompe: borda e som (`Activity.needsAttention`).
    #[serde(default)]
    pub needs_attention: bool,
    /// O id da tela do terminal (`screen/<id>`), o mesmo do nó no canvas.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub screen: Option<String>,
    /// A linha embaixo do nome, pronta: o que o participante faz agora ou,
    /// parado, o papel (`roleText` do Swift).
    #[serde(default)]
    pub status: String,
    /// A cor dessa linha: `orange` pedindo você, `red` falhou, `agent` (a cor
    /// do agente) trabalhando; ausente, o cinza de sempre.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status_tone: Option<String>,
}

/// O `"\(p.activity)"` do Swift: o nome do caso em minúsculas, sem os valores
/// associados.
pub fn activity_name(activity: &Activity) -> &'static str {
    match activity {
        Activity::Starting => "starting",
        Activity::Ready => "ready",
        Activity::Working => "working",
        Activity::Waiting => "waiting",
        Activity::Asking => "asking",
        Activity::Background => "background",
        Activity::Awaiting(_) => "awaiting",
        Activity::Retrying { .. } => "retrying",
        Activity::Failed(_) => "failed",
        Activity::Dead => "dead",
    }
}

/// Uma fila na coluna: não é participante — ninguém fala com ela pelo composer.
/// `summary` e `asking` vêm prontos (o `ChatQueue` do Swift).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QueueInfo {
    pub id: String,
    pub summary: String,
    pub asking: bool,
}

impl From<&ChatQueue> for QueueInfo {
    fn from(queue: &ChatQueue) -> Self {
        QueueInfo {
            id: queue.id.clone(),
            summary: queue.summary(),
            asking: queue.asking,
        }
    }
}

/// A linha embaixo do nome na coluna (`ParticipantsColumn.roleText` do
/// Swift): o estado quando ele diz algo, senão o papel.
pub fn status_text(activity: &Activity, role: Option<&str>) -> String {
    match activity {
        Activity::Dead => "terminal fechado".to_owned(),
        Activity::Working => "trabalhando…".to_owned(),
        Activity::Starting => "preparando…".to_owned(),
        Activity::Asking => "precisa de você".to_owned(),
        Activity::Background => "em segundo plano".to_owned(),
        Activity::Awaiting(peers) => format!(
            "aguardando {}",
            if peers.is_empty() {
                "vizinho".to_owned()
            } else {
                peers.join(", ")
            }
        ),
        Activity::Retrying { attempt, .. } => {
            format!("tentando de novo ({attempt}/{MAX_ATTEMPTS})")
        }
        Activity::Failed(why) => format!("falhou — {why}"),
        Activity::Ready | Activity::Waiting => role.unwrap_or_default().to_owned(),
    }
}

/// A cor dessa linha (`roleColor` do Swift).
pub fn status_tone(activity: &Activity) -> Option<&'static str> {
    match activity {
        Activity::Asking => Some("orange"),
        Activity::Failed(_) => Some("red"),
        Activity::Working => Some("agent"),
        _ => None,
    }
}

/// A tabela de cor do `Activity` do Swift; a mesma que `runtime::org::activity_view`
/// põe no `tone` do nó.
pub fn activity_tone(activity: &Activity) -> Option<&'static str> {
    match activity {
        Activity::Waiting => Some("green"),
        Activity::Asking => Some("orange"),
        Activity::Failed(_) | Activity::Dead => Some("red"),
        _ => None,
    }
}

impl ChatParticipant {
    pub fn info(&self) -> ParticipantInfo {
        ParticipantInfo {
            id: self.id.clone(),
            address: self.address.clone(),
            is_agent: self.is_agent,
            role: self.role.clone(),
            activity: activity_name(&self.activity).to_owned(),
            tone: activity_tone(&self.activity).map(str::to_owned),
            needs_attention: self.activity.needs_attention(),
            screen: self.screen.clone(),
            status: status_text(&self.activity, self.role.as_deref()),
            status_tone: status_tone(&self.activity).map(str::to_owned),
        }
    }

    pub fn who(&self) -> Who {
        Who {
            id: self.id.clone(),
            address: self.address.clone(),
            is_agent: self.is_agent,
            role: self.role.clone(),
        }
    }

    /// `✦` para agente, `❯` para shell.
    pub fn glyph(&self) -> &'static str {
        if self.is_agent { "✦" } else { "❯" }
    }

    /// Quem entra no grupo: agentes e shells. `activity` devolve o estado do
    /// terminal; sem alvo no Dispatcher é terminal morto. O endereço usa o nome
    /// da bancada; a tela, o id.
    pub fn from_nodes(
        nodes: &[NodeConfig],
        workbench_id: &str,
        workbench: &str,
        activity: impl Fn(&str) -> Option<Activity>,
    ) -> Vec<ChatParticipant> {
        nodes
            .iter()
            .filter(|n| matches!(n.kind, NodeKind::Agent | NodeKind::Shell))
            .map(|node| {
                let address = format!("{workbench}/{}", node.id);
                let is_agent = node.kind == NodeKind::Agent;
                // Só a primeira linha do papel: a lista não é lugar de prompt
                // inteiro.
                let role = if is_agent {
                    node.prompt
                        .as_deref()
                        .and_then(|p| p.split('\n').find(|l| !l.is_empty()))
                        .map(str::to_owned)
                } else {
                    Some(node.cmd.clone().unwrap_or_else(|| "shell".to_owned()))
                };
                ChatParticipant {
                    id: node.id.clone(),
                    screen: NodeId::screen(workbench_id, &node.id).map(String::from),
                    activity: activity(&address).unwrap_or(Activity::Dead),
                    address,
                    is_agent,
                    role,
                }
            })
            .collect()
    }
}

/// As cores dos agentes, em sRGB 0…1 (`AgentPalette.colors`). Hex fixo, não cor
/// dinâmica do sistema: ela muda com o tema e quebraria o "reconheço o agente pela
/// cor de longe".
pub const AGENT_COLORS: [(f64, f64, f64); 6] = [
    (0.784, 0.529, 0.980), // roxo
    (0.255, 0.765, 0.949), // azul
    (0.941, 0.392, 0.549), // rosa
    (0.404, 0.847, 0.910), // ciano
    (0.843, 0.706, 0.353), // amarelo
    (0.263, 0.820, 0.486), // verde
];

/// A cor do shell, que não é agente (`AgentPalette.shell`).
pub const SHELL_COLOR: (f64, f64, f64) = (0.604, 0.655, 0.733);

/// O índice da cor de um agente em [`AGENT_COLORS`]: FNV-1a de 64 bits sobre o id.
/// Hash estável e não o do `HashMap`, que muda a cada processo — a cor do agente
/// não pode trocar entre um arranque e outro.
pub fn agent_color_index(id: &str) -> usize {
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    for byte in id.bytes() {
        hash ^= u64::from(byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
    }
    (hash % AGENT_COLORS.len() as u64) as usize
}

pub fn agent_color(id: &str) -> (f64, f64, f64) {
    AGENT_COLORS[agent_color_index(id)]
}

/// A citação em cima de uma bolha, no jeito do WhatsApp: de quem é, o que dizia e
/// onde está na thread (para o clique rolar até lá).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatQuote {
    /// `None` é o usuário.
    pub author_id: Option<String>,
    pub text: String,
    #[serde(with = "iso")]
    pub at: SystemTime,
    pub target_key: String,
}

/// Uma linha da thread: o prompt do usuário para alguém, a resposta de alguém, ou
/// um prompt que acabou de sair e o transcript ainda não confirmou.
#[derive(Debug, Clone, PartialEq)]
pub enum ChatMessage {
    /// `from` é quem mandou quando não foi o usuário: o id do agente remetente (ou
    /// o endereço cru, se ele não está na bancada). A linha do tempo é plana, como
    /// num grupo do WhatsApp: a mensagem do front para o back é uma bolha do front,
    /// e a resposta do back é uma bolha do back (ADR-042).
    Prompt {
        to: ChatParticipant,
        turn_id: String,
        text: String,
        at: SystemTime,
        quote: Option<ChatQuote>,
        from: Option<String>,
    },
    Reply {
        from: ChatParticipant,
        turn: Box<ChatTurn>,
        quote: Option<ChatQuote>,
    },
    /// Eco local. Entra na linha do tempo pela hora do envio — pinado embaixo,
    /// uma resposta que chegasse antes da confirmação passaria por cima dele.
    Pending {
        to: ChatParticipant,
        text: String,
        at: SystemTime,
        quote: Option<ChatQuote>,
    },
}

impl ChatMessage {
    pub fn prompt(to: &ChatParticipant, turn_id: &str, text: &str, at: SystemTime) -> Self {
        ChatMessage::Prompt {
            to: to.clone(),
            turn_id: turn_id.to_owned(),
            text: text.to_owned(),
            at,
            quote: None,
            from: None,
        }
    }

    pub fn reply(from: &ChatParticipant, turn: ChatTurn) -> Self {
        ChatMessage::Reply {
            from: from.clone(),
            turn: Box::new(turn),
            quote: None,
        }
    }

    pub fn at(&self) -> SystemTime {
        match self {
            ChatMessage::Prompt { at, .. } | ChatMessage::Pending { at, .. } => *at,
            ChatMessage::Reply { turn, .. } => turn.reply_at.unwrap_or(turn.prompt_at),
        }
    }

    /// Identidade estável da mensagem entre remontagens — alvo de citação.
    pub fn key(&self) -> String {
        match self {
            ChatMessage::Prompt { turn_id, .. } => format!("p|{turn_id}"),
            ChatMessage::Reply { turn, .. } => format!("r|{}", turn.id),
            ChatMessage::Pending { to, at, .. } => {
                format!("e|{}|{}", to.id, swift_double(unix_f64(*at)))
            }
        }
    }

    pub fn participant_id(&self) -> &str {
        match self {
            ChatMessage::Prompt { to, .. } | ChatMessage::Pending { to, .. } => &to.id,
            ChatMessage::Reply { from, .. } => &from.id,
        }
    }

    pub fn prompt_text(&self) -> Option<&str> {
        match self {
            ChatMessage::Prompt { text, .. } => Some(text),
            _ => None,
        }
    }

    /// Quem mandou o prompt, quando foi outro agente. `None` é o usuário.
    pub fn sender_id(&self) -> Option<&str> {
        match self {
            ChatMessage::Prompt { from, .. } => from.as_deref(),
            _ => None,
        }
    }

    pub fn quote(&self) -> Option<&ChatQuote> {
        match self {
            ChatMessage::Prompt { quote, .. }
            | ChatMessage::Reply { quote, .. }
            | ChatMessage::Pending { quote, .. } => quote.as_ref(),
        }
    }

    fn with_quote(&self, new: Option<ChatQuote>) -> ChatMessage {
        let mut copy = self.clone();
        match &mut copy {
            ChatMessage::Prompt { quote, .. }
            | ChatMessage::Reply { quote, .. }
            | ChatMessage::Pending { quote, .. } => *quote = new,
        }
        copy
    }

    /// Cruza os transcripts de todos os agentes por tempo e marca as citações.
    ///
    /// A regra é a do WhatsApp: consecutivo é limpo; intercalado é citado. Uma
    /// resposta que não vem logo depois do próprio prompt cita esse prompt; um
    /// prompt do usuário que não vem logo depois de uma fala do mesmo agente cita a
    /// última resposta dele. Sem isto, dois papos ao mesmo tempo "juntam".
    pub fn thread(
        participants: &[ChatParticipant],
        extra: Vec<ChatMessage>,
        turns: impl Fn(&ChatParticipant) -> Vec<ChatTurn>,
    ) -> Vec<ChatMessage> {
        let agents: Vec<&ChatParticipant> = participants.iter().filter(|p| p.is_agent).collect();
        // Plano, sem sub-conversa: cada turno de cada agente é uma bolha de topo,
        // inclusive o que chegou de outro agente — esse leva quem mandou.
        let mut by_address: BTreeMap<&str, &ChatParticipant> = BTreeMap::new();
        for agent in &agents {
            by_address.entry(agent.address.as_str()).or_insert(agent);
        }
        let mut messages = extra;
        for agent in &agents {
            for turn in turns(agent) {
                let from = turn.from.as_ref().map(|address| {
                    by_address
                        .get(address.as_str())
                        .map_or_else(|| address.clone(), |p| p.id.clone())
                });
                messages.push(ChatMessage::Prompt {
                    to: (*agent).clone(),
                    turn_id: turn.id.clone(),
                    text: turn.prompt.clone(),
                    at: turn.prompt_at,
                    quote: None,
                    from,
                });
                if turn.has_reply() {
                    messages.push(ChatMessage::reply(agent, turn));
                }
            }
        }
        // `sort` por chave composta: dois itens no mesmo instante trocariam de
        // lugar entre uma remontagem e outra. O índice desempata.
        let mut indexed: Vec<(usize, ChatMessage)> = messages.into_iter().enumerate().collect();
        indexed.sort_by_key(|(index, message)| (message.at(), *index));
        let sorted: Vec<ChatMessage> = indexed.into_iter().map(|(_, m)| m).collect();
        Self::quoting(&sorted)
    }

    pub fn quoting(sorted: &[ChatMessage]) -> Vec<ChatMessage> {
        let mut out = Vec::with_capacity(sorted.len());
        for (index, message) in sorted.iter().enumerate() {
            let previous = index.checked_sub(1).map(|i| &sorted[i]);
            match message {
                ChatMessage::Reply { turn, .. } => {
                    let follows_own_prompt = matches!(
                        previous,
                        Some(ChatMessage::Prompt { turn_id, .. }) if *turn_id == turn.id
                    );
                    if follows_own_prompt {
                        out.push(message.clone());
                    } else {
                        // O prompt pode ter vindo de outro agente: a citação diz
                        // quem perguntou, não "você".
                        let sender = sorted
                            .iter()
                            .find(|m| matches!(m, ChatMessage::Prompt { turn_id, .. } if *turn_id == turn.id))
                            .and_then(|m| m.sender_id())
                            .map(str::to_owned);
                        out.push(message.with_quote(Some(ChatQuote {
                            author_id: sender,
                            text: turn.prompt.clone(),
                            at: turn.prompt_at,
                            target_key: format!("p|{}", turn.id),
                        })));
                    }
                }
                ChatMessage::Prompt { to, .. } | ChatMessage::Pending { to, .. } => {
                    // Mensagem de agente para agente já diz de quem é e para quem
                    // vai: não é resposta a nada, não cita.
                    if previous.is_none_or(|p| p.participant_id() == to.id)
                        || message.sender_id().is_some()
                    {
                        out.push(message.clone());
                        continue;
                    }
                    let last = sorted[..index]
                        .iter()
                        .rev()
                        .find(|m| matches!(m, ChatMessage::Reply { from, .. } if from.id == to.id));
                    match last {
                        Some(last @ ChatMessage::Reply { from, turn, .. }) => {
                            out.push(message.with_quote(Some(ChatQuote {
                                author_id: Some(from.id.clone()),
                                text: turn.reply_text.clone(),
                                at: last.at(),
                                target_key: last.key(),
                            })));
                        }
                        _ => out.push(message.clone()),
                    }
                }
            }
        }
        out
    }
}

/// O eco local de um envio que o transcript ainda não confirmou.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pending {
    pub text: String,
    pub target: String,
    pub sent_at: SystemTime,
    /// Os turnos que o agente JÁ tinha quando este envio saiu — e os que foram
    /// aparecendo depois sem ser este eco.
    pub known_turn_ids: BTreeSet<String>,
}

/// Monta a thread cruzando os transcripts de todos os agentes por tempo.
pub fn build(
    participants: &[ChatParticipant],
    turns: impl Fn(&ChatParticipant) -> Vec<ChatTurn>,
) -> Vec<ChatMessage> {
    ChatMessage::thread(participants, Vec::new(), turns)
}

/// A thread com os ecos DENTRO da linha do tempo, e os ecos que sobraram depois
/// de o transcript confirmar o que já chegou.
pub fn build_with_pending(
    participants: &[ChatParticipant],
    pending: &[Pending],
    turns: impl Fn(&ChatParticipant) -> Vec<ChatTurn>,
) -> (Vec<ChatMessage>, Vec<Pending>) {
    let confirmed = ChatMessage::thread(participants, Vec::new(), &turns);
    let left = still_pending(pending, &confirmed);
    let echoes: Vec<ChatMessage> = left
        .iter()
        .filter_map(|item| {
            let to = participants.iter().find(|p| p.id == item.target)?;
            Some(ChatMessage::Pending {
                to: to.clone(),
                text: item.text.clone(),
                at: item.sent_at,
                quote: None,
            })
        })
        .collect();
    (ChatMessage::thread(participants, echoes, &turns), left)
}

/// O eco local de um envio só vale até o transcript mostrar o prompt: daí a
/// mensagem de verdade entra e o eco sairia duplicado. Só confirma um turno NOVO
/// — id que não existia na hora do envio — com o mesmo texto. Por texto e hora, o
/// segundo "oi" era confirmado pelo primeiro.
pub fn still_pending(pending: &[Pending], messages: &[ChatMessage]) -> Vec<Pending> {
    let mut remaining: Vec<Pending> = pending.to_vec();
    // Um turno novo confirma UM eco: dois "oi" seguidos são dois turnos, e o
    // primeiro a chegar não pode dar baixa nos dois. Depois de visto, o turno vira
    // conhecido para os ecos que sobraram — esta função roda a cada refresh com a
    // lista inteira, e sem isso o mesmo turno daria baixa no eco seguinte na
    // rodada seguinte.
    for message in messages {
        let ChatMessage::Prompt { to, turn_id, .. } = message else {
            continue;
        };
        if let Some(at) = remaining.iter().position(|p| {
            p.target == to.id
                && Some(p.text.as_str()) == message.prompt_text()
                && !p.known_turn_ids.contains(turn_id)
        }) {
            remaining.remove(at);
        }
        for item in &mut remaining {
            item.known_turn_ids.insert(turn_id.clone());
        }
    }
    remaining
}

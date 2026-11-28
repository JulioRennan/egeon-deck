//! A visão do chat de uma bancada: o que o ator guarda para montar a thread, o
//! diff de linhas que vai para a UI e as ações que a UI manda (abrir um passo,
//! carregar mais histórico, limpar).
//!
//! # O contrato do canal `/ui`
//!
//! A cada mudança o ator chama [`ChatView::rebuild`] com o que leu (histórico,
//! cauda do transcript, atividade dos terminais); quando algo mudou ele devolve um
//! [`ChatUpdate`], que serializa numa linha NDJSON:
//!
//! ```json
//! {"topic":"chat/w1","workbench":"w1","rev":7,"ops":[
//!   {"op":"remove","id":"b|u1|2"},
//!   {"op":"insert","index":7,"block":{…}},
//!   {"op":"update","block":{…}}]}
//! ```
//!
//! O tópico é por bancada: `chat/<id da bancada>` (decisão 29). Além dos blocos há
//! dois ops de estado, que sempre levam o valor inteiro: `participants`, a barra
//! de quem está na conversa com o estado de cada um, `queues`, as filas da
//! bancada (`{"op":"queues","list":[{id,summary,asking}]}`) e `permissions`, a
//! bandeja com os pedidos abertos, empilhados como no Swift
//! (`{"op":"permissions","list":[{…}]}`).
//!
//! `reset` leva a lista inteira e vale na primeira entrega, quando a ordem dos
//! ids comuns muda (a resposta ao vivo muda de hora e pode trocar de lugar), na
//! limpeza e quando a janela de histórico cresce. Fora isso: `remove` por id,
//! `insert` com o índice na lista FINAL (em ordem crescente, depois dos
//! `remove`) e `update` do mesmo id com o conteúdo novo — o mesmo critério do
//! `ChatThreadController.apply` do Swift. `rev` sobe um por evento; quem perder um
//! `rev` pede o [`ChatView::snapshot`].

use std::collections::{BTreeMap, BTreeSet};
use std::time::SystemTime;

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::blocks::{
    BlockKind, BuildInput, ChatBlock, ChatGroupLevel, ChatLive, LiveStatus, build as build_blocks,
};
use super::model::{ChatPart, ChatRecord, ChatTurn};
use super::thread::{
    ChatMessage, ChatParticipant, ParticipantInfo, Pending, QueueInfo, build_with_pending,
};
use crate::features::activity::model::Activity;
use crate::features::agent::claude::transcript::{LastBlock, LiveTurn};
use crate::features::usage::PriceTable;

/// Conversa longa tem milhares de turnos; a UI só desenha o visível, mas medir
/// todos na primeira montagem pesa e ninguém rola até lá. Entra o fim, e a janela
/// cresce quando o usuário rola até o começo do que há — como o WhatsApp
/// carregando mensagens antigas.
pub const WINDOW_STEP: usize = 60;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "camelCase")]
pub enum BlockOp {
    Reset {
        blocks: Vec<ChatBlock>,
    },
    /// A barra de quem está na conversa.
    Participants {
        list: Vec<ParticipantInfo>,
    },
    /// As filas da bancada, para a seção FILAS da coluna.
    Queues {
        list: Vec<QueueInfo>,
    },
    /// Os pedidos de permissão em aberto, na ordem do `PermissionDesk`; vazia,
    /// a bandeja some.
    Permissions {
        list: Vec<Value>,
    },
    Remove {
        id: String,
    },
    Insert {
        index: usize,
        block: ChatBlock,
    },
    Update {
        block: ChatBlock,
    },
}

/// Uma linha do canal `/ui`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChatUpdate {
    pub topic: String,
    pub workbench: String,
    pub rev: u64,
    pub ops: Vec<BlockOp>,
}

/// O que um refresh lê de fora.
pub struct ThreadInput<'a> {
    pub participants: &'a [ChatParticipant],
    pub records: &'a [ChatRecord],
    /// O turno em curso de cada agente, lido da cauda do transcript.
    pub live: &'a BTreeMap<String, LiveTurn>,
    pub prices: &'a PriceTable,
}

pub struct ChatView {
    workbench: String,
    rev: u64,
    loaded_messages: usize,
    loading_more: bool,
    expanded: BTreeSet<String>,
    groups: BTreeMap<String, ChatGroupLevel>,
    pending: Vec<Pending>,
    messages: Vec<ChatMessage>,
    blocks: Vec<ChatBlock>,
    participants: Vec<ParticipantInfo>,
    queues: Vec<QueueInfo>,
    permissions: Vec<Value>,
}

impl ChatView {
    pub fn new(workbench: &str) -> ChatView {
        ChatView {
            workbench: workbench.to_owned(),
            rev: 0,
            loaded_messages: WINDOW_STEP,
            loading_more: false,
            expanded: BTreeSet::new(),
            groups: BTreeMap::new(),
            pending: Vec::new(),
            messages: Vec::new(),
            blocks: Vec::new(),
            participants: Vec::new(),
            queues: Vec::new(),
            permissions: Vec::new(),
        }
    }

    /// O tópico do canal desta bancada.
    pub fn topic(&self) -> String {
        format!("chat/{}", self.workbench)
    }

    fn update(&mut self, ops: Vec<BlockOp>) -> ChatUpdate {
        self.rev += 1;
        ChatUpdate {
            topic: self.topic(),
            workbench: self.workbench.clone(),
            rev: self.rev,
            ops,
        }
    }

    pub fn participants(&self) -> &[ParticipantInfo] {
        &self.participants
    }

    pub fn queues(&self) -> &[QueueInfo] {
        &self.queues
    }

    pub fn permissions(&self) -> &[Value] {
        &self.permissions
    }

    /// A barra de quem está na conversa mudou? Só sai evento quando a lista (ou o
    /// estado de alguém) é outra.
    pub fn set_participants(&mut self, list: Vec<ParticipantInfo>) -> Option<ChatUpdate> {
        if list == self.participants {
            return None;
        }
        self.participants = list.clone();
        Some(self.update(vec![BlockOp::Participants { list }]))
    }

    /// As filas da bancada mudaram?
    pub fn set_queues(&mut self, list: Vec<QueueInfo>) -> Option<ChatUpdate> {
        if list == self.queues {
            return None;
        }
        self.queues = list.clone();
        Some(self.update(vec![BlockOp::Queues { list }]))
    }

    /// A bandeja de permissão mudou? Lista vazia a esvazia.
    pub fn set_permissions(&mut self, list: Vec<Value>) -> Option<ChatUpdate> {
        if list == self.permissions {
            return None;
        }
        self.permissions = list.clone();
        Some(self.update(vec![BlockOp::Permissions { list }]))
    }

    pub fn blocks(&self) -> &[ChatBlock] {
        &self.blocks
    }

    pub fn messages(&self) -> &[ChatMessage] {
        &self.messages
    }

    pub fn pending_count(&self) -> usize {
        self.pending.len()
    }

    pub fn loaded_messages(&self) -> usize {
        self.loaded_messages
    }

    pub fn expanded_steps(&self) -> &BTreeSet<String> {
        &self.expanded
    }

    pub fn group_levels(&self) -> &BTreeMap<String, ChatGroupLevel> {
        &self.groups
    }

    pub fn rev(&self) -> u64 {
        self.rev
    }

    // ---- montagem ----------------------------------------------------------

    /// Cruza transcripts, ordena, cita, monta as linhas e devolve o que mudou
    /// desde a última vez; `None` quando nada mudou — o tique de 1 s sem mudança
    /// não monta nem manda nada.
    pub fn rebuild(&mut self, input: &ThreadInput) -> Option<ChatUpdate> {
        let recorded: BTreeSet<String> = input.records.iter().map(ChatRecord::key).collect();
        let (messages, pending) = build_with_pending(input.participants, &self.pending, |agent| {
            turns_of(agent, input)
        });

        // O turno ao vivo de cada agente que trabalha: a bolha dele ganha a linha
        // de status. Quem trabalha e ainda não gravou nada do turno (ou não tem
        // transcript) ganha a bolha de "trabalhando…" solta no fim. Terminal
        // subindo não está respondendo a ninguém — a coluna já diz "preparando…",
        // e uma bolha ali era resposta a um prompt que não existe.
        let mut live_by_agent: BTreeMap<String, LiveStatus> = BTreeMap::new();
        let mut typing: Vec<ChatParticipant> = Vec::new();
        for agent in input
            .participants
            .iter()
            .filter(|a| a.is_agent && matches!(a.activity, Activity::Working | Activity::Asking))
        {
            let live = input.live.get(&agent.id).filter(|l| {
                l.turn.has_reply() && !recorded.contains(&format!("{}#{}", agent.id, l.turn.id))
            });
            match live {
                Some(live) => {
                    let status = if agent.activity == Activity::Asking {
                        ChatLive::Asking
                    } else {
                        live_status(live)
                    };
                    live_by_agent.insert(
                        agent.id.clone(),
                        LiveStatus {
                            turn_id: live.turn.id.clone(),
                            status,
                        },
                    );
                }
                None if agent.activity == Activity::Working => typing.push(agent.clone()),
                None => {}
            }
        }
        let window_start = messages.len().saturating_sub(self.loaded_messages);
        let blocks = build_blocks(&BuildInput {
            messages: &messages[window_start..],
            live: &live_by_agent,
            typing: &typing,
            expanded: &self.expanded,
            groups: &self.groups,
            prices: input.prices,
        });
        self.messages = messages;
        self.pending = pending;
        self.loading_more = false;
        self.apply(blocks)
    }

    fn apply(&mut self, next: Vec<ChatBlock>) -> Option<ChatUpdate> {
        let ops = diff_blocks(&self.blocks, &next);
        if ops.is_empty() {
            return None;
        }
        self.blocks = next;
        Some(self.update(ops))
    }

    /// A lista inteira, para quem acabou de assinar ou perdeu um `rev`.
    pub fn snapshot(&self) -> Value {
        json!({"rev": self.rev, "blocks": self.blocks,
               "participants": self.participants, "queues": self.queues,
               "permissions": self.permissions})
    }

    /// O mesmo que [`ChatView::snapshot`], no formato do canal: um `reset` com a
    /// lista atual e o `rev` de agora. É o que o core manda a quem acabou de
    /// assinar o tópico ou pediu de novo por ter perdido um `rev`.
    pub fn reset_update(&self) -> ChatUpdate {
        ChatUpdate {
            topic: self.topic(),
            workbench: self.workbench.clone(),
            rev: self.rev,
            ops: vec![
                BlockOp::Reset {
                    blocks: self.blocks.clone(),
                },
                BlockOp::Participants {
                    list: self.participants.clone(),
                },
                BlockOp::Queues {
                    list: self.queues.clone(),
                },
                BlockOp::Permissions {
                    list: self.permissions.clone(),
                },
            ],
        }
    }

    // ---- ações da UI -------------------------------------------------------

    /// Clique no título de um passo (ou na capa de um grupo): abre ou recolhe. É
    /// também como a rota de teste alterna um passo sem clique. Quem chama
    /// refaz o [`ChatView::rebuild`] em seguida.
    /// Devolve `false` quando não há linha com esse id (nada muda).
    pub fn toggle_step(&mut self, id: &str) -> bool {
        let Some(at) = self.blocks.iter().position(|b| b.id == id) else {
            return false;
        };
        if let BlockKind::Group { level, .. } = &self.blocks[at].kind {
            let inside = self.steps_under(at);
            let opened = inside.iter().any(|s| self.expanded.contains(s));
            let next = level.next(opened);
            self.groups.insert(id.to_owned(), next);
            match next {
                // Voltar ao resumo esquece o que o usuário tinha aberto lá dentro: a
                // capa fechada é o estado limpo.
                ChatGroupLevel::Summary => {
                    for step in &inside {
                        self.expanded.remove(step);
                    }
                }
                // Detalhar é abrir todos de uma vez, e cada um continua seu: o
                // clique num passo aberto assim o fecha como qualquer outro.
                ChatGroupLevel::Details => self.expanded.extend(inside),
                ChatGroupLevel::Titles => {}
            }
        } else if !self.expanded.remove(id) {
            self.expanded.insert(id.to_owned());
        }
        true
    }

    /// Os passos de uma capa. Não sai do id — sai da montagem: são as linhas de
    /// passo aninhadas logo abaixo dela.
    fn steps_under(&self, cover: usize) -> Vec<String> {
        self.blocks[cover + 1..]
            .iter()
            .take_while(|b| matches!(b.kind, BlockKind::Step { .. }) && b.depth > 0)
            .map(|b| b.id.clone())
            .collect()
    }

    /// O usuário mandou mensagem: o eco entra na linha do tempo até o transcript
    /// confirmar. `known_turn_ids` são os turnos que o agente já tinha.
    pub fn sent(
        &mut self,
        text: &str,
        target: &str,
        at: SystemTime,
        known_turn_ids: BTreeSet<String>,
    ) {
        self.pending.push(Pending {
            text: text.to_owned(),
            target: target.to_owned(),
            sent_at: at,
            known_turn_ids,
        });
    }

    /// Topo é o usuário rolando até o começo do que há — não a descida animada
    /// passando por ele. Ao abrir o chat a thread nasce no topo e desce até o fim
    /// com movimento; contar aqueles quadros carregava duas janelas a mais sem
    /// ninguém ter pedido, e quanto mais lenta a máquina, mais quadros.
    pub fn should_load_more(
        near_top: bool,
        descending: bool,
        loading: bool,
        total: usize,
        loaded: usize,
        has_rows: bool,
    ) -> bool {
        near_top && !descending && !loading && total > loaded && has_rows
    }

    /// A UI rolou até o topo (`POST /chat/scroll?edge=top`): a janela cresce. Devolve
    /// `true` quando cresceu — quem chama refaz o [`ChatView::rebuild`].
    pub fn load_more(&mut self, near_top: bool, descending: bool) -> bool {
        if !Self::should_load_more(
            near_top,
            descending,
            self.loading_more,
            self.messages.len(),
            self.loaded_messages,
            !self.blocks.is_empty(),
        ) {
            return false;
        }
        self.loading_more = true;
        self.loaded_messages += WINDOW_STEP;
        true
    }

    /// A conversa foi arquivada: o que a thread guardava em memória vai junto.
    ///
    /// Arquivar move o `chat.jsonl` e nada mais — o eco local de um envio que o
    /// transcript nunca confirmou continuava aqui dentro e voltava a desenhar
    /// sozinho numa thread vazia. Era a mensagem órfã que sobrava depois de limpar
    /// a bancada (ADR-059). O que estava aberto era daquela conversa: a nova nasce
    /// fechada, e a janela de rolagem volta ao começo.
    pub fn cleared_history(&mut self) -> Option<ChatUpdate> {
        self.pending.clear();
        self.messages.clear();
        self.expanded.clear();
        self.groups.clear();
        self.loaded_messages = WINDOW_STEP;
        self.loading_more = false;
        if self.blocks.is_empty() {
            return None;
        }
        self.blocks.clear();
        Some(self.update(vec![BlockOp::Reset { blocks: Vec::new() }]))
    }

    // ---- rota de conferência ----------------------------------------------

    /// O estado do chat como dados para `/chat` (a rota que o teste e o curl
    /// leem): quantos ecos esperam, as linhas montadas e as mensagens. O foco, os
    /// participantes e o composer são da UI e o core os junta.
    pub fn route_snapshot(&self) -> Value {
        let blocks: Vec<Value> = self
            .blocks
            .iter()
            .map(|block| {
                let (kind, expanded) = match &block.kind {
                    BlockKind::Prompt { .. } => ("prompt".to_owned(), true),
                    BlockKind::Header { .. } => ("header".to_owned(), true),
                    BlockKind::Prose { .. } => ("prose".to_owned(), true),
                    BlockKind::Code { .. } => ("code".to_owned(), true),
                    BlockKind::Status { .. } => ("status".to_owned(), true),
                    BlockKind::Typing { .. } => ("typing".to_owned(), true),
                    BlockKind::Diff { .. } => ("diff".to_owned(), true),
                    BlockKind::Step { step, expanded, .. } => {
                        ("step".to_owned(), *expanded || !step.is_expandable())
                    }
                    BlockKind::Group { level, .. } => {
                        (format!("group:{}", level.raw()), level.shows_steps())
                    }
                };
                json!({"id": block.id, "kind": kind, "expanded": expanded})
            })
            .collect();
        let live_label = |turn_id: &str| -> String {
            let id = format!("s|{turn_id}");
            self.blocks
                .iter()
                .find_map(|b| match (&b.kind, b.id == id) {
                    (BlockKind::Status { live, .. }, true) => Some(live.label()),
                    _ => None,
                })
                .unwrap_or_default()
        };
        let messages: Vec<Value> = self
            .messages
            .iter()
            .map(|message| {
                let quote = message
                    .quote()
                    .map(|q| json!({"author": q.author_id.clone().unwrap_or_else(|| "você".to_owned()), "text": q.text}))
                    .unwrap_or_else(|| json!({}));
                match message {
                    ChatMessage::Prompt { to, turn_id, text, from, .. } => json!({
                        "kind": "prompt", "id": turn_id, "to": to.id, "text": text,
                        "from": from.clone().unwrap_or_default(), "quote": quote}),
                    ChatMessage::Pending { to, text, .. } => {
                        json!({"kind": "pending", "to": to.id, "text": text, "quote": quote})
                    }
                    ChatMessage::Reply { from, turn, .. } => json!({
                        "kind": "reply", "id": turn.id, "from": from.id, "text": turn.reply_text,
                        "steps": turn.steps.iter().map(|s| format!("{} {}", s.glyph, s.text)).collect::<Vec<_>>(),
                        "chain": turn.chain().iter().map(chain_line).collect::<Vec<_>>(),
                        "live": live_label(&turn.id),
                        "quote": quote}),
                }
            })
            .collect();
        json!({"pending": self.pending.len(), "blocks": blocks, "messages": messages})
    }
}

fn chain_line(part: &ChatPart) -> String {
    match part {
        ChatPart::Text(text) => format!("¶ {text}"),
        ChatPart::Step(step) => {
            let mut line = format!("{} {}", step.glyph, step.text);
            if let Some((added, removed)) = step.diff_counts() {
                line.push_str(&format!(" (+{added} −{removed})"));
            }
            if let Some(output) = &step.output {
                let n = output.split('\n').filter(|l| !l.is_empty()).count();
                line.push_str(&format!(" ⎿ {n} linha{}", if n == 1 { "" } else { "s" }));
            }
            if step.is_error {
                line.push_str(" ✗");
            }
            line
        }
    }
}

/// Os turnos de um agente: os gravados e, se ainda não estiver entre eles, o ao
/// vivo. O consumo sem preço congela aqui, com a tabela em vigor.
fn turns_of(agent: &ChatParticipant, input: &ThreadInput) -> Vec<ChatTurn> {
    let mut turns: Vec<ChatTurn> = input
        .records
        .iter()
        .filter(|r| r.node == agent.id)
        .map(|r| r.turn.clone())
        .collect();
    if let Some(live) = input.live.get(&agent.id)
        && !turns.iter().any(|t| t.id == live.turn.id)
    {
        turns.push(live.turn.clone());
    }
    for turn in &mut turns {
        turn.settle(input.prices);
    }
    turns
}

/// O que a bolha ao vivo diz no fim: o último passo se o agente está numa
/// ferramenta, "pensando…" se raciocina, "trabalhando…" no resto.
pub fn live_status(live: &LiveTurn) -> ChatLive {
    match live.last {
        Some(LastBlock::Thinking) => ChatLive::Thinking,
        Some(LastBlock::Tool) => live
            .turn
            .chain()
            .into_iter()
            .rev()
            .find_map(|part| match part {
                ChatPart::Step(step) => Some(ChatLive::Step { step }),
                ChatPart::Text(_) => None,
            })
            .unwrap_or(ChatLive::Working),
        _ => ChatLive::Working,
    }
}

/// O diff de duas montagens, por id: a linha que entrou é inserida, a que mudou é
/// atualizada, a que saiu é removida, o resto fica. Os ids comuns têm de estar na
/// mesma ordem para inserir/remover por índice valer; senão é recarga inteira.
pub fn diff_blocks(old: &[ChatBlock], new: &[ChatBlock]) -> Vec<BlockOp> {
    let old_ids: BTreeSet<&str> = old.iter().map(|b| b.id.as_str()).collect();
    let new_ids: BTreeSet<&str> = new.iter().map(|b| b.id.as_str()).collect();
    let common_old: Vec<&str> = old
        .iter()
        .map(|b| b.id.as_str())
        .filter(|i| new_ids.contains(i))
        .collect();
    let common_new: Vec<&str> = new
        .iter()
        .map(|b| b.id.as_str())
        .filter(|i| old_ids.contains(i))
        .collect();
    let unchanged_set = old.len() == new.len() && old.iter().zip(new).all(|(a, b)| a == b);
    if unchanged_set {
        return Vec::new();
    }
    if common_old != common_new || old.is_empty() {
        return vec![BlockOp::Reset {
            blocks: new.to_vec(),
        }];
    }
    let by_id: BTreeMap<&str, &ChatBlock> = old.iter().map(|b| (b.id.as_str(), b)).collect();
    let mut ops = Vec::new();
    for block in old.iter().filter(|b| !new_ids.contains(b.id.as_str())) {
        ops.push(BlockOp::Remove {
            id: block.id.clone(),
        });
    }
    for (index, block) in new.iter().enumerate() {
        if !old_ids.contains(block.id.as_str()) {
            ops.push(BlockOp::Insert {
                index,
                block: block.clone(),
            });
        }
    }
    for block in new {
        if by_id
            .get(block.id.as_str())
            .is_some_and(|before| *before != block)
        {
            ops.push(BlockOp::Update {
                block: block.clone(),
            });
        }
    }
    ops
}

/// Aplica as operações a uma lista — o que a UI faz do outro lado do canal, e
/// como o teste prova que o diff reconstrói a lista nova.
pub fn apply_ops(blocks: &mut Vec<ChatBlock>, ops: &[BlockOp]) {
    for op in ops {
        match op {
            BlockOp::Reset { blocks: all } => *blocks = all.clone(),
            // Estado fora da lista de blocos: quem aplica na UI guarda à parte.
            BlockOp::Participants { .. } | BlockOp::Queues { .. } | BlockOp::Permissions { .. } => {
            }
            BlockOp::Remove { id } => blocks.retain(|b| &b.id != id),
            BlockOp::Insert { index, block } => {
                let at = (*index).min(blocks.len());
                blocks.insert(at, block.clone());
            }
            BlockOp::Update { block } => {
                if let Some(slot) = blocks.iter_mut().find(|b| b.id == block.id) {
                    *slot = block.clone();
                }
            }
        }
    }
}

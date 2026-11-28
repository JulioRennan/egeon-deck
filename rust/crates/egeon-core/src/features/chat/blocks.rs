//! A thread como linhas. A tabela da UI desenha linha por linha e só o que está
//! na tela; a bolha é o conjunto de linhas com o mesmo `message_key` — a primeira
//! arredonda em cima, a última embaixo (ADR-042). O `id` é estável entre
//! montagens: é por ele que a UI sabe o que entrou, saiu ou mudou, e é o alvo de
//! rolagem de uma citação.
//!
//! O JSON de [`ChatBlock`] é o contrato do canal `/ui` (ver [`super::view`]).

use std::collections::{BTreeMap, BTreeSet};
use std::time::SystemTime;

use serde::{Deserialize, Serialize};

use super::markdown::{self, Block as MdBlock};
use super::model::{ChatPart, ChatStep};
use super::syntax::{Language, Token, tokens};
use super::thread::{ChatMessage, ChatParticipant, ChatQuote, Who};
use super::time::{iso, iso_opt};
use crate::features::usage::{PriceTable, UsageByPrice, text as usage_text, total_usage};

/// O que a bolha ao vivo diz que o agente está fazendo agora.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "camelCase")]
pub enum ChatLive {
    Working,
    Thinking,
    Step {
        step: ChatStep,
    },
    /// Permissão pedida no meio do turno: laranja, sem spinner — não há trabalho
    /// andando, há o usuário para decidir.
    Asking,
}

impl ChatLive {
    pub fn label(&self) -> String {
        match self {
            ChatLive::Working => "trabalhando…".to_owned(),
            ChatLive::Thinking => "pensando…".to_owned(),
            ChatLive::Step { step } => format!("{} {}", step.glyph, step.text),
            ChatLive::Asking => "precisa de você".to_owned(),
        }
    }
}

/// Quanto de uma sequência de passos está à vista. O clique na capa avança um
/// nível e volta ao começo depois do último (ADR-049).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ChatGroupLevel {
    /// Só a capa: "3 passos · echo três".
    Summary,
    /// A capa e os títulos dos passos.
    Titles,
    /// Tudo aberto: cada passo com comando e saída.
    Details,
}

impl ChatGroupLevel {
    pub fn raw(self) -> u8 {
        match self {
            ChatGroupLevel::Summary => 0,
            ChatGroupLevel::Titles => 1,
            ChatGroupLevel::Details => 2,
        }
    }

    /// Para onde o clique na capa leva. `opened` é "o usuário já abriu algum passo
    /// desta capa à mão": aí o clique FECHA, em vez de aprofundar — a capa nunca
    /// desfaz o que ele acabou de abrir (ADR-053).
    pub fn next(self, opened: bool) -> ChatGroupLevel {
        match self {
            ChatGroupLevel::Summary => ChatGroupLevel::Titles,
            ChatGroupLevel::Titles if opened => ChatGroupLevel::Summary,
            ChatGroupLevel::Titles => ChatGroupLevel::Details,
            ChatGroupLevel::Details => ChatGroupLevel::Summary,
        }
    }

    pub fn shows_steps(self) -> bool {
        self != ChatGroupLevel::Summary
    }
}

/// O custo de um turno, pronto para o cabeçalho da bolha (ADR-085).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatCost {
    pub text: String,
    pub detail: String,
}

impl ChatCost {
    pub fn new(usage: &UsageByPrice, prices: &PriceTable) -> Option<ChatCost> {
        if usage.is_empty() {
            return None;
        }
        Some(ChatCost {
            text: usage_text::cost(usage, prices),
            detail: format!("Este turno: {}", usage_text::breakdown(&total_usage(usage))),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum BlockKind {
    /// Prompt do usuário (ou o de outro agente, com `from`) — bolha de uma linha.
    /// `mention` é a marca `@destinatário` no começo do texto: só quando a
    /// mensagem não é contínua — consecutivo é limpo, intercalado é marcado, como
    /// no WhatsApp.
    #[serde(rename_all = "camelCase")]
    Prompt {
        to: Who,
        from: Option<String>,
        text: String,
        #[serde(with = "iso")]
        at: SystemTime,
        quote: Option<ChatQuote>,
        pending: bool,
        mention: bool,
    },
    /// Cabeçalho da resposta: nome, endereço, hora (`None` é "agora"), a citação e
    /// o custo do turno (ADR-085).
    #[serde(rename_all = "camelCase")]
    Header {
        from: Who,
        #[serde(with = "iso_opt")]
        at: Option<SystemTime>,
        quote: Option<ChatQuote>,
        cost: Option<ChatCost>,
    },
    /// Um trecho de prosa: parágrafos, títulos e listas seguidos.
    Prose { from: Who, blocks: Vec<MdBlock> },
    /// Bloco de código da prosa (```), na sua caixa.
    Code {
        from: Who,
        language: Option<String>,
        code: String,
        /// Os trechos coloridos de cada linha de `code` (decisão 29): o realce é
        /// do core, a cor é da UI. Linguagem sem realce vem com um trecho só,
        /// `plain`, por linha.
        spans: Vec<Vec<Token>>,
    },
    /// Um passo na sua caixa. Recolhido é só o título (com `+a −b` e o tamanho da
    /// saída); aberto mostra comando e saída. O diff aberto é `diff`; recolhido,
    /// é um `step` como os outros.
    Step {
        from: Who,
        step: ChatStep,
        expanded: bool,
    },
    /// A capa de uma sequência de passos: "3 passos · echo três". O clique
    /// aprofunda — resumo, títulos, tudo aberto (ADR-049).
    Group {
        from: Who,
        count: usize,
        /// Título do último passo. No JSON é `lastStep`: o `last` do bloco (a
        /// última linha da bolha) mora no mesmo objeto e os dois colidiam.
        #[serde(rename = "lastStep")]
        last: String,
        level: ChatGroupLevel,
    },
    Diff {
        from: Who,
        file: String,
        diff: Vec<String>,
    },
    /// A linha de status no fim da bolha ao vivo.
    Status { from: Who, live: ChatLive },
    /// O agente trabalha e ainda não gravou nada: bolha só de status.
    Typing { from: Who },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatBlock {
    pub id: String,
    pub message_key: String,
    #[serde(flatten)]
    pub kind: BlockKind,
    pub first: bool,
    pub last: bool,
    /// Um degrau de recuo por nível: o passo que pertence a uma capa entra um tab,
    /// e cada um fica na SUA caixinha, separadas por um respiro (ADR-050).
    pub depth: u8,
}

impl ChatBlock {
    fn new(id: String, message_key: &str, kind: BlockKind, depth: u8) -> ChatBlock {
        ChatBlock {
            id,
            message_key: message_key.to_owned(),
            kind,
            first: true,
            last: true,
            depth,
        }
    }

    pub fn participant(&self) -> &Who {
        match &self.kind {
            BlockKind::Prompt { to, .. } => to,
            BlockKind::Header { from, .. }
            | BlockKind::Prose { from, .. }
            | BlockKind::Code { from, .. }
            | BlockKind::Step { from, .. }
            | BlockKind::Group { from, .. }
            | BlockKind::Diff { from, .. }
            | BlockKind::Status { from, .. }
            | BlockKind::Typing { from } => from,
        }
    }

    /// Bolha do usuário fica à direita; a de qualquer agente, à esquerda.
    pub fn aligns_right(&self) -> bool {
        matches!(&self.kind, BlockKind::Prompt { from: None, .. })
    }
}

/// O turno em curso de um agente: o id e o que ele diz estar fazendo.
#[derive(Debug, Clone, PartialEq)]
pub struct LiveStatus {
    pub turn_id: String,
    pub status: ChatLive,
}

/// O que a montagem das linhas precisa.
pub struct BuildInput<'a> {
    pub messages: &'a [ChatMessage],
    /// O turno em curso de cada agente, por id do agente.
    pub live: &'a BTreeMap<String, LiveStatus>,
    /// Quem trabalha sem turno gravado.
    pub typing: &'a [ChatParticipant],
    /// Os ids dos passos que o usuário abriu — todo o resto fica só no título.
    /// Passo sem nada além do título é sempre inteiro, e passo com diff nunca
    /// recolhe.
    pub expanded: &'a BTreeSet<String>,
    pub groups: &'a BTreeMap<String, ChatGroupLevel>,
    pub prices: &'a PriceTable,
}

/// A thread inteira em linhas.
pub fn build(input: &BuildInput) -> Vec<ChatBlock> {
    let mut out: Vec<ChatBlock> = Vec::new();
    for (index, message) in input.messages.iter().enumerate() {
        let key = message.key();
        // Contínua é a que vem logo depois de uma fala do mesmo destinatário (ou é
        // a primeira): não precisa de marca.
        let previous = index.checked_sub(1).map(|i| &input.messages[i]);
        let mention = previous.is_some_and(|p| p.participant_id() != message.participant_id());
        match message {
            ChatMessage::Prompt {
                to,
                text,
                at,
                quote,
                from,
                ..
            } => out.push(ChatBlock::new(
                key.clone(),
                &key,
                BlockKind::Prompt {
                    to: to.who(),
                    from: from.clone(),
                    text: text.clone(),
                    at: *at,
                    quote: quote.clone(),
                    pending: false,
                    mention,
                },
                0,
            )),
            ChatMessage::Pending {
                to,
                text,
                at,
                quote,
            } => out.push(ChatBlock::new(
                key.clone(),
                &key,
                BlockKind::Prompt {
                    to: to.who(),
                    from: None,
                    text: text.clone(),
                    at: *at,
                    quote: quote.clone(),
                    pending: true,
                    mention,
                },
                0,
            )),
            ChatMessage::Reply { from, turn, quote } => {
                reply_rows(&mut out, input, &key, from, turn, quote.clone());
            }
        }
    }
    for agent in input.typing {
        let key = format!("t|{}", agent.id);
        out.push(ChatBlock::new(
            key.clone(),
            &key,
            BlockKind::Typing { from: agent.who() },
            0,
        ));
    }
    positioned(&mut out);
    out
}

/// Os passos seguidos, com nada entre eles: dois ou mais ganham capa, e a capa
/// decide quanto deles aparece.
struct Rows<'a> {
    rows: Vec<ChatBlock>,
    index: usize,
    key: &'a str,
    turn_id: &'a str,
    agent: Who,
    run: Vec<(ChatStep, String)>,
}

impl Rows<'_> {
    fn add(&mut self, kind: BlockKind, id: Option<String>, depth: u8) {
        let fresh = id.is_none();
        let id = id.unwrap_or_else(|| format!("b|{}|{}", self.turn_id, self.index));
        self.rows.push(ChatBlock::new(id, self.key, kind, depth));
        if fresh {
            self.index += 1;
        }
    }

    fn flush_run(&mut self, input: &BuildInput) {
        let run = std::mem::take(&mut self.run);
        if run.is_empty() {
            return;
        }
        let step_kind = |step: &ChatStep, id: &str, agent: &Who| BlockKind::Step {
            from: agent.clone(),
            step: step.clone(),
            expanded: !step.is_expandable() || input.expanded.contains(id),
        };
        if run.len() == 1 {
            let (step, id) = &run[0];
            let kind = step_kind(step, id, &self.agent);
            self.add(kind, Some(id.clone()), 0);
            return;
        }
        let group_id = format!("g|{}", &run[0].1[2..]);
        let level = input
            .groups
            .get(&group_id)
            .copied()
            .unwrap_or(ChatGroupLevel::Summary);
        let last = run.last().map(|(s, _)| s.text.clone()).unwrap_or_default();
        self.add(
            BlockKind::Group {
                from: self.agent.clone(),
                count: run.len(),
                last,
                level,
            },
            Some(group_id),
            0,
        );
        if !level.shows_steps() {
            return;
        }
        // Quem manda no passo é sempre o `expanded`, mesmo em `details`: o nível
        // ABRE os passos (o `view` põe os ids lá) e sai da frente, senão fechar um
        // deles não teria efeito nenhum (ADR-053).
        for (step, id) in &run {
            let kind = step_kind(step, id, &self.agent);
            self.add(kind, Some(id.clone()), 1);
        }
    }
}

fn reply_rows(
    out: &mut Vec<ChatBlock>,
    input: &BuildInput,
    key: &str,
    from: &ChatParticipant,
    turn: &super::model::ChatTurn,
    quote: Option<ChatQuote>,
) {
    let agent = from.who();
    let status = input
        .live
        .get(&from.id)
        .filter(|live| live.turn_id == turn.id)
        .map(|live| live.status.clone());
    let header = ChatBlock::new(
        format!("h|{}", turn.id),
        key,
        BlockKind::Header {
            from: agent.clone(),
            at: if status.is_none() {
                Some(turn.reply_at.unwrap_or(turn.prompt_at))
            } else {
                None
            },
            quote,
            cost: ChatCost::new(&turn.usage, input.prices),
        },
        0,
    );
    let mut rows = Rows {
        rows: vec![header],
        index: 0,
        key,
        turn_id: &turn.id,
        agent: agent.clone(),
        run: Vec::new(),
    };
    for part in turn.chain() {
        match part {
            ChatPart::Text(text) => {
                rows.flush_run(input);
                for kind in split(&text, &agent) {
                    rows.add(kind, None, 0);
                }
            }
            ChatPart::Step(step) => {
                // Diff nunca recolhe: ver o que mudou no arquivo é o que sempre
                // interessa — é o passo de comando, com o seu despejo de saída, que
                // nasce só no título.
                if let Some(diff) = step.diff.as_ref().filter(|d| !d.is_empty()) {
                    rows.flush_run(input);
                    rows.add(
                        BlockKind::Diff {
                            from: agent.clone(),
                            file: step.text.clone(),
                            diff: diff.clone(),
                        },
                        None,
                        0,
                    );
                } else {
                    let id = format!("b|{}|{}", turn.id, rows.index);
                    rows.run.push((step, id));
                    rows.index += 1;
                }
            }
        }
    }
    rows.flush_run(input);
    let mut collected = rows.rows;
    if let Some(status) = status {
        collected.push(ChatBlock::new(
            format!("s|{}", turn.id),
            key,
            BlockKind::Status {
                from: agent,
                live: status,
            },
            0,
        ));
    }
    out.extend(collected);
}

/// A prosa em linhas: parágrafos, títulos e listas seguidos numa linha só; cada
/// bloco de código na sua.
pub fn split(text: &str, agent: &Who) -> Vec<BlockKind> {
    let mut out = Vec::new();
    let mut run: Vec<MdBlock> = Vec::new();
    for block in markdown::blocks(text) {
        if let MdBlock::Code { language, text } = block {
            if !run.is_empty() {
                out.push(BlockKind::Prose {
                    from: agent.clone(),
                    blocks: std::mem::take(&mut run),
                });
            }
            let spans = code_spans(language.as_deref(), &text);
            out.push(BlockKind::Code {
                from: agent.clone(),
                language,
                code: text,
                spans,
            });
        } else {
            run.push(block);
        }
    }
    if !run.is_empty() {
        out.push(BlockKind::Prose {
            from: agent.clone(),
            blocks: run,
        });
    }
    out
}

/// O realce de um bloco de código, uma lista de trechos por linha. A linguagem é
/// a do rótulo da cerca (` ```swift `); sem rótulo ou desconhecida, sem cor.
pub fn code_spans(language: Option<&str>, code: &str) -> Vec<Vec<Token>> {
    let language = language.map_or(Language::Plain, Language::named);
    code.split('\n')
        .map(|line| tokens(line, language))
        .collect()
}

/// Marca a primeira e a última linha de cada bolha.
pub fn positioned(blocks: &mut [ChatBlock]) {
    let keys: Vec<String> = blocks.iter().map(|b| b.message_key.clone()).collect();
    for i in 0..blocks.len() {
        blocks[i].first = i == 0 || keys[i - 1] != keys[i];
        blocks[i].last = i == blocks.len() - 1 || keys[i + 1] != keys[i];
    }
}

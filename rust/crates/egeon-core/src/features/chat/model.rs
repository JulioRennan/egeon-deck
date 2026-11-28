//! Um turno de conversa: o prompt, o que o agente fez com ele e o carimbo de
//! quem o produziu — o espelho do que o chat mostra, não o transcript do CLI,
//! que traz `tool_result`, `thinking` e snapshot e passa de dezenas de MB
//! (ADR-037). O JSON é o do Swift: o `chat.jsonl` de hoje abre como está.

use std::time::SystemTime;

use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::time::{iso, iso_opt};
use crate::features::usage::{PriceTable, UsageByPrice, settled};

/// Um passo que o agente deu para responder: comando, edição, leitura, envio —
/// e o que voltou dele. É o que o terminal mostra, peneirado: a linha do passo,
/// o comando por extenso, o diff da edição, a saída com teto (ADR-039).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatStep {
    /// `$` comando · `±` edição · `→` outro uso de ferramenta · `⇄` egeon send.
    /// Tolerante ao que falta: os campos do passo inteiro nasceram depois do
    /// histórico, e as linhas antigas só têm `glyph`, `text` e `sendTo`.
    #[serde(default = "default_glyph")]
    pub glyph: String,
    #[serde(default)]
    pub text: String,
    /// Endereço `bancada/id` quando o passo foi um `egeon send` — é por ele que
    /// a resposta do outro agente encontra a bolha de quem perguntou.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub send_to: Option<String>,
    /// O `tool_use_id` do CLI: é por ele que o resultado encontra o passo.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_id: Option<String>,
    /// O comando por extenso (Bash), ou a entrada compacta de outra ferramenta.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// Linhas do patch, no formato do diff unificado (` `, `-`, `+`), com teto.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub diff: Option<Vec<String>>,
    /// Prévia da saída, com teto de linhas e bytes; a última linha avisa quanto
    /// ficou de fora.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    #[serde(default)]
    pub is_error: bool,
}

fn default_glyph() -> String {
    "→".to_owned()
}

impl ChatStep {
    /// Tetos do que vai para o histórico: sem eles o `chat.jsonl` viraria o
    /// transcript de novo, e a ADR-037 existe para ele não virar.
    pub const MAX_OUTPUT_LINES: usize = 40;
    pub const MAX_OUTPUT_BYTES: usize = 2048;
    pub const MAX_DIFF_LINES: usize = 200;

    pub fn new(glyph: &str, text: &str) -> Self {
        ChatStep {
            glyph: glyph.to_owned(),
            text: text.to_owned(),
            send_to: None,
            tool_id: None,
            detail: None,
            diff: None,
            output: None,
            is_error: false,
        }
    }

    /// Tem mais que o título: comando ou saída. Na bolha o passo nasce recolhido
    /// — só o título — e é isto que decide se há o que abrir. Diff não conta:
    /// ele nunca recolhe.
    pub fn is_expandable(&self) -> bool {
        self.detail.is_some() || self.output.is_some()
    }

    /// `+a −b` do diff, para o cabeçalho do grupo.
    pub fn diff_counts(&self) -> Option<(usize, usize)> {
        let diff = self.diff.as_ref().filter(|d| !d.is_empty())?;
        let added = diff.iter().filter(|l| l.starts_with('+')).count();
        let removed = diff.iter().filter(|l| l.starts_with('-')).count();
        Some((added, removed))
    }

    /// Corta por linhas E por bytes, e diz o que cortou. Saída de ferramenta
    /// chega a dezenas de KB numa linha só (JSON, base64): só o teto de linhas
    /// não segura.
    pub fn capped(text: &str) -> String {
        Self::capped_with(text, Self::MAX_OUTPUT_LINES, Self::MAX_OUTPUT_BYTES)
    }

    pub fn capped_with(text: &str, max_lines: usize, max_bytes: usize) -> String {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return String::new();
        }
        let mut lines: Vec<&str> = trimmed.split('\n').collect();
        let mut note: Option<String> = None;
        if lines.len() > max_lines {
            note = Some(format!("… +{} linhas", lines.len() - max_lines));
            lines.truncate(max_lines);
        }
        let mut out = lines.join("\n");
        if out.len() > max_bytes {
            // Corte em bytes, como o Swift: o último caractere partido vira o
            // de substituição, e uma quebra de linha perto do fim vence.
            let mut cut = String::from_utf8_lossy(&out.as_bytes()[..max_bytes]).into_owned();
            if let Some(last) = cut.rfind('\n')
                && cut[last..].chars().count() < 200
            {
                cut.truncate(last);
            }
            out = cut;
            note = Some(format!("… {} bytes ao todo", text.len()));
        }
        if let Some(note) = note {
            out.push('\n');
            out.push_str(&note);
        }
        out
    }
}

/// Um elo da cadeia do turno, na ordem em que o agente o produziu: um parágrafo
/// de prosa ou um passo. É a cadeia que a bolha desenha — "vou olhar X", três
/// comandos, "achei", uma edição, a resposta — e não "todos os passos, depois
/// todo o texto" (ADR-039).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatPart {
    Text(String),
    Step(ChatStep),
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PartWire {
    kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    step: Option<ChatStep>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    glyph: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    send_to: Option<String>,
}

impl Serialize for ChatPart {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let wire = match self {
            ChatPart::Text(text) => PartWire {
                kind: "text".into(),
                text: Some(text.clone()),
                step: None,
                glyph: None,
                send_to: None,
            },
            ChatPart::Step(step) => PartWire {
                kind: "step".into(),
                text: None,
                step: Some(step.clone()),
                glyph: None,
                send_to: None,
            },
        };
        wire.serialize(s)
    }
}

impl<'de> Deserialize<'de> for ChatPart {
    /// Tipo que não existe mais (a "troca" achatada da sub-conversa, que nunca
    /// foi gravada) cai em prosa vazia, e o turno a descarta. A forma achatada
    /// antiga do passo (`glyph`/`text` soltos) ainda decodifica.
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let wire = PartWire::deserialize(d)?;
        let text = wire.text.unwrap_or_default();
        Ok(match wire.kind.as_str() {
            "step" => match wire.step {
                Some(step) => ChatPart::Step(step),
                None => {
                    let mut step = ChatStep::new(wire.glyph.as_deref().unwrap_or("→"), &text);
                    step.send_to = wire.send_to;
                    ChatPart::Step(step)
                }
            },
            _ => ChatPart::Text(text),
        })
    }
}

/// Seu prompt e o que o agente fez com ele. O contrato é genérico: quem sabe ler
/// o arquivo do CLI é o leitor do perfil (`claude::transcript`); daí em diante o
/// turno é do app, gravado no histórico (ADR-037).
#[derive(Debug, Clone, PartialEq)]
pub struct ChatTurn {
    /// Identidade do turno — o `uuid` que o CLI grava na linha do prompt. Dois
    /// "oi" seguidos são dois turnos; texto e hora não bastam para separá-los.
    pub id: String,
    pub prompt: String,
    pub prompt_at: SystemTime,
    /// Endereço do agente que mandou o prompt, quando não foi o usuário. A bolha
    /// dele fica no topo como qualquer outra, com quem mandou em cima (ADR-042).
    pub from: Option<String>,
    pub steps: Vec<ChatStep>,
    pub reply_text: String,
    pub reply_at: Option<SystemTime>,
    /// Prosa e passos na ordem em que saíram. `steps` e `reply_text` continuam
    /// existindo — são as somas que a citação e o histórico antigo usam; a bolha
    /// desenha por aqui.
    pub parts: Vec<ChatPart>,
    /// O que o turno gastou, por tarifa (ADR-085) — o custo no cabeçalho da
    /// bolha. Vazio em turno gravado antes do registro de consumo.
    pub usage: UsageByPrice,
}

impl ChatTurn {
    pub fn new(id: &str, prompt: &str, prompt_at: SystemTime, from: Option<String>) -> Self {
        ChatTurn {
            id: id.to_owned(),
            prompt: prompt.to_owned(),
            prompt_at,
            from,
            steps: Vec::new(),
            reply_text: String::new(),
            reply_at: None,
            parts: Vec::new(),
            usage: UsageByPrice::new(),
        }
    }

    /// Congela o consumo que entrou sem preço, se a tabela já o tiver.
    pub fn settle(&mut self, prices: &PriceTable) {
        self.usage = settled(&self.usage, prices);
    }

    pub fn has_reply(&self) -> bool {
        !self.reply_text.is_empty() || !self.steps.is_empty()
    }

    /// A cadeia para desenhar. Registro gravado antes da cadeia existir não tem
    /// `parts`: reconstrói na forma antiga — passos, depois o texto.
    pub fn chain(&self) -> Vec<ChatPart> {
        if !self.parts.is_empty() {
            return self.parts.clone();
        }
        let mut out: Vec<ChatPart> = self.steps.iter().cloned().map(ChatPart::Step).collect();
        if !self.reply_text.is_empty() {
            out.push(ChatPart::Text(self.reply_text.clone()));
        }
        out
    }

    /// O último bloco de prosa da cadeia — o que está sendo dito agora.
    pub fn last_text(&self) -> Option<String> {
        self.chain().into_iter().rev().find_map(|part| match part {
            ChatPart::Text(text) => Some(text),
            ChatPart::Step(_) => None,
        })
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TurnOut<'a> {
    id: &'a str,
    prompt: &'a str,
    #[serde(with = "iso")]
    prompt_at: SystemTime,
    #[serde(skip_serializing_if = "Option::is_none")]
    from: &'a Option<String>,
    steps: &'a [ChatStep],
    reply_text: &'a str,
    #[serde(with = "iso_opt", skip_serializing_if = "Option::is_none")]
    reply_at: Option<SystemTime>,
    parts: &'a [ChatPart],
    #[serde(skip_serializing_if = "UsageByPrice::is_empty")]
    usage: &'a UsageByPrice,
}

impl Serialize for ChatTurn {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        TurnOut {
            id: &self.id,
            prompt: &self.prompt,
            prompt_at: self.prompt_at,
            from: &self.from,
            steps: &self.steps,
            reply_text: &self.reply_text,
            reply_at: self.reply_at,
            parts: &self.parts,
            usage: &self.usage,
        }
        .serialize(s)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TurnIn {
    id: String,
    prompt: String,
    #[serde(with = "iso")]
    prompt_at: SystemTime,
    #[serde(default)]
    from: Option<String>,
    #[serde(default)]
    steps: Vec<ChatStep>,
    #[serde(default)]
    reply_text: String,
    #[serde(default, with = "iso_opt")]
    reply_at: Option<SystemTime>,
    #[serde(default)]
    parts: Vec<ChatPart>,
    #[serde(default)]
    usage: UsageByPrice,
}

impl<'de> Deserialize<'de> for ChatTurn {
    /// Tolerante ao que falta: `parts` nasceu depois do histórico (ADR-039), e as
    /// linhas antigas do `chat.jsonl` não a têm. Chave `exchanges` de arquivo
    /// antigo é ignorada; elo de tipo extinto decodifica como prosa vazia e sai
    /// aqui. O consumo pendente congela depois, com a tabela em vigor
    /// ([`ChatTurn::settle`]): o decode não conhece a tabela.
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let raw = TurnIn::deserialize(d)?;
        Ok(ChatTurn {
            id: raw.id,
            prompt: raw.prompt,
            prompt_at: raw.prompt_at,
            from: raw.from,
            steps: raw.steps,
            reply_text: raw.reply_text,
            reply_at: raw.reply_at,
            parts: raw
                .parts
                .into_iter()
                .filter(|p| !matches!(p, ChatPart::Text(t) if t.is_empty()))
                .collect(),
            usage: raw.usage,
        })
    }
}

/// Um turno como o chat o mostra, pronto para ficar no disco.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatRecord {
    /// Id do nó dentro da bancada; a bancada é o arquivo.
    pub node: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub conversation: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cli: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub turn: ChatTurn,
}

impl ChatRecord {
    pub fn new(node: &str, turn: ChatTurn) -> Self {
        ChatRecord {
            node: node.to_owned(),
            conversation: None,
            cli: None,
            model: None,
            turn,
        }
    }

    /// Dois `Stop` do mesmo turno não podem virar duas linhas: o uuid do prompt
    /// no CLI identifica o turno, e o nó separa dois CLIs que por acaso gerem o
    /// mesmo.
    pub fn key(&self) -> String {
        format!("{}#{}", self.node, self.turn.id)
    }
}

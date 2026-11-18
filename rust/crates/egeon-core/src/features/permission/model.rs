//! Um pedido de permissão do CLI e a resposta que volta ao gancho (ADR-068).
//! Porte de `PermissionAsk.swift`.

use std::collections::HashMap;
use std::time::SystemTime;

use serde_json::{Map, Value, json};

/// Uma pergunta do `AskUserQuestion`: passa pelo mesmo gancho que a
/// permissão, e respondê-la é permitir a ferramenta com as respostas dentro.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Question {
    pub question: String,
    pub header: Option<String>,
    pub options: Vec<String>,
    pub multi_select: bool,
}

/// Aberto enquanto o diálogo do CLI está na tela. Vem do `PermissionRequest`,
/// que dispara depois das regras e do classificador do modo auto: só chega
/// aqui o que de fato iria perguntar a você.
#[derive(Debug, Clone)]
pub struct PermissionAsk {
    pub id: String,
    /// `bancada/id` do terminal que pediu.
    pub address: String,
    pub tool: String,
    /// Uma linha: o comando, o arquivo, a URL — o que se aprova.
    pub summary: String,
    /// A descrição que o próprio agente deu, quando deu.
    pub detail: Option<String>,
    /// As regras do "sim, e não pergunte mais", cruas, para voltar ao CLI do
    /// jeito que vieram.
    pub suggestions: Vec<Value>,
    /// O `tool_input` cru: a resposta de uma pergunta volta nele.
    pub input: Map<String, Value>,
    pub opened_at: SystemTime,
}

/// Igualdade como a do Swift: as sugestões contam só pela quantidade.
impl PartialEq for PermissionAsk {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
            && self.address == other.address
            && self.tool == other.tool
            && self.summary == other.summary
            && self.detail == other.detail
            && self.suggestions.len() == other.suggestions.len()
            && self.questions() == other.questions()
    }
}

/// `as? [[String: Any]]` do Swift: a lista só vale se todo elemento for objeto.
fn objects(value: Option<&Value>) -> Option<Vec<&Map<String, Value>>> {
    value?.as_array()?.iter().map(Value::as_object).collect()
}

fn clip(text: &str, limit: usize) -> String {
    if text.chars().count() > limit {
        let mut out: String = text.chars().take(limit).collect();
        out.push('…');
        out
    } else {
        text.to_owned()
    }
}

impl PermissionAsk {
    /// Montado do payload do gancho. `None` sem `tool_name`.
    ///
    /// Das sugestões fica fora o `setMode`: ele troca o modo da sessão inteira,
    /// e "sempre permitir isto" não pode virar "permitir tudo" sem você ler.
    pub fn from_payload(
        id: impl Into<String>,
        address: impl Into<String>,
        payload: &Value,
        opened_at: SystemTime,
    ) -> Option<Self> {
        let tool = payload
            .get("tool_name")
            .and_then(Value::as_str)
            .filter(|t| !t.is_empty())?
            .to_owned();
        let input = payload
            .get("tool_input")
            .and_then(Value::as_object)
            .cloned()
            .unwrap_or_default();
        let suggestions = objects(payload.get("permission_suggestions"))
            .unwrap_or_default()
            .into_iter()
            .filter(|s| s.get("type").and_then(Value::as_str) != Some("setMode"))
            .map(|s| Value::Object(s.clone()))
            .collect();
        Some(Self {
            id: id.into(),
            address: address.into(),
            summary: Self::summary(&tool, &input),
            detail: input
                .get("description")
                .and_then(Value::as_str)
                .filter(|d| !d.is_empty())
                .map(str::to_owned),
            tool,
            suggestions,
            input,
            opened_at,
        })
    }

    /// O campo que diz o que se aprova, por ferramenta; o resto vai como JSON
    /// compacto de chaves ordenadas, cortado.
    pub fn summary(tool: &str, input: &Map<String, Value>) -> String {
        if tool == "AskUserQuestion"
            && let Some(first) = objects(input.get("questions"))
                .and_then(|qs| qs.first().copied())
                .and_then(|q| q.get("question"))
                .and_then(Value::as_str)
        {
            return clip(first, 600);
        }
        for key in [
            "command",
            "file_path",
            "notebook_path",
            "url",
            "pattern",
            "path",
            "query",
        ] {
            if let Some(value) = input
                .get(key)
                .and_then(Value::as_str)
                .filter(|v| !v.is_empty())
            {
                return clip(value, 600);
            }
        }
        if input.is_empty() {
            return tool.to_owned();
        }
        // O `JSONSerialization` escapa a barra, e aqui também. Desvio anotado,
        // só no texto do resumo: o `.sortedKeys` do Darwin ordena sem caixa e
        // números como números, e o `Map` do serde_json ordena por byte; `1.0`
        // lá sai `1`.
        match serde_json::to_string(input) {
            Ok(text) => clip(&text.replace('/', "\\/"), 600),
            Err(_) => tool.to_owned(),
        }
    }

    pub fn questions(&self) -> Vec<Question> {
        if self.tool != "AskUserQuestion" {
            return Vec::new();
        }
        objects(self.input.get("questions"))
            .unwrap_or_default()
            .into_iter()
            .filter_map(|raw| {
                let question = raw.get("question")?.as_str()?.to_owned();
                let options = objects(raw.get("options"))
                    .unwrap_or_default()
                    .into_iter()
                    .filter_map(|o| o.get("label").and_then(Value::as_str).map(str::to_owned))
                    .collect();
                Some(Question {
                    question,
                    header: raw.get("header").and_then(Value::as_str).map(str::to_owned),
                    options,
                    multi_select: raw
                        .get("multiSelect")
                        .and_then(Value::as_bool)
                        .unwrap_or(false),
                })
            })
            .collect()
    }

    pub fn can_always_allow(&self) -> bool {
        !self.suggestions.is_empty()
    }

    /// A saída que responde as perguntas: a ferramenta permitida, com o
    /// `tool_input` original e as escolhas em `answers`. Mais de uma escolha
    /// vai separada por vírgula, como o CLI grava.
    pub fn answer_output(&self, choices: &HashMap<String, Vec<String>>) -> Value {
        let mut updated = self.input.clone();
        let answers: Map<String, Value> = choices
            .iter()
            .map(|(q, picked)| (q.clone(), Value::String(picked.join(", "))))
            .collect();
        updated.insert("answers".to_owned(), Value::Object(answers));
        json!({"hookSpecificOutput": {"hookEventName": "PermissionRequest",
            "decision": {"behavior": "allow", "updatedInput": updated}}})
    }

    /// Toda pergunta tem pelo menos uma escolha, e só entre as opções dela.
    pub fn accepts(&self, choices: &HashMap<String, Vec<String>>) -> bool {
        let questions = self.questions();
        !questions.is_empty()
            && questions.iter().all(|q| {
                choices.get(&q.question).is_some_and(|picked| {
                    !picked.is_empty()
                        && (q.multi_select || picked.len() == 1)
                        && picked.iter().all(|p| q.options.contains(p))
                })
            })
    }
}

/// O que você respondeu.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PermissionAnswer {
    Allow,
    /// Permite e grava as regras que o CLI sugeriu.
    Always,
    Deny,
}

impl PermissionAnswer {
    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "allow" => Some(Self::Allow),
            "always" => Some(Self::Always),
            "deny" => Some(Self::Deny),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Allow => "allow",
            Self::Always => "always",
            Self::Deny => "deny",
        }
    }

    /// A saída do gancho, como o Claude Code lê em
    /// `hookSpecificOutput.decision`. "Sempre" sem sugestão é só "permitir".
    pub fn hook_output(self, suggestions: &[Value]) -> Value {
        let decision = match self {
            Self::Allow => json!({"behavior": "allow"}),
            Self::Always if !suggestions.is_empty() => {
                json!({"behavior": "allow", "updatedPermissions": suggestions})
            }
            Self::Always => json!({"behavior": "allow"}),
            Self::Deny => {
                json!({"behavior": "deny", "message": "Negado pelo usuário no Egeon Deck."})
            }
        };
        json!({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}})
    }
}

//! Os comandos que o `/` do Claude Code oferece e que não estão em disco: os
//! embutidos (`/compact`, `/model`…) e as skills que vêm no binário
//! (`/simplify`, `/loop`, `/debug`…).
//!
//! Mesma via do `model_registry`: o JavaScript minificado do CLI declara cada
//! embutido como um objeto com `type:"local"` (ou `local-jsx`, `prompt`), `name`
//! e `description` — em qualquer ordem — e cada skill do binário como
//! `x({name:"…",menuDescription:"…"})`. Formato interno, que muda sem aviso:
//! leitura que não acha nada devolve vazio, e a lista fica com os embutidos de
//! `slash_catalog::builtins`.

use std::collections::{BTreeSet, HashSet};
use std::sync::LazyLock;

use regex::Regex;
use serde::{Deserialize, Serialize};

use super::binary_source::Bytes;
use super::regex;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Entry {
    pub name: String,
    #[serde(default)]
    pub detail: String,
    /// Skill que só roda digitada (`disableModelInvocation`): nunca entra na
    /// `skill_listing` do transcript, então só o binário a conhece.
    #[serde(default)]
    pub user_only: bool,
    /// `/cost` e `/stats` levam ao `/usage`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub aliases: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct CommandRegistry {
    /// Sobe quando a leitura muda: cache de outra versão relê o binário.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<u32>,
    pub builtins: Vec<Entry>,
    pub skills: Vec<Entry>,
    /// Fora do `/`: embutido com `isHidden` e skill com `userInvocable: false` —
    /// esta aparece na `skill_listing`, que é a lista do MODELO.
    pub hidden: Vec<String>,
}

impl Default for CommandRegistry {
    fn default() -> Self {
        CommandRegistry {
            version: Some(Self::CURRENT_VERSION),
            builtins: Vec::new(),
            skills: Vec::new(),
            hidden: Vec::new(),
        }
    }
}

const BUILTIN_MARKS: [&[u8]; 3] = [
    br#"type:"local""#,
    br#"type:"local-jsx""#,
    br#"type:"prompt""#,
];
const SKILL_START: &[u8] = br#"({name:""#;
const WINDOW: usize = 1500;
/// Quanto antes do `type:` o objeto pode começar.
const LOOK_BACK: usize = 800;

static TOP_NAME: LazyLock<Regex> = LazyLock::new(|| regex(r#"[{,]name:"([a-z][a-z0-9:-]*)""#));
static SKILL_HEAD: LazyLock<Regex> = LazyLock::new(|| regex(r#"^\(\{name:"([a-z][a-z0-9:-]*)","#));
static ALIAS_LIST: LazyLock<Regex> = LazyLock::new(|| regex(r"aliases:\[([^\]]*)\]"));

#[derive(Debug, PartialEq, Eq)]
pub struct BuiltinRead {
    pub name: String,
    pub detail: String,
    pub hidden: bool,
    pub aliases: Vec<String>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct SkillRead {
    pub name: String,
    pub detail: Option<String>,
    pub hidden: bool,
    pub user_only: bool,
    pub aliases: Vec<String>,
}

fn opt(list: Vec<String>) -> Option<Vec<String>> {
    (!list.is_empty()).then_some(list)
}

impl CommandRegistry {
    pub const CURRENT_VERSION: u32 = 2;

    pub fn parse_binary(data: &[u8]) -> CommandRegistry {
        Self::parse_source(&mut { data })
    }

    pub fn parse_source(source: &mut impl Bytes) -> CommandRegistry {
        let mut out = CommandRegistry::default();
        let mut hidden: BTreeSet<String> = BTreeSet::new();
        let mut seen: HashSet<String> = HashSet::new();
        for mark in BUILTIN_MARKS {
            let mut cursor = 0;
            while let Some(at) = source.find(mark, cursor) {
                cursor = at + mark.len();
                let before = source.slice(at.saturating_sub(LOOK_BACK), at);
                let before = String::from_utf8_lossy(&before);
                let after = source.slice(at, at + WINDOW);
                let after = String::from_utf8_lossy(&after);
                let Some(open) = opening_brace(&before) else {
                    continue;
                };
                let Some(entry) = builtin(&format!("{}{after}", &before[open..])) else {
                    continue;
                };
                if entry.hidden {
                    hidden.insert(entry.name);
                    continue;
                }
                if !seen.insert(entry.name.clone()) {
                    continue;
                }
                out.builtins.push(Entry {
                    name: entry.name,
                    detail: entry.detail,
                    user_only: false,
                    aliases: opt(entry.aliases),
                });
            }
        }
        let mut skill_seen: HashSet<String> = HashSet::new();
        let mut cursor = 0;
        while let Some(at) = source.find(SKILL_START, cursor) {
            cursor = at + SKILL_START.len();
            // Janela cortada no meio de um caractere: o decodificador troca só
            // ele por `?`, o resto vale.
            let window = source.slice(at, at + WINDOW);
            let text = String::from_utf8_lossy(&window);
            let Some(entry) = skill(&text) else {
                continue;
            };
            if entry.hidden {
                hidden.insert(entry.name);
                continue;
            }
            let Some(detail) = entry.detail else {
                continue;
            };
            if !skill_seen.insert(entry.name.clone()) {
                continue;
            }
            out.skills.push(Entry {
                name: entry.name,
                detail,
                user_only: entry.user_only,
                aliases: opt(entry.aliases),
            });
        }
        out.builtins.sort_by(|a, b| a.name.cmp(&b.name));
        out.skills.sort_by(|a, b| a.name.cmp(&b.name));
        out.hidden = hidden
            .into_iter()
            .filter(|n| !seen.contains(n) && !skill_seen.contains(n))
            .collect();
        out
    }
}

/// O `{` que abre o objeto em que o texto termina — o último sem par.
pub fn opening_brace(text: &str) -> Option<usize> {
    let mut depth = 0;
    for (index, c) in text.char_indices().rev() {
        match c {
            '}' => depth += 1,
            '{' => {
                if depth == 0 {
                    return Some(index);
                }
                depth -= 1;
            }
            _ => {}
        }
    }
    None
}

/// Um embutido, a partir do `{` do objeto dele. O que vale é o próprio objeto
/// até o código (`load`/`call`) — logo depois costuma vir um `stub` com
/// `isHidden:!0` que não é dele.
pub fn builtin(text: &str) -> Option<BuiltinRead> {
    let body = cut(
        object(text),
        &["load:", "call:", "async call(", "getPromptForCommand"],
        1,
    );
    let name = first(&TOP_NAME, body)?;
    let hidden = body.contains("isHidden:!0") || body.contains("isEnabled:()=>!1");
    Some(BuiltinRead {
        name: name.to_owned(),
        detail: literal("description", body).unwrap_or_default(),
        hidden,
        aliases: aliases(body),
    })
}

/// Uma skill do binário, a partir do `({name:"`. Sem `menuDescription` não é
/// skill de menu — o mesmo começo é de um sem-número de objetos.
pub fn skill(text: &str) -> Option<SkillRead> {
    let name = first(&SKILL_HEAD, text)?;
    let rest = text.get(1..)?;
    let body = cut(object(rest), &["getPromptForCommand"], 1);
    let detail = literal("menuDescription", body);
    let hidden = body.contains("userInvocable:!1") && body.contains("description:");
    if detail.is_none() && !hidden {
        return None;
    }
    Some(SkillRead {
        name: name.to_owned(),
        detail,
        hidden,
        user_only: body.contains("disableModelInvocation:!0"),
        aliases: aliases(body),
    })
}

fn aliases(body: &str) -> Vec<String> {
    let Some(list) = first(&ALIAS_LIST, body) else {
        return Vec::new();
    };
    list.split(',')
        .map(|a| {
            a.trim_matches(|c: char| c == '"' || c == '\'' || c == ' ')
                .to_owned()
        })
        .filter(|a| !a.is_empty())
        .collect()
}

fn first<'a>(re: &Regex, text: &'a str) -> Option<&'a str> {
    re.captures(text)?.get(1).map(|m| m.as_str())
}

/// Do `{` do começo até o `}` que o fecha, pulando o que está entre aspas. Sem
/// fechamento na janela, a janela inteira.
pub fn object(text: &str) -> &str {
    let mut depth = 0;
    let mut quote: Option<char> = None;
    let mut escaped = false;
    for (index, c) in text.char_indices() {
        if let Some(open) = quote {
            if escaped {
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == open {
                quote = None;
            }
            continue;
        }
        match c {
            '"' | '\'' | '`' => quote = Some(c),
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    return &text[..index + c.len_utf8()];
                }
            }
            _ => {}
        }
    }
    text
}

fn cut<'a>(text: &'a str, marks: &[&str], skip: usize) -> &'a str {
    let from = text
        .char_indices()
        .nth(skip)
        .map_or(text.len(), |(index, _)| index);
    let end = marks
        .iter()
        .filter_map(|mark| text[from..].find(mark).map(|at| from + at))
        .min();
    &text[..end.unwrap_or(text.len())]
}

/// O valor de `chave:"…"` (ou com `'`/crase), com os escapes do JS desfeitos.
/// `None` quando o valor não é literal — um getter, uma variável.
pub fn literal(key: &str, text: &str) -> Option<String> {
    let at = text.find(&format!("{key}:"))?;
    let mut chars = text[at + key.len() + 1..].chars();
    let quote = chars.next().filter(|q| "\"'`".contains(*q))?;
    let mut out = String::new();
    while let Some(c) = chars.next() {
        if c == quote {
            return Some(out);
        }
        if quote == '`' && c == '$' {
            return None;
        }
        if c != '\\' {
            out.push(c);
            continue;
        }
        match chars.next()? {
            'n' => out.push(' '),
            'u' => {
                let hex: String = chars.by_ref().take(4).collect();
                if let Some(ch) = u32::from_str_radix(&hex, 16).ok().and_then(char::from_u32) {
                    out.push(ch);
                }
            }
            other => out.push(other),
        }
    }
    None
}

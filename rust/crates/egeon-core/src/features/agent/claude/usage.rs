//! O consumo que o Claude Code grava no transcript (ADR-085): cada resposta do
//! modelo traz `message.usage`, repetido em toda linha da mesma mensagem — uma
//! por bloco de conteúdo. Conta-se cada `message.id` uma vez.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::Value;

use crate::features::usage::{TokenUsage, UsageEntry};

const ASSISTANT_MARK: &[u8] = b"\"type\":\"assistant\"";
const USAGE_MARK: &[u8] = b"\"usage\"";

fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.windows(needle.len()).any(|w| w == needle)
}

/// `after`: o último id do trecho anterior do mesmo arquivo — a leitura
/// incremental pode partir no meio das linhas de uma mensagem.
pub fn entries(data: &[u8], after: Option<&str>) -> Vec<UsageEntry> {
    let mut out = Vec::new();
    let mut seen: HashSet<String> = after.map(str::to_owned).into_iter().collect();
    for line in data.split(|b| *b == b'\n') {
        // Antes do JSON: a maioria das linhas é ferramenta e prompt, e
        // decodificar todas custa caro num transcript de MB.
        if !contains(line, ASSISTANT_MARK) || !contains(line, USAGE_MARK) {
            continue;
        }
        if let Some(entry) = entry_from_line(line)
            && seen.insert(entry.id.clone())
        {
            out.push(entry);
        }
    }
    out
}

pub fn entry_from_line(line: &[u8]) -> Option<UsageEntry> {
    let object: Value = serde_json::from_slice(line).ok()?;
    if object.get("type")?.as_str()? != "assistant" {
        return None;
    }
    entry_from_message(object.get("message")?)
}

/// O `(x as? NSNumber)?.intValue` do Swift: número (decimal trunca), e `true`
/// conta como 1; o resto é 0.
fn int(value: &Value, key: &str) -> i64 {
    match value.get(key) {
        Some(Value::Number(n)) => n
            .as_i64()
            .or_else(|| n.as_f64().map(|f| f as i64))
            .unwrap_or(0),
        Some(Value::Bool(b)) => i64::from(*b),
        _ => 0,
    }
}

pub fn entry_from_message(message: &Value) -> Option<UsageEntry> {
    let usage = message.get("usage").filter(|u| u.is_object())?;
    let id = message.get("id")?.as_str()?;
    let model = message.get("model")?.as_str()?;
    // Resposta que o próprio CLI fabrica (erro, interrupção): não passou pelo
    // modelo e vem com uso zero.
    if model == "<synthetic>" {
        return None;
    }
    let mut tokens = TokenUsage {
        input: int(usage, "input_tokens"),
        output: int(usage, "output_tokens"),
        cache_read: int(usage, "cache_read_input_tokens"),
        ..TokenUsage::default()
    };
    let written = int(usage, "cache_creation_input_tokens");
    match usage.get("cache_creation").filter(|s| s.is_object()) {
        Some(split) => {
            tokens.cache_write5m = int(split, "ephemeral_5m_input_tokens");
            tokens.cache_write1h = int(split, "ephemeral_1h_input_tokens");
            // O que a divisão não explica fica no de 5 minutos, o padrão da API.
            tokens.cache_write5m += (written - tokens.cache_write()).max(0);
        }
        None => tokens.cache_write5m = written,
    }
    Some(UsageEntry {
        id: id.to_owned(),
        model: model.to_owned(),
        fast: usage.get("speed").and_then(Value::as_str) == Some("fast"),
        usage: tokens,
    })
}

/// Os transcripts de uma conversa: o dela e os dos subagentes, que o CLI grava
/// em `<sessão>/subagents/` e também são pagos.
pub fn files(transcript: &Path) -> Vec<PathBuf> {
    let folder = transcript.with_extension("").join("subagents");
    let mut subagents: Vec<PathBuf> = fs::read_dir(folder)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("jsonl"))
        .collect();
    subagents.sort();
    let mut all = vec![transcript.to_path_buf()];
    all.extend(subagents);
    all
}

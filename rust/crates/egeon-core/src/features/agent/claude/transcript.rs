//! O transcript do Claude Code, como turnos.
//!
//! Lê o JSONL que o Claude Code grava por conversa. Uma linha por evento; as
//! que interessam são `user` com texto (o prompt) e `assistant` (texto e
//! `tool_use`). `tool_result` vem como `user`, e attachment/system/progress são
//! ruído para o chat.
//!
//! Tudo aqui é função de bytes e de um relógio recebido por parâmetro; o disco
//! entra só em [`last_turn`], [`live_turn`] e [`context_tokens_at`], que leem a
//! cauda do arquivo.

use std::collections::{BTreeMap, HashSet};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::sync::LazyLock;
use std::time::{Duration, SystemTime};

use regex::Regex;
use serde_json::Value;

use super::usage::entry_from_message;
use super::{find, regex};
use crate::features::chat::diff_hunk::DiffHunk;
use crate::features::chat::model::{ChatPart, ChatStep, ChatTurn};
use crate::features::chat::time::{parse_iso, swift_double, unix_f64};
use crate::features::dispatch::marker::stripping_markers;
use crate::features::dispatch::request::TAG;
use crate::features::usage::{PriceTable, add_entry};

/// O que o agente estava fazendo quando a leitura parou: o tipo do último bloco
/// do assistant. `thinking` é raciocínio em curso — vale mostrar "pensando…", não
/// o conteúdo (ADR-029).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LastBlock {
    Text,
    Tool,
    Thinking,
}

/// O que a leitura precisa de fora: o relógio (turno sem data cai em "agora") e a
/// tabela de preços em vigor (o uso do turno congela o custo no preço de agora).
pub struct Context<'a> {
    pub now: SystemTime,
    pub prices: &'a PriceTable,
}

/// A varredura com onde cada turno começa no arquivo — a leitura ao vivo parte
/// dali na vez seguinte em vez de reler a cauda inteira.
#[derive(Debug, Default)]
pub struct Scan {
    pub turns: Vec<ChatTurn>,
    pub last: Option<LastBlock>,
    /// Byte (relativo ao início dos dados) da linha do prompt de cada turno, na
    /// ordem de `turns`.
    pub prompt_offsets: Vec<usize>,
}

const USER_MARK: &[u8] = b"\"type\":\"user\"";
const ASSISTANT_MARK: &[u8] = b"\"type\":\"assistant\"";

pub fn parse(jsonl: &str, ctx: &Context) -> Vec<ChatTurn> {
    scan(jsonl.as_bytes(), ctx).turns
}

pub fn parse_detailed(jsonl: &str, ctx: &Context) -> (Vec<ChatTurn>, Option<LastBlock>) {
    let scanned = scan(jsonl.as_bytes(), ctx);
    (scanned.turns, scanned.last)
}

fn has(line: &[u8], needle: &[u8]) -> bool {
    find(line, needle, 0).is_some()
}

/// Linha a linha em bytes. Em `String`, `split` e `contains` andam grafema a
/// grafema: 4 MB de cauda custavam dezenas de ms por leitura, várias vezes por
/// segundo enquanto o agente trabalha.
pub fn scan(data: &[u8], ctx: &Context) -> Scan {
    let mut out = Scan::default();
    let mut turns: Vec<ChatTurn> = Vec::new();
    let mut last: Option<LastBlock> = None;
    let mut counted: HashSet<String> = HashSet::new();
    let mut offset = 0usize;
    for line in data.split(|b| *b == b'\n') {
        let line_offset = offset;
        offset += line.len() + 1;
        // A maior parte do arquivo é attachment e snapshot — linhas enormes que
        // não interessam. Procurar o tipo antes de decodificar JSON é o que faz
        // um transcript de dezenas de MB ser lido em tempo útil. A linha
        // inteira, e não só o começo: `type` vem depois de parentUuid, cwd,
        // sessionId e afins.
        if line.is_empty() || !(has(line, USER_MARK) || has(line, ASSISTANT_MARK)) {
            continue;
        }
        let Ok(entry) = serde_json::from_slice::<Value>(line) else {
            continue;
        };
        let (Some(kind), Some(message)) = (
            entry.get("type").and_then(Value::as_str),
            entry.get("message").filter(|m| m.is_object()),
        ) else {
            continue;
        };
        let at = entry
            .get("timestamp")
            .and_then(Value::as_str)
            .and_then(parse_iso)
            .unwrap_or(ctx.now);

        match kind {
            "user" => {
                // Devolução de ferramenta vem como `user`: não é prompt, é o
                // resultado de um passo deste turno — encontra o passo pelo id.
                if let Some(blocks) = message.get("content").and_then(object_array)
                    && blocks
                        .iter()
                        .any(|b| str_of(b, "type") == Some("tool_result"))
                {
                    let Some(turn) = turns.last_mut() else {
                        continue;
                    };
                    for block in blocks
                        .iter()
                        .filter(|b| str_of(b, "type") == Some("tool_result"))
                    {
                        attach(block, entry.get("toolUseResult"), turn);
                    }
                    continue;
                }
                let Some(raw) = prompt_text(message.get("content")) else {
                    continue;
                };
                if entry.get("isMeta").and_then(Value::as_bool) == Some(true) {
                    continue;
                }
                let id = str_of(&entry, "uuid")
                    .map(str::to_owned)
                    .unwrap_or_else(|| format!("t-{}-{}", swift_double(unix_f64(at)), turns.len()));
                let envelope = agent_envelope(&raw);
                let (prompt, from) = match envelope {
                    Some((from, text)) => (text, Some(from)),
                    None => (raw, None),
                };
                turns.push(ChatTurn::new(&id, &prompt, at, from));
                out.prompt_offsets.push(line_offset);
                last = None;
            }
            "assistant" => {
                let Some(turn) = turns.last_mut() else {
                    continue;
                };
                // Uma linha por bloco, o mesmo uso em todas: conta o id uma vez.
                if let Some(usage) = entry_from_message(message)
                    && counted.insert(usage.id.clone())
                {
                    add_entry(&mut turn.usage, &usage, ctx.prices);
                }
                let Some(blocks) = message.get("content").and_then(object_array) else {
                    continue;
                };
                for block in blocks {
                    match str_of(block, "type") {
                        Some("text") => {
                            let text = stripping_markers(str_of(block, "text").unwrap_or(""));
                            if text.is_empty() {
                                continue;
                            }
                            if !turn.reply_text.is_empty() {
                                turn.reply_text.push_str("\n\n");
                            }
                            turn.reply_text.push_str(&text);
                            turn.parts.push(ChatPart::Text(text));
                            turn.reply_at = Some(at);
                            last = Some(LastBlock::Text);
                        }
                        Some("tool_use") => {
                            let step = step(block);
                            turn.steps.push(step.clone());
                            turn.parts.push(ChatPart::Step(step));
                            turn.reply_at = Some(at);
                            last = Some(LastBlock::Tool);
                        }
                        Some("thinking") => last = Some(LastBlock::Thinking),
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    out.turns = turns;
    out.last = last;
    out
}

/// `as? [[String: Any]]`: uma lista cujos elementos são todos objetos.
fn object_array(value: &Value) -> Option<&Vec<Value>> {
    value.as_array().filter(|a| a.iter().all(Value::is_object))
}

fn str_of<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

/// Prompt do usuário: string, ou blocos de texto. `tool_result` não é prompt, e
/// `<command-…>` é comando de barra que a TUI registra como mensagem.
fn prompt_text(content: Option<&Value>) -> Option<String> {
    let content = content?;
    let text = if let Some(string) = content.as_str() {
        string.to_owned()
    } else {
        let blocks = object_array(content)?;
        let parts: Vec<&str> = blocks
            .iter()
            .filter(|b| str_of(b, "type") == Some("text"))
            .filter_map(|b| str_of(b, "text"))
            .collect();
        if parts.is_empty() {
            return None;
        }
        parts.join("\n")
    };
    let text = text.trim();
    if text.is_empty() || text.starts_with("<command-") || text.starts_with("<local-command") {
        return None;
    }
    Some(text.to_owned())
}

/// O envelope que o Dispatcher põe em mensagem de outro agente: primeira linha
/// `[ED] mensagem de bancada/id` e o texto. Devolve quem mandou e só o texto.
///
/// `[egeon]` é a marca anterior (ADR-055) e continua sendo reconhecida: o
/// histórico do chat e os transcripts do CLI já gravados têm mensagens com ela,
/// e deixar de aceitá-la faria a bolha antiga perder o remetente.
pub fn agent_envelope(prompt: &str) -> Option<(String, String)> {
    let new = format!("{TAG} mensagem de ");
    let header = [new.as_str(), "[egeon] mensagem de "]
        .into_iter()
        .find(|h| prompt.starts_with(h))?;
    let mut lines = prompt.split('\n');
    let first = lines.next().unwrap_or("");
    let from = first[header.len()..]
        .trim_matches(|c| c == ' ' || c == '\t')
        .to_owned();
    let text = lines.collect::<Vec<_>>().join("\n").trim().to_owned();
    Some((from, text))
}

/// O passo como o terminal o mostra: a linha, o comando por extenso, e — para
/// edição — o diff já na hora do `tool_use`, antes de o resultado voltar: é o que
/// se quer acompanhar ao vivo.
fn step(block: &Value) -> ChatStep {
    let name = str_of(block, "name").unwrap_or("?");
    let empty = Value::Object(serde_json::Map::new());
    let input = block
        .get("input")
        .filter(|i| i.is_object())
        .unwrap_or(&empty);
    let id = str_of(block, "id").map(str::to_owned);
    let with_id = |mut step: ChatStep| {
        step.tool_id.clone_from(&id);
        step
    };
    match name {
        "Bash" => {
            let command = str_of(input, "command").unwrap_or("");
            if let Some(target) = send_target(command) {
                let mut step = ChatStep::new("⇄", &format!("egeon send {target}"));
                step.send_to = Some(target);
                step.detail = heredoc_body(command);
                return with_id(step);
            }
            let description = str_of(input, "description");
            let text = description
                .map_or_else(|| if command.is_empty() { "bash" } else { command }, |d| d);
            let mut step = ChatStep::new("$", text);
            step.detail = description.map(|_| command.to_owned());
            with_id(step)
        }
        "Edit" => {
            let mut step = ChatStep::new("±", &short_path(str_of(input, "file_path")));
            step.diff = diff(
                str_of(input, "old_string").unwrap_or(""),
                str_of(input, "new_string").unwrap_or(""),
            );
            with_id(step)
        }
        "MultiEdit" => {
            let lines: Vec<String> = input
                .get("edits")
                .and_then(object_array)
                .into_iter()
                .flatten()
                .flat_map(|edit| {
                    diff(
                        str_of(edit, "old_string").unwrap_or(""),
                        str_of(edit, "new_string").unwrap_or(""),
                    )
                    .unwrap_or_default()
                })
                .collect();
            let mut step = ChatStep::new("±", &short_path(str_of(input, "file_path")));
            step.diff = capped_diff(lines);
            with_id(step)
        }
        "Write" => {
            let content = str_of(input, "content").unwrap_or("");
            let lines: Vec<String> = content.split('\n').map(|l| format!("+{l}")).collect();
            let mut step = ChatStep::new("±", &short_path(str_of(input, "file_path")));
            step.diff = capped_diff(lines);
            with_id(step)
        }
        "NotebookEdit" => with_id(ChatStep::new(
            "±",
            &short_path(str_of(input, "notebook_path")),
        )),
        "Read" => with_id(ChatStep::new(
            "→",
            &format!("read {}", short_path(str_of(input, "file_path"))),
        )),
        _ => {
            let mut step = ChatStep::new("→", name);
            step.detail = compact_input(input);
            with_id(step)
        }
    }
}

/// Diff sem LCS: o `old_string` de um Edit é curto e localizado; `-` para o que
/// saiu, `+` para o que entrou é o que o terminal mostra também. O
/// `structuredPatch` do resultado, com contexto, substitui isto ao chegar.
pub fn diff(old: &str, new: &str) -> Option<Vec<String>> {
    let mut lines: Vec<String> = Vec::new();
    if !old.is_empty() {
        lines.extend(old.split('\n').map(|l| format!("-{l}")));
    }
    if !new.is_empty() {
        lines.extend(new.split('\n').map(|l| format!("+{l}")));
    }
    capped_diff(lines)
}

/// Vazio é `None`: edição sem texto não tem diff a mostrar.
fn capped_diff(mut lines: Vec<String>) -> Option<Vec<String>> {
    if lines.is_empty() {
        return None;
    }
    let max = ChatStep::MAX_DIFF_LINES;
    if lines.len() > max {
        let rest = lines.len() - max;
        lines.truncate(max);
        lines.push(format!("… +{rest} linhas"));
    }
    Some(lines)
}

/// O texto de um `egeon send … <<'MB' … MB`: o que foi dito, sem a moldura.
fn heredoc_body(command: &str) -> Option<String> {
    let lines: Vec<&str> = command.split('\n').collect();
    (lines.len() > 2).then(|| lines[1..lines.len() - 1].join("\n"))
}

/// Entrada de ferramenta genérica em uma linha por chave, sem afogar:
/// `pattern: foo · path: app/` diz o que o Grep procurou.
fn compact_input(input: &Value) -> Option<String> {
    let map: BTreeMap<&String, &Value> = input.as_object()?.iter().collect();
    let pairs: Vec<String> = map
        .into_iter()
        .map(|(key, value)| {
            let text = match value {
                Value::String(s) => s.clone(),
                // `JSONSerialization` escapa a barra; o valor segue o dele.
                other => serde_json::to_string(other)
                    .unwrap_or_default()
                    .replace('/', "\\/"),
            };
            let one_line = text.replace('\n', " ");
            let shown = if one_line.chars().count() > 160 {
                format!("{}…", one_line.chars().take(160).collect::<String>())
            } else {
                one_line
            };
            format!("{key}: {shown}")
        })
        .collect();
    (!pairs.is_empty()).then(|| pairs.join("\n"))
}

/// Casa o resultado com o passo pelo `tool_use_id` e guarda a prévia. O
/// `toolUseResult` estruturado vale mais que o texto: `stdout`/`stderr` do Bash
/// sem a moldura, o `structuredPatch` do Edit com contexto, o número de linhas
/// do Read em vez do arquivo inteiro.
fn attach(block: &Value, structured: Option<&Value>, turn: &mut ChatTurn) {
    let Some(id) = str_of(block, "tool_use_id") else {
        return;
    };
    let Some(index) = turn
        .parts
        .iter()
        .rposition(|p| matches!(p, ChatPart::Step(s) if s.tool_id.as_deref() == Some(id)))
    else {
        return;
    };
    let ChatPart::Step(step) = &mut turn.parts[index] else {
        return;
    };
    let is_error = block.get("is_error").and_then(Value::as_bool) == Some(true);
    let mut output: Option<String> = None;
    let payload = structured.filter(|p| p.is_object());
    if let Some(patch) = payload
        .and_then(|p| p.get("structuredPatch"))
        .and_then(object_array)
        .filter(|p| !p.is_empty())
    {
        // Com o cabeçalho `@@` de cada trecho: é dele que a vista lado a lado
        // tira o número de linha de cada versão.
        let int = |hunk: &Value, key: &str| hunk.get(key).and_then(Value::as_i64).unwrap_or(0);
        let lines: Vec<String> = patch
            .iter()
            .flat_map(|hunk| {
                let header = DiffHunk::header(
                    int(hunk, "oldStart"),
                    int(hunk, "oldLines"),
                    int(hunk, "newStart"),
                    int(hunk, "newLines"),
                );
                let body = hunk
                    .get("lines")
                    .and_then(Value::as_array)
                    .filter(|l| l.iter().all(Value::is_string))
                    .map(|l| {
                        l.iter()
                            .filter_map(|s| s.as_str().map(str::to_owned))
                            .collect::<Vec<_>>()
                    })
                    .unwrap_or_default();
                std::iter::once(header).chain(body)
            })
            .collect();
        step.diff = capped_diff(lines).or(step.diff.take());
    }
    let file = payload
        .and_then(|p| p.get("file"))
        .filter(|f| f.is_object());
    let num_lines = file.and_then(|f| f.get("numLines")).and_then(Value::as_i64);
    if let (Some(file), Some(n)) = (file, num_lines) {
        // O que foi lido, e não só "119 linhas": recolhido o passo mostra a
        // conta, aberto mostra o texto realçado pela extensão do arquivo
        // (ADR-044/046). O teto do `capped` é o que impede o arquivo inteiro de
        // virar histórico.
        let total = file
            .get("totalLines")
            .and_then(Value::as_i64)
            .map(|t| {
                if t > n {
                    format!(" de {t}")
                } else {
                    String::new()
                }
            })
            .unwrap_or_default();
        let content = str_of(file, "content").unwrap_or("");
        output = Some(if content.is_empty() {
            format!("{n} linha{}{total}", if n == 1 { "" } else { "s" })
        } else {
            content.to_owned()
        });
    } else if payload.is_some_and(|p| p.get("stdout").is_some() || p.get("stderr").is_some()) {
        let payload = payload.unwrap_or(&Value::Null);
        let out = str_of(payload, "stdout").unwrap_or("").trim();
        let err = str_of(payload, "stderr").unwrap_or("").trim();
        output = Some(
            [out, err]
                .iter()
                .filter(|s| !s.is_empty())
                .copied()
                .collect::<Vec<_>>()
                .join("\n"),
        );
    } else if step.glyph == "±" {
        output = None;
    } else if let Some(text) = str_of(block, "content") {
        output = Some(text.to_owned());
    } else if let Some(blocks) = block.get("content").and_then(object_array) {
        let texts: Vec<String> = blocks
            .iter()
            .filter_map(|b| match str_of(b, "type") {
                Some("text") => str_of(b, "text").map(str::to_owned),
                Some("image") => Some("[imagem]".to_owned()),
                _ => None,
            })
            .collect();
        output = Some(texts.join("\n"));
    }
    if is_error
        && output.as_deref().is_none_or(str::is_empty)
        && let Some(text) = str_of(block, "content")
    {
        output = Some(text.to_owned());
    }
    step.output = output
        .map(|o| ChatStep::capped(&o))
        .filter(|o| !o.is_empty());
    step.is_error = is_error;
    let updated = step.clone();
    if let Some(at) = turn
        .steps
        .iter()
        .rposition(|s| s.tool_id.as_deref() == Some(id))
    {
        turn.steps[at] = updated;
    }
}

static SEND_TARGET: LazyLock<Regex> = LazyLock::new(|| regex(r"egeon[ \t]+send[ \t]+([^\s<]+)"));

/// O endereço num `egeon send <bancada/id>`, se o comando for um. Só espaço e tab
/// entre as palavras, e o alvo sem `<`: num heredoc torto, `send\nMB` e
/// `send <<'MB'` passavam por endereço.
pub fn send_target(command: &str) -> Option<String> {
    SEND_TARGET
        .captures(command)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().to_owned())
}

fn short_path(path: Option<&str>) -> String {
    let Some(path) = path else {
        return String::new();
    };
    let parts: Vec<&str> = path
        .split(crate::features::path_text::is_separator)
        .filter(|p| !p.is_empty())
        .collect();
    let start = parts.len().saturating_sub(2);
    parts[start..].join("/")
}

// ---- leitura da cauda do arquivo -------------------------------------------

fn tail(path: &Path, bytes: u64) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let size = file.seek(SeekFrom::End(0)).unwrap_or(0);
    let start = size.saturating_sub(bytes);
    file.seek(SeekFrom::Start(start)).ok()?;
    let mut data = Vec::new();
    file.read_to_end(&mut data).ok()?;
    // Como `String(data:encoding:.utf8)`: cauda que corta um caractere ao meio
    // não é texto — defeito do legado, portado como está.
    String::from_utf8(data).ok()
}

/// Cauda lida para o último turno: maior que a do marcador, porque um turno com
/// muitas ferramentas passa fácil de 512 KB, e o prompt dele ficaria de fora.
pub const LAST_TURN_TAIL_BYTES: u64 = 2 * 1024 * 1024;

/// O último turno inteiro — prompt, passos, resposta — para o histórico do chat
/// (ADR-037).
///
/// A cauda pode cortar justamente a linha do prompt — aí o parse devolve o turno
/// ANTERIOR inteiro, que parece certo. `not_before` é o instante do `prompt`
/// deste turno: turno mais velho que isso não é ele, e o arquivo é lido inteiro.
pub fn last_turn(
    path: &Path,
    not_before: Option<SystemTime>,
    tail_bytes: u64,
    ctx: &Context,
) -> Option<ChatTurn> {
    let text = tail(path, tail_bytes)?;
    if let Some(turn) = parse(&text, ctx).pop()
        && not_before.is_none_or(|limit| turn.prompt_at >= limit)
    {
        return Some(turn);
    }
    let whole = std::fs::read_to_string(path).ok()?;
    parse(&whole, ctx).pop()
}

/// O turno EM CURSO, para a bolha ao vivo (ADR-039): a cadeia até onde o CLI já
/// gravou, e o que ele estava fazendo no fim dela.
#[derive(Debug, Clone, PartialEq)]
pub struct LiveTurn {
    pub turn: ChatTurn,
    pub last: Option<LastBlock>,
    /// Byte do arquivo onde a linha do prompt deste turno começa. A leitura
    /// seguinte parte daqui (`from`): só o turno em curso é relido, não os 4 MB
    /// de turnos velhos atrás dele.
    pub prompt_offset: u64,
}

pub const LIVE_TAIL_BYTES: u64 = 4 * 1024 * 1024;

/// Diferente de [`last_turn`], não cai para o arquivo inteiro: isto roda a cada
/// mudança do transcript durante o turno, e um transcript de dezenas de MB relido
/// a cada segundo pesaria. Turno mais velho que o `prompt` deste (a cauda cortou a
/// linha do prompt, ou a linha ainda não foi gravada) devolve `None`, e a bolha
/// fica em "trabalhando…".
pub fn live_turn(
    path: &Path,
    not_before: Option<SystemTime>,
    from: u64,
    tail_bytes: u64,
    ctx: &Context,
) -> Option<LiveTurn> {
    let (data, base) = read_from(path, from, tail_bytes)?;
    let mut scanned = scan(&data, ctx);
    let mut base = base;
    // Offset de uma conversa que já não existe (arquivo trocado ou encolhido):
    // sem turno a partir dele, volta à cauda.
    if scanned.turns.is_empty()
        && from > 0
        && let Some((again, again_base)) = read_from(path, 0, tail_bytes)
    {
        scanned = scan(&again, ctx);
        base = again_base;
    }
    let turn = scanned.turns.pop()?;
    let prompt_offset = *scanned.prompt_offsets.last()?;
    // Folga porque o gancho `prompt` e a linha do prompt nascem no mesmo segundo,
    // em ordem que não se controla.
    if let Some(limit) = not_before
        && turn.prompt_at < limit.checked_sub(Duration::from_secs(5)).unwrap_or(limit)
    {
        return None;
    }
    Some(LiveTurn {
        turn,
        last: scanned.last,
        prompt_offset: base + prompt_offset as u64,
    })
}

/// Do byte `from` ao fim — é o turno em curso, do tamanho que for. Sem offset (ou
/// com um que passou do fim do arquivo), só a cauda.
fn read_from(path: &Path, from: u64, tail_bytes: u64) -> Option<(Vec<u8>, u64)> {
    let mut file = File::open(path).ok()?;
    let size = file.seek(SeekFrom::End(0)).unwrap_or(0);
    let tail_start = size.saturating_sub(tail_bytes);
    let start = if from > 0 && from <= size {
        from
    } else {
        tail_start
    };
    file.seek(SeekFrom::Start(start)).ok()?;
    let mut data = Vec::new();
    file.read_to_end(&mut data).ok()?;
    Some((data, start))
}

// ---- modelo e contexto ------------------------------------------------------

pub const MODEL_TAIL_BYTES: u64 = 256 * 1024;

/// O modelo que respondeu por último, pelo nome completo que o CLI grava
/// (`claude-fable-5`). É a única fonte literal: o apelido pedido na flag
/// (`sonnet`) não diz qual versão o CLI resolveu, e `padrão` não diz nada.
/// `<synthetic>` é resposta fabricada pela TUI, não modelo — pula.
pub fn last_model_at(path: &Path, since: Option<SystemTime>, tail_bytes: u64) -> Option<String> {
    last_model(&tail(path, tail_bytes)?, since)
}

/// `since` descarta resposta anterior a esse instante: depois de trocar de
/// modelo, a última linha da conversa ainda é do modelo antigo até o novo
/// responder.
pub fn last_model(jsonl: &str, since: Option<SystemTime>) -> Option<String> {
    for line in jsonl.split('\n').filter(|l| !l.is_empty()).rev() {
        if !line.contains("\"type\":\"assistant\"") {
            continue;
        }
        let Ok(entry) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if str_of(&entry, "type") != Some("assistant") {
            continue;
        }
        let Some(model) = entry
            .get("message")
            .and_then(|m| m.get("model"))
            .and_then(Value::as_str)
            .filter(|m| !m.is_empty() && !m.starts_with('<'))
        else {
            continue;
        };
        if let Some(since) = since {
            // De baixo para cima: a primeira velha encerra a busca.
            let at = str_of(&entry, "timestamp").and_then(parse_iso)?;
            if at < since {
                return None;
            }
        }
        return Some(model.to_owned());
    }
    None
}

/// Quantos tokens a conversa ocupa: o prompt da última resposta do modelo.
/// Subagente tem contexto próprio e não conta. Compactar invalida o número até a
/// próxima resposta, e `None` é "não se sabe": mostrar o de antes diria que o
/// contexto segue cheio logo depois de esvaziar.
pub fn context_tokens_at(path: &Path, tail_bytes: u64) -> Option<i64> {
    context_tokens(&tail(path, tail_bytes)?)
}

pub fn context_tokens(jsonl: &str) -> Option<i64> {
    for line in jsonl.split('\n').filter(|l| !l.is_empty()).rev() {
        let boundary = line.contains("\"compact_boundary\"");
        if !(boundary || line.contains("\"type\":\"assistant\"")) {
            continue;
        }
        let Ok(entry) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if str_of(&entry, "type") == Some("system")
            && str_of(&entry, "subtype") == Some("compact_boundary")
        {
            return None;
        }
        if entry.get("isSidechain").and_then(Value::as_bool) == Some(true) {
            continue;
        }
        let Some(usage) = super::usage::entry_from_line(line.as_bytes()) else {
            continue;
        };
        return Some(usage.usage.prompt());
    }
    None
}

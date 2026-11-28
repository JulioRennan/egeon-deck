//! O protocolo de fim de turno: o marcador que o agente escreve, o evento que o
//! gancho do CLI relata e a leitura do marcador no transcript. Porte de
//! `MarkerConfig` (AgentProfile.swift), `HookEvent.swift` e
//! `ClaudeTranscript.lastMarker`/`strippingMarkers`.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::time::{Duration, SystemTime};

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Com que marcador o turno fechou.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Marker {
    Ok,
    Ask,
    Wait,
}

impl Marker {
    /// O nome que vai para o log, como o `rawValue` do Swift.
    pub fn as_str(self) -> &'static str {
        match self {
            Marker::Ok => "ok",
            Marker::Ask => "ask",
            Marker::Wait => "wait",
        }
    }
}

/// O que o gancho do CLI relata pelo socket — o contrato de `/activity` e
/// `/conversation`. O desconhecido morre na borda, com a lista do que vale.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HookEvent {
    Stop,
    Prompt,
    Ask,
    Start,
    Failure,
}

impl HookEvent {
    pub const ALL: [HookEvent; 5] = [
        HookEvent::Stop,
        HookEvent::Prompt,
        HookEvent::Ask,
        HookEvent::Start,
        HookEvent::Failure,
    ];

    pub fn parse(raw: &str) -> Option<HookEvent> {
        Self::ALL.into_iter().find(|e| e.as_str() == raw)
    }

    pub fn as_str(self) -> &'static str {
        match self {
            HookEvent::Stop => "stop",
            HookEvent::Prompt => "prompt",
            HookEvent::Ask => "ask",
            HookEvent::Start => "start",
            HookEvent::Failure => "failure",
        }
    }

    /// Para a mensagem de erro da rota: o que ela aceita, por extenso.
    pub fn expected() -> String {
        Self::ALL.map(HookEvent::as_str).join("|")
    }
}

/// Os marcadores e a instrução que vai no system prompt. Chave ausente no
/// `agents.json` herda o padrão, como o decode tolerante do Swift.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(from = "RawMarker")]
pub struct MarkerConfig {
    pub enabled: bool,
    pub done: String,
    pub ask: String,
    pub wait: String,
    pub instruction: String,
}

/// ASCII curto e numa linha só de propósito: marcador comprido é quebrado pela
/// TUI quando a janela é estreita, e um marcador partido não casa mais.
pub const DEFAULT_INSTRUCTION: &str =
    "Protocolo Egeon: termine TODA resposta com um marcador sozinho na \
última linha, sem nada depois dele.
{done} — terminei e não dependo de você.
{ask} — parei e dependo de uma resposta sua: dúvida, escolha, permissão \
ou informação que falta.
{wait} — parei, mas deixei trabalho rodando em segundo plano (comando em \
background, subagente, vizinho acionado) e volto sozinho quando ele acabar.
Se você fez uma pergunta ao usuário, o marcador é {ask}. Um marcador só, \
sempre por último.";

/// A linha do `{wait}` para instrução gravada antes dele existir: o
/// `agents.json` guarda a instrução por extenso, e sem isto o marcador novo
/// nunca chegaria a quem já tinha o arquivo.
pub const WAIT_LINE: &str = "{wait} — parei, mas deixei trabalho rodando em segundo plano (comando em \
background, subagente, vizinho acionado) e volto sozinho quando ele acabar.";

/// Chave ausente e `null` herdam o padrão, como o `decodeIfPresent ?? fallback`
/// do Swift.
#[derive(Deserialize, Default)]
#[serde(default)]
struct RawMarker {
    enabled: Option<bool>,
    done: Option<String>,
    ask: Option<String>,
    wait: Option<String>,
    instruction: Option<String>,
}

impl From<RawMarker> for MarkerConfig {
    fn from(raw: RawMarker) -> Self {
        let d = MarkerConfig::default();
        Self {
            enabled: raw.enabled.unwrap_or(d.enabled),
            done: raw.done.unwrap_or(d.done),
            ask: raw.ask.unwrap_or(d.ask),
            wait: raw.wait.unwrap_or(d.wait),
            instruction: raw.instruction.unwrap_or(d.instruction),
        }
    }
}

impl Default for MarkerConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            done: "[[ED:ok]]".to_owned(),
            ask: "[[ED:ask]]".to_owned(),
            wait: "[[ED:wait]]".to_owned(),
            instruction: DEFAULT_INSTRUCTION.to_owned(),
        }
    }
}

impl MarkerConfig {
    pub fn resolved_instruction(&self) -> String {
        let text = if self.instruction.contains("{wait}") {
            self.instruction.clone()
        } else {
            format!("{}\n{WAIT_LINE}", self.instruction)
        };
        text.replace("{done}", &self.done)
            .replace("{ask}", &self.ask)
            .replace("{wait}", &self.wait)
    }

    /// O marcador mais recente do texto — o de baixo, porque terminal e
    /// resposta escrevem para baixo.
    ///
    /// Token vazio nunca casa (`range(of: "")` é `nil` no Swift), e no empate
    /// fica o primeiro da lista, como o `max(by:)` de lá.
    pub fn latest(&self, text: &str) -> Option<Marker> {
        [
            (Marker::Ok, &self.done),
            (Marker::Ask, &self.ask),
            (Marker::Wait, &self.wait),
        ]
        .into_iter()
        .filter(|(_, token)| !token.is_empty())
        .filter_map(|(kind, token)| text.rfind(token.as_str()).map(|at| (kind, at)))
        .fold(
            None,
            |best: Option<(Marker, usize)>, (kind, at)| match best {
                Some((_, top)) if top >= at => best,
                _ => Some((kind, at)),
            },
        )
        .map(|(kind, _)| kind)
    }

    /// Os três marcadores, sem os vazios — que nunca casam.
    pub fn all(&self) -> Vec<&str> {
        [&self.done, &self.ask, &self.wait]
            .into_iter()
            .map(String::as_str)
            .filter(|t| !t.is_empty())
            .collect()
    }
}

/// O marcador do último turno e quando a linha foi gravada: sem a data, o
/// marcador do turno passado passaria pelo deste quando o `Stop` chega antes
/// da escrita.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LastMarker {
    pub marker: Option<Marker>,
    pub at: Option<SystemTime>,
}

/// Cauda lida do transcript: ele passa de dezenas de MB, e o que interessa é a
/// última mensagem do assistente.
pub const MARKER_TAIL_BYTES: u64 = 512 * 1024;

pub fn last_marker_at(path: &Path, marker: &MarkerConfig, tail_bytes: u64) -> Option<LastMarker> {
    let text = tail(path, tail_bytes)?;
    last_marker(&text, marker)
}

/// Como no Swift (`String(data:encoding:.utf8)`), uma cauda que corta um
/// caractere de vários bytes ao meio não é texto e devolve `None` — defeito do
/// legado, portado como está.
fn tail(path: &Path, bytes: u64) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let size = file.seek(SeekFrom::End(0)).unwrap_or(0);
    let start = size.saturating_sub(bytes);
    file.seek(SeekFrom::Start(start)).ok()?;
    let mut data = Vec::new();
    file.read_to_end(&mut data).ok()?;
    String::from_utf8(data).ok()
}

pub fn last_marker(jsonl: &str, marker: &MarkerConfig) -> Option<LastMarker> {
    for line in jsonl.split('\n').filter(|l| !l.is_empty()).rev() {
        if !line.contains("\"type\":\"assistant\"") {
            continue;
        }
        let Ok(entry) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        if entry.get("type").and_then(Value::as_str) != Some("assistant") {
            continue;
        }
        let Some(blocks) = entry
            .get("message")
            .and_then(|m| m.get("content"))
            .and_then(Value::as_array)
        else {
            continue;
        };
        // `as? [[String: Any]]` do Swift: um elemento que não é objeto
        // derruba a linha inteira.
        if !blocks.iter().all(Value::is_object) {
            continue;
        }
        // Linha de assistant só com tool_use não é fim de turno: sobe.
        let Some(text) = blocks
            .iter()
            .rev()
            .find(|b| b.get("type").and_then(Value::as_str) == Some("text"))
            .and_then(|b| b.get("text"))
            .and_then(Value::as_str)
        else {
            continue;
        };
        let at = entry
            .get("timestamp")
            .and_then(Value::as_str)
            .and_then(parse_iso8601);
        return Some(LastMarker {
            marker: marker.latest(text),
            at,
        });
    }
    None
}

/// Os marcadores são para o app, não para você ler na bolha.
pub fn stripping_markers(text: &str) -> String {
    text.replace("[[ED:ok]]", "")
        .replace("[[ED:ask]]", "")
        .replace("[[ED:wait]]", "")
        .trim()
        .to_owned()
}

/// `2026-08-25T17:19:23.796Z`, com ou sem fração, `Z` ou `±HH:MM` — o que o
/// `ISO8601DateFormatter` do Swift aceita com `withInternetDateTime`.
pub fn parse_iso8601(raw: &str) -> Option<SystemTime> {
    let b = raw.as_bytes();
    let num = |from: usize, len: usize| -> Option<i64> {
        let s = raw.get(from..from + len)?;
        if !s.bytes().all(|c| c.is_ascii_digit()) {
            return None;
        }
        s.parse().ok()
    };
    if b.len() < 20 || b[4] != b'-' || b[7] != b'-' || !matches!(b[10], b'T' | b't') {
        return None;
    }
    if b[13] != b':' || b[16] != b':' {
        return None;
    }
    let (year, month, day) = (num(0, 4)?, num(5, 2)?, num(8, 2)?);
    let (hour, minute, second) = (num(11, 2)?, num(14, 2)?, num(17, 2)?);
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) || hour > 23 || minute > 59 {
        return None;
    }
    if second > 60 {
        return None;
    }
    let mut i = 19;
    let mut nanos: u64 = 0;
    if b.get(i) == Some(&b'.') {
        i += 1;
        let start = i;
        while b.get(i).is_some_and(u8::is_ascii_digit) {
            i += 1;
        }
        if i == start {
            return None;
        }
        let digits = &raw[start..i.min(start + 9)];
        nanos = digits.parse::<u64>().ok()? * 10u64.pow(9 - digits.len() as u32);
    }
    let offset = match b.get(i)? {
        b'Z' | b'z' if i + 1 == b.len() => 0,
        sign @ (b'+' | b'-') if i + 6 == b.len() && b[i + 3] == b':' => {
            let minutes = num(i + 1, 2)? * 60 + num(i + 4, 2)?;
            if *sign == b'+' {
                minutes * 60
            } else {
                -minutes * 60
            }
        }
        _ => return None,
    };
    let days = days_from_civil(year, month, day);
    let secs = days * 86_400 + hour * 3_600 + minute * 60 + second - offset;
    let base = if secs >= 0 {
        SystemTime::UNIX_EPOCH.checked_add(Duration::from_secs(secs as u64))?
    } else {
        SystemTime::UNIX_EPOCH.checked_sub(Duration::from_secs(secs.unsigned_abs()))?
    };
    base.checked_add(Duration::from_nanos(nanos))
}

/// Dias desde 1970-01-01 no calendário gregoriano proléptico (Howard Hinnant).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assistant(blocks: &str) -> String {
        format!(r#"{{"type":"assistant","message":{{"content":[{blocks}]}}}}"#)
    }
    fn text(s: &str) -> String {
        format!(r#"{{"type":"text","text":"{s}"}}"#)
    }
    const TOOL: &str = r#"{"type":"tool_use","name":"Bash","input":{}}"#;
    const USER: &str = r#"{"type":"user","message":{"content":"oi"}}"#;

    fn read(lines: &[String]) -> Option<LastMarker> {
        last_marker(&lines.join("\n"), &MarkerConfig::default())
    }

    #[test]
    fn ok_at_end_of_last_reply() {
        let r = read(&[USER.into(), assistant(&text(r"Feito.\n\n[[ED:ok]]"))]);
        assert_eq!(r.and_then(|r| r.marker), Some(Marker::Ok));
    }

    #[test]
    fn ask_wins() {
        let r = read(&[USER.into(), assistant(&text(r"Qual?\n\n[[ED:ask]]"))]);
        assert_eq!(r.and_then(|r| r.marker), Some(Marker::Ask));
    }

    #[test]
    fn wait_means_background() {
        let r = read(&[
            USER.into(),
            assistant(&text(r"Deixei o build rodando.\n\n[[ED:wait]]")),
        ]);
        assert_eq!(r.and_then(|r| r.marker), Some(Marker::Wait));
    }

    #[test]
    fn lowest_of_the_three_wins() {
        let m = MarkerConfig::default();
        assert_eq!(
            m.latest("uso [[ED:wait]] ou [[ED:ask]]\n[[ED:ok]]"),
            Some(Marker::Ok)
        );
        assert_eq!(m.latest("[[ED:ok]] antes\n[[ED:wait]]"), Some(Marker::Wait));
        assert_eq!(m.latest("nada aqui"), None);
    }

    #[test]
    fn empty_token_never_matches() {
        let m = MarkerConfig {
            wait: String::new(),
            ..MarkerConfig::default()
        };
        assert_eq!(m.latest("nada aqui"), None);
        assert_eq!(m.latest("feito [[ED:ok]]"), Some(Marker::Ok));
        assert_eq!(m.all(), ["[[ED:ok]]", "[[ED:ask]]"]);
    }

    #[test]
    fn tie_keeps_the_first_like_swift() {
        let m = MarkerConfig {
            ask: "[[ED:ok]]".into(),
            ..MarkerConfig::default()
        };
        assert_eq!(m.latest("fim [[ED:ok]]"), Some(Marker::Ok));
    }

    #[test]
    fn wait_is_stripped_from_the_chat() {
        assert_eq!(stripping_markers("Rodando.\n[[ED:wait]]"), "Rodando.");
    }

    #[test]
    fn legacy_instruction_still_teaches_wait() {
        let legacy = MarkerConfig {
            instruction: "{done} fim. {ask} pergunta.".into(),
            ..MarkerConfig::default()
        };
        assert!(legacy.resolved_instruction().contains("[[ED:wait]]"));
        let current = MarkerConfig::default().resolved_instruction();
        assert_eq!(current.split("[[ED:wait]]").count(), 2);
    }

    #[test]
    fn only_the_last_reply_counts() {
        let r = read(&[
            USER.into(),
            assistant(&text("Posso? [[ED:ask]]")),
            USER.into(),
            assistant(&text("Pronto. [[ED:ok]]")),
        ]);
        assert_eq!(r.and_then(|r| r.marker), Some(Marker::Ok));
    }

    #[test]
    fn mention_above_does_not_override_final_marker() {
        let r = read(&[
            USER.into(),
            assistant(&text(r"Se perguntar, uso [[ED:ask]]. Aqui não.\n[[ED:ok]]")),
        ]);
        assert_eq!(r.and_then(|r| r.marker), Some(Marker::Ok));
    }

    #[test]
    fn skips_trailing_tool_use_only_lines() {
        let r = read(&[
            USER.into(),
            assistant(&text("Fim. [[ED:ok]]")),
            assistant(TOOL),
        ]);
        assert_eq!(r.and_then(|r| r.marker), Some(Marker::Ok));
    }

    #[test]
    fn carries_the_line_timestamp() {
        let line = format!(
            r#"{{"type":"assistant","timestamp":"2026-08-25T17:19:23.796Z","message":{{"content":[{}]}}}}"#,
            text("x [[ED:ask]]")
        );
        let r = read(&[USER.into(), line]).unwrap();
        assert_eq!(r.marker, Some(Marker::Ask));
        let secs =
            r.at.unwrap()
                .duration_since(SystemTime::UNIX_EPOCH)
                .unwrap()
                .as_secs_f64();
        assert!((secs - 1_787_678_363.796).abs() < 0.01, "{secs}");
    }

    #[test]
    fn no_marker_is_nil() {
        let r = read(&[USER.into(), assistant(&text("esqueci o protocolo"))]);
        assert_eq!(r.and_then(|r| r.marker), None);
        assert_eq!(last_marker("", &MarkerConfig::default()), None);
    }

    #[test]
    fn reads_only_the_tail_of_the_file() {
        let dir = std::env::temp_dir().join(format!("egeon-marker-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("t.jsonl");
        let filler = "x".repeat(4000);
        let jsonl = [
            USER.to_owned(),
            assistant(&text(&format!("velho [[ED:ask]] {filler}"))),
            USER.to_owned(),
            assistant(&text("novo [[ED:ok]]")),
        ]
        .join("\n");
        std::fs::write(&path, jsonl).unwrap();
        let r = last_marker_at(&path, &MarkerConfig::default(), 200);
        std::fs::remove_dir_all(&dir).ok();
        assert_eq!(r.and_then(|r| r.marker), Some(Marker::Ok));
    }

    #[test]
    fn the_known_events() {
        assert_eq!(HookEvent::parse("start"), Some(HookEvent::Start));
        assert_eq!(HookEvent::parse("stop"), Some(HookEvent::Stop));
        assert_eq!(HookEvent::parse("prompt"), Some(HookEvent::Prompt));
        assert_eq!(HookEvent::parse("ask"), Some(HookEvent::Ask));
    }

    #[test]
    fn unknown_event_does_not_parse() {
        assert_eq!(HookEvent::parse("recap"), None);
        assert_eq!(HookEvent::parse(""), None);
        assert_eq!(HookEvent::parse("Stop"), None);
    }

    #[test]
    fn expected_lists_all_cases() {
        assert_eq!(HookEvent::expected(), "stop|prompt|ask|start|failure");
    }

    #[test]
    fn marker_config_reads_missing_keys_as_default() {
        let m: MarkerConfig = serde_json::from_str(r#"{"done":"FIM","ask":null}"#).unwrap();
        assert_eq!(m.done, "FIM");
        assert_eq!(m.ask, "[[ED:ask]]");
        assert!(m.enabled);
    }

    #[test]
    fn iso8601_variants() {
        let z = parse_iso8601("2026-08-25T17:19:23Z").unwrap();
        let off = parse_iso8601("2026-08-25T14:19:23-03:00").unwrap();
        assert_eq!(z, off);
        assert_eq!(
            parse_iso8601("1970-01-01T00:00:00Z"),
            Some(SystemTime::UNIX_EPOCH)
        );
        assert_eq!(parse_iso8601("ontem"), None);
        assert_eq!(parse_iso8601("2026-08-25 17:19:23Z"), None);
    }
}

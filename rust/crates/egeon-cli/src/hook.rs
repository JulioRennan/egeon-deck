//! `egeon hook <evento>` — porte do `agent-hook.sh` que o Swift instalava.
//!
//! Conta ao app o que acabou de acontecer neste terminal. Três regras, e as
//! três mordem se ignoradas:
//!
//! - o **stdout do `UserPromptSubmit` entra no contexto do prompt**: o gancho
//!   não escreve nada, salvo a decisão do `permission`;
//! - **exit 2 apaga o prompt** e **impede o agente de parar**: aqui nada
//!   devolve erro, o processo sempre sai com 0;
//! - o gancho **roda síncrono e segura a TUI**: cada aviso tem teto de 1s.
//!
//! O `transcript_path` carrega a pasta do usuário, então a query é montada
//! aqui, com cada campo escapado — um home com espaço não vira dois campos.
//!
//! Divergências aceitas do python, só com tipos que o Claude Code não manda:
//! `background_tasks` ou `session_crons` que não seja lista valem lista vazia
//! (o python contava o `len` de dict e texto, e estourava em número); `type`
//! ou `description` que não seja texto não esvazia a query (o python estourava);
//! o `str()` de valor que não é texto sai em JSON (`true`, `["a"]`) e não em
//! Python (`True`, `['a']`); `NaN` é recusado. Payload que não é JSON, ou cujo
//! `session_id` e `transcript_path` são verdadeiros e não texto, esvazia a
//! query, como lá.

use std::io::Write;
use std::path::Path;
use std::time::{Duration, Instant};

use serde_json::{Map, Value};

use crate::encode::{quote, quote_all};
use crate::http::{self, Limit};
use crate::pyjson::Json;

/// Teto de cada aviso ao app.
const POST_LIMIT: Duration = Duration::from_secs(1);

/// Prazo de cada operação da conversa do gancho de permissão.
const PERMISSION_OP_LIMIT: Duration = Duration::from_secs(3);

/// Quanto o gancho de permissão espera a resposta do chat. Esgotado, sai
/// calado e o diálogo do terminal segue sozinho — é o teto de um processo
/// parado, não um prazo para o usuário.
pub const PERMISSION_WAIT: Duration = Duration::from_secs(580);

/// De quanto em quanto o gancho de permissão pergunta se o chat respondeu.
pub const PERMISSION_POLL: Duration = Duration::from_millis(400);

/// O que o gancho pode relatar na rota `/activity` — o contrato (ADR-014,
/// ADR-024, ADR-072). O desconhecido morre na borda, não num `default`
/// silencioso.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActivityEvent {
    /// `Stop`: o turno acabou.
    Stop,
    /// `UserPromptSubmit`: diz qual conversa está aberta.
    Prompt,
    /// `Notification`: pedido de permissão.
    Ask,
    /// `SessionStart`: a TUI subiu e está pronta para receber prompt.
    Start,
    /// `StopFailure`: o turno morreu por erro da API.
    Failure,
}

impl ActivityEvent {
    pub const ALL: [ActivityEvent; 5] = [
        ActivityEvent::Stop,
        ActivityEvent::Prompt,
        ActivityEvent::Ask,
        ActivityEvent::Start,
        ActivityEvent::Failure,
    ];

    pub fn raw(self) -> &'static str {
        match self {
            ActivityEvent::Stop => "stop",
            ActivityEvent::Prompt => "prompt",
            ActivityEvent::Ask => "ask",
            ActivityEvent::Start => "start",
            ActivityEvent::Failure => "failure",
        }
    }

    pub fn parse(raw: &str) -> Option<ActivityEvent> {
        Self::ALL.into_iter().find(|e| e.raw() == raw)
    }

    /// Para a mensagem de erro da rota: o que ela aceita, por extenso.
    pub fn expected() -> String {
        Self::ALL.map(ActivityEvent::raw).join("|")
    }
}

/// O relógio do gancho de permissão, para o teste avançar o tempo.
pub trait Clock {
    fn now(&self) -> Instant;
    fn sleep(&self, duration: Duration);
}

pub struct SystemClock;

impl Clock for SystemClock {
    fn now(&self) -> Instant {
        Instant::now()
    }

    fn sleep(&self, duration: Duration) {
        std::thread::sleep(duration);
    }
}

/// Onde o gancho roda: o socket do app, se estamos dentro do Egeon, e quanto
/// o `permission` espera.
pub struct Setup<'a> {
    pub sock: &'a Path,
    /// `EGEON_TARGET` presente. Fora do Egeon (claude aberto num terminal
    /// comum) não há a quem contar. A variável NÃO diz quem somos: o app
    /// descobre pelo processo que abriu a conexão (ADR-040).
    pub in_egeon: bool,
    pub clock: &'a dyn Clock,
    pub permission_wait: Duration,
}

/// Roda o gancho. Só o `permission` escreve em `out`.
pub fn run(event: &[u8], payload: &[u8], setup: &Setup, out: &mut dyn Write) {
    if !setup.in_egeon {
        return;
    }
    // O shell guardava o payload em `$(cat)`, que tira as quebras de linha do
    // fim; o corpo do `permission` seguia assim.
    let trimmed = trim_newlines(payload);
    let sock = setup.sock;
    match event {
        b"prompt" => {
            let query = prompt_query(trimmed);
            if !query.is_empty() {
                post(sock, &format!("/conversation?{query}"));
            }
        }
        b"stop" => post(
            sock,
            &format!("/activity?event=stop&{}", stop_query(trimmed)),
        ),
        b"start" => {
            // O `/clear` abre outra conversa sem passar pelo gancho de prompt,
            // e até o próximo prompt o app seguiria apontando para a velha.
            // Só esse caso: no arranque, quem decide a conversa ainda é o app.
            let query = start_query(trimmed);
            if !query.is_empty() {
                post(sock, &format!("/conversation?{query}&noturn=1"));
            }
            post(sock, "/activity?event=start");
        }
        b"ask" => post(sock, "/activity?event=ask"),
        b"failure" => {
            let query = failure_query(trimmed);
            let query = if query.is_empty() {
                "error=unknown"
            } else {
                &query
            };
            post(sock, &format!("/activity?event=failure&{query}"));
        }
        b"permission" => {
            if let Some(decision) = permission(trimmed, setup) {
                let _ = writeln!(out, "{decision}");
            }
        }
        _ => {}
    }
}

fn trim_newlines(bytes: &[u8]) -> &[u8] {
    let end = bytes.iter().rposition(|&b| b != b'\n').map_or(0, |i| i + 1);
    &bytes[..end]
}

/// Aviso sem resposta que importe: app fora do ar não pode atrasar nem
/// derrubar o gancho.
fn post(sock: &Path, target: &str) {
    let _ = http::request(
        sock,
        "POST",
        target.as_bytes(),
        None,
        Limit::Total(POST_LIMIT),
    );
}

fn parse_object(payload: &[u8]) -> Option<Map<String, Value>> {
    match serde_json::from_slice(payload) {
        Ok(Value::Object(map)) => Some(map),
        _ => None,
    }
}

/// `d.get(chave) or ""`, antes de escapar. `None` quando o valor é verdadeiro e
/// não é texto: a query inteira fica vazia.
fn text_or_empty(map: &Map<String, Value>, key: &str) -> Option<String> {
    match map.get(key) {
        None | Some(Value::Null | Value::Bool(false)) => Some(String::new()),
        Some(Value::String(s)) => Some(s.clone()),
        Some(Value::Number(n)) if n.as_f64() == Some(0.0) => Some(String::new()),
        Some(Value::Array(a)) if a.is_empty() => Some(String::new()),
        Some(Value::Object(o)) if o.is_empty() => Some(String::new()),
        Some(_) => None,
    }
}

/// O texto de um valor que sobrou depois do `or`.
fn display(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

fn truthy(value: &Value) -> bool {
    match value {
        Value::Null | Value::Bool(false) => false,
        Value::Number(n) => n.as_f64() != Some(0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
        Value::Bool(true) => true,
    }
}

/// `a or b or ""` sobre os campos de um objeto.
fn first_truthy(map: &Map<String, Value>, keys: &[&str]) -> String {
    keys.iter()
        .filter_map(|k| map.get(*k))
        .find(|v| truthy(v))
        .map(display)
        .unwrap_or_default()
}

fn first_chars(text: &str, count: usize) -> String {
    text.chars().take(count).collect()
}

fn last_chars(text: &str, count: usize) -> String {
    let total = text.chars().count();
    text.chars().skip(total.saturating_sub(count)).collect()
}

/// A conversa aberta. Vazia quando o payload não traz sessão — ou não é o
/// JSON esperado: o gancho nunca falha por isso.
fn prompt_query(payload: &[u8]) -> String {
    conversation_query(payload, |_| true).unwrap_or_default()
}

fn start_query(payload: &[u8]) -> String {
    conversation_query(payload, |d| {
        d.get("source").and_then(Value::as_str) == Some("clear")
    })
    .unwrap_or_default()
}

fn conversation_query(
    payload: &[u8],
    when: impl Fn(&Map<String, Value>) -> bool,
) -> Option<String> {
    let d = parse_object(payload)?;
    let id = text_or_empty(&d, "session_id")?;
    if id.is_empty() || !when(&d) {
        return Some(String::new());
    }
    let transcript = text_or_empty(&d, "transcript_path")?;
    Some(format!(
        "id={}&transcript={}",
        quote(&id),
        quote(&transcript)
    ))
}

/// O transcript vai junto: o histórico do chat lê o turno dele. `bg` é o
/// trabalho de fundo que vai acordar o agente (tarefas mais crons) e `last` o
/// fim da última mensagem, de onde sai o marcador sem esperar o transcript ser
/// gravado (ADR-067). Os dois só vão quando o CLI manda. `bgw` são os vigias
/// de página publicada, que o CLI arma sozinho a cada publicação e nunca
/// terminam (ADR-081).
fn stop_query(payload: &[u8]) -> String {
    stop_query_inner(payload).unwrap_or_default()
}

fn stop_query_inner(payload: &[u8]) -> Option<String> {
    let d = parse_object(payload)?;
    let transcript = text_or_empty(&d, "transcript_path")?;
    let mut query = format!("transcript={}", quote(&transcript));

    if d.contains_key("background_tasks") || d.contains_key("session_crons") {
        let list = |key: &str| match d.get(key) {
            Some(Value::Array(items)) => items.clone(),
            _ => Vec::new(),
        };
        let tasks = list("background_tasks");
        let crons = list("session_crons");
        let objects = |items: &[Value]| -> Vec<Map<String, Value>> {
            items
                .iter()
                .filter_map(|v| v.as_object().cloned())
                .collect()
        };
        let task_objects = objects(&tasks);
        let cron_objects = objects(&crons);

        let watchers = task_objects
            .iter()
            .filter(|x| {
                x.get("type").and_then(Value::as_str) == Some("monitor")
                    && x.get("description")
                        .and_then(Value::as_str)
                        .is_some_and(|d| d.contains("(auto-armed on publish)"))
            })
            .count();
        query.push_str(&format!("&bg={}", tasks.len() + crons.len()));
        query.push_str(&format!("&bgw={watchers}"));

        let mut notes: Vec<String> = task_objects
            .iter()
            .map(|x| {
                let kind = first_truthy(x, &["type"]);
                let what = first_truthy(x, &["description", "command"]);
                first_chars(&format!("{kind}: {what}"), 80)
            })
            .collect();
        notes.extend(cron_objects.iter().map(|c| {
            format!(
                "cron: {}",
                first_chars(&first_truthy(c, &["prompt", "cron"]), 60)
            )
        }));
        query.push_str(&format!("&bgd={}", quote_all(&notes.join(" | "))));
    }

    if let Some(Value::String(last)) = d.get("last_assistant_message")
        && !last.is_empty()
    {
        query.push_str(&format!("&last={}", quote_all(&last_chars(last, 400))));
    }
    Some(query)
}

/// O tipo do erro decide se o app tenta de novo; o detalhe é o que a API
/// disse, para o card e a notificação (ADR-072).
fn failure_query(payload: &[u8]) -> String {
    let Some(d) = parse_object(payload) else {
        return String::new();
    };
    let error = match d.get("error").filter(|v| truthy(v)) {
        Some(v) => display(v),
        None => "unknown".to_owned(),
    };
    let mut query = format!("error={}", quote(&error));
    if let Some(Value::String(detail)) = d.get("error_details")
        && !detail.is_empty()
    {
        query.push_str(&format!("&detail={}", quote_all(&first_chars(detail, 300))));
    }
    query
}

/// Abre o pedido no app e espera a resposta do chat. O diálogo do CLI
/// continua na tela enquanto isto roda, e responder lá também vale: aí o app
/// diz `gone` e o gancho sai sem imprimir nada (ADR-068). Só o que sai no
/// stdout é a decisão, e só quando ela veio daqui.
fn permission(payload: &[u8], setup: &Setup) -> Option<String> {
    // O gancho antigo mandava `Content-Length` em toda requisição, GET também.
    let call = |method: &str, target: &str, body: &[u8]| -> Option<Json> {
        let response = http::request(
            setup.sock,
            method,
            target.as_bytes(),
            Some(body),
            Limit::PerOp(PERMISSION_OP_LIMIT),
        )
        .ok()?;
        let raw: &[u8] = if response.body.is_empty() {
            b"{}"
        } else {
            &response.body
        };
        Json::parse(raw).ok()
    };

    let opened = call("POST", "/permission", payload)?;
    let id = opened.get("id").filter(|v| v.is_truthy())?;
    // O id vai como veio, sem escapar, como no gancho antigo; o que não é
    // texto estourava na concatenação e o gancho saía calado.
    let id = id.as_str()?;

    let end = setup.clock.now() + setup.permission_wait;
    while setup.clock.now() < end {
        setup.clock.sleep(PERMISSION_POLL);
        let reply = call("GET", &format!("/permission?id={id}"), &[])?;
        match reply.get("state").and_then(Json::as_str) {
            Some("answered") => {
                let output = reply.get("output").filter(|v| v.is_truthy());
                return Some(
                    output
                        .map_or_else(|| Json::Object(Vec::new()), Clone::clone)
                        .dumps(),
                );
            }
            Some("pending") => {}
            _ => return None,
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    // Porte de HookEventTests: o contrato da rota /activity, o que o gancho
    // pode relatar.
    #[test]
    fn os_eventos_conhecidos() {
        assert_eq!(ActivityEvent::parse("start"), Some(ActivityEvent::Start));
        assert_eq!(ActivityEvent::parse("stop"), Some(ActivityEvent::Stop));
        assert_eq!(ActivityEvent::parse("prompt"), Some(ActivityEvent::Prompt));
        assert_eq!(ActivityEvent::parse("ask"), Some(ActivityEvent::Ask));
    }

    // O desconhecido morre na borda do socket, não num default silencioso.
    #[test]
    fn evento_desconhecido_nao_converte() {
        assert_eq!(ActivityEvent::parse("recap"), None);
        assert_eq!(ActivityEvent::parse(""), None);
        assert_eq!(ActivityEvent::parse("Stop"), None);
    }

    #[test]
    fn expected_lista_todos_os_casos() {
        assert_eq!(ActivityEvent::expected(), "stop|prompt|ask|start|failure");
    }

    #[test]
    fn consultas_por_evento() {
        assert_eq!(
            prompt_query(br#"{"session_id":"s 1","transcript_path":"/Users/a b/t.jsonl"}"#),
            "id=s%201&transcript=/Users/a%20b/t.jsonl"
        );
        assert_eq!(prompt_query(br#"{"transcript_path":"/x"}"#), "");
        assert_eq!(prompt_query(b"isto nao e json"), "");
        assert_eq!(prompt_query(b"[1]"), "");
        // Valor verdadeiro que não é texto esvazia a query.
        assert_eq!(prompt_query(br#"{"session_id":5}"#), "");
    }

    #[test]
    fn start_so_leva_a_conversa_no_clear() {
        let clear = br#"{"session_id":"s","transcript_path":"/t","source":"clear"}"#;
        let startup = br#"{"session_id":"s","transcript_path":"/t","source":"startup"}"#;
        assert_eq!(start_query(clear), "id=s&transcript=/t");
        assert_eq!(start_query(startup), "");
    }

    #[test]
    fn stop_sem_trabalho_de_fundo() {
        assert_eq!(
            stop_query(br#"{"transcript_path":"/t.jsonl","last_assistant_message":"fim / ok"}"#),
            "transcript=/t.jsonl&last=fim%20%2F%20ok"
        );
        assert_eq!(stop_query(b"lixo"), "");
    }

    #[test]
    fn stop_com_trabalho_de_fundo() {
        let payload = r#"{"transcript_path":"/t","background_tasks":[
            {"type":"monitor","description":"vigia (auto-armed on publish)"},
            {"type":"bash","command":"sleep 9"}],
          "session_crons":[{"prompt":"olá"}]}"#
            .as_bytes();
        assert_eq!(
            stop_query(payload),
            "transcript=/t&bg=3&bgw=1&bgd=monitor%3A%20vigia%20%28auto-armed%20on%20publish%29\
             %20%7C%20bash%3A%20sleep%209%20%7C%20cron%3A%20ol%C3%A1"
        );
    }

    #[test]
    fn stop_corta_por_caracteres() {
        let longa = "é".repeat(500);
        let payload = format!(
            r#"{{"transcript_path":"","last_assistant_message":"{longa}",
               "background_tasks":[{{"type":"t","description":"{longa}"}}],
               "session_crons":[{{"cron":"{longa}"}}]}}"#
        );
        let q = stop_query(payload.as_bytes());
        // Fim da mensagem: 400 caracteres; tarefa: 80 contando o prefixo;
        // cron: 60 depois do prefixo, que não conta.
        let last = q.split("&last=").nth(1).unwrap();
        assert_eq!(last.matches("%C3%A9").count(), 400);
        let bgd = q.split("&bgd=").nth(1).unwrap().split('&').next().unwrap();
        let (task, cron) = bgd.split_once("%20%7C%20").unwrap();
        assert_eq!(task.matches("%C3%A9").count(), 80 - "t: ".len());
        assert_eq!(cron.matches("%C3%A9").count(), 60);
    }

    #[test]
    fn failure_leva_erro_e_detalhe() {
        assert_eq!(
            failure_query(r#"{"error":"rate_limit","error_details":"muito/rápido"}"#.as_bytes()),
            "error=rate_limit&detail=muito%2Fr%C3%A1pido"
        );
        assert_eq!(failure_query(br#"{"error":""}"#), "error=unknown");
        assert_eq!(failure_query(b"lixo"), "");
    }
}

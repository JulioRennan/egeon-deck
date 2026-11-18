//! Testes portados de `ClaudeTranscriptTests`, `ChatThreadTests`,
//! `ChatBlocksTests`, `ChatStepTests`, `ChatHistoryTests`, `ChatClearTests`,
//! `ChatLazyLoadTests`, `ChatThreadReuseTests`, `ChatStepToggleTests` (a regra,
//! sem a view), `ChatBlockLayoutTests` (o texto, sem a medida),
//! `ClaudeTranscriptLiveTests`, `ContextTokensTests`, `LastModelSinceTests`,
//! `TranscriptModelTests` e `UsageTests.testTurnCarriesItsUsage` — mais o
//! contrato do diff de blocos que a UI lê.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Write;
use std::path::Path;
use std::sync::LazyLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};

use super::blocks::{self, BlockKind, BuildInput, ChatBlock, ChatGroupLevel, ChatLive, LiveStatus};
use super::layout;
use super::model::{ChatPart, ChatRecord, ChatStep, ChatTurn};
use super::store::{ChatHistory, read as read_history};
use super::thread::{
    ChatMessage, ChatParticipant, Pending, build, build_with_pending, still_pending,
};
use super::time::{format_clock, format_iso, parse_clock, parse_iso, utc};
use super::view::{BlockOp, ChatView, ThreadInput, WINDOW_STEP, apply_ops, diff_blocks};
use crate::features::activity::model::Activity;
use crate::features::agent::claude::transcript::{
    self, Context, LastBlock, LiveTurn, agent_envelope, context_tokens, last_model, send_target,
};
use crate::features::queue::chat::ChatQueue;
use crate::features::usage::{PriceTable, TokenUsage};

/// Brasília, sem verão: -03:00 em qualquer data.
fn brt(_: SystemTime) -> i64 {
    -3 * 3600
}

fn at(secs: f64) -> SystemTime {
    UNIX_EPOCH + Duration::from_secs_f64(secs)
}

static PRICES: LazyLock<PriceTable> = LazyLock::new(PriceTable::from_built_in);

fn ctx() -> Context<'static> {
    Context {
        now: at(1_000.0),
        prices: &PRICES,
    }
}

fn agent(id: &str, activity: Activity) -> ChatParticipant {
    ChatParticipant {
        id: id.to_owned(),
        address: format!("deck/{id}"),
        is_agent: true,
        role: None,
        activity,
    }
}

fn ready(id: &str) -> ChatParticipant {
    agent(id, Activity::Ready)
}

fn temp() -> tempfile::TempDir {
    tempfile::tempdir().expect("pasta temporária")
}

fn write(path: &Path, text: &str) {
    fs::create_dir_all(path.parent().expect("pai")).expect("pasta");
    fs::write(path, text).expect("grava");
}

// ===========================================================================
// ClaudeTranscriptTests
// ===========================================================================

const SAMPLE: &str = r#"{"type":"attachment","timestamp":"2026-08-24T23:13:11.000Z","message":{"content":"x"}}
{"parentUuid":"a1","isSidechain":false,"userType":"external","cwd":"/x","sessionId":"s","version":"2.1","gitBranch":"main","type":"user","timestamp":"2026-08-24T23:13:27.000Z","message":{"role":"user","content":"echo egeon-chat-ok"}}
{"type":"assistant","timestamp":"2026-08-24T23:13:31.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo egeon-chat-ok","description":"Ecoa a marca"}}]}}
{"type":"user","timestamp":"2026-08-24T23:13:32.000Z","message":{"content":[{"type":"tool_result","content":"egeon-chat-ok"}]}}
{"type":"assistant","timestamp":"2026-08-24T23:13:33.000Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b/app/Main.swift"}}]}}
{"type":"assistant","timestamp":"2026-08-24T23:13:35.000Z","message":{"content":[{"type":"text","text":"`egeon-chat-ok`\n\n[[ED:ok]]"}]}}
{"type":"user","timestamp":"2026-08-24T23:14:00.000Z","message":{"content":"<command-name>/clear</command-name>"}}
{"type":"user","timestamp":"2026-08-24T23:15:00.000Z","message":{"content":[{"type":"text","text":"oi"}]}}"#;

#[test]
fn transcript_vira_prompt_passos_e_resposta() {
    let turns = transcript::parse(SAMPLE, &ctx());
    assert_eq!(turns.len(), 2);

    let first = &turns[0];
    assert_eq!(first.prompt, "echo egeon-chat-ok");
    let steps: Vec<String> = first
        .steps
        .iter()
        .map(|s| format!("{} {}", s.glyph, s.text))
        .collect();
    assert_eq!(steps, ["$ Ecoa a marca", "± app/Main.swift"]);
    assert_eq!(first.steps[0].detail.as_deref(), Some("echo egeon-chat-ok"));
    // Marcador do protocolo é do app, não da bolha.
    assert_eq!(first.reply_text, "`egeon-chat-ok`");
    assert!(first.reply_at.is_some());
    assert!(first.has_reply());

    // Comando de barra não é prompt; o "oi" em bloco de texto é.
    assert_eq!(turns[1].prompt, "oi");
    assert!(!turns[1].has_reply());
}

/// A cadeia guarda a ORDEM: prosa, passos, prosa — é ela que a bolha desenha, e
/// não "todos os passos, depois todo o texto" (ADR-039).
#[test]
fn cadeia_guarda_prosa_e_passos_em_ordem() {
    let jsonl = r#"{"type":"user","uuid":"u1","timestamp":"2026-08-24T23:13:27.000Z","message":{"content":"faz"}}
{"type":"assistant","timestamp":"2026-08-24T23:13:28.000Z","message":{"content":[{"type":"text","text":"Vou olhar."}]}}
{"type":"assistant","timestamp":"2026-08-24T23:13:29.000Z","message":{"content":[{"type":"thinking","thinking":"hmm"}]}}
{"type":"assistant","timestamp":"2026-08-24T23:13:30.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls","description":"Lista"}}]}}
{"type":"assistant","timestamp":"2026-08-24T23:13:31.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b.swift"}}]}}
{"type":"assistant","timestamp":"2026-08-24T23:13:32.000Z","message":{"content":[{"type":"text","text":"Achei.\n\n[[ED:ok]]"}]}}"#;
    let (turns, last) = transcript::parse_detailed(jsonl, &ctx());
    let turn = &turns[0];
    let mut ls = ChatStep::new("$", "Lista");
    ls.detail = Some("ls".into());
    assert_eq!(
        turn.parts,
        [
            ChatPart::Text("Vou olhar.".into()),
            ChatPart::Step(ls),
            ChatPart::Step(ChatStep::new("→", "read a/b.swift")),
            ChatPart::Text("Achei.".into()),
        ]
    );
    assert_eq!(turn.chain(), turn.parts);
    assert_eq!(turn.last_text().as_deref(), Some("Achei."));
    // As somas continuam valendo para citação, troca e histórico antigo.
    assert_eq!(turn.reply_text, "Vou olhar.\n\nAchei.");
    assert_eq!(turn.steps.len(), 2);
    assert_eq!(last, Some(LastBlock::Text));
}

/// Registro gravado antes da cadeia existir: a bolha reconstrói na forma antiga —
/// passos, depois o texto — e o decode não derruba a linha.
#[test]
fn turno_sem_parts_decodifica_e_reconstroi_a_cadeia() {
    let json = r#"{"id":"t1","prompt":"oi","promptAt":"2026-08-24T23:13:27.000Z","steps":[{"glyph":"$","text":"ls"}],"replyText":"feito","exchanges":[]}"#;
    let turn: ChatTurn = serde_json::from_str(json).expect("lê");
    assert!(turn.parts.is_empty());
    assert_eq!(
        turn.chain(),
        [
            ChatPart::Step(ChatStep::new("$", "ls")),
            ChatPart::Text("feito".into())
        ]
    );
    let back: ChatTurn =
        serde_json::from_str(&serde_json::to_string(&turn).expect("grava")).expect("relê");
    assert_eq!(back, turn);
}

#[test]
fn elos_da_cadeia_voltam_do_disco_com_o_destino_do_envio() {
    let mut turn = ChatTurn::new("t1", "oi", at(1_000.0), None);
    let mut send = ChatStep::new("⇄", "egeon send deck/b");
    send.send_to = Some("deck/b".into());
    turn.parts = vec![ChatPart::Text("vou mandar".into()), ChatPart::Step(send)];
    let text = serde_json::to_string(&turn).expect("grava");
    assert!(text.contains("\"kind\":\"step\""));
    let back: ChatTurn = serde_json::from_str(&text).expect("relê");
    assert_eq!(back.parts, turn.parts);
}

/// O leitor ao vivo: a cadeia até onde o CLI gravou, e o que ele fazia no fim —
/// ferramenta em curso ou raciocínio. Turno mais velho que o prompt deste é o
/// turno passado: `None`, e a bolha fica em "trabalhando…".
#[test]
fn turno_ao_vivo_diz_o_que_acontece_agora() {
    let dir = temp();
    let url = dir.path().join("live.jsonl");
    let jsonl = r#"{"type":"user","uuid":"u1","timestamp":"2026-08-25T17:00:00.000Z","message":{"content":"faz"}}
{"type":"assistant","timestamp":"2026-08-25T17:00:01.000Z","message":{"content":[{"type":"text","text":"Vou olhar."}]}}
{"type":"assistant","timestamp":"2026-08-25T17:00:02.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test","description":"Roda os testes"}}]}}"#;
    write(&url, jsonl);
    let iso = |s: &str| parse_iso(s);
    let live = transcript::live_turn(&url, iso("2026-08-25T17:00:03Z"), 0, 4 << 20, &ctx())
        .expect("ao vivo");
    assert_eq!(live.turn.id, "u1");
    assert_eq!(live.last, Some(LastBlock::Tool));
    assert_eq!(live.turn.parts.len(), 2);

    // Prompt novo veio depois do que o arquivo tem: é o turno passado.
    assert!(transcript::live_turn(&url, iso("2026-08-25T17:05:00Z"), 0, 4 << 20, &ctx()).is_none());

    write(
        &url,
        &format!(
            "{jsonl}\n{}",
            r#"{"type":"assistant","timestamp":"2026-08-25T17:00:03.000Z","message":{"content":[{"type":"thinking","thinking":"…"}]}}"#
        ),
    );
    let thinking = transcript::live_turn(&url, None, 0, 4 << 20, &ctx()).map(|l| l.last);
    assert_eq!(thinking, Some(Some(LastBlock::Thinking)));
}

/// Mensagem de outro agente chega envelopada pelo Dispatcher: sai o remetente e
/// só o texto, sem o cabeçalho.
#[test]
fn envelope_de_agente_e_desembrulhado() {
    let wrapped = "[ED] mensagem de deck/front\n\no /nodes devolve o estado calculado?";
    let envelope = agent_envelope(wrapped).expect("envelope");
    assert_eq!(envelope.0, "deck/front");
    assert_eq!(envelope.1, "o /nodes devolve o estado calculado?");
    assert_eq!(agent_envelope("oi"), None);
}

/// `[egeon]` foi a marca até a ADR-055, e o histórico do chat e os transcripts do
/// CLI já gravados estão cheios dela: quem parar de reconhecê-la faz a bolha
/// antiga perder o remetente.
#[test]
fn marca_antiga_ainda_e_desembrulhada() {
    let envelope = agent_envelope("[egeon] mensagem de deck/front\n\ne a mensagem de ontem?")
        .expect("envelope");
    assert_eq!(envelope.0, "deck/front");
    assert_eq!(envelope.1, "e a mensagem de ontem?");
}

#[test]
fn passo_de_envio_leva_o_destino() {
    assert_eq!(
        send_target("egeon send deck/back <<'MB'\nveja isso\nMB").as_deref(),
        Some("deck/back")
    );
    assert_eq!(send_target("egeon peers"), None);
}

#[test]
fn assistente_antes_de_qualquer_prompt_e_ignorado() {
    let orphan = r#"{"type":"assistant","timestamp":"2026-08-24T23:13:35.000Z","message":{"content":[{"type":"text","text":"solto"}]}}"#;
    assert!(transcript::parse(orphan, &ctx()).is_empty());
}

#[test]
fn alvo_do_envio_ignora_ruido_de_heredoc() {
    assert_eq!(
        send_target("egeon send deck/b <<'MB'\noi\nMB").as_deref(),
        Some("deck/b")
    );
    assert_eq!(
        send_target("egeon   send\tback <<'MB'\nMB").as_deref(),
        Some("back")
    );
    assert_eq!(send_target("egeon send <<'MB'\nsend\nMB"), None);
    assert_eq!(send_target("egeon send\ndeck/b"), None);
}

// ===========================================================================
// ClaudeTranscriptLiveTests
// ===========================================================================

const U1: &str = r#"{"type":"user","uuid":"u1","timestamp":"2026-08-25T17:00:00.000Z","message":{"content":"olá, ação"}}"#;
const A1: &str = r#"{"type":"assistant","timestamp":"2026-08-25T17:00:01.000Z","message":{"content":[{"type":"text","text":"Vou olhar."}]}}"#;
const U2: &str = r#"{"type":"user","uuid":"u2","timestamp":"2026-08-25T17:01:00.000Z","message":{"content":"faz"}}"#;
const A2: &str = r#"{"type":"assistant","timestamp":"2026-08-25T17:01:01.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls","description":"Lista"}}]}}"#;
const A3: &str = r#"{"type":"assistant","timestamp":"2026-08-25T17:01:02.000Z","message":{"content":[{"type":"thinking","thinking":"…"}]}}"#;

#[test]
fn varredura_guarda_o_byte_de_cada_prompt() {
    let jsonl = format!("{}\n", [U1, A1, U2, A2].join("\n"));
    let scanned = transcript::scan(jsonl.as_bytes(), &ctx());
    let ids: Vec<&str> = scanned.turns.iter().map(|t| t.id.as_str()).collect();
    assert_eq!(ids, ["u1", "u2"]);
    // "olá, ação" tem acentos: o offset conta bytes, não caracteres.
    let second_line = format!("{U1}\n{A1}\n").len();
    assert_eq!(scanned.prompt_offsets, [0, second_line]);
    assert_eq!(scanned.last, Some(LastBlock::Tool));
}

#[test]
fn leitura_ao_vivo_parte_do_offset_do_prompt() {
    let dir = temp();
    let url = dir.path().join("live.jsonl");
    write(&url, &format!("{}\n", [U1, A1, U2, A2].join("\n")));

    let first = transcript::live_turn(&url, None, 0, 4 << 20, &ctx()).expect("ao vivo");
    assert_eq!(first.turn.id, "u2");
    assert_eq!(first.prompt_offset, format!("{U1}\n{A1}\n").len() as u64);

    // Cauda minúscula: a partir do offset o prompt entra; da cauda, não.
    let mut file = fs::OpenOptions::new()
        .append(true)
        .open(&url)
        .expect("abre");
    file.write_all(format!("{A3}\n").as_bytes()).expect("anexa");
    drop(file);
    let next = transcript::live_turn(&url, None, first.prompt_offset, 64, &ctx())
        .expect("a partir do offset");
    assert_eq!(next.turn.id, "u2");
    assert_eq!(next.turn.parts.len(), 1);
    assert_eq!(next.last, Some(LastBlock::Thinking));
    assert_eq!(
        next.prompt_offset, first.prompt_offset,
        "o turno é o mesmo, o offset também"
    );
    assert!(
        transcript::live_turn(&url, None, 0, 64, &ctx()).is_none(),
        "sem o offset, 64 bytes de cauda não trazem o prompt"
    );
}

#[test]
fn offset_velho_volta_para_a_cauda() {
    let dir = temp();
    let url = dir.path().join("live.jsonl");
    write(&url, &format!("{}\n", [U1, A1].join("\n")));
    // Offset de uma conversa maior que já não existe: volta à cauda.
    let live = transcript::live_turn(&url, None, 999_999, 4 << 20, &ctx()).expect("ao vivo");
    assert_eq!(live.turn.id, "u1");
    assert_eq!(live.prompt_offset, 0);
}

// ===========================================================================
// TranscriptLastTurnTests, TranscriptModelTests, LastModelSinceTests, ContextTokensTests
// ===========================================================================

fn user_line(text: &str, id: &str, stamp: &str) -> String {
    format!(
        r#"{{"type":"user","uuid":"{id}","timestamp":"{stamp}","message":{{"content":"{text}"}}}}"#
    )
}

fn assistant_line(text: &str, stamp: &str) -> String {
    format!(
        r#"{{"type":"assistant","timestamp":"{stamp}","message":{{"content":[{{"type":"text","text":"{text}"}}]}}}}"#
    )
}

#[test]
fn ultimo_turno_leva_prompt_e_resposta() {
    let dir = temp();
    let url = dir.path().join("t.jsonl");
    write(
        &url,
        &[
            user_line("um", "u1", "2026-08-25T17:00:00Z"),
            assistant_line("r1 [[ED:ok]]", "2026-08-25T17:00:05Z"),
            user_line("dois", "u2", "2026-08-25T17:01:00Z"),
            assistant_line("r2 [[ED:ask]]", "2026-08-25T17:01:05Z"),
        ]
        .join("\n"),
    );
    let turn =
        transcript::last_turn(&url, None, transcript::LAST_TURN_TAIL_BYTES, &ctx()).expect("turno");
    assert_eq!(turn.id, "u2");
    assert_eq!(turn.prompt, "dois");
    assert_eq!(turn.reply_text, "r2");
}

/// A cauda cortou a linha do prompt atual: o parse da cauda devolve o turno
/// ANTERIOR inteiro, e só o instante do prompt desmascara isso.
#[test]
fn cauda_que_perde_o_prompt_volta_ao_arquivo_inteiro() {
    let filler = "x".repeat(300);
    let dir = temp();
    let url = dir.path().join("t.jsonl");
    write(
        &url,
        &[
            user_line("um", "u1", "2026-08-25T17:00:00Z"),
            assistant_line("r1", "2026-08-25T17:00:05Z"),
            user_line(&format!("dois {filler}"), "u2", "2026-08-25T17:01:00Z"),
            assistant_line("r2", "2026-08-25T17:01:05Z"),
        ]
        .join("\n"),
    );
    let started = parse_iso("2026-08-25T17:00:50Z");
    assert_eq!(
        transcript::last_turn(&url, started, 200, &ctx()).map(|t| t.id),
        Some("u2".to_owned())
    );
    assert_eq!(
        transcript::last_turn(&url, None, 200, &ctx()).map(|t| t.id),
        Some("u2".to_owned())
    );
}

#[test]
fn ultimo_turno_vazio_ou_ausente() {
    let dir = temp();
    let url = dir.path().join("t.jsonl");
    write(&url, "");
    assert!(transcript::last_turn(&url, None, 1 << 20, &ctx()).is_none());
    assert!(transcript::last_turn(&dir.path().join("nada.jsonl"), None, 1 << 20, &ctx()).is_none());
}

fn model_line(model: &str) -> String {
    format!(
        r#"{{"type":"assistant","message":{{"model":"{model}","content":[{{"type":"text","text":"x"}}]}}}}"#
    )
}

#[test]
fn o_ultimo_modelo_vence() {
    let jsonl = [model_line("claude-sonnet-5"), model_line("claude-fable-5")].join("\n");
    assert_eq!(last_model(&jsonl, None).as_deref(), Some("claude-fable-5"));
}

/// A TUI grava respostas fabricadas com model "<synthetic>": não é modelo.
#[test]
fn sintetico_e_pulado() {
    let jsonl = [model_line("claude-fable-5"), model_line("<synthetic>")].join("\n");
    assert_eq!(last_model(&jsonl, None).as_deref(), Some("claude-fable-5"));
    assert_eq!(last_model(&model_line("<synthetic>"), None), None);
    assert_eq!(last_model("", None), None);
}

#[test]
fn modelo_descarta_resposta_anterior_ao_arranque() {
    let jsonl = r#"{"type":"assistant","timestamp":"2026-09-27T01:06:45.373Z","message":{"model":"claude-haiku-4-5"}}"#;
    let late = parse_iso("2026-09-29T12:00:00Z");
    assert_eq!(last_model(jsonl, late), None);
}

#[test]
fn modelo_mantem_resposta_posterior_ao_arranque() {
    let jsonl = r#"{"type":"assistant","timestamp":"2026-09-27T01:06:45.373Z","message":{"model":"claude-haiku-4-5"}}"#;
    let early = parse_iso("2026-09-27T01:00:00Z");
    assert_eq!(
        last_model(jsonl, early).as_deref(),
        Some("claude-haiku-4-5")
    );
    assert_eq!(
        last_model(jsonl, None).as_deref(),
        Some("claude-haiku-4-5"),
        "sem limite, como antes"
    );
}

/// A cor do agente é identidade: tem de ser a MESMA em todo arranque. Os valores
/// fixos são o FNV-1a de 64 bits do id, módulo 6 — o que o Swift calcula.
#[test]
fn cor_do_agente_e_deterministica() {
    use super::thread::{AGENT_COLORS, agent_color, agent_color_index};
    assert_eq!(agent_color("revisor"), agent_color("revisor"));
    assert!(AGENT_COLORS.contains(&agent_color("x")));
    assert_eq!(agent_color_index("revisor"), 3);
    assert_eq!(agent_color_index("x"), 5);
    assert_eq!(agent_color_index("front"), 4);
    assert_eq!(agent_color_index("back"), 2);
    assert_eq!(
        agent_color_index(""),
        (0xcbf2_9ce4_8422_2325_u64 % 6) as usize
    );
}

fn answer(input: u64, read: u64, write: u64, id: &str, sidechain: bool, model: &str) -> String {
    format!(
        r#"{{"type":"assistant","isSidechain":{sidechain},"message":{{"id":"{id}","model":"{model}","usage":{{"input_tokens":{input},"output_tokens":5,"cache_read_input_tokens":{read},"cache_creation_input_tokens":{write}}}}}}}"#
    )
}

#[test]
fn contexto_conta_o_prompt_da_ultima_resposta_sem_a_saida() {
    let text = [
        answer(1, 0, 0, "m", false, "claude-x"),
        answer(10, 100, 1000, "m", false, "claude-x"),
    ]
    .join("\n");
    assert_eq!(context_tokens(&text), Some(1110));
}

#[test]
fn contexto_pula_subagente_e_resposta_fabricada() {
    let text = [
        answer(10, 0, 0, "m", false, "claude-x"),
        answer(99, 0, 0, "m", true, "claude-x"),
        answer(0, 0, 0, "m", false, "<synthetic>"),
    ]
    .join("\n");
    assert_eq!(context_tokens(&text), Some(10));
}

#[test]
fn compactar_esconde_o_numero_velho_ate_a_proxima_resposta() {
    let boundary = r#"{"type":"system","subtype":"compact_boundary"}"#;
    assert_eq!(
        context_tokens(&format!(
            "{}\n{boundary}",
            answer(500, 0, 0, "m", false, "claude-x")
        )),
        None
    );
    let text = [
        answer(500, 0, 0, "m", false, "claude-x"),
        boundary.to_owned(),
        answer(20, 0, 0, "m", false, "claude-x"),
    ]
    .join("\n");
    assert_eq!(context_tokens(&text), Some(20));
}

/// Uma conversa que só cita o nome do marcador não foi compactada.
#[test]
fn citar_o_marcador_nao_e_compactar() {
    let quote =
        r#"{"type":"user","message":{"content":"o compact_boundary é \"compact_boundary\""}}"#;
    assert_eq!(
        context_tokens(&format!(
            "{}\n{quote}",
            answer(500, 0, 0, "m", false, "claude-x")
        )),
        Some(500)
    );
}

#[test]
fn contexto_sem_resposta_ainda() {
    assert_eq!(
        context_tokens(r#"{"type":"user","message":{"content":"oi"}}"#),
        None
    );
}

// ===========================================================================
// UsageTests.testTurnCarriesItsUsage
// ===========================================================================

fn usage_line(id: &str, output: u64, write1h: u64, read: u64, text: &str) -> String {
    format!(
        r#"{{"type":"assistant","message":{{"id":"{id}","model":"claude-opus-5-5","content":[{{"type":"text","text":"{text}"}}],"usage":{{"input_tokens":10,"output_tokens":{output},"cache_creation_input_tokens":{write1h},"cache_read_input_tokens":{read},"cache_creation":{{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":{write1h}}},"speed":"standard"}}}}}}"#
    )
}

#[test]
fn o_turno_carrega_o_seu_consumo() {
    let jsonl = [
        r#"{"type":"user","uuid":"u1","timestamp":"2026-10-22T10:00:00Z","message":{"content":"faz"}}"#.to_owned(),
        usage_line("m1", 100, 50, 0, "feito"),
        usage_line("m1", 100, 50, 0, "feito"),
        usage_line("m2", 100, 0, 70, "mais"),
        r#"{"type":"user","uuid":"u2","timestamp":"2026-10-22T10:05:00Z","message":{"content":"de novo"}}"#.to_owned(),
        usage_line("m3", 3, 0, 0, "ok"),
    ]
    .join("\n");
    let turns = transcript::parse(&jsonl, &ctx());
    assert_eq!(turns.len(), 2);
    assert_eq!(
        crate::features::usage::total_usage(&turns[0].usage),
        TokenUsage {
            input: 20,
            output: 200,
            cache_write1h: 50,
            cache_read: 70,
            ..TokenUsage::default()
        }
    );
    assert_eq!(
        crate::features::usage::total_usage(&turns[1].usage).output,
        3
    );

    // Vai e volta do histórico do chat com o uso junto.
    let text = serde_json::to_string(&turns[0]).expect("grava");
    let back: ChatTurn = serde_json::from_str(&text).expect("relê");
    assert_eq!(back.usage, turns[0].usage);
}

// ===========================================================================
// ChatStepTests
// ===========================================================================

fn line(kind: &str, stamp: &str, message: &str, extra: &str) -> String {
    format!(
        r#"{{"type":"{kind}","timestamp":"{stamp}","uuid":"{stamp}","message":{message}{extra}}}"#
    )
}

#[test]
fn resultado_do_bash_preenche_comando_saida_e_erro() {
    let jsonl = [
        line("user", "2026-08-25T17:00:00Z", r#"{"content":"faz"}"#, ""),
        line("assistant", "2026-08-25T17:00:01Z", r#"{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test","description":"Roda os testes"}}]}"#, ""),
        line("user", "2026-08-25T17:00:02Z", r#"{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok\n131 tests"}]}"#, r#","toolUseResult":{"stdout":"ok\n131 tests","stderr":"","interrupted":false}"#),
        line("assistant", "2026-08-25T17:00:03Z", r#"{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"cd nope"}}]}"#, ""),
        line("user", "2026-08-25T17:00:04Z", r#"{"content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"Exit code 1\nno such file"}]}"#, r#","toolUseResult":"Error: Exit code 1\nno such file""#),
    ]
    .join("\n");
    let turns = transcript::parse(&jsonl, &ctx());
    let turn = turns.first().expect("turno");
    assert_eq!(turn.steps.len(), 2);
    let first = &turn.steps[0];
    assert_eq!(first.text, "Roda os testes");
    assert_eq!(first.detail.as_deref(), Some("swift test"));
    assert_eq!(first.output.as_deref(), Some("ok\n131 tests"));
    assert!(!first.is_error);
    let second = &turn.steps[1];
    // Sem description, o comando É a linha: não repete embaixo.
    assert_eq!(second.text, "cd nope");
    assert_eq!(second.detail, None);
    assert!(second.is_error);
    assert_eq!(second.output.as_deref(), Some("Exit code 1\nno such file"));
    // A cadeia carrega o mesmo passo, com o resultado.
    assert_eq!(turn.parts[1], ChatPart::Step(second.clone()));
}

#[test]
fn edicao_mostra_o_diff_no_uso_e_o_patch_quando_o_resultado_chega() {
    let usage = line(
        "assistant",
        "2026-08-25T17:00:01Z",
        r#"{"content":[{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"/x/app/A.swift","old_string":"let a = 1","new_string":"let a = 2\nlet b = 3"}}]}"#,
        "",
    );
    let prompt = line("user", "2026-08-25T17:00:00Z", r#"{"content":"faz"}"#, "");
    let before = transcript::parse(&[prompt.clone(), usage.clone()].join("\n"), &ctx());
    assert_eq!(before[0].steps[0].glyph, "±");
    assert_eq!(before[0].steps[0].text, "app/A.swift");
    assert_eq!(
        before[0].steps[0].diff,
        Some(vec![
            "-let a = 1".into(),
            "+let a = 2".into(),
            "+let b = 3".into()
        ])
    );

    let result = line(
        "user",
        "2026-08-25T17:00:02Z",
        r#"{"content":[{"type":"tool_result","tool_use_id":"e1","content":"The file has been updated"}]}"#,
        r#","toolUseResult":{"filePath":"/x/app/A.swift","structuredPatch":[{"oldStart":1,"oldLines":2,"newStart":1,"newLines":3,"lines":[" import Foundation","-let a = 1","+let a = 2","+let b = 3"]}]}"#,
    );
    let after = transcript::parse(&[prompt, usage, result].join("\n"), &ctx());
    let step = &after[0].steps[0];
    // Com o cabeçalho do trecho: é dele que a vista lado a lado numera.
    assert_eq!(
        step.diff,
        Some(vec![
            "@@ -1,2 +1,3 @@".into(),
            " import Foundation".into(),
            "-let a = 1".into(),
            "+let a = 2".into(),
            "+let b = 3".into()
        ])
    );
    // Edição não mostra "The file has been updated": o diff já diz.
    assert_eq!(step.output, None);
    assert_eq!(step.diff_counts(), Some((2, 1)));
    // Recolhido, a linha do passo ainda diz o tamanho da mudança.
    assert!(layout::step(step, false).ends_with("+2 −1"));
    assert!(!layout::step(step, false).contains("import"));
}

#[test]
fn write_e_tudo_adicionado_e_read_conta_linhas() {
    let jsonl = [
        line("user", "2026-08-25T17:00:00Z", r#"{"content":"faz"}"#, ""),
        line("assistant", "2026-08-25T17:00:01Z", r#"{"content":[{"type":"tool_use","id":"w1","name":"Write","input":{"file_path":"/x/N.swift","content":"a\nb"}}]}"#, ""),
        line("assistant", "2026-08-25T17:00:02Z", r#"{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"/x/N.swift"}}]}"#, ""),
        line("user", "2026-08-25T17:00:03Z", r#"{"content":[{"type":"tool_result","tool_use_id":"r1","content":"1\ta\n2\tb"}]}"#, r#","toolUseResult":{"type":"text","file":{"filePath":"/x/N.swift","numLines":2,"totalLines":2}}"#),
        line("assistant", "2026-08-25T17:00:04Z", r#"{"content":[{"type":"tool_use","id":"g1","name":"Grep","input":{"pattern":"foo","path":"app/"}}]}"#, ""),
    ]
    .join("\n");
    let turns = transcript::parse(&jsonl, &ctx());
    let turn = &turns[0];
    assert_eq!(turn.steps[0].diff, Some(vec!["+a".into(), "+b".into()]));
    assert_eq!(turn.steps[1].output.as_deref(), Some("2 linhas"));
    assert_eq!(turn.steps[2].text, "Grep");
    assert_eq!(
        turn.steps[2].detail.as_deref(),
        Some("path: app/\npattern: foo")
    );
}

/// Leitura mostra o que foi lido: o conteúdo vira a saída do passo (com teto), e
/// a linguagem sai da extensão do arquivo citado no título — sem `content`,
/// continua a conta de linhas.
#[test]
fn leitura_mostra_o_conteudo_do_arquivo() {
    let code = "import Foundation\nlet answer = 42  // nota";
    let jsonl = [
        line("user", "2026-08-25T17:00:00Z", r#"{"content":"faz"}"#, ""),
        line("assistant", "2026-08-25T17:00:01Z", r#"{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"/x/app/N.swift"}}]}"#, ""),
        line("user", "2026-08-25T17:00:02Z", r#"{"content":[{"type":"tool_result","tool_use_id":"r1","content":"lido"}]}"#, r#","toolUseResult":{"type":"text","file":{"filePath":"/x/app/N.swift","content":"import Foundation\nlet answer = 42  // nota","numLines":2,"totalLines":2}}"#),
    ]
    .join("\n");
    let turns = transcript::parse(&jsonl, &ctx());
    let step = &turns[0].steps[0];
    assert_eq!(step.text, "read app/N.swift");
    assert_eq!(step.output.as_deref(), Some(code));
    assert!(step.is_expandable(), "há o que abrir");

    // Recolhido: só o título e a conta. Aberto: o texto.
    let closed = layout::step(step, false);
    assert!(closed.ends_with("⎿ 2 linhas"), "{closed}");
    assert!(!closed.contains("import"));
    let open = layout::step(step, true);
    assert!(open.contains("⎿ import Foundation") && open.contains("   let answer = 42"));
}

#[test]
fn saida_tem_teto_de_linhas_e_de_bytes() {
    let many = (1..=100)
        .map(|n| n.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    let capped = ChatStep::capped(&many);
    assert_eq!(capped.split('\n').count(), ChatStep::MAX_OUTPUT_LINES + 1);
    assert!(capped.ends_with("… +60 linhas"));

    let wide = "x".repeat(5000);
    let cut = ChatStep::capped(&wide);
    assert!(cut.len() < 2200);
    assert!(cut.ends_with("… 5000 bytes ao todo"));
    assert_eq!(ChatStep::capped("  \n"), "");
}

#[test]
fn diff_tem_teto() {
    let big = (1..=300)
        .map(|n| format!("l{n}"))
        .collect::<Vec<_>>()
        .join("\n");
    let diff = transcript::diff("", &big).expect("diff");
    assert_eq!(diff.len(), ChatStep::MAX_DIFF_LINES + 1);
    assert_eq!(diff.last().map(String::as_str), Some("… +100 linhas"));
    assert_eq!(transcript::diff("", ""), None);
}

/// O passo inteiro vai para o histórico aninhado; a forma chata antiga
/// (glyph/text soltos) ainda decodifica.
#[test]
fn passo_de_cadeia_vai_e_volta_e_a_forma_antiga_decodifica() {
    let mut step = ChatStep::new("$", "Roda");
    step.tool_id = Some("t1".into());
    step.detail = Some("swift test".into());
    step.output = Some("ok".into());
    let part = ChatPart::Step(step);
    let back: ChatPart =
        serde_json::from_str(&serde_json::to_string(&part).expect("grava")).expect("relê");
    assert_eq!(back, part);

    let flat = r#"{"kind":"step","glyph":"±","text":"a.swift"}"#;
    assert_eq!(
        serde_json::from_str::<ChatPart>(flat).expect("lê"),
        ChatPart::Step(ChatStep::new("±", "a.swift"))
    );
}

/// Linha antiga com o elo extinto ("exchange") e a chave `exchanges`: o turno
/// decodifica sem tropeçar, e o elo some.
#[test]
fn elo_extinto_decodifica_para_nada() {
    let json = r#"{"id":"t1","prompt":"oi","promptAt":"2026-08-24T23:13:27.000Z","steps":[],"replyText":"feito","exchanges":[{"fromId":"a","toId":"b","text":"x","at":"2026-08-24T23:13:27.000Z","steps":0,"note":""}],"parts":[{"kind":"text","text":"feito"},{"kind":"exchange","exchange":{"fromId":"a","toId":"b","text":"x","at":"2026-08-24T23:13:27.000Z","steps":0,"note":""}}]}"#;
    let turn: ChatTurn = serde_json::from_str(json).expect("lê");
    assert_eq!(turn.parts, [ChatPart::Text("feito".into())]);
    assert!(turn.has_reply());
}

// ===========================================================================
// ChatThreadTests
// ===========================================================================

#[test]
fn thread_intercala_por_tempo() {
    let base = 1_000.0;
    let (front, back) = (ready("front"), ready("back"));
    let mut front_turn = ChatTurn::new("f1", "faz a coluna", at(base), None);
    front_turn.reply_text = "feita".into();
    front_turn.reply_at = Some(at(base + 30.0));
    let back_turn = ChatTurn::new("b1", "expõe /nodes", at(base + 10.0), None);
    let shell = ChatParticipant {
        id: "zsh".into(),
        address: "deck/zsh".into(),
        is_agent: false,
        role: None,
        activity: Activity::Ready,
    };
    // Shell não tem transcript: mesmo que a fechadura devolva algo, fica fora.
    let thread = build(&[front.clone(), back.clone(), shell], |p| {
        match p.id.as_str() {
            "front" => vec![front_turn.clone()],
            "back" => vec![back_turn.clone()],
            _ => vec![ChatTurn::new("z", "nunca", at(base), None)],
        }
    });

    assert_eq!(thread.len(), 3);
    assert_eq!(
        thread[0],
        ChatMessage::prompt(&front, "f1", "faz a coluna", at(base))
    );
    // Prompt ao back logo depois de prompt ao front: o back ainda não falou, não
    // há o que citar.
    assert_eq!(
        thread[1],
        ChatMessage::prompt(&back, "b1", "expõe /nodes", at(base + 10.0))
    );
    // A resposta do front NÃO vem logo depois do prompt dela (o prompt ao back
    // entrou no meio): cita o prompt, estilo WhatsApp.
    let ChatMessage::Reply { from, turn, quote } = &thread[2] else {
        panic!("esperava resposta do front");
    };
    assert_eq!(from, &front);
    assert_eq!(**turn, front_turn);
    let quote = quote.as_ref().expect("citação");
    assert_eq!(quote.author_id, None);
    assert_eq!(quote.text, "faz a coluna");
    assert_eq!(quote.target_key, thread[0].key());
}

/// Consecutivo é limpo: prompt e resposta um atrás do outro, sem citação.
#[test]
fn resposta_consecutiva_nao_cita() {
    let front = ready("front");
    let mut turn = ChatTurn::new("t1", "oi", at(1_000.0), None);
    turn.reply_text = "oi".into();
    turn.reply_at = Some(at(1_005.0));
    let thread = build(&[front], |_| vec![turn.clone()]);
    assert!(thread[1].quote().is_none());
}

/// O prompt do usuário intercalado cita a última fala do agente a quem fala.
#[test]
fn prompt_intercalado_cita_a_ultima_resposta_do_agente() {
    let (front, back) = (ready("front"), ready("back"));
    let base = 1_000.0;
    let mut back_turn = ChatTurn::new("b1", "expõe", at(base), None);
    back_turn.reply_text = "no ar".into();
    back_turn.reply_at = Some(at(base + 5.0));
    let front_turn = ChatTurn::new("f1", "faz", at(base + 10.0), None);
    let later = ChatTurn::new("b2", "adiciona lastActivity", at(base + 20.0), None);

    let thread = build(&[front, back], |p| {
        if p.id == "back" {
            vec![back_turn.clone(), later.clone()]
        } else {
            vec![front_turn.clone()]
        }
    });
    // back: expõe, no ar · front: faz · back: adiciona (intercalado → cita "no ar")
    assert_eq!(thread.len(), 4);
    let quote = thread[3].quote().expect("citação");
    assert_eq!(quote.author_id.as_deref(), Some("back"));
    assert_eq!(quote.text, "no ar");
    assert_eq!(quote.target_key, thread[1].key());
    assert!(
        thread[2].quote().is_none(),
        "front ainda não falou: nada a citar"
    );
}

fn pending(text: &str, target: &str, sent: SystemTime, known: &[&str]) -> Pending {
    Pending {
        text: text.to_owned(),
        target: target.to_owned(),
        sent_at: sent,
        known_turn_ids: known.iter().map(|s| (*s).to_owned()).collect(),
    }
}

#[test]
fn eco_sai_quando_o_transcript_confirma() {
    let front = ready("front");
    let now = at(5_000.0);
    let messages = vec![ChatMessage::prompt(&front, "u2", "oi", now)];
    let left = still_pending(
        &[
            pending("oi", "front", now, &["u1"]),
            pending("oi", "back", now, &[]),
            pending("tchau", "front", now, &["u1"]),
        ],
        &messages,
    );
    assert_eq!(
        left.iter().map(|p| p.text.as_str()).collect::<Vec<_>>(),
        ["oi", "tchau"]
    );
    assert_eq!(
        left.iter().map(|p| p.target.as_str()).collect::<Vec<_>>(),
        ["back", "front"]
    );
}

/// Plano como um grupo do WhatsApp: a mensagem do front para o back é uma bolha do
/// front, a resposta do back é do back, e a volta ao front é do back também —
/// tudo na ordem do tempo, sem sub-conversa aninhada.
#[test]
fn mensagens_entre_agentes_sao_bolhas_proprias() {
    let (front, back) = (ready("front"), ready("back"));
    let base = 1_000.0;
    let mut root = ChatTurn::new("f1", "faz a coluna", at(base), None);
    let mut send = ChatStep::new("⇄", "egeon send deck/back");
    send.send_to = Some("deck/back".into());
    root.steps = vec![send];
    root.reply_at = Some(at(base + 5.0));

    let mut back_turn = ChatTurn::new(
        "b1",
        "o estado vem pronto?",
        at(base + 10.0),
        Some("deck/front".into()),
    );
    back_turn.reply_text = "Respondi ao front.".into();
    back_turn.reply_at = Some(at(base + 15.0));

    let mut front_back = ChatTurn::new(
        "f2",
        "vem pronto: state ∈ {…}",
        at(base + 20.0),
        Some("deck/back".into()),
    );
    front_back.reply_text = "Coluna pronta.".into();
    front_back.reply_at = Some(at(base + 30.0));

    let thread = build(&[front, back], |p| {
        if p.id == "front" {
            vec![root.clone(), front_back.clone()]
        } else {
            vec![back_turn.clone()]
        }
    });

    let keys: Vec<String> = thread.iter().map(ChatMessage::key).collect();
    assert_eq!(keys, ["p|f1", "r|f1", "p|b1", "r|b1", "p|f2", "r|f2"]);
    let senders: Vec<Option<&str>> = thread.iter().map(ChatMessage::sender_id).collect();
    assert_eq!(
        senders,
        [None, None, Some("front"), None, Some("back"), None]
    );
    assert_eq!(
        thread[2].prompt_text(),
        Some("o estado vem pronto?"),
        "sem prefixo 'de …': quem mandou vai em `from`"
    );
    // Mensagem de agente para agente não cita: ela já diz de quem é.
    assert!(thread[2].quote().is_none());
    assert!(thread[4].quote().is_none());
    // A resposta logo depois do próprio prompt é limpa.
    assert!(thread[3].quote().is_none());
    let ChatMessage::Reply { turn, .. } = &thread[5] else {
        panic!("esperava resposta")
    };
    assert_eq!(turn.reply_text, "Coluna pronta.");
}

/// A resposta a uma mensagem de outro agente, quando não vem logo depois dela,
/// cita quem perguntou — não "você".
#[test]
fn resposta_a_mensagem_de_agente_cita_o_remetente() {
    let (front, back) = (ready("front"), ready("back"));
    let base = 1_000.0;
    let mut ask = ChatTurn::new("b1", "vem pronto?", at(base), Some("deck/front".into()));
    ask.reply_text = "Vem.".into();
    ask.reply_at = Some(at(base + 20.0));
    let mut other = ChatTurn::new("f9", "e a cor?", at(base + 10.0), None);
    other.reply_text = "azul".into();
    other.reply_at = Some(at(base + 12.0));
    let thread = build(&[front, back.clone()], |p| {
        if p.id == "back" {
            vec![ask.clone()]
        } else {
            vec![other.clone()]
        }
    });
    let Some(ChatMessage::Reply { from, quote, .. }) = thread.last() else {
        panic!("esperava resposta")
    };
    assert_eq!(from, &back);
    let quote = quote.as_ref().expect("citação");
    assert_eq!(quote.author_id.as_deref(), Some("front"));
    assert_eq!(quote.text, "vem pronto?");
}

/// Remetente que não está na bancada: o endereço cru vai em `from`.
#[test]
fn remetente_desconhecido_guarda_o_endereco_cru() {
    let back = ready("back");
    let turn = ChatTurn::new("b1", "oi", at(2_000.0), Some("outra/coisa".into()));
    let thread = build(&[back], |_| vec![turn.clone()]);
    assert_eq!(thread.len(), 1);
    assert_eq!(thread[0].prompt_text(), Some("oi"));
    assert_eq!(thread[0].sender_id(), Some("outra/coisa"));
}

/// O eco entra NA linha do tempo pela hora do envio: resposta que chega depois
/// dele fica embaixo, não em cima de um eco pinado no rodapé.
#[test]
fn eco_pendente_fica_na_linha_do_tempo() {
    let (front, back) = (ready("front"), ready("back"));
    let base = 1_000.0;
    let mut front_turn = ChatTurn::new("f1", "oi", at(base), None);
    front_turn.reply_text = "oi".into();
    front_turn.reply_at = Some(at(base + 8.0));
    let echo = pending("oi", "back", at(base + 3.0), &[]);

    let (messages, left) = build_with_pending(&[front, back], &[echo], |p| {
        if p.id == "front" {
            vec![front_turn.clone()]
        } else {
            vec![]
        }
    });
    assert_eq!(
        left.iter().map(|p| p.text.as_str()).collect::<Vec<_>>(),
        ["oi"]
    );
    // O turno do front foi visto e virou conhecido para o eco do back.
    assert_eq!(left[0].known_turn_ids, BTreeSet::from(["f1".to_owned()]));
    let keys: Vec<String> = messages.iter().map(ChatMessage::key).collect();
    assert_eq!(keys, ["p|f1", "e|back|1003.0", "r|f1"]);
}

/// Dois "oi" seguidos: o primeiro turno novo dá baixa em UM eco, não nos dois.
#[test]
fn um_turno_novo_confirma_um_eco() {
    let front = ready("front");
    let now = at(5_000.0);
    let messages = vec![ChatMessage::prompt(&front, "u2", "oi", now)];
    let left = still_pending(
        &[
            pending("oi", "front", now, &["u1"]),
            pending("oi", "front", now, &["u1"]),
        ],
        &messages,
    );
    assert_eq!(left.len(), 1);
    // Rodada seguinte, mesma lista: o turno já usado não dá baixa de novo.
    assert_eq!(still_pending(&left, &messages).len(), 1);
    // Só o segundo turno novo fecha o segundo eco.
    let mut more = messages;
    more.push(ChatMessage::prompt(&front, "u3", "oi", now));
    assert_eq!(still_pending(&left, &more).len(), 0);
}

/// Um "oi" que JÁ existia na hora do envio não confirma o "oi" novo — nem que
/// tenha sido gravado há um segundo. Só id que o envio ainda não conhecia.
#[test]
fn turno_conhecido_nao_confirma_eco_novo() {
    let front = ready("front");
    let now = at(5_000.0);
    let messages = vec![ChatMessage::prompt(&front, "u1", "oi", now)];
    let left = still_pending(&[pending("oi", "front", now, &["u1"])], &messages);
    assert_eq!(left.len(), 1);
}

#[test]
fn participantes_vem_dos_nos_agentes_e_shells() {
    use crate::features::node::model::NodeConfig;
    let nodes: Vec<NodeConfig> = [
        r#"{"type":"agent","id":"revisor","agent":"claude","prompt":"revise\ntudo"}"#,
        r#"{"type":"shell","id":"zsh","cmd":"npm run dev"}"#,
        r#"{"type":"web","id":"docs"}"#,
    ]
    .iter()
    .map(|j| serde_json::from_str(j).expect("nó"))
    .collect();
    let participants = ChatParticipant::from_nodes(&nodes, "deck", |address| {
        (address == "deck/revisor").then_some(Activity::Working)
    });
    assert_eq!(
        participants
            .iter()
            .map(|p| p.id.as_str())
            .collect::<Vec<_>>(),
        ["revisor", "zsh"]
    );
    assert_eq!(participants[0].address, "deck/revisor");
    // Só a primeira linha do papel: a lista não é lugar de prompt inteiro.
    assert_eq!(participants[0].role.as_deref(), Some("revise"));
    assert_eq!(participants[0].activity, Activity::Working);
    assert!(participants[0].is_agent);
    assert_eq!(participants[1].role.as_deref(), Some("npm run dev"));
    // Sem alvo no Dispatcher = terminal morto.
    assert_eq!(participants[1].activity, Activity::Dead);
    assert!(!participants[1].is_agent);
}

/// A UI não mapeia nome em cor: o tom e a atenção vão no participante, pela
/// mesma tabela do `Activity` do Swift.
#[test]
fn participante_leva_o_tom_e_a_atencao_do_estado() {
    let casos = [
        (Activity::Waiting, Some("green"), false),
        (Activity::Asking, Some("orange"), true),
        (Activity::Failed("429".into()), Some("red"), true),
        (Activity::Dead, Some("red"), false),
        (Activity::Working, None, false),
        (Activity::Awaiting(vec![]), None, false),
        (Activity::Ready, None, false),
    ];
    for (activity, tone, attention) in casos {
        let p = ChatParticipant {
            id: "a".into(),
            address: "deck/a".into(),
            is_agent: true,
            role: None,
            activity: activity.clone(),
        };
        let info = p.info();
        assert_eq!(info.tone.as_deref(), tone, "{activity:?}");
        assert_eq!(info.needs_attention, attention, "{activity:?}");
        let json = serde_json::to_value(&info).expect("json");
        assert_eq!(json.get("tone").is_some(), tone.is_some());
        assert_eq!(json["needsAttention"], attention);
    }
}

// ===========================================================================
// ChatBlocksTests
// ===========================================================================

fn block_turn() -> ChatTurn {
    let t0 = 1_000.0;
    let mut turn = ChatTurn::new("u1", "faz", at(t0), None);
    let mut run = ChatStep::new("$", "Roda");
    run.detail = Some("swift test".into());
    let mut edit = ChatStep::new("±", "a.swift");
    edit.diff = Some(vec!["@@ -1 +1 @@".into(), "-a".into(), "+b".into()]);
    turn.parts = vec![
        ChatPart::Text("Vou olhar.\n\n```swift\nlet a = 1\n```\n\nDepois disso.".into()),
        ChatPart::Step(run),
        ChatPart::Step(edit),
        ChatPart::Text("Pronto.".into()),
    ];
    turn.reply_at = Some(at(t0 + 9.0));
    turn
}

fn build_blocks(
    messages: &[ChatMessage],
    live: &BTreeMap<String, LiveStatus>,
    typing: &[ChatParticipant],
    expanded: &BTreeSet<String>,
    groups: &BTreeMap<String, ChatGroupLevel>,
) -> Vec<ChatBlock> {
    blocks::build(&BuildInput {
        messages,
        live,
        typing,
        expanded,
        groups,
        prices: &PRICES,
    })
}

fn plain(messages: &[ChatMessage]) -> Vec<ChatBlock> {
    build_blocks(
        messages,
        &BTreeMap::new(),
        &[],
        &BTreeSet::new(),
        &BTreeMap::new(),
    )
}

fn ids(blocks: &[ChatBlock]) -> Vec<&str> {
    blocks.iter().map(|b| b.id.as_str()).collect()
}

#[test]
fn uma_linha_por_bloco_com_id_estavel() {
    let front = agent("front", Activity::Working);
    let messages = vec![
        ChatMessage::prompt(&front, "u1", "faz", at(1_000.0)),
        ChatMessage::reply(&front, block_turn()),
    ];
    let rows = plain(&messages);
    assert_eq!(
        ids(&rows),
        [
            "p|u1", "h|u1", "b|u1|0", "b|u1|1", "b|u1|2", "b|u1|3", "b|u1|4", "b|u1|5"
        ]
    );
    let keys: Vec<&str> = rows.iter().map(|b| b.message_key.as_str()).collect();
    assert_eq!(
        keys,
        [
            "p|u1", "r|u1", "r|u1", "r|u1", "r|u1", "r|u1", "r|u1", "r|u1"
        ]
    );
    assert_eq!(
        rows.iter().map(|b| b.first).collect::<Vec<_>>(),
        [true, true, false, false, false, false, false, false]
    );
    assert_eq!(
        rows.iter().map(|b| b.last).collect::<Vec<_>>(),
        [true, false, false, false, false, false, false, true]
    );
    // Prosa, código, prosa, passo, diff, prosa — na ordem da cadeia.
    assert!(matches!(rows[2].kind, BlockKind::Prose { .. }));
    assert!(
        matches!(&rows[3].kind, BlockKind::Code { language: Some(l), code, .. } if l == "swift" && code == "let a = 1")
    );
    assert!(matches!(rows[4].kind, BlockKind::Prose { .. }));
    assert!(matches!(
        rows[5].kind,
        BlockKind::Step {
            expanded: false,
            ..
        }
    ));
    assert!(matches!(&rows[6].kind, BlockKind::Diff { file, .. } if file == "a.swift"));
    assert!(matches!(rows[7].kind, BlockKind::Prose { .. }));
    assert!(rows[0].aligns_right());
    assert!(!rows[1].aligns_right());
}

/// Passo de comando nasce só no título e abre por id. Passo sem nada além do
/// título é sempre inteiro, e o de edição nunca recolhe: o diff é justamente o
/// que se quer ver.
#[test]
fn passos_recolhem_ate_abrir_por_id_mas_o_diff_nunca() {
    let front = agent("front", Activity::Working);
    let mut turn = block_turn();
    turn.parts
        .push(ChatPart::Step(ChatStep::new("→", "só título")));
    let messages = vec![ChatMessage::reply(&front, turn)];
    let closed = plain(&messages);
    assert!(
        matches!(&closed[4].kind, BlockKind::Step { step, expanded: false, .. } if step.text == "Roda")
    );
    assert!(matches!(&closed[5].kind, BlockKind::Diff { file, .. } if file == "a.swift"));
    assert!(matches!(
        closed[7].kind,
        BlockKind::Step { expanded: true, .. }
    ));

    let open = build_blocks(
        &messages,
        &BTreeMap::new(),
        &[],
        &BTreeSet::from(["b|u1|3".to_owned()]),
        &BTreeMap::new(),
    );
    assert!(matches!(
        open[4].kind,
        BlockKind::Step { expanded: true, .. }
    ));
    assert!(matches!(&open[5].kind, BlockKind::Diff { file, .. } if file == "a.swift"));
    assert_eq!(ids(&open), ids(&closed), "abrir não muda o id");
}

fn group_turn() -> ChatTurn {
    let step = |text: &str, detail: &str| {
        let mut s = ChatStep::new("$", text);
        s.detail = Some(detail.into());
        ChatPart::Step(s)
    };
    let mut turn = ChatTurn::new("u1", "faz", at(1_000.0), None);
    turn.parts = vec![
        step("um", "a"),
        step("dois", "b"),
        step("três", "c"),
        ChatPart::Text("No meio.\n\n```swift\nlet a = 1\n```".into()),
        step("quatro", "d"),
    ];
    turn.reply_at = Some(at(1_009.0));
    turn
}

/// Passos seguidos viram uma CAPA — "3 passos · três" — e o clique nela aprofunda:
/// capa, títulos, tudo aberto, capa de novo. Um passo sozinho não ganha capa, e
/// prosa, diff ou código cortam a sequência.
#[test]
fn passos_seguidos_viram_uma_capa() {
    let front = agent("front", Activity::Working);
    let messages = vec![ChatMessage::reply(&front, group_turn())];

    let summary = plain(&messages);
    assert_eq!(
        ids(&summary),
        ["h|u1", "g|u1|0", "b|u1|3", "b|u1|4", "b|u1|5"]
    );
    assert!(
        matches!(&summary[1].kind, BlockKind::Group { count: 3, last, level: ChatGroupLevel::Summary, .. } if last == "três")
    );
    assert!(
        matches!(&summary[4].kind, BlockKind::Step { step, expanded: false, .. } if step.text == "quatro")
    );

    // Um clique: a capa e os três títulos, tudo numa caixa só.
    let titles = build_blocks(
        &messages,
        &BTreeMap::new(),
        &[],
        &BTreeSet::new(),
        &BTreeMap::from([("g|u1|0".to_owned(), ChatGroupLevel::Titles)]),
    );
    assert_eq!(
        ids(&titles),
        [
            "h|u1", "g|u1|0", "b|u1|0", "b|u1|1", "b|u1|2", "b|u1|3", "b|u1|4", "b|u1|5"
        ]
    );
    // A capa fica na raiz; os passos dela entram um tab, cada um na sua caixinha.
    assert_eq!(
        titles[1..=4].iter().map(|b| b.depth).collect::<Vec<_>>(),
        [0, 1, 1, 1]
    );
    assert_eq!(titles.iter().filter(|b| b.depth > 0).count(), 3);
    assert!(
        summary.iter().all(|b| b.depth == 0),
        "sem capa aberta, nada é filho"
    );
    assert!(
        titles[2..=4].iter().all(|b| matches!(
            b.kind,
            BlockKind::Step {
                expanded: false,
                ..
            }
        )),
        "no primeiro clique os passos ainda são só título"
    );

    // Detalhar não é um estado que sobrescreve o passo: quem abre é o `expanded`.
    let details = build_blocks(
        &messages,
        &BTreeMap::new(),
        &[],
        &BTreeSet::from([
            "b|u1|0".to_owned(),
            "b|u1|1".to_owned(),
            "b|u1|2".to_owned(),
        ]),
        &BTreeMap::from([("g|u1|0".to_owned(), ChatGroupLevel::Details)]),
    );
    assert!(
        details[2..=4]
            .iter()
            .all(|b| matches!(b.kind, BlockKind::Step { expanded: true, .. }))
    );
    assert_eq!(ChatGroupLevel::Summary.next(false), ChatGroupLevel::Titles);
    assert_eq!(ChatGroupLevel::Titles.next(false), ChatGroupLevel::Details);
    assert_eq!(
        ChatGroupLevel::Titles.next(true),
        ChatGroupLevel::Summary,
        "com passo aberto à mão, a capa fecha em vez de aprofundar"
    );
    assert_eq!(
        ChatGroupLevel::Details.next(true),
        ChatGroupLevel::Summary,
        "o ciclo volta ao começo"
    );
}

#[test]
fn turno_ao_vivo_ganha_linha_de_status_e_nao_tem_hora() {
    let front = agent("front", Activity::Working);
    let messages = vec![ChatMessage::reply(&front, block_turn())];
    let live = BTreeMap::from([(
        "front".to_owned(),
        LiveStatus {
            turn_id: "u1".into(),
            status: ChatLive::Thinking,
        },
    )]);
    let rows = build_blocks(&messages, &live, &[], &BTreeSet::new(), &BTreeMap::new());
    let last = rows.last().expect("linha");
    assert_eq!(last.id, "s|u1");
    assert!(matches!(
        &last.kind,
        BlockKind::Status {
            live: ChatLive::Thinking,
            ..
        }
    ));
    assert!(
        matches!(&rows[0].kind, BlockKind::Header { at: None, .. }),
        "ao vivo é 'agora'"
    );
    assert!(last.last);
    assert!(!rows[rows.len() - 2].last);

    // Outro turno ao vivo do mesmo agente não pinga aqui.
    let other = BTreeMap::from([(
        "front".to_owned(),
        LiveStatus {
            turn_id: "u9".into(),
            status: ChatLive::Working,
        },
    )]);
    let rows = build_blocks(&messages, &other, &[], &BTreeSet::new(), &BTreeMap::new());
    assert_ne!(rows.last().map(|b| b.id.as_str()), Some("s|u1"));
}

#[test]
fn digitando_e_prompt_de_agente_para_agente() {
    let (front, back) = (
        agent("front", Activity::Working),
        agent("back", Activity::Working),
    );
    let mut message = ChatMessage::prompt(&back, "b1", "oi", at(1_000.0));
    if let ChatMessage::Prompt { from, .. } = &mut message {
        *from = Some("front".into());
    }
    let rows = build_blocks(
        &[message],
        &BTreeMap::new(),
        &[front],
        &BTreeSet::new(),
        &BTreeMap::new(),
    );
    assert_eq!(ids(&rows), ["p|b1", "t|front"]);
    assert!(
        !rows[0].aligns_right(),
        "mensagem de agente fica à esquerda"
    );
    assert_eq!(rows[0].participant().id, "back");
    assert_eq!(rows[1].participant().id, "front");
}

/// Consecutivo é limpo, intercalado é marcado: o `@` só entra quando a mensagem
/// anterior não é do mesmo participante.
#[test]
fn mencao_so_quando_nao_e_continua() {
    let (front, back) = (
        agent("front", Activity::Working),
        agent("back", Activity::Working),
    );
    let t0 = 1_000.0;
    let mut from_back = ChatMessage::prompt(&front, "f3", "volta", at(t0 + 40.0));
    if let ChatMessage::Prompt { from, .. } = &mut from_back {
        *from = Some("back".into());
    }
    let messages = vec![
        ChatMessage::prompt(&front, "f1", "faz", at(t0)),
        ChatMessage::reply(&front, block_turn()),
        ChatMessage::prompt(&front, "f2", "continua", at(t0 + 20.0)),
        ChatMessage::prompt(&back, "b1", "e você?", at(t0 + 30.0)),
        from_back,
    ];
    let rows = plain(&messages);
    let mention = |id: &str| {
        rows.iter()
            .find(|b| b.id == id)
            .and_then(|b| match &b.kind {
                BlockKind::Prompt { mention, .. } => Some(*mention),
                _ => None,
            })
    };
    assert_eq!(mention("p|f1"), Some(false), "primeira mensagem");
    assert_eq!(
        mention("p|f2"),
        Some(false),
        "logo depois da resposta do front"
    );
    assert_eq!(mention("p|b1"), Some(true), "trocou de interlocutor");
    assert_eq!(
        mention("p|f3"),
        Some(true),
        "do back para o front, depois de uma fala ao back"
    );
}

#[test]
fn atividade_nao_muda_as_linhas() {
    let a = plain(&[ChatMessage::reply(
        &agent("x", Activity::Working),
        block_turn(),
    )]);
    let b = plain(&[ChatMessage::reply(
        &agent("x", Activity::Waiting),
        block_turn(),
    )]);
    assert_eq!(a, b);
}

// ===========================================================================
// ChatBlockLayoutTests — o que a linha DIZ (altura e largura são da UI)
// ===========================================================================

#[test]
fn passo_recolhido_e_uma_linha_e_o_aberto_tem_comando_e_saida() {
    let mut step = ChatStep::new("$", "Roda");
    step.detail = Some("swift test".into());
    step.output = Some("ok\nok\nok".into());
    let closed = layout::step(&step, false);
    assert!(closed.starts_with("▸ $  Roda"), "{closed}");
    assert!(closed.ends_with("⎿ 3 linhas"), "{closed}");
    assert!(!closed.contains("swift test"));
    let open = layout::step(&step, true);
    assert!(open.starts_with("▾ $  Roda\n"), "{open}");
    assert!(open.contains("swift test") && open.contains("⎿ ok"));
    // Sem nada além do título, não há o que abrir — nem chevron.
    assert_eq!(layout::step(&ChatStep::new("→", "Lê"), false), "→  Lê");
}

/// Mensagem de agente para agente: quem mandou em cima, `@destinatário` no texto
/// — sem seta, como no WhatsApp.
#[test]
fn prompt_de_agente_menciona_sem_seta() {
    assert_eq!(
        layout::prompt("vem pronto?", "back", Some("front"), true),
        "✦ front\n@back vem pronto?"
    );
    assert_eq!(layout::prompt("oi", "back", None, true), "@back oi");
    assert_eq!(
        layout::prompt("oi", "back", None, false),
        "oi",
        "mensagem contínua não marca"
    );
}

#[test]
fn capa_status_e_hora_do_cabecalho() {
    assert_eq!(
        layout::group(3, "três", ChatGroupLevel::Summary),
        "▸ ⚙  3 passos  ·  três"
    );
    assert_eq!(
        layout::group(3, "três", ChatGroupLevel::Titles),
        "▾ ⚙  3 passos"
    );
    assert_eq!(
        layout::group(3, "três", ChatGroupLevel::Details),
        "▾ ⚙  3 passos  ·  detalhes"
    );
    assert_eq!(layout::status(&ChatLive::Thinking, '⠋'), "⠋ pensando…");
    assert_eq!(layout::status(&ChatLive::Asking, '⠋'), "● precisa de você");
    // 1_787_678_363 = 2026-08-25T17:19:23Z; em -03:00 são 14:19.
    let when = at(1_787_678_363.0);
    assert_eq!(layout::clock(when, 0), "17:19");
    assert_eq!(layout::clock(when, -3 * 3600), "14:19");
    assert_eq!(layout::header_time(None, None, 0), "agora");
    let cost = blocks::ChatCost {
        text: "US$ 0,42".into(),
        detail: String::new(),
    };
    assert_eq!(
        layout::header_time(Some(when), Some(&cost), 0),
        "US$ 0,42 · 17:19"
    );
}

// ===========================================================================
// ChatHistoryTests
// ===========================================================================

const T0: f64 = 1_787_678_363.25;

fn record(node: &str, id: &str, prompt: &str, reply: &str, reply_after: f64) -> ChatRecord {
    let mut turn = ChatTurn::new(id, prompt, at(T0), None);
    let mut send = ChatStep::new("⇄", "egeon send deck/b");
    send.send_to = Some("deck/b".into());
    turn.steps = vec![ChatStep::new("$", "ls"), send];
    turn.reply_text = reply.to_owned();
    turn.reply_at = Some(at(T0 + reply_after));
    ChatRecord {
        node: node.to_owned(),
        conversation: Some("3C0C394C".into()),
        cli: Some("Claude Code".into()),
        model: Some("claude-opus-5".into()),
        turn,
    }
}

fn simple(node: &str, id: &str) -> ChatRecord {
    record(node, id, "oi", "olá", 3.5)
}

#[test]
fn a_corrente_mora_na_raiz_da_bancada() {
    let root = temp();
    let mut history = ChatHistory::new(root.path().to_path_buf(), utc);
    assert_eq!(
        history.current("93cbec07"),
        root.path().join("93cbec07/chat.jsonl")
    );
    history.append(&simple("a", "u1"), "93cbec07");
    assert!(history.current("93cbec07").exists());
    assert!(history.archived("93cbec07").is_empty());
}

/// O que sai é o que entrou: passos, envio, datas com fração de segundo.
#[test]
fn ida_e_volta() {
    let root = temp();
    let mut history = ChatHistory::new(root.path().to_path_buf(), utc);
    let r = record("a", "u1", "revisa", "feito", 3.5);
    history.append(&r, "w");
    let back = history.load("w", None);
    assert_eq!(back, vec![r]);
    assert_eq!(back[0].turn.steps[1].send_to.as_deref(), Some("deck/b"));
    let delta = back[0]
        .turn
        .reply_at
        .expect("resposta")
        .duration_since(at(T0))
        .expect("depois");
    assert!((delta.as_secs_f64() - 3.5).abs() < 0.001);
}

/// Duas linhas gravadas por outro processo e o formato do Swift: chaves em ordem,
/// datas ISO com milissegundos, sem barra escapada.
#[test]
fn formato_da_linha_e_o_do_swift() {
    let root = temp();
    let mut history = ChatHistory::new(root.path().to_path_buf(), utc);
    history.append(&simple("a", "u1"), "w");
    let text = fs::read_to_string(history.current("w")).expect("lê");
    assert_eq!(text.matches('\n').count(), 1);
    assert!(text.starts_with(r#"{"cli":"Claude Code","conversation":"3C0C394C","model":"claude-opus-5","node":"a","turn":{"#), "{text}");
    assert!(
        text.contains(r#""promptAt":"2026-08-25T17:19:23.250Z""#),
        "{text}"
    );
    assert!(
        text.contains(r#""replyAt":"2026-08-25T17:19:26.750Z""#),
        "{text}"
    );
    assert!(text.contains(r#""sendTo":"deck/b""#));
}

/// Dois Stop do mesmo turno, ou releitura depois do arranque: uma linha só.
#[test]
fn o_mesmo_turno_nao_e_gravado_duas_vezes() {
    let root = temp();
    let mut history = ChatHistory::new(root.path().to_path_buf(), utc);
    history.append(&simple("a", "u1"), "w");
    history.append(&record("a", "u1", "oi", "outra", 3.5), "w");
    history.append(&simple("b", "u1"), "w"); // outro nó, mesmo uuid: vale
    assert_eq!(
        history
            .load("w", None)
            .iter()
            .map(|r| r.node.as_str())
            .collect::<Vec<_>>(),
        ["a", "b"]
    );

    // Um processo novo não sabe do anterior: aprende do arquivo.
    let mut again = ChatHistory::new(root.path().to_path_buf(), utc);
    again.append(&simple("a", "u1"), "w");
    again.append(&simple("a", "u2"), "w");
    assert_eq!(
        again
            .load("w", None)
            .iter()
            .map(|r| r.turn.id.as_str())
            .collect::<Vec<_>>(),
        ["u1", "u1", "u2"]
    );
}

fn name_matches_period(name: &str) -> bool {
    // ^chat-\d{8}-\d{6}_\d{8}-\d{6}\.jsonl$
    let Some(body) = name
        .strip_prefix("chat-")
        .and_then(|n| n.strip_suffix(".jsonl"))
    else {
        return false;
    };
    let digits = |s: &str, n: usize| s.len() == n && s.bytes().all(|b| b.is_ascii_digit());
    let Some((a, b)) = body.split_once('_') else {
        return false;
    };
    let stamp = |s: &str| {
        s.split_once('-')
            .is_some_and(|(d, t)| digits(d, 8) && digits(t, 6))
    };
    stamp(a) && stamp(b)
}

/// O nome é o período da conversa: primeiro prompt → última resposta.
#[test]
fn o_arquivo_leva_o_periodo_da_conversa() {
    let root = temp();
    let mut history = ChatHistory::new(root.path().to_path_buf(), brt);
    let late = record("b", "u2", "oi", "olá", 3_600.0 * 5.0 + 7.0);
    history.append(&simple("a", "u1"), "w");
    history.append(&late, "w");
    let archived = history.archive("w", at(T0 + 86_400.0)).expect("arquivou");
    let (start, end) = history.period_of_file(&archived).expect("período");
    let secs = |t: SystemTime| {
        t.duration_since(UNIX_EPOCH)
            .expect("depois de 1970")
            .as_secs_f64()
    };
    assert!((secs(start) - T0).abs() < 1.0);
    assert!((secs(end) - secs(late.turn.reply_at.expect("resposta"))).abs() < 1.0);
    let name = archived
        .file_name()
        .expect("nome")
        .to_string_lossy()
        .into_owned();
    assert!(name_matches_period(&name), "{name}");
    // O relógio do nome é o do fuso dado (-03:00): 14:19:23.
    assert!(name.starts_with("chat-20260825-141923_"), "{name}");
}

#[test]
fn arquivar_move_a_corrente_e_recomeca() {
    let root = temp();
    let mut history = ChatHistory::new(root.path().to_path_buf(), utc);
    history.append(&simple("a", "u1"), "w");
    let archived = history.archive("w", at(T0)).expect("arquivou");
    assert_eq!(
        archived.parent(),
        Some(root.path().join("w/chat-archive").as_path())
    );
    assert_eq!(history.archived("w"), vec![archived.clone()]);
    assert!(history.load("w", None).is_empty());
    assert_eq!(history.load("w", Some(&archived)).len(), 1);
    assert!(!history.current("w").exists());

    // O turno já gravado na arquivada pode entrar na nova: é outra conversa.
    history.append(&simple("a", "u1"), "w");
    assert_eq!(history.load("w", None).len(), 1);
}

/// Limpar sem conversa não deixa arquivo vazio para trás.
#[test]
fn arquivar_sem_conversa_nao_faz_nada() {
    let root = temp();
    let mut history = ChatHistory::new(root.path().to_path_buf(), utc);
    assert!(history.archive("w", at(T0)).is_none());
    history.append(&simple("a", "u1"), "w");
    assert!(history.archive("w", at(T0)).is_some());
    assert!(history.archive("w", at(T0 + 60.0)).is_none());
    assert_eq!(history.archived("w").len(), 1);
}

/// Mesmo período duas vezes (os registros têm as mesmas datas): sufixo.
#[test]
fn mesmo_periodo_duas_vezes_tem_nomes_distintos() {
    let root = temp();
    let mut history = ChatHistory::new(root.path().to_path_buf(), utc);
    history.append(&simple("a", "u1"), "w");
    let first = history.archive("w", at(T0)).expect("primeiro");
    history.append(&simple("a", "u2"), "w");
    let second = history.archive("w", at(T0)).expect("segundo");
    assert_ne!(first, second);
    // A mais recente é a última da lista — o sufixo tem que ordenar depois.
    assert_eq!(history.archived("w"), vec![first.clone(), second.clone()]);
    assert_eq!(
        history.period_of_file(&second).map(|p| p.0),
        history.period_of_file(&first).map(|p| p.0)
    );
}

#[test]
fn linha_ruim_e_pulada_e_arquivo_invalido_e_vazio() {
    let root = temp();
    let history = ChatHistory::new(root.path().to_path_buf(), utc);
    let file = history.current("w");
    let good = serde_json::to_string(&simple("a", "u1")).expect("grava");
    write(
        &file,
        &format!("{good}\nisto não é json\n{{\"node\":\"x\"}}\n{good}\n"),
    );
    assert_eq!(read_history(&file).len(), 2, "só as linhas que decodificam");
    fs::write(&file, [0xff, 0xfe, b'\n']).expect("grava");
    assert!(
        read_history(&file).is_empty(),
        "UTF-8 inválido derruba o arquivo, como no Swift"
    );
}

#[test]
fn datas_iso_e_relogio_do_nome() {
    assert_eq!(format_iso(at(1_787_678_363.25)), "2026-08-25T17:19:23.250Z");
    assert_eq!(format_iso(UNIX_EPOCH), "1970-01-01T00:00:00.000Z");
    let round = parse_iso("2026-08-25T17:19:23.250Z").expect("lê");
    assert_eq!(format_iso(round), "2026-08-25T17:19:23.250Z");
    assert_eq!(format_clock(at(T0), 0), "20260825-171923");
    assert_eq!(
        parse_clock("20260825-141923", brt),
        parse_iso("2026-08-25T17:19:23Z")
    );
    assert_eq!(parse_clock("lixo", utc), None);
}

// ===========================================================================
// ChatClearTests, ChatThreadReuseTests, ChatLazyLoadTests, ChatStepToggleTests
// ===========================================================================

fn view_input<'a>(
    participants: &'a [ChatParticipant],
    records: &'a [ChatRecord],
    live: &'a BTreeMap<String, LiveTurn>,
) -> ThreadInput<'a> {
    ThreadInput {
        participants,
        records,
        live,
        prices: &PRICES,
    }
}

fn rebuild(
    view: &mut ChatView,
    participants: &[ChatParticipant],
    records: &[ChatRecord],
) -> Option<super::view::ChatUpdate> {
    let live = BTreeMap::new();
    view.rebuild(&view_input(participants, records, &live))
}

fn turn_record(node: &str, i: usize) -> ChatRecord {
    let mut turn = ChatTurn::new(
        &format!("u{i}"),
        &format!("pergunta {i}"),
        at(1_787_678_000.0 + i as f64 * 60.0),
        None,
    );
    turn.reply_text = format!("resposta {i}");
    turn.reply_at = Some(at(1_787_678_005.0 + i as f64 * 60.0));
    ChatRecord::new(node, turn)
}

/// A thread não renasce à toa: um refresh sem mudança (o tique de 1 s, o vigia do
/// transcript) não monta nem manda nada.
#[test]
fn refresh_sem_mudanca_nao_renasce() {
    let mut turn = ChatTurn::new("u1", "oi", at(1_787_678_363.0), None);
    turn.reply_text = "olá".into();
    turn.reply_at = Some(at(1_787_678_365.0));
    let records = vec![ChatRecord::new("a", turn)];
    let mut view = ChatView::new("w");

    let participants = vec![agent("a", Activity::Waiting)];
    let first =
        rebuild(&mut view, &participants, &records).expect("prompt + resposta entram uma vez");
    assert_eq!(first.rev, 1);
    assert!(matches!(first.ops.as_slice(), [BlockOp::Reset { blocks }] if !blocks.is_empty()));

    assert!(
        rebuild(&mut view, &participants, &records).is_none(),
        "nada mudou, nada renasce"
    );
    assert!(rebuild(&mut view, &participants, &records).is_none());
    assert_eq!(view.rev(), 1);

    // Agente passou a trabalhar: só a bolha de "trabalhando…" entra.
    let working = vec![agent("a", Activity::Working)];
    let update = rebuild(&mut view, &working, &records).expect("digitando");
    assert_eq!(update.rev, 2);
    assert!(matches!(update.ops.as_slice(), [BlockOp::Insert { block, .. }] if block.id == "t|a"));
    assert!(rebuild(&mut view, &working, &records).is_none());
}

/// Arquivar move um arquivo — e o chat guarda coisa que não está nele: o eco local
/// de um envio que o transcript ainda não confirmou. Sem avisar a thread, esse eco
/// voltava a desenhar sozinho numa conversa vazia (ADR-059).
#[test]
fn limpar_o_historico_leva_o_eco_junto() {
    let participants = vec![agent("front", Activity::Waiting)];
    let mut view = ChatView::new("w");
    view.sent(
        "olha essa melhoria aqui",
        "front",
        at(1_787_678_000.0),
        BTreeSet::new(),
    );
    assert!(rebuild(&mut view, &participants, &[]).is_some());
    assert_eq!(view.pending_count(), 1, "o envio precisa aparecer na hora");
    assert!(!view.blocks().is_empty());

    let update = view.cleared_history().expect("a thread esvazia");
    assert_eq!(update.ops, vec![BlockOp::Reset { blocks: vec![] }]);
    assert_eq!(view.pending_count(), 0, "o eco sobreviveu à limpeza");
    assert!(
        view.blocks().is_empty(),
        "sobrou bolha órfã na thread limpa"
    );
    assert!(view.messages().is_empty());
    assert!(
        rebuild(&mut view, &participants, &[]).is_none(),
        "e não volta sozinho"
    );
    assert!(
        view.cleared_history().is_none(),
        "limpar o vazio não manda nada"
    );
}

/// O que estava aberto era daquela conversa: a nova nasce fechada, e a janela de
/// rolagem volta ao começo.
#[test]
fn limpar_zera_o_estado_da_thread() {
    let mut view = ChatView::new("w");
    let participants = vec![agent("a", Activity::Waiting)];
    let step = vec![step_record()];
    rebuild(&mut view, &participants, &step);
    view.toggle_step("b|u1|0");
    assert!(!view.expanded_steps().is_empty());
    let records: Vec<ChatRecord> = (0..100).map(|i| turn_record("a", i)).collect();
    rebuild(&mut view, &participants, &records);
    assert!(view.load_more(true, false));
    assert_eq!(view.loaded_messages(), 2 * WINDOW_STEP);
    view.cleared_history();
    assert!(view.expanded_steps().is_empty());
    assert!(view.group_levels().is_empty());
    assert_eq!(view.loaded_messages(), WINDOW_STEP);
}

/// A thread é preguiçosa: o histórico entra em janelas — o fim primeiro, o resto
/// quando o usuário rola até o começo do que há.
#[test]
fn historico_carrega_em_janelas_ao_rolar_ate_o_topo() {
    let participants = vec![ready("front")];
    let records: Vec<ChatRecord> = (0..100).map(|i| turn_record("front", i)).collect();
    let mut view = ChatView::new("w");
    rebuild(&mut view, &participants, &records).expect("monta");
    assert_eq!(view.loaded_messages(), WINDOW_STEP);
    let initial = view.blocks().len();
    assert!(initial <= WINDOW_STEP * 3, "60 mensagens do fim, não 200");
    // O fim primeiro: a última pergunta está na janela, a primeira não.
    assert!(view.blocks().iter().any(|b| b.id == "p|u99"));
    assert!(!view.blocks().iter().any(|b| b.id == "p|u0"));

    assert!(view.load_more(true, false));
    assert_eq!(view.loaded_messages(), 2 * WINDOW_STEP);
    let update = rebuild(&mut view, &participants, &records).expect("o topo trouxe mais histórico");
    assert!(view.blocks().len() > initial);
    // Entrou coisa em cima: as linhas de antes continuam, só chegam inserts.
    assert!(
        update
            .ops
            .iter()
            .all(|op| matches!(op, BlockOp::Insert { .. } | BlockOp::Update { .. })),
        "{:?}",
        update.ops
    );
}

/// Abrir uma conversa de 300 turnos não pode trazer mais de uma janela: a descida
/// animada passando pelo topo não conta como "o usuário rolou até o começo".
#[test]
fn a_descida_animada_nao_carrega_mais() {
    let load = |near_top, descending, loading, total, loaded, has_rows| {
        ChatView::should_load_more(near_top, descending, loading, total, loaded, has_rows)
    };
    assert!(
        load(true, false, false, 100, 60, true),
        "no topo, com mais histórico: carrega"
    );
    assert!(
        !load(true, true, false, 100, 60, true),
        "a descida animada passando pelo topo não conta"
    );
    assert!(!load(false, false, false, 100, 60, true));
    assert!(!load(true, false, true, 100, 60, true));
    assert!(
        !load(true, false, false, 60, 60, true),
        "não há mais o que trazer"
    );
    assert!(!load(true, false, false, 100, 60, false));

    let participants = vec![ready("front")];
    let records: Vec<ChatRecord> = (0..300).map(|i| turn_record("front", i)).collect();
    let mut view = ChatView::new("w");
    assert!(
        !view.load_more(true, false),
        "sem linhas ainda: nada a carregar"
    );
    rebuild(&mut view, &participants, &records);
    assert!(!view.load_more(true, true), "descendo");
    assert_eq!(view.loaded_messages(), WINDOW_STEP);
    assert!(view.load_more(true, false));
    assert!(
        !view.load_more(true, false),
        "carregando: só uma janela por vez"
    );
    rebuild(&mut view, &participants, &records);
    assert!(
        view.load_more(true, false),
        "depois que a montagem chega, outra janela"
    );
}

fn step_record() -> ChatRecord {
    let mut turn = ChatTurn::new("u1", "faz", at(1_787_678_363.0), None);
    let mut run = ChatStep::new("$", "Roda");
    run.detail = Some("swift test".into());
    run.output = Some("ok".into());
    let mut edit = ChatStep::new("±", "a.swift");
    edit.diff = Some(vec!["@@ -1 +1 @@".into(), "-a".into(), "+b".into()]);
    turn.steps = vec![run.clone(), edit.clone()];
    turn.reply_text = "Pronto.".into();
    turn.parts = vec![
        ChatPart::Step(run),
        ChatPart::Step(edit),
        ChatPart::Text("Pronto.".into()),
    ];
    turn.reply_at = Some(at(1_787_678_365.0));
    ChatRecord::new("a", turn)
}

fn is_step(block: &ChatBlock, expanded: bool) -> bool {
    matches!(&block.kind, BlockKind::Step { expanded: e, .. } if *e == expanded)
}

#[test]
fn alternar_abre_o_passo_e_o_diff_continua_aberto() {
    let participants = vec![agent("a", Activity::Waiting)];
    let records = vec![step_record()];
    let mut view = ChatView::new("w");
    rebuild(&mut view, &participants, &records);

    let step = view
        .blocks()
        .iter()
        .find(|b| b.id == "b|u1|0")
        .expect("passo")
        .clone();
    assert!(is_step(&step, false));
    assert!(
        matches!(&view.blocks().iter().find(|b| b.id == "b|u1|1").expect("diff").kind,
        BlockKind::Diff { file, .. } if file == "a.swift"),
        "o diff nasce aberto"
    );

    view.toggle_step("b|u1|0");
    let update = rebuild(&mut view, &participants, &records).expect("o passo abriu");
    assert!(matches!(update.ops.as_slice(), [BlockOp::Update { block }] if block.id == "b|u1|0"));
    assert_eq!(
        view.expanded_steps(),
        &BTreeSet::from(["b|u1|0".to_owned()])
    );
    assert!(is_step(
        view.blocks()
            .iter()
            .find(|b| b.id == "b|u1|0")
            .expect("passo"),
        true
    ));
    assert!(
        matches!(
            &view
                .blocks()
                .iter()
                .find(|b| b.id == "b|u1|1")
                .expect("diff")
                .kind,
            BlockKind::Diff { .. }
        ),
        "o diff continua aberto"
    );

    view.toggle_step("b|u1|0");
    rebuild(&mut view, &participants, &records);
    assert!(view.expanded_steps().is_empty());
    view.toggle_step("não existe");
    assert!(
        view.expanded_steps().is_empty(),
        "id desconhecido não abre nada"
    );
}

fn group_record() -> ChatRecord {
    let mut turn = ChatTurn::new("u1", "faz", at(1_787_678_363.0), None);
    let steps: Vec<ChatStep> = [("um", "a", "1"), ("dois", "b", "2")]
        .iter()
        .map(|(text, detail, output)| {
            let mut s = ChatStep::new("$", text);
            s.detail = Some((*detail).into());
            s.output = Some((*output).into());
            s
        })
        .collect();
    turn.steps = steps.clone();
    turn.parts = steps
        .into_iter()
        .map(ChatPart::Step)
        .chain([ChatPart::Text("ok".into())])
        .collect();
    turn.reply_text = "ok".into();
    turn.reply_at = Some(at(1_787_678_365.0));
    ChatRecord::new("a", turn)
}

fn open_steps(view: &ChatView) -> Vec<String> {
    view.blocks()
        .iter()
        .filter(|b| is_step(b, true))
        .map(|b| b.id.clone())
        .collect()
}

/// O clique na capa avança o nível, e voltar ao resumo esquece o que estava
/// aberto lá dentro.
#[test]
fn clicar_na_capa_cicla_os_niveis() {
    let participants = vec![agent("a", Activity::Waiting)];
    let records = vec![group_record()];
    let mut view = ChatView::new("w");
    rebuild(&mut view, &participants, &records);
    assert!(view.blocks().iter().any(|b| b.id == "g|u1|0"));
    assert_eq!(
        view.blocks()
            .iter()
            .filter(|b| b.id.starts_with("b|"))
            .count(),
        1,
        "no resumo só a prosa acompanha a capa"
    );
    let level = |view: &ChatView| view.group_levels().get("g|u1|0").copied();

    view.toggle_step("g|u1|0");
    rebuild(&mut view, &participants, &records);
    assert_eq!(level(&view), Some(ChatGroupLevel::Titles));
    assert!(view.blocks().iter().any(|b| b.id == "b|u1|0"));

    // Sem nada aberto à mão, o clique aprofunda — e detalhar é abrir os passos de
    // verdade, não sobrescrevê-los.
    view.toggle_step("g|u1|0");
    rebuild(&mut view, &participants, &records);
    assert_eq!(level(&view), Some(ChatGroupLevel::Details));
    assert_eq!(open_steps(&view).len(), 2);
    assert_eq!(
        view.expanded_steps(),
        &BTreeSet::from(["b|u1|0".to_owned(), "b|u1|1".to_owned()])
    );

    // E cada um continua seu: clicar num passo aberto pela capa o fecha.
    view.toggle_step("b|u1|0");
    rebuild(&mut view, &participants, &records);
    assert_eq!(
        open_steps(&view),
        ["b|u1|1"],
        "o passo aberto pela capa fecha no clique"
    );

    view.toggle_step("g|u1|0");
    rebuild(&mut view, &participants, &records);
    assert_eq!(level(&view), Some(ChatGroupLevel::Summary));
    assert!(
        view.expanded_steps().is_empty(),
        "fechar a capa limpa o que estava aberto dentro"
    );
    assert!(!view.blocks().iter().any(|b| b.id == "b|u1|0"));
}

/// Abrir a capa, abrir um passo dentro dela e clicar na capa de novo: ela FECHA.
/// Aprofundar ali desfazia o que o usuário tinha acabado de abrir (ADR-053).
#[test]
fn a_capa_fecha_quando_um_passo_foi_aberto_a_mao() {
    let participants = vec![agent("a", Activity::Waiting)];
    let records = vec![group_record()];
    let mut view = ChatView::new("w");
    rebuild(&mut view, &participants, &records);

    view.toggle_step("g|u1|0");
    rebuild(&mut view, &participants, &records);
    view.toggle_step("b|u1|0");
    rebuild(&mut view, &participants, &records);
    assert!(view.expanded_steps().contains("b|u1|0"));

    view.toggle_step("g|u1|0");
    rebuild(&mut view, &participants, &records);
    assert_eq!(
        view.group_levels().get("g|u1|0"),
        Some(&ChatGroupLevel::Summary)
    );
    assert!(view.expanded_steps().is_empty());
}

/// Turno ao vivo: a bolha ganha a linha de status enquanto o agente trabalha, e
/// some quando o histórico traz o turno gravado.
#[test]
fn bolha_ao_vivo_ate_o_historico_gravar() {
    let participants = vec![agent("a", Activity::Working)];
    let mut live_turn = ChatTurn::new("u1", "faz", at(1_787_678_363.0), None);
    let mut step = ChatStep::new("$", "Roda");
    step.tool_id = Some("t1".into());
    live_turn.parts = vec![
        ChatPart::Text("Vou olhar.".into()),
        ChatPart::Step(step.clone()),
    ];
    live_turn.steps = vec![step];
    live_turn.reply_text = "Vou olhar.".into();
    live_turn.reply_at = Some(at(1_787_678_364.0));
    let live = BTreeMap::from([(
        "a".to_owned(),
        LiveTurn {
            turn: live_turn.clone(),
            last: Some(LastBlock::Tool),
            prompt_offset: 0,
        },
    )]);
    let mut view = ChatView::new("w");
    view.rebuild(&view_input(&participants, &[], &live))
        .expect("monta ao vivo");
    let last = view.blocks().last().expect("linha");
    assert_eq!(last.id, "s|u1");
    assert!(
        matches!(&last.kind, BlockKind::Status { live: ChatLive::Step { step }, .. } if step.text == "Roda")
    );
    assert!(
        !view.blocks().iter().any(|b| b.id.starts_with("t|")),
        "com turno ao vivo não há 'digitando'"
    );

    // Gravado: o histórico traz o mesmo turno, e a linha de status sai.
    let records = vec![ChatRecord::new("a", live_turn)];
    view.rebuild(&view_input(&participants, &records, &live))
        .expect("troca");
    assert!(!view.blocks().iter().any(|b| b.id == "s|u1"));

    // Pedido de permissão: laranja, sem spinner.
    let asking = vec![agent("a", Activity::Asking)];
    let mut again = ChatView::new("w");
    again.rebuild(&view_input(&asking, &[], &live));
    assert!(matches!(
        &again.blocks().last().expect("linha").kind,
        BlockKind::Status {
            live: ChatLive::Asking,
            ..
        }
    ));

    // Trabalhando e ainda sem nada gravado: bolha só de status.
    let mut quiet = ChatView::new("w");
    quiet.rebuild(&view_input(&participants, &[], &BTreeMap::new()));
    assert_eq!(
        quiet
            .blocks()
            .iter()
            .map(|b| b.id.as_str())
            .collect::<Vec<_>>(),
        ["t|a"]
    );
}

#[test]
fn estado_da_rota_de_conferencia() {
    let participants = vec![agent("a", Activity::Waiting)];
    let mut view = ChatView::new("w");
    view.sent("pendente", "a", at(1_787_678_999.0), BTreeSet::new());
    rebuild(&mut view, &participants, &[step_record()]);
    let state = view.route_snapshot();
    assert_eq!(state["pending"], 1);
    let blocks = state["blocks"].as_array().expect("blocos");
    assert!(
        blocks
            .iter()
            .any(|b| b["id"] == "b|u1|0" && b["kind"] == "step" && b["expanded"] == false)
    );
    let messages = state["messages"].as_array().expect("mensagens");
    let reply = messages
        .iter()
        .find(|m| m["kind"] == "reply")
        .expect("resposta");
    assert_eq!(reply["steps"], json!(["$ Roda", "± a.swift"]));
    assert_eq!(reply["chain"][0], "$ Roda ⎿ 1 linha");
    assert_eq!(reply["chain"][1], "± a.swift (+1 −1)");
    assert_eq!(reply["chain"][2], "¶ Pronto.");
    assert!(
        messages
            .iter()
            .any(|m| m["kind"] == "pending" && m["to"] == "a")
    );
}

// ===========================================================================
// O contrato do diff de blocos (canal /ui)
// ===========================================================================

fn sample_blocks() -> Vec<ChatBlock> {
    let front = agent("front", Activity::Working);
    let mut turn = block_turn();
    turn.usage = {
        let mut usage = crate::features::usage::UsageByPrice::new();
        crate::features::usage::add_entry(
            &mut usage,
            &crate::features::usage::prices::entry(
                "m1",
                "claude-opus-5-5",
                TokenUsage {
                    output: 1_000_000,
                    ..TokenUsage::default()
                },
            ),
            &PRICES,
        );
        usage
    };
    let mut asked = ChatMessage::prompt(&front, "f2", "cita a anterior", at(1_020.0));
    if let ChatMessage::Prompt { from, .. } = &mut asked {
        *from = Some("back".into());
    }
    let mut messages = vec![
        ChatMessage::prompt(&front, "u1", "faz", at(1_000.0)),
        ChatMessage::reply(&front, turn),
        asked,
        ChatMessage::Pending {
            to: front.clone(),
            text: "eco".into(),
            at: at(1_030.0),
            quote: None,
        },
    ];
    messages = ChatMessage::quoting(&messages);
    let live = BTreeMap::from([(
        "front".to_owned(),
        LiveStatus {
            turn_id: "u1".into(),
            status: ChatLive::Thinking,
        },
    )]);
    let mut rows = build_blocks(
        &messages,
        &live,
        &[ready("back")],
        &BTreeSet::from(["b|u1|3".to_owned()]),
        &BTreeMap::new(),
    );
    let group = group_turn();
    rows.extend(build_blocks(
        &[ChatMessage::reply(&front, group)],
        &BTreeMap::new(),
        &[],
        &BTreeSet::new(),
        &BTreeMap::new(),
    ));
    rows
}

#[test]
fn o_json_de_um_bloco_e_o_contrato() {
    let rows = sample_blocks();
    let step = rows.iter().find(|b| b.id == "b|u1|3").expect("passo");
    let value = serde_json::to_value(step).expect("json");
    assert_eq!(
        value,
        json!({
            "id": "b|u1|3", "messageKey": "r|u1", "kind": "step", "first": false, "last": false, "depth": 0,
            "from": {"id": "front", "address": "deck/front", "isAgent": true, "role": null},
            "step": {"glyph": "$", "text": "Roda", "detail": "swift test", "isError": false},
            "expanded": true
        })
    );
    let header = serde_json::to_value(rows.iter().find(|b| b.id == "h|u1").expect("cabeçalho"))
        .expect("json");
    assert_eq!(header["kind"], "header");
    assert_eq!(header["at"], Value::Null, "ao vivo é agora");
    assert_eq!(header["cost"]["text"], "US$ 20,00");
    let prompt =
        serde_json::to_value(rows.iter().find(|b| b.id == "p|f2").expect("prompt")).expect("json");
    assert_eq!(prompt["at"], "1970-01-01T00:17:00.000Z");
    assert_eq!(prompt["from"], "back");
    assert_eq!(prompt["to"]["id"], "front");
    let prose =
        serde_json::to_value(rows.iter().find(|b| b.id == "b|u1|0").expect("prosa")).expect("json");
    assert_eq!(prose["blocks"][0]["kind"], "paragraph");
    let status =
        serde_json::to_value(rows.iter().find(|b| b.id == "s|u1").expect("status")).expect("json");
    assert_eq!(status["live"], json!({"state": "thinking"}));
    // Todo bloco volta do JSON igual.
    for block in &rows {
        let back: ChatBlock =
            serde_json::from_value(serde_json::to_value(block).expect("json")).expect("volta");
        assert_eq!(&back, block, "{}", block.id);
    }
}

fn changed(mut block: ChatBlock, last: bool) -> ChatBlock {
    block.last = last;
    block
}

#[test]
fn diff_de_blocos_reconstroi_a_lista_nova() {
    let rows = sample_blocks();
    assert!(diff_blocks(&rows, &rows).is_empty(), "nada mudou, nada vai");

    // Primeira entrega: recarga inteira.
    let first = diff_blocks(&[], &rows);
    assert!(matches!(first.as_slice(), [BlockOp::Reset { blocks }] if blocks == &rows));

    // Linha nova no fim, uma mudada e uma removida: remove, insert, update.
    let mut next = rows.clone();
    let removed = next.remove(2).id;
    let updated = next[0].id.clone();
    next[0] = changed(next[0].clone(), !next[0].last);
    let extra = changed(rows[0].clone(), true);
    next.push(ChatBlock {
        id: "novo".into(),
        ..extra
    });
    let ops = diff_blocks(&rows, &next);
    assert!(
        matches!(&ops[0], BlockOp::Remove { id } if *id == removed),
        "{ops:?}"
    );
    assert!(ops.iter().any(|op| matches!(op, BlockOp::Insert { index, block } if *index == next.len() - 1 && block.id == "novo")));
    assert!(
        ops.iter()
            .any(|op| matches!(op, BlockOp::Update { block } if block.id == updated))
    );
    let mut applied = rows.clone();
    apply_ops(&mut applied, &ops);
    assert_eq!(applied, next);

    // Ordem dos ids comuns mudou (a resposta ao vivo muda de hora): recarga.
    let mut swapped = rows.clone();
    swapped.swap(0, 3);
    let ops = diff_blocks(&rows, &swapped);
    assert!(matches!(ops.as_slice(), [BlockOp::Reset { .. }]));
    let mut applied = rows.clone();
    apply_ops(&mut applied, &ops);
    assert_eq!(applied, swapped);

    // Inserts no meio entram pelo índice da lista FINAL, em ordem crescente.
    let mut grown = rows.clone();
    grown.insert(
        1,
        ChatBlock {
            id: "a".into(),
            ..rows[3].clone()
        },
    );
    grown.insert(
        4,
        ChatBlock {
            id: "b".into(),
            ..rows[3].clone()
        },
    );
    let ops = diff_blocks(&rows, &grown);
    let indexes: Vec<usize> = ops
        .iter()
        .filter_map(|op| match op {
            BlockOp::Insert { index, .. } => Some(*index),
            _ => None,
        })
        .collect();
    assert_eq!(indexes, [1, 4]);
    let mut applied = rows;
    apply_ops(&mut applied, &ops);
    assert_eq!(applied, grown);
}

#[test]
fn o_evento_do_canal_ui_e_uma_linha_ndjson() {
    let participants = vec![agent("a", Activity::Waiting)];
    let mut view = ChatView::new("w1");
    let update = rebuild(&mut view, &participants, &[step_record()]).expect("monta");
    let line = serde_json::to_string(&update).expect("json");
    assert!(!line.contains('\n'));
    let value: Value = serde_json::from_str(&line).expect("lê");
    assert_eq!(value["topic"], "chat/w1");
    assert_eq!(value["workbench"], "w1");
    assert_eq!(value["rev"], 1);
    assert_eq!(value["ops"][0]["op"], "reset");
    let back: super::view::ChatUpdate = serde_json::from_str(&line).expect("volta");
    assert_eq!(back, update);
    assert_eq!(view.snapshot()["rev"], 1);
    assert_eq!(
        view.snapshot()["blocks"].as_array().map(Vec::len),
        Some(view.blocks().len())
    );
}

/// Fixtures de contrato lidas pelo Dart: a lista de blocos de cada kind e os
/// diffs que a UI aplica. `EGEON_UPDATE_FIXTURES=1 cargo test chat::tests::fixtures`
/// as regrava; sem a variável o teste só confere que o arquivo em disco é o que o
/// código gera hoje.
#[test]
fn fixtures_do_contrato_do_dart() {
    let rows = sample_blocks();
    let mut shorter = rows.clone();
    shorter.remove(2);
    shorter[0] = changed(shorter[0].clone(), !shorter[0].last);
    let mut longer = rows.clone();
    longer.insert(
        1,
        ChatBlock {
            id: "novo|meio".into(),
            ..rows[3].clone()
        },
    );
    longer.push(ChatBlock {
        id: "novo|fim".into(),
        ..rows[3].clone()
    });
    let mut reordered = rows.clone();
    reordered.swap(0, 3);

    let scenario = |name: &str, old: &[ChatBlock], new: &[ChatBlock]| json!({"name": name, "old": old, "new": new, "ops": diff_blocks(old, new)});
    let diffs = json!({"scenarios": [
        scenario("primeira entrega", &[], &rows),
        scenario("nada mudou", &rows, &rows),
        scenario("remove e atualiza", &rows, &shorter),
        scenario("insere no meio e no fim", &rows, &longer),
        scenario("ordem trocada recarrega", &rows, &reordered),
        scenario("limpar a conversa", &rows, &[]),
    ]});
    let blocks = json!({"blocks": rows});
    let mut envelope = ChatView::new("w1");
    let bar = envelope
        .set_participants(vec![
            agent("front", Activity::Working).info(),
            agent("back", Activity::Waiting).info(),
        ])
        .expect("barra");
    let working = ChatQueue {
        id: "fila1".into(),
        pending: 2,
        asking: false,
        working_with: Some("front".into()),
    };
    let asking = ChatQueue {
        id: "fila2".into(),
        pending: 1,
        asking: true,
        working_with: None,
    };
    let queue_one = envelope
        .set_queues(vec![(&working).into()])
        .expect("uma fila");
    let queue_two = envelope
        .set_queues(vec![(&working).into(), (&asking).into()])
        .expect("duas filas");
    let tray = envelope
        .set_permission(Some(
            json!({"id": "p1", "tool": "Bash", "detail": "rm -rf x"}),
        ))
        .expect("bandeja");
    let closed = envelope.set_permission(None).expect("bandeja fechada");
    let events = json!({"topic": "chat/w1", "events": [bar, queue_one, queue_two, tray, closed], "subscribe": envelope.reset_update()});

    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("fixtures/chat");
    for (name, value) in [
        ("blocks.json", blocks),
        ("diffs.json", diffs),
        ("events.json", events),
    ] {
        let file = dir.join(name);
        let canonical = crate::features::json_file::canonical(value);
        if std::env::var_os("EGEON_UPDATE_FIXTURES").is_some() || !file.exists() {
            fs::create_dir_all(&dir).expect("pasta");
            let mut text = serde_json::to_string_pretty(&canonical).expect("json");
            text.push('\n');
            fs::write(&file, text).expect("grava");
        }
        let on_disk: Value = serde_json::from_slice(&fs::read(&file).expect("lê")).expect("json");
        assert_eq!(
            on_disk, canonical,
            "{name} está velho: rode com EGEON_UPDATE_FIXTURES=1"
        );
    }
}

// ===========================================================================
// O envelope do canal (decisão 29): tópico por bancada, participantes, permissão
// ===========================================================================

fn infos(list: &[ChatParticipant]) -> Vec<super::thread::ParticipantInfo> {
    list.iter().map(ChatParticipant::info).collect()
}

#[test]
fn o_topico_e_por_bancada_e_a_barra_e_a_bandeja_tem_ops_proprios() {
    let mut view = ChatView::new("w1");
    assert_eq!(view.topic(), "chat/w1");

    let list = infos(&[
        agent("front", Activity::Working),
        agent("back", Activity::Waiting),
    ]);
    let update = view.set_participants(list.clone()).expect("a barra mudou");
    assert_eq!(update.topic, "chat/w1");
    assert_eq!(update.rev, 1);
    let value = serde_json::to_value(&update).expect("json");
    assert_eq!(value["ops"][0]["op"], "participants");
    assert_eq!(
        value["ops"][0]["list"][0],
        json!({"id": "front", "address": "deck/front", "isAgent": true, "role": null, "activity": "working",
               "needsAttention": false})
    );
    assert_eq!(value["ops"][0]["list"][1]["tone"], "green");
    assert!(view.set_participants(list).is_none(), "igual: nada vai");
    let busy = infos(&[
        agent("front", Activity::Waiting),
        agent("back", Activity::Waiting),
    ]);
    assert_eq!(view.set_participants(busy).expect("estado mudou").rev, 2);

    let ask = json!({"id": "p1", "tool": "Bash", "detail": "rm -rf x"});
    let update = view.set_permission(Some(ask.clone())).expect("pedido novo");
    assert_eq!(
        serde_json::to_value(&update.ops).expect("json"),
        json!([{"op": "permission", "request": ask}])
    );
    assert!(view.set_permission(Some(ask)).is_none());
    let closed = view.set_permission(None).expect("fechou");
    assert_eq!(
        serde_json::to_value(&closed.ops).expect("json"),
        json!([{"op": "permission", "request": null}])
    );
    assert_eq!(closed.rev, 4);
}

/// Na assinatura (e em `rev` perdido) chega tudo: blocos, barra e bandeja.
#[test]
fn a_assinatura_leva_blocos_barra_e_bandeja() {
    let participants = vec![agent("a", Activity::Waiting)];
    let mut view = ChatView::new("w1");
    rebuild(&mut view, &participants, &[step_record()]);
    view.set_participants(infos(&participants));
    view.set_permission(Some(json!({"id": "p1"})));
    let reset = view.reset_update();
    assert_eq!(reset.topic, "chat/w1");
    assert_eq!(reset.rev, view.rev());
    let kinds: Vec<&str> = reset
        .ops
        .iter()
        .map(|op| match op {
            BlockOp::Reset { .. } => "reset",
            BlockOp::Participants { .. } => "participants",
            BlockOp::Queues { .. } => "queues",
            BlockOp::Permission { .. } => "permission",
            _ => "outro",
        })
        .collect();
    assert_eq!(kinds, ["reset", "participants", "queues", "permission"]);
    let snapshot = view.snapshot();
    assert_eq!(snapshot["participants"][0]["id"], "a");
    assert_eq!(snapshot["permission"], json!({"id": "p1"}));
    let back: super::view::ChatUpdate =
        serde_json::from_str(&serde_json::to_string(&reset).expect("json")).expect("volta");
    assert_eq!(back, reset);
}

#[test]
fn comandos_do_canal_chegam_aos_handlers() {
    use super::routes::{ChatEffect, ChatRoutes};
    let dir = temp();
    let mut routes = ChatRoutes::new(ChatHistory::new(dir.path().to_path_buf(), utc));
    routes.register("w1", "deck", "chat");
    let participants = vec![
        agent("front", Activity::Waiting),
        agent("back", Activity::Dead),
    ];
    let effects = routes.set_participants("w1", participants.clone());
    assert!(matches!(effects.as_slice(), [ChatEffect::Ui(u)] if u.topic == "chat/w1"));
    assert!(
        routes
            .set_participants("w1", participants.clone())
            .is_empty(),
        "sem mudança, sem evento"
    );

    // chat_send: só para quem está vivo; texto vazio não vai.
    let to = vec![
        "front".to_owned(),
        "back".to_owned(),
        "nao-existe".to_owned(),
    ];
    let sends = routes.send("w1", &to, "  olha isso  ");
    assert_eq!(
        sends,
        [ChatEffect::Send {
            workbench: "w1".into(),
            target: "front".into(),
            text: "olha isso".into()
        }]
    );
    assert!(routes.send("w1", &to, "   ").is_empty());
    assert!(
        routes.send("w9", &to, "oi").is_empty(),
        "bancada desconhecida"
    );

    // chat_step / chat_more só pedem remontagem quando mudam algo.
    assert!(routes.step("w1", "nao existe").is_empty());
    {
        let live = BTreeMap::new();
        let records = vec![step_record_for("front")];
        routes
            .view_mut("w1")
            .expect("view")
            .rebuild(&view_input(&participants, &records, &live));
    }
    assert_eq!(
        routes.step("w1", "b|u1|0"),
        [ChatEffect::Rebuild {
            workbench: "w1".into()
        }]
    );
    assert!(
        routes.more("w1").is_empty(),
        "não há mais histórico que a janela"
    );

    // chat_snapshot e a assinatura.
    assert_eq!(
        routes.snapshot_of("w1").expect("retrato")["rev"],
        routes.view("w1").expect("view").rev()
    );
    assert!(routes.snapshot_of("w9").is_none());
    assert_eq!(routes.reset_update("w1").expect("reset").topic, "chat/w1");

    // chat_clear: arquiva (aqui não havia conversa) e esvazia a thread.
    let (archived, effects) = routes.clear("w1", at(9_000.0)).expect("bancada");
    assert!(archived.is_none());
    assert!(matches!(effects.as_slice(), [ChatEffect::Ui(u)] if u.topic == "chat/w1"));
    assert!(routes.clear("w9", at(9_000.0)).is_none());
    assert!(routes.view("w1").expect("view").blocks().is_empty());

    // permission_answer vai para o dispatch; a bandeja do chat só espelha o pedido.
    let ask = json!({"id": "p1"});
    assert!(matches!(
        routes.set_permission("w1", Some(ask)).as_slice(),
        [ChatEffect::Ui(_)]
    ));
    assert!(matches!(
        routes.set_permission("w1", None).as_slice(),
        [ChatEffect::Ui(_)]
    ));
}

fn step_record_for(node: &str) -> ChatRecord {
    let mut record = step_record();
    record.node = node.to_owned();
    record
}

/// O fuso é o de CADA data: com horário de verão, o mesmo relógio de parede cai em
/// instantes diferentes no inverno e no verão, e o nome do arquivo volta ao instante
/// certo nos dois.
#[test]
fn o_relogio_do_nome_usa_o_fuso_de_cada_data() {
    // Nova York: -5 h no inverno (até 2026-03-08), -4 h no verão.
    fn new_york(at: SystemTime) -> i64 {
        let secs = at
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_secs());
        if (1_773_000_000..1_793_000_000).contains(&secs) {
            -4 * 3600
        } else {
            -5 * 3600
        }
    }
    let winter = parse_iso("2026-01-15T17:00:00Z").expect("data");
    let summer = parse_iso("2026-07-15T17:00:00Z").expect("data");
    assert_eq!(format_clock(winter, new_york(winter)), "20260115-120000");
    assert_eq!(format_clock(summer, new_york(summer)), "20260715-130000");
    assert_eq!(parse_clock("20260115-120000", new_york), Some(winter));
    assert_eq!(parse_clock("20260715-130000", new_york), Some(summer));
}

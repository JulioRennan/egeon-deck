//! As respostas das rotas, com as chaves e os textos do `ControlSocket.swift`.

use std::collections::HashMap;
use std::path::Path;
use std::time::{Duration, SystemTime};

use serde_json::json;

use super::coordination::{Coordination, Outward, World};
use super::marker::{LastMarker, MarkerConfig};
use super::profile::TargetProfile;
use super::routes;
use super::target::Surface;
use crate::features::activity::model::Activity;
use crate::features::edge::model::EdgeConfig;
use crate::features::node::model::{NodeConfig, NodeKind};
use crate::features::permission::routes as permission;
use crate::features::workbench::model::WorkbenchConfig;
use crate::protocol::handler::RouteRequest;

struct Bench {
    bench: WorkbenchConfig,
    active: bool,
}

impl Surface for Bench {
    fn running(&self, _: &str) -> bool {
        true
    }
    fn focused(&self, _: &str) -> bool {
        false
    }
    fn peek(&self, _: &str, _: usize) -> Vec<String> {
        Vec::new()
    }
    fn last_marker(&self, _: &Path, _: &MarkerConfig) -> Option<LastMarker> {
        None
    }
}

impl World for Bench {
    fn workbench(&self, name: &str) -> Option<WorkbenchConfig> {
        (self.bench.name == name).then(|| self.bench.clone())
    }
    fn app_active(&self) -> bool {
        self.active
    }
    fn notifier_authorized(&self) -> bool {
        true
    }
}

fn agent(id: &str, maestro: bool) -> NodeConfig {
    let mut n = NodeConfig::new(NodeKind::Agent, id);
    n.agent = Some("claude".into());
    n.maestro = maestro.then_some(true);
    n
}

/// `deck`: maestro, `a` e `b` ligados nos dois sentidos, e o shell `sh`.
fn world() -> Bench {
    let mut a = agent("a", false);
    a.prompt = Some("Revisa.".into());
    let mut bench = WorkbenchConfig::new(
        "deck",
        "/tmp",
        vec![
            agent("m", true),
            a,
            agent("b", false),
            NodeConfig::new(NodeKind::Shell, "sh"),
        ],
    );
    bench.edges = Some(vec![
        EdgeConfig::with_default_limit("a", "b"),
        EdgeConfig::with_default_limit("b", "a"),
    ]);
    Bench {
        bench,
        active: false,
    }
}

fn t(ms: u64) -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(1_800_000_000) + Duration::from_millis(ms)
}

fn state() -> Coordination {
    let mut c = Coordination::new();
    for id in ["m", "a", "b"] {
        c.register(
            format!("deck/{id}"),
            Some(TargetProfile::new("Claude Code")),
            true,
            t(0),
        );
    }
    c.register("deck/sh", None, false, t(0));
    c
}

fn req(method: &str, target: &str, body: &[u8], origin: Option<&str>) -> RouteRequest {
    let (path, raw) = target.split_once('?').unwrap_or((target, ""));
    let query: HashMap<String, String> = raw
        .split('&')
        .filter_map(|p| p.split_once('='))
        .map(|(k, v)| (k.to_owned(), v.replace("%2F", "/")))
        .collect();
    RouteRequest {
        method: method.into(),
        target: target.into(),
        path: path.into(),
        query,
        body: body.to_vec(),
        origin: origin.map(str::to_owned),
    }
}

#[test]
fn targets_lists_the_living_twice() {
    let (reply, _) = routes::targets(
        &mut state(),
        &req("GET", "/targets", b"", None),
        t(0),
        &world(),
    );
    let all = json!(["deck/a", "deck/b", "deck/m", "deck/sh"]);
    assert_eq!(reply.json, json!({"targets": all, "all": all}));
}

#[test]
fn dispatch_reads_json_and_answers_with_detail() {
    let (mut s, w) = (state(), world());
    let ok = routes::dispatch(
        &mut s,
        &req(
            "POST",
            "/dispatch",
            br#"{"target":"deck/a","text":"oi"}"#,
            None,
        ),
        t(0),
        &w,
    )
    .0;
    assert_eq!(ok.status, 200);
    assert_eq!(
        ok.json,
        json!({"ok": true, "detail": "enfileirado para deck/a; 1 na fila"})
    );
    let bad = routes::dispatch(&mut s, &req("POST", "/dispatch", b"{", None), t(0), &w).0;
    assert_eq!(
        (bad.status, bad.json),
        (400, json!({"ok": false, "error": "json inválido"}))
    );
    let unknown = routes::dispatch(
        &mut s,
        &req("POST", "/dispatch", br#"{"target":"x"}"#, None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(unknown.status, 404);
    assert!(
        unknown.json["error"]
            .as_str()
            .unwrap()
            .starts_with("alvo desconhecido 'x'")
    );
}

#[test]
fn message_from_an_agent_goes_through_the_edges() {
    let (mut s, w) = (state(), world());
    let ok = routes::message(
        &mut s,
        &req("POST", "/message?target=b", b"revisa\n", Some("deck/a")),
        t(0),
        &w,
    )
    .0;
    assert_eq!(
        ok.json["detail"],
        "enfileirado para deck/b; 1 na fila; envio 1/2"
    );
    let refused = routes::message(
        &mut s,
        &req("POST", "/message?target=sh", b"ls", Some("deck/a")),
        t(0),
        &w,
    )
    .0;
    assert_eq!(refused.status, 404);
    assert_eq!(
        refused.json["error"],
        "não existe ligação de deck/a para deck/sh — desenhe a aresta no canvas"
    );
}

/// O maestro alcança todos sem aresta desenhada, e a volta não tem limite.
#[test]
fn maestro_reaches_everyone_through_the_implicit_links() {
    let (mut s, w) = (state(), world());
    let to_shell = routes::message(
        &mut s,
        &req("POST", "/message?target=sh", b"npm test", Some("deck/m")),
        t(0),
        &w,
    )
    .0;
    assert_eq!(
        to_shell.json["detail"],
        "enfileirado para deck/sh; 1 na fila; envio 1/∞"
    );
    let back = routes::message(
        &mut s,
        &req("POST", "/message?target=m", b"feito", Some("deck/b")),
        t(0),
        &w,
    )
    .0;
    assert_eq!(back.json["ok"], true);
}

#[test]
fn peers_are_the_callers_with_role() {
    let (mut s, w) = (state(), world());
    let (reply, _) = routes::peers(&mut s, &req("GET", "/peers", b"", Some("deck/b")), t(0), &w);
    assert_eq!(
        reply.json,
        json!({"peers": [
            {"address": "deck/a", "cli": "Claude Code", "role": "Revisa."},
            {"address": "deck/m", "cli": "Claude Code"},
        ]})
    );
    let (yours, _) = routes::peers(&mut s, &req("GET", "/peers", b"", None), t(0), &w);
    assert_eq!(yours.json, json!({"peers": []}));
}

#[test]
fn activity_validates_the_event_and_the_caller() {
    let (mut s, w) = (state(), world());
    let missing = routes::activity(
        &mut s,
        &req("POST", "/activity", b"", Some("deck/a")),
        t(0),
        &w,
    )
    .0;
    assert_eq!(
        (missing.status, missing.json["error"].clone()),
        (400, json!("event é obrigatório"))
    );
    let unknown = routes::activity(
        &mut s,
        &req("POST", "/activity?event=recap", b"", Some("deck/a")),
        t(0),
        &w,
    )
    .0;
    assert_eq!(
        unknown.json["error"],
        "evento desconhecido 'recap'; use stop|prompt|ask|start|failure"
    );
    let stranger = routes::activity(
        &mut s,
        &req("POST", "/activity?event=stop", b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(stranger.status, 403);
    assert_eq!(
        stranger.json["error"],
        "esta conexão não veio de um terminal"
    );
    // O `target` da query vale como reserva.
    let named = routes::activity(
        &mut s,
        &req("POST", "/activity?event=start&target=deck%2Fa", b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(named.json, json!({"ok": true}));
}

#[test]
fn stop_with_ask_calls_you_with_notice_and_no_double_sound() {
    let (mut s, w) = (state(), world());
    routes::activity(
        &mut s,
        &req("POST", "/activity?event=prompt", b"", Some("deck/a")),
        t(5_000),
        &w,
    );
    let (_, out) = routes::activity(
        &mut s,
        &req(
            "POST",
            "/activity?event=stop&last=[[ED:ask]]",
            b"",
            Some("deck/a"),
        ),
        t(6_000),
        &w,
    );
    let notices: Vec<_> = out
        .iter()
        .filter_map(|o| match o {
            Outward::Notify(n) => Some(n.title.clone()),
            _ => None,
        })
        .collect();
    assert_eq!(notices, ["A bancada deck precisa de você"]);
    assert!(
        !out.iter().any(|o| matches!(o, Outward::Sound { .. })),
        "a central toca o dela"
    );
    assert!(out.iter().any(|o| matches!(o, Outward::TurnEnded { .. })));
    assert_eq!(
        *s.dispatcher.target("deck/a").unwrap().activity(),
        Activity::Asking
    );
}

#[test]
fn conversation_records_then_opens_the_turn() {
    let (mut s, w) = (state(), world());
    let no_id = routes::conversation(
        &mut s,
        &req("POST", "/conversation", b"", Some("deck/a")),
        t(0),
        &w,
    )
    .0;
    assert_eq!(
        (no_id.status, no_id.json),
        (400, json!({"ok": false, "error": "id é obrigatório"}))
    );
    let (ok, out) = routes::conversation(
        &mut s,
        &req(
            "POST",
            "/session?id=abc&transcript=/tmp/t.jsonl",
            b"",
            Some("deck/a"),
        ),
        t(0),
        &w,
    );
    assert_eq!(ok.json, json!({"ok": true}));
    assert_eq!(
        out[0],
        Outward::Conversation {
            address: "deck/a".into(),
            id: "abc".into(),
            transcript: Some("/tmp/t.jsonl".into())
        }
    );
    let forbidden = routes::conversation(
        &mut s,
        &req("POST", "/conversation?id=x", b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(forbidden.status, 403);
}

#[test]
fn retry_without_a_schedule_is_a_conflict() {
    let (mut s, w) = (state(), world());
    let reply = routes::retry(
        &mut s,
        &req("POST", "/retry?target=deck%2Fa&now=1", b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(reply.status, 409);
    assert_eq!(
        reply.json["error"],
        "nenhuma tentativa agendada em 'deck/a'"
    );
    routes::activity(
        &mut s,
        &req(
            "POST",
            "/activity?event=failure&error=overloaded",
            b"",
            Some("deck/a"),
        ),
        t(0),
        &w,
    );
    let ok = routes::retry(
        &mut s,
        &req("POST", "/retry?target=deck%2Fa", b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(ok.json, json!({"ok": true}));
}

const BASH: &[u8] = br#"{"tool_name":"Bash","tool_input":{"command":"rm -rf build"},"permission_suggestions":[{"type":"addRules"}]}"#;

#[test]
fn permission_round_trip_and_the_maestro_is_told() {
    let (mut s, w) = (state(), world());
    let stranger = permission::open(&mut s, &req("POST", "/permission", BASH, None), t(0), &w).0;
    assert_eq!(stranger.status, 403);
    let no_tool = permission::open(
        &mut s,
        &req("POST", "/permission", b"[]", Some("deck/a")),
        t(0),
        &w,
    )
    .0;
    assert_eq!(
        (no_tool.status, no_tool.json["error"].clone()),
        (400, json!("payload sem tool_name"))
    );

    let opened = permission::open(
        &mut s,
        &req("POST", "/permission", BASH, Some("deck/a")),
        t(0),
        &w,
    )
    .0;
    let id = opened.json["id"].as_str().unwrap().to_owned();
    assert_eq!(opened.json["ok"], true);
    assert_eq!(
        s.dispatcher.target("deck/m").unwrap().pending(),
        1,
        "o aviso entrou na fila do maestro"
    );

    let list = permission::list(&mut s, &req("GET", "/permissions", b"", None), t(0), &w).0;
    assert_eq!(list.json["open"][0]["address"], "deck/a");
    assert_eq!(list.json["open"][0]["always"], true);

    let pending = permission::poll(
        &mut s,
        &req("GET", &format!("/permission?id={id}"), b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(pending.json, json!({"state": "pending"}));

    let bad = permission::answer(
        &mut s,
        &req("POST", "/permission/answer?id=x", b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(bad.status, 400);
    let gone = permission::answer(
        &mut s,
        &req("POST", "/permission/answer?id=zz&answer=allow", b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(gone.status, 404);
    assert_eq!(
        gone.json["error"],
        "pedido zz já acabou, ou escolha fora das opções"
    );

    let ok = permission::answer(
        &mut s,
        &req(
            "POST",
            &format!("/permission/answer?id={id}&answer=always"),
            b"",
            None,
        ),
        t(0),
        &w,
    )
    .0;
    assert_eq!(ok.json, json!({"ok": true}));
    let answered = permission::poll(
        &mut s,
        &req("GET", &format!("/permission?id={id}"), b"", None),
        t(0),
        &w,
    )
    .0;
    assert_eq!(answered.json["state"], "answered");
    assert_eq!(
        answered.json["output"]["hookSpecificOutput"]["decision"]["updatedPermissions"],
        json!([{"type": "addRules"}])
    );
}

#[test]
fn question_is_answered_by_choice_or_body() {
    let (mut s, w) = (state(), world());
    let payload = br#"{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Qual?","options":[{"label":"A"},{"label":"B"}]}]}}"#;
    let id = permission::open(
        &mut s,
        &req("POST", "/permission", payload, Some("deck/a")),
        t(0),
        &w,
    )
    .0
    .json["id"]
        .as_str()
        .unwrap()
        .to_owned();
    assert_eq!(
        s.dispatcher.target("deck/m").unwrap().pending(),
        0,
        "pergunta é para você"
    );
    let off = permission::answer(
        &mut s,
        &req(
            "POST",
            &format!("/permission/answer?id={id}&choice=C"),
            b"",
            None,
        ),
        t(0),
        &w,
    )
    .0;
    assert_eq!(off.status, 404);
    let by_body = permission::answer(
        &mut s,
        &req(
            "POST",
            &format!("/permission/answer?id={id}"),
            br#"{"answers":{"Qual?":"B"}}"#,
            None,
        ),
        t(0),
        &w,
    )
    .0;
    assert_eq!(by_body.json, json!({"ok": true}));
}

#[test]
fn question_by_choice_and_answer_withdraws_with_the_turn_in_flight() {
    let (mut s, w) = (state(), world());
    routes::activity(
        &mut s,
        &req("POST", "/activity?event=prompt", b"", Some("deck/a")),
        t(5_000),
        &w,
    );
    routes::activity(
        &mut s,
        &req("POST", "/activity?event=ask", b"", Some("deck/a")),
        t(5_100),
        &w,
    );
    assert_eq!(
        *s.dispatcher.target("deck/a").unwrap().activity(),
        Activity::Asking
    );
    let payload = br#"{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Qual?","options":[{"label":"A"},{"label":"B"}]}]}}"#;
    let id = permission::open(
        &mut s,
        &req("POST", "/permission", payload, Some("deck/a")),
        t(5_200),
        &w,
    )
    .0
    .json["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (ok, out) = permission::answer(
        &mut s,
        &req(
            "POST",
            &format!("/permission/answer?id={id}&choice=B"),
            b"",
            None,
        ),
        t(5_300),
        &w,
    );
    assert_eq!(ok.json, json!({"ok": true}));
    assert_eq!(
        *s.dispatcher.target("deck/a").unwrap().activity(),
        Activity::Working
    );
    assert_eq!(
        out,
        [Outward::Withdraw {
            identifier: "egeon.deck/a".into()
        }]
    );
    let answered = permission::poll(
        &mut s,
        &req("GET", &format!("/permission?id={id}"), b"", None),
        t(5_300),
        &w,
    )
    .0;
    assert_eq!(
        answered.json["output"]["hookSpecificOutput"]["decision"]["updatedInput"]["answers"],
        json!({"Qual?": "B"})
    );
}

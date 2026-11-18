//! Porte de `PermissionDeskTests.swift` (sem o teste do system prompt, que é
//! do perfil do agente).

use std::collections::HashMap;
use std::time::{Duration, SystemTime};

use serde_json::{Map, Value, json};

use super::model::{PermissionAnswer, PermissionAsk};
use super::service::{LIFETIME, PermissionDesk, PermissionState};

fn now() -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(1000)
}

fn payload() -> Value {
    json!({
        "tool_name": "Bash",
        "tool_input": {"command": "touch x.txt", "description": "Cria x.txt"},
        "permission_suggestions": [
            {"type": "addDirectories", "directories": ["/tmp/w"], "destination": "session"},
            {"type": "setMode", "mode": "acceptEdits", "destination": "session"},
        ],
    })
}

fn ask(payload: &Value) -> PermissionAsk {
    PermissionAsk::from_payload("p1", "deck/back", payload, now()).unwrap()
}

fn input(v: Value) -> Map<String, Value> {
    v.as_object().cloned().unwrap()
}

#[test]
fn ask_reads_tool_summary_and_detail() {
    let ask = ask(&payload());
    assert_eq!(ask.tool, "Bash");
    assert_eq!(ask.summary, "touch x.txt");
    assert_eq!(ask.detail.as_deref(), Some("Cria x.txt"));
}

#[test]
fn set_mode_suggestion_is_dropped() {
    let ask = ask(&payload());
    assert_eq!(ask.suggestions.len(), 1);
    assert_eq!(ask.suggestions[0]["type"], "addDirectories");
    assert!(ask.can_always_allow());
}

#[test]
fn payload_without_tool_is_refused() {
    assert!(
        PermissionAsk::from_payload("p1", "deck/back", &json!({"tool_input": {}}), now()).is_none()
    );
}

#[test]
fn summary_by_tool() {
    assert_eq!(
        PermissionAsk::summary(
            "Edit",
            &input(json!({"file_path": "/a.swift", "old_string": "x"}))
        ),
        "/a.swift"
    );
    assert_eq!(
        PermissionAsk::summary("WebFetch", &input(json!({"url": "https://x.dev"}))),
        "https://x.dev"
    );
    assert_eq!(
        PermissionAsk::summary("mcp__x__y", &input(json!({"b": 1, "a": "z"}))),
        r#"{"a":"z","b":1}"#
    );
    assert_eq!(PermissionAsk::summary("Foo", &Map::new()), "Foo");
    // O `JSONSerialization` do Swift escapa a barra.
    assert_eq!(
        PermissionAsk::summary("mcp__x__y", &input(json!({"dir": "/tmp"}))),
        r#"{"dir":"\/tmp"}"#
    );
}

#[test]
fn hook_output_shapes() {
    let rules =
        vec![json!({"type": "addDirectories", "directories": ["/tmp"], "destination": "session"})];
    let decision = |answer: PermissionAnswer, suggestions: &[Value]| {
        let out = answer.hook_output(suggestions);
        assert_eq!(
            out["hookSpecificOutput"]["hookEventName"],
            "PermissionRequest"
        );
        out["hookSpecificOutput"]["decision"].clone()
    };
    assert_eq!(
        decision(PermissionAnswer::Allow, &rules)["behavior"],
        "allow"
    );
    assert!(
        decision(PermissionAnswer::Allow, &rules)
            .get("updatedPermissions")
            .is_none()
    );
    assert_eq!(
        decision(PermissionAnswer::Always, &rules)["updatedPermissions"]
            .as_array()
            .map(Vec::len),
        Some(1)
    );
    assert!(
        decision(PermissionAnswer::Always, &[])
            .get("updatedPermissions")
            .is_none()
    );
    assert_eq!(decision(PermissionAnswer::Deny, &rules)["behavior"], "deny");
}

#[test]
fn answered_once_then_gone() {
    let mut desk = PermissionDesk::new();
    let ask = desk.open_ask("deck/back", &payload(), now()).unwrap();
    assert_eq!(desk.state(&ask.id, now()), PermissionState::Pending);
    assert!(desk.answer(&ask.id, PermissionAnswer::Allow, "pelo chat", now()));
    assert!(!desk.answer(&ask.id, PermissionAnswer::Deny, "pelo chat", now()));
    assert_eq!(
        desk.state(&ask.id, now()),
        PermissionState::Answered(PermissionAnswer::Allow)
    );
    assert!(desk.take_output(&ask.id).is_some());
    assert_eq!(desk.state(&ask.id, now()), PermissionState::Gone);
    assert!(desk.open(now()).is_empty());
}

#[test]
fn poll_hands_the_output_once() {
    let mut desk = PermissionDesk::new();
    let ask = desk.open_ask("deck/back", &payload(), now()).unwrap();
    assert_eq!(desk.poll(&ask.id, now()), json!({"state": "pending"}));
    desk.answer(&ask.id, PermissionAnswer::Deny, "pelo chat", now());
    let reply = desk.poll(&ask.id, now());
    assert_eq!(reply["state"], "answered");
    assert_eq!(
        reply["output"]["hookSpecificOutput"]["decision"]["behavior"],
        "deny"
    );
    assert_eq!(desk.poll(&ask.id, now()), json!({"state": "gone"}));
}

#[test]
fn drop_makes_it_gone() {
    let mut desk = PermissionDesk::new();
    let ask = desk.open_ask("deck/back", &payload(), now()).unwrap();
    desk.drop("deck/front", None);
    assert_eq!(desk.state(&ask.id, now()), PermissionState::Pending);
    desk.drop("deck/back", None);
    assert_eq!(desk.state(&ask.id, now()), PermissionState::Gone);
}

#[test]
fn asks_of_the_same_terminal_coexist() {
    let mut desk = PermissionDesk::new();
    let first = desk.open_ask("deck/back", &payload(), now()).unwrap();
    let other = desk.open_ask("deck/front", &payload(), now()).unwrap();
    let second = desk.open_ask("deck/back", &payload(), now()).unwrap();
    let ids: Vec<_> = desk.open(now()).iter().map(|a| a.id.clone()).collect();
    assert_eq!(ids, [first.id.clone(), other.id, second.id.clone()]);
    assert!(desk.answer(&second.id, PermissionAnswer::Deny, "pelo chat", now()));
    assert_eq!(desk.state(&first.id, now()), PermissionState::Pending);
    assert_eq!(desk.pending_in_workbench("deck", now()).len(), 2);
    assert!(desk.pending_in_workbench("dec", now()).is_empty());
}

#[test]
fn ids_count_and_carry_the_instant() {
    let mut desk = PermissionDesk::new();
    let ask = desk.open_ask("deck/back", &payload(), now()).unwrap();
    assert_eq!(ask.id, "p1-1000000");
}

#[test]
fn asks_expire_with_the_hook() {
    let mut desk = PermissionDesk::new();
    let ask = desk.open_ask("deck/back", &payload(), now()).unwrap();
    let almost = now() + LIFETIME - Duration::from_secs(1);
    assert_eq!(desk.state(&ask.id, almost), PermissionState::Pending);
    let past = almost + Duration::from_secs(2);
    assert_eq!(desk.state(&ask.id, past), PermissionState::Gone);
    assert!(desk.open(past).is_empty());
    assert!(!desk.answer(&ask.id, PermissionAnswer::Allow, "pelo chat", past));
}

#[test]
fn rename_follows_the_workbench() {
    let mut desk = PermissionDesk::new();
    let ask = desk.open_ask("deck/back", &payload(), now()).unwrap();
    desk.renamed("deck/back", "deck2/back");
    let ids: Vec<_> = desk
        .pending_in_workbench("deck2", now())
        .into_iter()
        .map(|a| a.id)
        .collect();
    assert_eq!(ids, [ask.id]);
}

#[test]
fn listing_has_the_route_shape() {
    let mut desk = PermissionDesk::new();
    desk.open_ask("deck/back", &payload(), now()).unwrap();
    let list = desk.listing(now());
    let first = &list["open"][0];
    assert_eq!(first["address"], "deck/back");
    assert_eq!(first["detail"], "Cria x.txt");
    assert_eq!(first["always"], true);
    assert_eq!(first["questions"], json!([]));
    assert_eq!(
        desk.last_summary("deck/back", now()).as_deref(),
        Some("touch x.txt")
    );
}

// PermissionQuestionTests

fn question_payload() -> Value {
    json!({
        "tool_name": "AskUserQuestion",
        "tool_input": {"questions": [
            {"question": "Qual cor?", "header": "Cor", "multiSelect": false,
             "options": [{"label": "Vermelho", "description": "r"}, {"label": "Azul", "description": "b"}]},
            {"question": "Quais frutas?", "header": "Frutas", "multiSelect": true,
             "options": [{"label": "Maçã"}, {"label": "Uva"}, {"label": "Pera"}]},
        ]},
    })
}

fn choices(pairs: &[(&str, &[&str])]) -> HashMap<String, Vec<String>> {
    pairs
        .iter()
        .map(|(q, picked)| {
            (
                (*q).to_owned(),
                picked.iter().map(|p| (*p).to_owned()).collect(),
            )
        })
        .collect()
}

#[test]
fn questions_are_read() {
    let ask = ask(&question_payload());
    assert_eq!(ask.summary, "Qual cor?");
    let qs = ask.questions();
    assert_eq!(
        qs.iter().map(|q| q.question.as_str()).collect::<Vec<_>>(),
        ["Qual cor?", "Quais frutas?"]
    );
    assert_eq!(qs[0].options, ["Vermelho", "Azul"]);
    assert!(qs[1].multi_select);
}

#[test]
fn other_tools_have_no_questions() {
    let ask = ask(&json!({"tool_name": "Bash", "tool_input": {"command": "ls"}}));
    assert!(ask.questions().is_empty());
    assert!(!ask.accepts(&choices(&[("x", &["y"])])));
}

#[test]
fn choices_must_cover_every_question_within_its_options() {
    let ask = ask(&question_payload());
    assert!(ask.accepts(&choices(&[
        ("Qual cor?", &["Azul"]),
        ("Quais frutas?", &["Maçã", "Uva"])
    ])));
    assert!(
        !ask.accepts(&choices(&[("Qual cor?", &["Azul"])])),
        "falta uma pergunta"
    );
    assert!(
        !ask.accepts(&choices(&[
            ("Qual cor?", &["Verde"]),
            ("Quais frutas?", &["Uva"])
        ])),
        "fora das opções"
    );
    assert!(
        !ask.accepts(&choices(&[
            ("Qual cor?", &["Azul", "Vermelho"]),
            ("Quais frutas?", &["Uva"])
        ])),
        "duas escolhas numa pergunta de uma"
    );
}

#[test]
fn answer_output_keeps_input_and_joins_multi_select() {
    let ask = ask(&question_payload());
    let out = ask.answer_output(&choices(&[
        ("Qual cor?", &["Azul"]),
        ("Quais frutas?", &["Maçã", "Uva"]),
    ]));
    let decision = &out["hookSpecificOutput"]["decision"];
    assert_eq!(decision["behavior"], "allow");
    let updated = &decision["updatedInput"];
    assert_eq!(updated["questions"].as_array().map(Vec::len), Some(2));
    assert_eq!(
        updated["answers"],
        json!({"Qual cor?": "Azul", "Quais frutas?": "Maçã, Uva"})
    );
}

#[test]
fn desk_refuses_bad_choices_and_keeps_the_ask_open() {
    let mut desk = PermissionDesk::new();
    let ask = desk
        .open_ask("deck/back", &question_payload(), now())
        .unwrap();
    assert!(!desk.answer_choices(&ask.id, &choices(&[("Qual cor?", &["Azul"])]), now()));
    assert_eq!(desk.state(&ask.id, now()), PermissionState::Pending);
    let first = desk.first_question_choice(&ask.id, "Azul", now()).unwrap();
    assert_eq!(first, choices(&[("Qual cor?", &["Azul"])]));
    assert!(desk.answer_choices(
        &ask.id,
        &choices(&[("Qual cor?", &["Azul"]), ("Quais frutas?", &["Pera"])]),
        now()
    ));
    assert_eq!(
        desk.state(&ask.id, now()),
        PermissionState::Answered(PermissionAnswer::Allow)
    );
}

#[test]
fn answer_older_than_the_lifetime_is_gone() {
    let mut desk = PermissionDesk::new();
    let ask = desk.open_ask("deck/back", &payload(), now()).unwrap();
    assert!(desk.answer(&ask.id, PermissionAnswer::Allow, "pelo chat", now()));
    let late = now() + LIFETIME + Duration::from_secs(1);
    assert_eq!(desk.state(&ask.id, late), PermissionState::Gone);
    assert!(desk.take_output(&ask.id).is_none());
}

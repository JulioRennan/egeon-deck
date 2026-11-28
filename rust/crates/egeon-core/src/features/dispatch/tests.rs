//! O Dispatcher inteiro com o relógio na mão: guardas de cadeia, entrega,
//! confirmação, fim de turno por gancho, falha de API e espera por vizinho.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use super::failure::ApiFailure;
use super::marker::{HookEvent, LastMarker, Marker, MarkerConfig};
use super::profile::TargetProfile;
use super::request::DispatchRequest;
use super::stop::StopReport;
use super::{DispatchError, Dispatcher, Effect, Hook, Surface, Topology};
use crate::features::activity::model::Activity;
use crate::features::edge::model::EdgeConfig as Edge;

#[derive(Default)]
struct World {
    dead: Vec<String>,
    focused: Option<String>,
    screens: HashMap<String, Vec<String>>,
    transcript: Option<LastMarker>,
    edges: Vec<Edge>,
}

impl Surface for World {
    fn running(&self, address: &str) -> bool {
        !self.dead.iter().any(|d| d == address)
    }
    fn focused(&self, address: &str) -> bool {
        self.focused.as_deref() == Some(address)
    }
    fn peek(&self, address: &str, lines: usize) -> Vec<String> {
        let all = self.screens.get(address).cloned().unwrap_or_default();
        let skip = all.len().saturating_sub(lines);
        all[skip..].to_vec()
    }
    fn last_marker(&self, _: &Path, _: &MarkerConfig) -> Option<LastMarker> {
        self.transcript.clone()
    }
}

impl Topology for World {
    fn edges(&self, _workbench: &str) -> Vec<Edge> {
        self.edges.clone()
    }
    fn role(&self, address: &str) -> Option<String> {
        (address == "deck/rev").then(|| "revisor".to_owned())
    }
}

fn t0() -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(1_800_000_000)
}

fn at(ms: u64) -> SystemTime {
    t0() + Duration::from_millis(ms)
}

fn edge(from: &str, to: &str, max: Option<i64>) -> Edge {
    Edge::new(from, to, max)
}

fn both(a: &str, b: &str, max: Option<i64>) -> Vec<Edge> {
    vec![edge(a, b, max), edge(b, a, max)]
}

fn agent() -> Option<TargetProfile> {
    Some(TargetProfile::new("Claude Code"))
}

fn text(t: &str) -> DispatchRequest {
    let mut r = DispatchRequest::new("");
    r.text = Some(t.into());
    r
}

fn to(target: &str, t: &str) -> DispatchRequest {
    DispatchRequest {
        target: target.into(),
        ..text(t)
    }
}

fn bench(names: &[&str]) -> Dispatcher {
    let mut d = Dispatcher::new();
    for n in names {
        d.register(format!("deck/{n}"), agent(), true, t0());
    }
    d
}

fn writes(effects: &[Effect], address: &str) -> Vec<String> {
    effects
        .iter()
        .filter_map(|e| match e {
            Effect::Write { address: a, bytes } if a == address => {
                Some(String::from_utf8_lossy(bytes).into_owned())
            }
            _ => None,
        })
        .collect()
}

fn announced(effects: &[Effect]) -> Vec<(String, Activity)> {
    effects
        .iter()
        .filter_map(|e| match e {
            Effect::Announce {
                address, activity, ..
            } => Some((address.clone(), activity.clone())),
            _ => None,
        })
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn hook(
    d: &mut Dispatcher,
    address: &str,
    event: HookEvent,
    transcript: Option<PathBuf>,
    report: StopReport,
    failure: Option<ApiFailure>,
    now: SystemTime,
    w: &World,
) -> Option<Vec<Effect>> {
    let hook = Hook {
        event,
        transcript,
        report,
        failure,
    };
    d.hook_reported(address, hook, now, w)
}

/// Liga a TUI: saiu o banner, passou o aquecimento, veio o `SessionStart`.
fn boot(d: &mut Dispatcher, w: &World, address: &str) {
    d.output(address, at(100), w);
    hook(
        d,
        address,
        HookEvent::Start,
        None,
        StopReport::default(),
        None,
        at(200),
        w,
    );
}

#[test]
fn you_deliver_without_guards() {
    let mut d = bench(&["a"]);
    let w = World::default();
    let ok = d.dispatch(&to("deck/a", "oi"), None, &w).unwrap();
    assert_eq!(ok, "enfileirado para deck/a; 1 na fila");
}

#[test]
fn unknown_target_lists_who_exists() {
    let mut d = bench(&["a", "b"]);
    let w = World::default();
    let err = d.dispatch(&to("deck/zz", "oi"), None, &w).unwrap_err();
    assert_eq!(
        err.to_string(),
        "alvo desconhecido 'deck/zz'. disponíveis: deck/a, deck/b"
    );
}

#[test]
fn empty_prompt_is_refused_but_image_alone_goes() {
    let mut d = bench(&["a"]);
    let w = World::default();
    assert_eq!(
        d.dispatch(&DispatchRequest::new("deck/a"), None, &w),
        Err(DispatchError::EmptyPrompt)
    );
    let mut image = DispatchRequest::new("deck/a");
    image.images = Some(vec!["/tmp/x.png".into()]);
    assert!(d.dispatch(&image, None, &w).is_ok());
}

#[test]
fn agent_needs_an_edge_and_may_name_only_the_id() {
    let mut d = bench(&["a", "b"]);
    let mut w = World::default();
    let err = d.dispatch(&to("b", "oi"), Some("deck/a"), &w).unwrap_err();
    assert_eq!(
        err.to_string(),
        "não existe ligação de deck/a para deck/b — desenhe a aresta no canvas"
    );
    w.edges = both("a", "b", Some(2));
    let ok = d.dispatch(&to("b", "oi"), Some("deck/a"), &w).unwrap();
    assert_eq!(ok, "enfileirado para deck/b; 1 na fila; envio 1/2");
}

#[test]
fn backlog_per_sender_refuses_a_loop() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        edges: both("a", "b", Some(2)),
        ..World::default()
    };
    d.dispatch(&to("deck/b", "1"), Some("deck/a"), &w).unwrap();
    d.dispatch(&to("deck/b", "2"), Some("deck/a"), &w).unwrap();
    let err = d
        .dispatch(&to("deck/b", "3"), Some("deck/a"), &w)
        .unwrap_err();
    assert_eq!(
        err.to_string(),
        "cadeia recusada: deck/b ainda tem 2 mensagens suas por ler (limite 2). \
         Espere ele responder antes de mandar outra."
    );
}

#[test]
fn unlimited_edge_has_no_backlog_ceiling() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        edges: both("a", "b", None),
        ..World::default()
    };
    for i in 0..8 {
        let ok = d
            .dispatch(&to("deck/b", &i.to_string()), Some("deck/a"), &w)
            .unwrap();
        assert!(ok.ends_with("envio 1/∞"), "{ok}");
    }
}

/// `a → b → a → b` com limite 1: a segunda ida de `a` para `b` na mesma
/// cadeia é cortada, contando a seta e não o comprimento.
#[test]
fn edge_limit_counts_sends_in_the_chain() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        edges: both("a", "b", Some(1)),
        ..World::default()
    };
    boot(&mut d, &w, "deck/a");
    boot(&mut d, &w, "deck/b");

    d.dispatch(&to("deck/b", "faz"), Some("deck/a"), &w)
        .unwrap();
    d.tick(at(5_000), &w);
    assert_eq!(d.target("deck/b").unwrap().pending(), 0, "b recebeu");
    d.dispatch(&to("deck/a", "feito"), Some("deck/b"), &w)
        .unwrap();
    d.tick(at(6_000), &w);
    let err = d
        .dispatch(&to("deck/b", "de novo"), Some("deck/a"), &w)
        .unwrap_err();
    assert_eq!(
        err.to_string(),
        "cadeia recusada: a ligação deck/a → deck/b já disparou 1× nesta conversa \
         (deck/a → deck/b → deck/a → deck/b). Volte a falar com o usuário."
    );
}

#[test]
fn shell_gets_raw_text_and_agent_the_envelope() {
    let mut d = bench(&["a"]);
    d.register("deck/sh", None, false, t0());
    let w = World {
        edges: vec![edge("a", "sh", Some(2)), edge("sh", "a", Some(2))],
        ..World::default()
    };
    d.output("deck/sh", at(100), &w);
    d.dispatch(&to("deck/sh", "npm test"), Some("deck/a"), &w)
        .unwrap();
    let fx = d.tick(at(2_000), &w);
    assert_eq!(writes(&fx, "deck/sh"), ["npm test"]);
    // Shell não é bastão: quem mandou não fica aguardando.
    assert!(
        !d.target("deck/a")
            .unwrap()
            .awaiting_peers
            .contains("deck/sh")
    );
}

#[test]
fn delivery_waits_idle_then_pastes_then_enters() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    d.dispatch(&to("deck/b", "oi\nmundo"), None, &w).unwrap();

    // Ainda no aquecimento (4s): nada sai.
    assert!(writes(&d.tick(at(3_000), &w), "deck/b").is_empty());
    let fx = d.tick(at(4_200), &w);
    assert_eq!(writes(&fx, "deck/b"), ["\u{1b}[200~oi\nmundo\u{1b}[201~"]);
    assert_eq!(*d.target("deck/b").unwrap().activity(), Activity::Working);
    // O Enter espera o mínimo do perfil e a TUI quieta.
    assert!(writes(&d.tick(at(4_250), &w), "deck/b").is_empty());
    d.output("deck/b", at(4_300), &w);
    assert!(writes(&d.tick(at(4_400), &w), "deck/b").is_empty());
    assert_eq!(writes(&d.tick(at(4_700), &w), "deck/b"), ["\r"]);
}

#[test]
fn images_are_pasted_one_by_one_before_the_text() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    let mut req = to("deck/b", "veja");
    req.images = Some(vec!["/tmp/a.png".into()]);
    d.dispatch(&req, None, &w).unwrap();
    assert_eq!(
        writes(&d.tick(at(5_000), &w), "deck/b"),
        ["\u{1b}[200~/tmp/a.png\u{1b}[201~"]
    );
    assert_eq!(
        writes(&d.tick(at(5_400), &w), "deck/b"),
        ["\u{1b}[200~veja\u{1b}[201~"]
    );
    assert_eq!(writes(&d.tick(at(5_800), &w), "deck/b"), ["\r"]);
}

#[test]
fn silent_delivery_is_resent_then_given_up() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    d.dispatch(&to("deck/b", "oi"), None, &w).unwrap();
    let paste = "\u{1b}[200~oi\u{1b}[201~";
    assert_eq!(writes(&d.tick(at(5_000), &w), "deck/b"), [paste]);
    assert_eq!(writes(&d.tick(at(5_400), &w), "deck/b"), ["\r"]);
    // Ninguém reagiu em 1,5s: cola de novo, até três vezes.
    assert_eq!(writes(&d.tick(at(6_600), &w), "deck/b"), [paste]);
    assert_eq!(writes(&d.tick(at(7_000), &w), "deck/b"), ["\r"]);
    assert_eq!(writes(&d.tick(at(8_600), &w), "deck/b"), [paste]);
    assert_eq!(writes(&d.tick(at(9_000), &w), "deck/b"), ["\r"]);
    assert!(writes(&d.tick(at(10_600), &w), "deck/b").is_empty());
    assert!(writes(&d.tick(at(12_600), &w), "deck/b").is_empty());
}

#[test]
fn the_prompt_hook_confirms_delivery() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    d.dispatch(&to("deck/b", "oi"), None, &w).unwrap();
    d.tick(at(5_000), &w);
    d.tick(at(5_400), &w);
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_500),
        &w,
    );
    assert!(writes(&d.tick(at(7_000), &w), "deck/b").is_empty());
}

fn stop_with(last: &str) -> StopReport {
    StopReport {
        last_message: Some(last.into()),
        ..StopReport::default()
    }
}

#[test]
fn stop_with_ok_finishes_and_ask_calls_you() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    d.tick(at(5_000), &w);
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_100),
        &w,
    );
    d.tick(at(5_200), &w);
    assert_eq!(*d.target("deck/b").unwrap().activity(), Activity::Working);

    let fx = hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        None,
        stop_with("feito\n[[ED:ok]]"),
        None,
        at(6_000),
        &w,
    )
    .unwrap();
    assert_eq!(announced(&fx), [("deck/b".to_owned(), Activity::Waiting)]);
    assert!(fx.iter().any(|e| matches!(e, Effect::TurnEnded { .. })));
    // O tique seguinte não rebaixa o aviso.
    d.tick(at(6_250), &w);
    assert_eq!(*d.target("deck/b").unwrap().activity(), Activity::Waiting);

    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(7_000),
        &w,
    );
    let fx = hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        None,
        stop_with("qual?\n[[ED:ask]]"),
        None,
        at(8_000),
        &w,
    )
    .unwrap();
    assert_eq!(announced(&fx), [("deck/b".to_owned(), Activity::Asking)]);
    let sound = fx.iter().find_map(|e| match e {
        Effect::Announce { sound, .. } => sound.clone(),
        _ => None,
    });
    assert_eq!(sound.as_deref(), Some("Tink"), "pergunta toca");
}

#[test]
fn deadlines_are_exposed_for_the_actor() {
    let mut d = bench(&["b"]);
    let mut w = World::default();
    boot(&mut d, &w, "deck/b");
    assert_eq!(d.next_deadline(), None);
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    w.transcript = Some(LastMarker {
        marker: Some(Marker::Ask),
        at: Some(at(1_000)),
    });
    let path = Some(PathBuf::from("/tmp/t.jsonl"));
    hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        path,
        StopReport::default(),
        None,
        at(6_000),
        &w,
    );
    assert_eq!(d.next_deadline(), Some(at(6_250)), "a releitura do Stop");
    hook(
        &mut d,
        "deck/b",
        HookEvent::Failure,
        None,
        StopReport::default(),
        Some(ApiFailure::new("overloaded")),
        at(6_100),
        &w,
    );
    assert_eq!(d.next_deadline(), Some(at(6_250)), "o mais cedo dos dois");
}

/// O transcript atrasado: a linha mais velha que o `prompt` é do turno
/// passado, e o Dispatcher relê até ela ficar em dia.
#[test]
fn stale_transcript_is_reread() {
    let mut d = bench(&["b"]);
    let mut w = World::default();
    boot(&mut d, &w, "deck/b");
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    w.transcript = Some(LastMarker {
        marker: Some(Marker::Ask),
        at: Some(at(1_000)),
    });
    let path = Some(PathBuf::from("/tmp/t.jsonl"));
    let fx = hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        path,
        StopReport::default(),
        None,
        at(6_000),
        &w,
    )
    .unwrap();
    assert!(announced(&fx).is_empty(), "esperando o transcript");
    w.transcript = Some(LastMarker {
        marker: Some(Marker::Ok),
        at: Some(at(6_100)),
    });
    let fx = d.tick(at(6_250), &w);
    assert_eq!(announced(&fx), [("deck/b".to_owned(), Activity::Waiting)]);
}

#[test]
fn wait_marker_with_background_holds_the_hourglass() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    let report = StopReport {
        background: Some(1),
        ..stop_with("rodando\n[[ED:wait]]")
    };
    let fx = hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        None,
        report,
        None,
        at(6_000),
        &w,
    )
    .unwrap();
    assert!(announced(&fx).is_empty(), "sem som na ampulheta");
    d.tick(at(6_250), &w);
    assert_eq!(
        *d.target("deck/b").unwrap().activity(),
        Activity::Background
    );
}

#[test]
fn api_failure_schedules_retry_then_gives_up() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    let fail = || Some(ApiFailure::new("overloaded"));
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    hook(
        &mut d,
        "deck/b",
        HookEvent::Failure,
        None,
        StopReport::default(),
        fail(),
        at(6_000),
        &w,
    );
    assert_eq!(
        *d.target("deck/b").unwrap().activity(),
        Activity::Retrying {
            attempt: 1,
            at: at(36_000)
        }
    );
    d.tick(at(20_000), &w);
    assert_eq!(d.target("deck/b").unwrap().pending(), 0);
    // A hora chegou: o "continue" entra na fila e sai na mesma volta.
    let fx = d.tick(at(36_000), &w);
    assert_eq!(
        writes(&fx, "deck/b"),
        [
            "\u{1b}[200~A última chamada à API falhou (API sobrecarregada). Continue de onde parou.\u{1b}[201~"
        ]
    );
    // A tentativa do app não zera a contagem.
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(36_500),
        &w,
    );
    hook(
        &mut d,
        "deck/b",
        HookEvent::Failure,
        None,
        StopReport::default(),
        fail(),
        at(37_000),
        &w,
    );
    assert!(matches!(
        d.target("deck/b").unwrap().activity(),
        Activity::Retrying { attempt: 2, .. }
    ));
    assert!(d.retry_control("deck/b", true, at(38_000)).is_some());
    d.tick(at(38_000), &w);
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(39_000),
        &w,
    );
    hook(
        &mut d,
        "deck/b",
        HookEvent::Failure,
        None,
        StopReport::default(),
        fail(),
        at(40_000),
        &w,
    );
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(41_000),
        &w,
    );
    assert!(
        d.retry_control("deck/b", true, at(41_000)).is_none(),
        "o prompt de novo não é tentativa"
    );
}

#[test]
fn fatal_failure_calls_you_in_red() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    let fx = hook(
        &mut d,
        "deck/b",
        HookEvent::Failure,
        None,
        StopReport::default(),
        Some(ApiFailure::new("billing_error")),
        at(5_000),
        &w,
    )
    .unwrap();
    assert_eq!(
        announced(&fx),
        [(
            "deck/b".to_owned(),
            Activity::Failed("problema de cobrança".into())
        )]
    );
    assert!(d.retry_control("deck/b", false, at(5_100)).is_none());
}

#[test]
fn cancel_retry_turns_into_finished() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    hook(
        &mut d,
        "deck/b",
        HookEvent::Failure,
        None,
        StopReport::default(),
        Some(ApiFailure::new("rate_limit")),
        at(5_000),
        &w,
    );
    assert!(d.retry_control("deck/b", false, at(6_000)).is_some());
    assert_eq!(*d.target("deck/b").unwrap().activity(), Activity::Waiting);
    assert_eq!(d.target("deck/b").unwrap().pending(), 0);
}

/// `a` aciona `b` e para: fica aguardando, sem te chamar. A resposta de `b`
/// é volta, e `b` não fica aguardando `a`.
#[test]
fn handoff_awaits_the_peer_and_reply_does_not_reopen() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        edges: both("a", "b", Some(2)),
        ..World::default()
    };
    boot(&mut d, &w, "deck/a");
    boot(&mut d, &w, "deck/b");
    hook(
        &mut d,
        "deck/a",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    d.dispatch(&to("deck/b", "revisa"), Some("deck/a"), &w)
        .unwrap();
    let fx = hook(
        &mut d,
        "deck/a",
        HookEvent::Stop,
        None,
        stop_with("[[ED:ask]]"),
        None,
        at(5_500),
        &w,
    )
    .unwrap();
    assert!(announced(&fx).is_empty(), "vizinho pendente vence o ask");
    assert_eq!(
        *d.target("deck/a").unwrap().activity(),
        Activity::Awaiting(vec!["b".into()])
    );

    d.dispatch(&to("deck/a", "aprovado"), Some("deck/b"), &w)
        .unwrap();
    assert!(d.target("deck/a").unwrap().awaiting_peers.is_empty());
    assert!(
        !d.target("deck/b")
            .unwrap()
            .awaiting_peers
            .contains("deck/a")
    );
}

/// O vizinho encerrou sem responder: quem esperava vira "terminou".
#[test]
fn peer_that_settles_without_reply_releases_the_waiter() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        edges: both("a", "b", Some(2)),
        ..World::default()
    };
    boot(&mut d, &w, "deck/a");
    boot(&mut d, &w, "deck/b");
    hook(
        &mut d,
        "deck/a",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    d.dispatch(&to("deck/b", "revisa"), Some("deck/a"), &w)
        .unwrap();
    hook(
        &mut d,
        "deck/a",
        HookEvent::Stop,
        None,
        stop_with("[[ED:wait]]"),
        None,
        at(5_500),
        &w,
    );
    d.tick(at(6_000), &w);
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(6_500),
        &w,
    );
    let fx = hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        None,
        stop_with("[[ED:ok]]"),
        None,
        at(7_000),
        &w,
    )
    .unwrap();
    let got = announced(&fx);
    assert!(
        got.contains(&("deck/a".to_owned(), Activity::Waiting)),
        "{got:?}"
    );
}

#[test]
fn slash_command_goes_raw_with_a_notice_and_opens_no_wait() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        edges: both("a", "b", None),
        ..World::default()
    };
    boot(&mut d, &w, "deck/b");
    d.dispatch(&to("deck/b", "/clear"), Some("deck/a"), &w)
        .unwrap();
    assert_eq!(d.target("deck/b").unwrap().pending(), 2);
    assert!(d.target("deck/a").unwrap().awaiting_peers.is_empty());
    let fx = d.tick(at(5_000), &w);
    let first = writes(&fx, "deck/b").join("");
    assert!(first.contains("[ED] mensagem de deck/a"), "{first}");
}

#[test]
fn typing_resets_the_chain() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        edges: both("a", "b", Some(1)),
        ..World::default()
    };
    boot(&mut d, &w, "deck/a");
    boot(&mut d, &w, "deck/b");
    d.dispatch(&to("deck/b", "1"), Some("deck/a"), &w).unwrap();
    d.tick(at(5_000), &w);
    d.dispatch(&to("deck/a", "2"), Some("deck/b"), &w).unwrap();
    d.tick(at(6_000), &w);
    let fx = d.user_typed("deck/a", at(6_100));
    assert!(fx.iter().any(|e| matches!(
        e,
        Effect::DropPermissions {
            why: "respondido no terminal",
            ..
        }
    )));
    assert!(d.dispatch(&to("deck/b", "3"), Some("deck/a"), &w).is_ok());
}

#[test]
fn notification_after_the_turn_is_ignored() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    d.tick(at(5_000), &w);
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_100),
        &w,
    );
    d.tick(at(5_200), &w);
    hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        None,
        stop_with("[[ED:ok]]"),
        None,
        at(6_000),
        &w,
    );
    let fx = hook(
        &mut d,
        "deck/b",
        HookEvent::Ask,
        None,
        StopReport::default(),
        None,
        at(66_000),
        &w,
    )
    .unwrap();
    assert!(announced(&fx).is_empty(), "o \"você sumiu\" não é aviso");
}

#[test]
fn permission_mid_turn_calls_you() {
    let mut d = bench(&["b"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_100),
        &w,
    );
    let fx = hook(
        &mut d,
        "deck/b",
        HookEvent::Ask,
        None,
        StopReport::default(),
        None,
        at(6_000),
        &w,
    )
    .unwrap();
    assert_eq!(announced(&fx), [("deck/b".to_owned(), Activity::Asking)]);
}

#[test]
fn dead_terminal_is_not_offered() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        dead: vec!["deck/b".into()],
        ..World::default()
    };
    d.tick(at(2_000), &w);
    assert_eq!(d.active_addresses(), ["deck/a"]);
    assert_eq!(d.addresses(), ["deck/a", "deck/b"]);
}

/// Shell sem gancho: o silêncio depois de uma rajada longa não chama ninguém
/// — só terminal com IA vigia atenção.
#[test]
fn shell_never_calls_you() {
    let mut d = Dispatcher::new();
    d.register("deck/sh", None, false, t0());
    let w = World::default();
    for ms in (0..3_000).step_by(100) {
        d.output("deck/sh", at(ms), &w);
    }
    let fx = d.tick(at(6_000), &w);
    assert!(announced(&fx).is_empty());
    assert_eq!(*d.target("deck/sh").unwrap().activity(), Activity::Ready);
}

/// CLI sem gancho: o marcador na tela decide, e um marcador velho que já
/// estava lá no arranque não toca.
#[test]
fn without_hooks_the_screen_marker_decides() {
    let mut d = Dispatcher::new();
    d.register("deck/x", agent(), false, t0());
    let mut w = World::default();
    w.screens
        .insert("deck/x".into(), vec!["velho".into(), "[[ED:ask]]".into()]);
    d.output("deck/x", at(100), &w);
    let fx = d.tick(at(5_000), &w);
    assert!(
        announced(&fx).is_empty(),
        "o marcador do arranque já foi visto"
    );

    // Só entrada nova solta o aviso segurado: você pede, o agente trabalha.
    d.user_typed("deck/x", at(5_050));
    for ms in (5_100..8_000).step_by(100) {
        d.output("deck/x", at(ms), &w);
    }
    w.screens.insert(
        "deck/x".into(),
        vec!["resposta nova".into(), "[[ED:ok]]".into()],
    );
    let fx = d.tick(at(8_100), &w);
    assert_eq!(announced(&fx), [("deck/x".to_owned(), Activity::Waiting)]);
}

/// `"wait": ""` no `agents.json` não casa em toda linha: sem marcador na
/// tela, decide o silêncio, e não a ampulheta.
#[test]
fn empty_marker_token_is_ignored_on_the_screen() {
    let mut profile = TargetProfile::new("Claude Code");
    if let Some(marker) = profile.attention.marker.as_mut() {
        marker.wait = String::new();
    }
    let mut d = Dispatcher::new();
    d.register("deck/x", Some(profile), false, t0());
    let mut w = World::default();
    w.screens
        .insert("deck/x".into(), vec!["resposta sem marcador".into()]);
    for ms in (5_000..8_000).step_by(100) {
        d.output("deck/x", at(ms), &w);
    }
    let fx = d.tick(at(9_600), &w);
    assert_eq!(announced(&fx), [("deck/x".to_owned(), Activity::Waiting)]);
}

/// Padrão do perfil é regex sem caixa, com o que o ICU do Swift aceitava —
/// lookaround incluído.
#[test]
fn attention_pattern_with_lookahead_calls_you() {
    let mut profile = TargetProfile::new("Claude Code");
    profile.attention.marker = None;
    profile.attention.patterns = vec![r"do you want(?= to proceed)".into(), "(".into()];
    let mut d = Dispatcher::new();
    d.register("deck/x", Some(profile), false, t0());
    let mut w = World::default();
    w.screens.insert(
        "deck/x".into(),
        vec!["DO YOU WANT TO PROCEED?".into(), "❯ 1. Yes".into()],
    );
    for ms in (5_000..8_000).step_by(100) {
        d.output("deck/x", at(ms), &w);
    }
    let fx = d.tick(at(9_600), &w);
    assert_eq!(announced(&fx), [("deck/x".to_owned(), Activity::Asking)]);
}

#[test]
fn focused_terminal_does_not_call_you() {
    let mut d = Dispatcher::new();
    d.register("deck/x", agent(), false, t0());
    let mut w = World {
        focused: Some("deck/x".into()),
        ..World::default()
    };
    w.screens.insert("deck/x".into(), vec!["[[ED:ok]]".into()]);
    for ms in (5_000..8_000).step_by(100) {
        d.output("deck/x", at(ms), &w);
    }
    let fx = d.tick(at(9_000), &w);
    assert!(announced(&fx).is_empty());
}

#[test]
fn opening_the_workbench_clears_only_the_green() {
    let mut d = bench(&["b", "c"]);
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    boot(&mut d, &w, "deck/c");
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        None,
        stop_with("[[ED:ok]]"),
        None,
        at(6_000),
        &w,
    );
    hook(
        &mut d,
        "deck/c",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    hook(
        &mut d,
        "deck/c",
        HookEvent::Stop,
        None,
        stop_with("[[ED:ask]]"),
        None,
        at(6_000),
        &w,
    );
    d.workbench_opened("deck");
    assert_eq!(*d.target("deck/b").unwrap().activity(), Activity::Ready);
    assert_eq!(*d.target("deck/c").unwrap().activity(), Activity::Asking);
}

#[test]
fn summary_counts_per_workbench() {
    let mut d = bench(&["b", "c"]);
    d.register("outra/x", agent(), true, t0());
    let w = World::default();
    boot(&mut d, &w, "deck/b");
    hook(
        &mut d,
        "deck/b",
        HookEvent::Prompt,
        None,
        StopReport::default(),
        None,
        at(5_000),
        &w,
    );
    hook(
        &mut d,
        "deck/b",
        HookEvent::Stop,
        None,
        stop_with("[[ED:ask]]"),
        None,
        at(6_000),
        &w,
    );
    let summary = d.activity_summary();
    assert_eq!(summary["deck"].attention, 1);
    assert_eq!(summary["deck"].starting, 1);
    assert!(summary["outra"].is_preparing());
}

#[test]
fn peers_are_asked_at_runtime() {
    let mut d = bench(&["a", "rev"]);
    d.register("deck/sh", None, false, t0());
    let w = World {
        edges: vec![
            edge("a", "rev", Some(2)),
            edge("a", "sh", Some(2)),
            edge("a", "fora", None),
        ],
        ..World::default()
    };
    let peers = d.peers("deck/a", &w);
    let summary: Vec<_> = peers
        .iter()
        .map(|p| (p.address.as_str(), p.cli.as_str(), p.role.as_deref()))
        .collect();
    assert_eq!(
        summary,
        [
            ("deck/rev", "Claude Code", Some("revisor")),
            ("deck/sh", "shell", None)
        ]
    );
}

#[test]
fn rekey_follows_the_waits() {
    let mut d = bench(&["a", "b"]);
    let w = World {
        edges: both("a", "b", Some(2)),
        ..World::default()
    };
    d.dispatch(&to("deck/b", "oi"), Some("deck/a"), &w).unwrap();
    assert!(d.rekey("deck/b", "nova/b"));
    assert!(
        d.target("deck/a")
            .unwrap()
            .awaiting_peers
            .contains("nova/b")
    );
    assert!(!d.rekey("deck/b", "nova/b"));
}

// PeekGuardTests.swift

#[test]
fn you_may_peek_anyone() {
    assert!(Dispatcher::may_peek("deck/back", None, &[]));
}

#[test]
fn agent_may_peek_only_its_peers() {
    let peers = ["deck/revisor".to_owned(), "deck/back".to_owned()];
    assert!(Dispatcher::may_peek(
        "deck/revisor",
        Some("deck/front"),
        &peers
    ));
    assert!(
        !Dispatcher::may_peek("outra/qualquer", Some("deck/front"), &peers),
        "sem aresta, não há o que espiar"
    );
}

#[test]
fn agent_may_always_peek_itself() {
    assert!(Dispatcher::may_peek("deck/front", Some("deck/front"), &[]));
}

//! Os ganchos contra um servidor falso: cada evento avisa a rota certa, nunca
//! escreve no stdout (salvo a decisão do `permission`) e nunca falha.

mod common;

use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

use common::{FakeServer, hook};

const WAIT: Duration = Duration::from_secs(580);

fn targets(server: &FakeServer) -> Vec<(String, String)> {
    server
        .seen()
        .into_iter()
        .map(|s| (s.method, s.target))
        .collect()
}

fn post(target: &str) -> (String, String) {
    ("POST".into(), target.into())
}

#[test]
fn fora_do_egeon_nao_ha_a_quem_contar() {
    let server = FakeServer::ok("{}");
    for event in ["prompt", "stop", "start", "ask", "failure", "permission"] {
        let out = hook(&server.sock, event, r#"{"session_id":"s"}"#, false, WAIT);
        assert_eq!(out, "", "{event}");
    }
    assert!(server.seen().is_empty());
}

#[test]
fn prompt_conta_a_conversa_com_o_caminho_escapado() {
    let server = FakeServer::ok("{}");
    let payload = r#"{"session_id":"abc","transcript_path":"/Users/a b/ç.jsonl"}"#;
    assert_eq!(hook(&server.sock, "prompt", payload, true, WAIT), "");
    assert_eq!(
        targets(&server),
        [post(
            "/conversation?id=abc&transcript=/Users/a%20b/%C3%A7.jsonl"
        )]
    );
}

#[test]
fn prompt_sem_sessao_ou_com_payload_ruim_nao_avisa() {
    let server = FakeServer::ok("{}");
    for payload in ["", "{}", "lixo", r#"{"session_id":""}"#] {
        assert_eq!(hook(&server.sock, "prompt", payload, true, WAIT), "");
    }
    assert!(server.seen().is_empty());
}

#[test]
fn stop_leva_o_transcript_e_o_fim_da_mensagem() {
    let server = FakeServer::ok("{}");
    let payload = r#"{"transcript_path":"/t.jsonl","last_assistant_message":"pronto [[ED:ok]]"}"#;
    assert_eq!(hook(&server.sock, "stop", payload, true, WAIT), "");
    assert_eq!(
        targets(&server),
        [post(
            "/activity?event=stop&transcript=/t.jsonl&last=pronto%20%5B%5BED%3Aok%5D%5D"
        )]
    );
}

#[test]
fn stop_com_payload_ruim_ainda_avisa() {
    let server = FakeServer::ok("{}");
    hook(&server.sock, "stop", "lixo", true, WAIT);
    assert_eq!(targets(&server), [post("/activity?event=stop&")]);
}

#[test]
fn start_avisa_o_arranque_e_so_no_clear_a_conversa() {
    let server = FakeServer::ok("{}");
    hook(
        &server.sock,
        "start",
        r#"{"session_id":"s","transcript_path":"/t","source":"startup"}"#,
        true,
        WAIT,
    );
    assert_eq!(targets(&server), [post("/activity?event=start")]);
    hook(
        &server.sock,
        "start",
        r#"{"session_id":"s","transcript_path":"/t","source":"clear"}"#,
        true,
        WAIT,
    );
    assert_eq!(
        targets(&server),
        [
            post("/conversation?id=s&transcript=/t&noturn=1"),
            post("/activity?event=start"),
        ]
    );
}

#[test]
fn ask_ignora_o_payload() {
    let server = FakeServer::ok("{}");
    hook(&server.sock, "ask", "qualquer coisa", true, WAIT);
    assert_eq!(targets(&server), [post("/activity?event=ask")]);
}

#[test]
fn failure_leva_o_erro_ou_unknown() {
    let server = FakeServer::ok("{}");
    hook(
        &server.sock,
        "failure",
        r#"{"error":"overloaded","error_details":"tente/depois"}"#,
        true,
        WAIT,
    );
    hook(&server.sock, "failure", "lixo", true, WAIT);
    assert_eq!(
        targets(&server),
        [
            post("/activity?event=failure&error=overloaded&detail=tente%2Fdepois"),
            post("/activity?event=failure&error=unknown"),
        ]
    );
}

#[test]
fn evento_desconhecido_e_vazio_nao_fazem_nada() {
    let server = FakeServer::ok("{}");
    for event in ["recap", "", "Stop"] {
        assert_eq!(hook(&server.sock, event, "{}", true, WAIT), "");
    }
    assert!(server.seen().is_empty());
}

#[test]
fn app_fora_do_ar_nao_atrapalha_nenhum_gancho() {
    let nowhere = tempfile::tempdir().unwrap().keep().join("sem-socket");
    for event in ["prompt", "stop", "start", "ask", "failure", "permission"] {
        let out = hook(&nowhere, event, r#"{"session_id":"s"}"#, true, WAIT);
        assert_eq!(out, "", "{event}");
    }
}

#[test]
fn app_que_nao_responde_nao_segura_o_gancho_alem_de_1s() {
    let server = FakeServer::start(|_| {
        std::thread::sleep(Duration::from_secs(3));
        (200, b"{}".to_vec())
    });
    let started = std::time::Instant::now();
    hook(&server.sock, "ask", "{}", true, WAIT);
    assert!(
        started.elapsed() < Duration::from_millis(2500),
        "{:?}",
        started.elapsed()
    );
}

fn permission_server(answer: &'static str, polls_pending: usize) -> (FakeServer, Arc<AtomicUsize>) {
    let polls = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&polls);
    let server =
        FakeServer::start(
            move |seen| match (seen.method.as_str(), seen.target.as_str()) {
                ("POST", "/permission") => (200, br#"{"id":"p-1"}"#.to_vec()),
                ("GET", "/permission?id=p-1") => {
                    let n = counter.fetch_add(1, Ordering::SeqCst);
                    if n < polls_pending {
                        (200, br#"{"state":"pending"}"#.to_vec())
                    } else {
                        (200, answer.as_bytes().to_vec())
                    }
                }
                _ => (404, b"{}".to_vec()),
            },
        );
    (server, polls)
}

#[test]
fn permission_devolve_a_decisao_do_chat_no_formato_do_python() {
    let answer = r#"{"state":"answered","output":{"z":1,"hookSpecificOutput":{"decision":{"behavior":"allow","message":"ação"}}}}"#;
    let (server, polls) = permission_server(answer, 2);
    let payload = "{\"tool_name\":\"Bash\"}\n\n";
    let out = hook(&server.sock, "permission", payload, true, WAIT);
    assert_eq!(
        out,
        "{\"z\": 1, \"hookSpecificOutput\": {\"decision\": {\"behavior\": \"allow\", \"message\": \"a\\u00e7\\u00e3o\"}}}\n"
    );
    assert_eq!(polls.load(Ordering::SeqCst), 3);

    let seen = server.seen();
    assert_eq!(seen[0].method, "POST");
    // O shell tirava as quebras de linha do fim do payload.
    assert_eq!(seen[0].body_text(), "{\"tool_name\":\"Bash\"}");
    assert!(seen[0].head.contains("Content-Length: 20"));
}

#[test]
fn permission_respondida_no_terminal_sai_calada() {
    for state in ["gone", "expired", ""] {
        let answer = format!(r#"{{"state":"{state}"}}"#);
        let (server, _) = permission_server(Box::leak(answer.into_boxed_str()), 0);
        assert_eq!(
            hook(&server.sock, "permission", "{}", true, WAIT),
            "",
            "{state}"
        );
    }
}

#[test]
fn permission_respondida_sem_output_devolve_objeto_vazio() {
    for answer in [
        r#"{"state":"answered"}"#,
        r#"{"state":"answered","output":null}"#,
    ] {
        let (server, _) = permission_server(answer, 0);
        assert_eq!(hook(&server.sock, "permission", "{}", true, WAIT), "{}\n");
    }
}

#[test]
fn permission_sem_id_nao_espera_nada() {
    let server = FakeServer::start(|_| (200, br#"{"error":"nao"}"#.to_vec()));
    assert_eq!(hook(&server.sock, "permission", "{}", true, WAIT), "");
    assert_eq!(server.seen().len(), 1);
}

#[test]
fn permission_desiste_calada_quando_o_prazo_acaba() {
    let (server, polls) = permission_server(r#"{"state":"pending"}"#, usize::MAX);
    let out = hook(
        &server.sock,
        "permission",
        "{}",
        true,
        Duration::from_secs(2),
    );
    assert_eq!(out, "");
    // De 0,4 em 0,4 s, a primeira pergunta depois da primeira espera.
    assert_eq!(polls.load(Ordering::SeqCst), 5);
}

#[test]
fn permission_cai_calada_se_o_app_some_no_meio() {
    let calls = Arc::new(AtomicUsize::new(0));
    let counter = Arc::clone(&calls);
    let server = FakeServer::start(move |_| {
        if counter.fetch_add(1, Ordering::SeqCst) == 0 {
            (200, br#"{"id":"p-1"}"#.to_vec())
        } else {
            (0, Vec::new())
        }
    });
    assert_eq!(hook(&server.sock, "permission", "{}", true, WAIT), "");
    assert_eq!(calls.load(Ordering::SeqCst), 2);
}

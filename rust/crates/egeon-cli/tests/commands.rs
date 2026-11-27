//! Cada subcomando contra um servidor falso: a rota, o corpo e a saída que o
//! script `egeon` do Swift produzia.

mod common;

use common::{FakeServer, egeon, egeon_at};

fn one(server: &FakeServer) -> common::Seen {
    let mut seen = server.seen();
    assert_eq!(seen.len(), 1, "esperava uma requisição: {seen:?}");
    seen.remove(0)
}

fn assert_get(server: &FakeServer, target: &str) {
    let seen = one(server);
    assert_eq!(
        (seen.method.as_str(), seen.target.as_str()),
        ("GET", target)
    );
    assert!(!seen.head.to_lowercase().contains("content-length"));
}

fn assert_post(server: &FakeServer, target: &str, body: &str) {
    let seen = one(server);
    assert_eq!(
        (seen.method.as_str(), seen.target.as_str()),
        ("POST", target)
    );
    assert_eq!(seen.body_text(), body);
}

#[test]
fn leituras_sao_get_e_devolvem_o_corpo_como_veio() {
    for (command, route) in [
        ("peers", "/peers"),
        ("status", "/status"),
        ("tasks", "/tasks"),
        ("bench", "/maestro/bench"),
        ("models", "/maestro/models"),
        ("permissions", "/maestro/asks"),
        ("ps", "/processes"),
    ] {
        let server = FakeServer::ok("{\"ok\":true}\n");
        let outcome = egeon(&server, &[command], b"");
        assert_eq!(
            (outcome.code, outcome.out_text()),
            (0, "{\"ok\":true}\n".into())
        );
        assert_get(&server, route);
    }
}

#[test]
fn send_codifica_o_endereco_e_leva_o_stdin_inteiro() {
    let server = FakeServer::ok("{}");
    let text = "linha 1\n\nlinha 2 com ação & = ?\n\n";
    let outcome = egeon(
        &server,
        &["send", "SPEI + SPI/backend", "ignorado"],
        text.as_bytes(),
    );
    assert_eq!(outcome.code, 0);
    assert_post(&server, "/message?target=SPEI%20%2B%20SPI/backend", text);
}

#[test]
fn send_e_peek_sem_endereco_dao_uso_e_nao_chamam_o_app() {
    let server = FakeServer::ok("{}");
    let sent = egeon(&server, &["send"], b"x");
    assert_eq!(sent.code, 2);
    assert_eq!(sent.err, "uso: egeon send <endereço> (texto no stdin)\n");
    let peeked = egeon(&server, &["peek"], b"");
    assert_eq!(peeked.code, 2);
    assert_eq!(peeked.err, "uso: egeon peek <endereço> [linhas]\n");
    assert!(server.seen().is_empty());
}

#[test]
fn peek_leva_as_linhas_so_quando_dadas() {
    let server = FakeServer::ok("{}");
    egeon(&server, &["peek", "deck/revisor"], b"");
    assert_get(&server, "/peek?target=deck/revisor");
    egeon(&server, &["peek", "deck/revisor", "40"], b"");
    assert_get(&server, "/peek?target=deck/revisor&lines=40");
    egeon(&server, &["peek", "deck/revisor", ""], b"");
    assert_get(&server, "/peek?target=deck/revisor");
}

#[test]
fn trace_junta_os_argumentos_ou_le_o_stdin() {
    let server = FakeServer::ok("{}");
    egeon(
        &server,
        &["trace", "pedido:", "x", "—", "entrega: y"],
        b"nao lido",
    );
    assert_post(&server, "/trace", "pedido: x — entrega: y");
    egeon(&server, &["trace"], "várias\nlinhas\n".as_bytes());
    assert_post(&server, "/trace", "várias\nlinhas\n");
}

#[test]
fn task_done_nao_espera_o_stdin() {
    let server = FakeServer::ok("{}");
    egeon(&server, &["task", "done", "T 1"], b"nao lido");
    assert_post(&server, "/task?action=done&id=T%201", "");
    egeon(
        &server,
        &["task", "done", "T-1", "feito", "e", "testado"],
        b"",
    );
    assert_post(&server, "/task?action=done&id=T-1", "feito e testado");
}

#[test]
fn task_ask_e_note_leem_o_stdin_ou_os_argumentos() {
    let server = FakeServer::ok("{}");
    egeon(&server, &["task", "ask", "T-1"], b"posso?\n");
    assert_post(&server, "/task?action=ask&id=T-1", "posso?\n");
    egeon(&server, &["task", "note", "T-1", "olhei"], b"nao lido");
    assert_post(&server, "/task?action=note&id=T-1", "olhei");
}

#[test]
fn task_sem_id_da_uso() {
    let server = FakeServer::ok("{}");
    let outcome = egeon(&server, &["task", "done"], b"");
    assert_eq!(outcome.code, 2);
    assert_eq!(
        outcome.err,
        "uso: egeon task done|ask|note <id> [texto, ou no stdin]\n"
    );
    assert!(server.seen().is_empty());
}

#[test]
fn ps_orphans_e_kill() {
    let server = FakeServer::ok("{}");
    egeon(&server, &["ps", "--orphans"], b"");
    assert_get(&server, "/processes?orphans=1");
    egeon(&server, &["ps", "--kill"], b"");
    assert_post(&server, "/processes/kill", "");
    egeon(&server, &["ps", "--kill", "12", "34", "56"], b"");
    assert_post(&server, "/processes/kill?pid=12,34,56", "");
    egeon(&server, &["ps", "qualquer", "coisa"], b"");
    assert_get(&server, "/processes");
}

#[test]
fn plan_e_apply_levam_o_plano_do_stdin() {
    let server = FakeServer::ok("{}");
    let plan = "{\"nodes\": []}\n";
    egeon(&server, &["plan"], plan.as_bytes());
    assert_post(&server, "/maestro/apply?dry=1", plan);
    egeon(&server, &["apply"], plan.as_bytes());
    assert_post(&server, "/maestro/apply", plan);
}

#[test]
fn o_bom_do_powershell_sai_do_stdin_de_plan_apply_send_e_trace() {
    // Os bytes que o PowerShell 5.1 mandou no Windows: quebra, BOM, texto.
    let plan = "{\"nodes\": []}\n";
    for (args, route) in [
        (&["plan"][..], "/maestro/apply?dry=1"),
        (&["apply"][..], "/maestro/apply"),
        (&["send", "deck/b"][..], "/message?target=deck/b"),
        (&["trace"][..], "/trace"),
    ] {
        let server = FakeServer::ok("{}");
        egeon(&server, args, format!("\u{feff}{plan}").as_bytes());
        assert_post(&server, route, plan);
        egeon(&server, args, format!("\n\u{feff}{plan}").as_bytes());
        assert_post(&server, route, &format!("\n{plan}"));
    }
    let server = FakeServer::ok("{}");
    let inside = "texto com \u{feff} no meio\n";
    egeon(&server, &["send", "deck/b"], inside.as_bytes());
    assert_post(&server, "/message?target=deck/b", inside);
}

#[test]
fn allow_deny_e_always() {
    let server = FakeServer::ok("{}");
    egeon(&server, &["allow", "a 1"], b"");
    assert_post(&server, "/maestro/answer?id=a%201&answer=allow", "");
    egeon(&server, &["allow", "a1", "--always"], b"");
    assert_post(&server, "/maestro/answer?id=a1&answer=always", "");
    egeon(&server, &["deny", "a1"], b"");
    assert_post(&server, "/maestro/answer?id=a1&answer=deny", "");
    // `--always` só vale no `allow`.
    egeon(&server, &["deny", "a1", "--always"], b"");
    assert_post(&server, "/maestro/answer?id=a1&answer=deny", "");
}

#[test]
fn allow_e_deny_sem_id_dao_uso() {
    let server = FakeServer::ok("{}");
    let allow = egeon(&server, &["allow"], b"");
    assert_eq!(
        (allow.code, allow.err.as_str()),
        (2, "uso: egeon allow <id do pedido>\n")
    );
    let deny = egeon(&server, &["deny"], b"");
    assert_eq!(
        (deny.code, deny.err.as_str()),
        (2, "uso: egeon deny <id do pedido>\n")
    );
    assert!(server.seen().is_empty());
}

#[test]
fn guide_imprime_o_manual_embutido_sem_o_app() {
    let nowhere = tempfile::tempdir().unwrap();
    let outcome = egeon_at(&nowhere.path().join("sem-socket"), &["guide"], b"");
    assert_eq!(outcome.code, 0);
    let text = outcome.out_text();
    assert!(text.starts_with("# Maestro — montar a bancada\n"));
    assert!(text.ends_with("\n"));
    assert!(text.contains("egeon apply"));
}

// Porte de `testMaestroCommandsAndGuide`: o `guide` imprime o manual do core,
// inteiro e sem expandir nada, e mais um `\n` — o heredoc do Swift.
#[test]
fn guide_e_exatamente_o_texto_do_core_com_uma_quebra_no_fim() {
    use egeon_core::features::maestro::guide::TEXT;
    let nowhere = tempfile::tempdir().unwrap();
    let outcome = egeon_at(&nowhere.path().join("sem-socket"), &["guide"], b"");
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.out_text(), format!("{TEXT}\n"));
    assert_eq!(outcome.err, "");
}

// Porte de `testPeekIsOfferedAndDocumented`: a ajuda que o programa IMPRIME
// mostra os dez comandos que o agente usa, e as rotas deles existem.
#[test]
fn a_ajuda_impressa_lista_os_dez_comandos() {
    let server = FakeServer::ok("{}");
    let shown = egeon(&server, &[], b"").out_text();
    for command in [
        "egeon peers",
        "egeon send",
        "egeon peek",
        "egeon trace",
        "egeon status",
        "egeon bench",
        "egeon models",
        "egeon plan",
        "egeon apply",
        "egeon guide",
    ] {
        assert!(
            shown.contains(command),
            "a ajuda impressa não mostra `{command}`"
        );
    }
    assert!(server.seen().is_empty());
    for (args, target, post) in [
        (
            &["peek", "deck/front"][..],
            "/peek?target=deck/front",
            false,
        ),
        (&["bench"][..], "/maestro/bench", false),
        (&["models"][..], "/maestro/models", false),
        (&["plan"][..], "/maestro/apply?dry=1", true),
        (&["apply"][..], "/maestro/apply", true),
    ] {
        let server = FakeServer::ok("{}");
        egeon(&server, args, b"{}");
        let seen = one(&server);
        assert_eq!(seen.target, target, "{args:?}");
        assert_eq!(seen.method == "POST", post, "{args:?}");
    }
}

// O que o script instalado imprimia sem argumento: as linhas 2 a 25 dele, que
// terminam no `allow` — o `deny` e o último parágrafo ficam de fora.
#[test]
fn sem_argumento_ou_comando_desconhecido_imprime_o_uso_e_sai_com_2() {
    let usage = egeon_cli::commands::USAGE;
    assert!(usage.starts_with("Egeon Deck — falar com os outros terminais desta bancada.\n\n"));
    assert!(
        usage.ends_with("  egeon allow <id> [--always]  permite (--always: não pergunta mais)\n")
    );
    assert_eq!(usage.lines().count(), 24);
    assert!(!usage.contains("deny"));
    let server = FakeServer::ok("{}");
    for args in [&[][..], &["nada"][..], &["hook-nao"][..], &[""][..]] {
        let outcome = egeon(&server, args, b"");
        assert_eq!(outcome.code, 2, "{args:?}");
        assert_eq!(outcome.out_text(), usage);
        assert_eq!(outcome.err, "");
    }
    assert!(server.seen().is_empty());
}

#[test]
fn peek_e_kill_recusam_o_que_o_curl_recusava() {
    let server = FakeServer::ok("{}");
    for bad in [
        "3 4",
        "3\r\nX: y",
        "[1-3]",
        "{a,b}",
        "3\u{7f}",
        "3]",
        "3}",
        "3#a b",
        "3#{",
    ] {
        let peek = egeon(&server, &["peek", "a", bad], b"");
        assert_eq!(peek.code, 3, "{bad:?}");
        assert_eq!(
            peek.err,
            "curl: (3) URL rejected: Malformed input to a URL function\n"
        );
        assert_eq!(
            egeon(&server, &["ps", "--kill", "1", bad], b"").code,
            3,
            "{bad:?}"
        );
    }
    assert!(server.seen().is_empty());
    // O fragmento não vai na requisição.
    egeon(&server, &["peek", "a", "5#resto"], b"");
    assert_get(&server, "/peek?target=a&lines=5");
    egeon(&server, &["ps", "--kill", "7#x", "8"], b"");
    assert_post(&server, "/processes/kill?pid=7", "");
}

#[test]
fn status_http_de_erro_imprime_o_corpo_e_sai_com_22() {
    let server = FakeServer::start(|_| (403, b"{\"error\":\"so o maestro\"}\n".to_vec()));
    let outcome = egeon(&server, &["bench"], b"");
    assert_eq!(outcome.code, 22);
    assert_eq!(outcome.out_text(), "{\"error\":\"so o maestro\"}\n");
    assert_eq!(
        outcome.err,
        "curl: (22) The requested URL returned error: 403\n"
    );
}

#[test]
fn sem_app_sai_com_7() {
    let nowhere = tempfile::tempdir().unwrap();
    let outcome = egeon_at(&nowhere.path().join("sem-socket"), &["peers"], b"");
    assert_eq!(outcome.code, 7);
    assert_eq!(outcome.out, b"");
    assert_eq!(
        outcome.err,
        "curl: (7) Failed to connect to eg port 80 after 0 ms: Couldn't connect to server\n"
    );
}

#[test]
fn app_que_fecha_sem_responder_sai_com_52() {
    let server = FakeServer::start(|_| (0, Vec::new()));
    let outcome = egeon(&server, &["status"], b"");
    assert_eq!(outcome.code, 52);
    assert_eq!(outcome.err, "curl: (52) Empty reply from server\n");
}

fn http_reply(body: &[u8], content_length: bool) -> Vec<u8> {
    let mut reply = b"HTTP/1.1 200 OK\r\nConnection: close\r\n".to_vec();
    if content_length {
        reply.extend_from_slice(format!("Content-Length: {}\r\n", body.len()).as_bytes());
    }
    reply.extend_from_slice(b"\r\n");
    reply.extend_from_slice(body);
    reply
}

// No macOS, ajustar o prazo de um socket que o par já fechou dá EINVAL; o
// corpo que já chegou não pode se perder por isso. Um `peek` de 20 KB falhava
// com 56 em 5 de cada 6 rodadas.
#[test]
fn resposta_grande_de_servidor_que_fecha_logo_chega_inteira() {
    let body: Vec<u8> = (0..20_000u32).map(|i| b'a' + (i % 26) as u8).collect();
    for with_length in [true, false] {
        for _ in 0..30 {
            let server = FakeServer::raw(http_reply(&body, with_length));
            let outcome = egeon(&server, &["peek", "a/b"], b"");
            assert_eq!(
                (outcome.code, outcome.err.as_str()),
                (0, ""),
                "content-length: {with_length}"
            );
            assert_eq!(outcome.out, body, "content-length: {with_length}");
        }
    }
}

// Porte de `testCLIOffersPs`: o comando oferece `ps`, e `ps --kill` chama a
// rota de encerrar.
#[test]
fn o_cli_oferece_ps() {
    let usage = egeon_cli::commands::USAGE;
    assert!(usage.contains("egeon ps [--orphans]"));
    assert!(usage.contains("egeon ps --kill [pid"));
    // E é a ajuda que o programa imprime, não só a constante.
    let printed = egeon(&FakeServer::ok("{}"), &[], b"").out_text();
    assert!(printed.contains("egeon ps [--orphans]"));
    let server = FakeServer::ok("{}");
    egeon(&server, &["ps", "--kill", "10"], b"");
    assert_post(&server, "/processes/kill?pid=10", "");
}

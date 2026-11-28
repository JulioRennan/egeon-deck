use std::path::PathBuf;

use serde_json::{Value, json};

use super::ProtocolError;
use super::http::{Parsed, Request, json_response, parse_query, parse_request, upgrade_response};
use super::message::{
    Command, CommandKind, CreateTerminal, Event, EventBody, NodeId, Reply, TerminalInfo, Topic,
    parse_command, to_line,
};
use super::routes::{FeatureRoute, Rejected, Route, route};
use super::screen::{
    Color, Cursor, CursorShape, Frame, FrameKind, Key, KeyPress, Line, Mods, NamedKey, RgbHex,
    Scrollbar, Span, Style,
};

fn complete(buf: &[u8]) -> (Request, usize) {
    match parse_request(buf, false).unwrap() {
        Parsed::Complete { request, consumed } => (request, consumed),
        Parsed::Partial => panic!("esperava requisição completa"),
    }
}

fn req(raw: &str) -> Request {
    complete(raw.as_bytes()).0
}

#[test]
fn requisicao_valida_com_corpo() {
    let raw = b"POST /message?from=a&target=deck%2Fclaude-1 HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nola!!";
    let (r, consumed) = complete(raw);
    assert_eq!(r.method, "POST");
    assert_eq!(r.path(), "/message");
    assert_eq!(r.header("host"), Some("x"));
    assert_eq!(r.header("CONTENT-LENGTH"), Some("5"));
    assert_eq!(r.body, b"ola!!");
    assert_eq!(consumed, raw.len());
    let q = r.query();
    assert_eq!(q["target"], "deck/claude-1");
    assert_eq!(q["from"], "a");
}

#[test]
fn requisicao_sem_corpo() {
    let r = req("GET /about HTTP/1.1\r\nHost: x\r\n\r\n");
    assert_eq!(r.method, "GET");
    assert_eq!(r.path(), "/about");
    assert!(r.body.is_empty());
}

#[test]
fn cabecalho_incompleto_pede_mais() {
    assert_eq!(
        parse_request(b"GET /about HTTP/1.1\r\nHost:", false).unwrap(),
        Parsed::Partial
    );
}

#[test]
fn corpo_parcial_pede_mais_e_no_fim_segue_com_o_que_chegou() {
    let raw = b"POST /trace HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc";
    assert_eq!(parse_request(raw, false).unwrap(), Parsed::Partial);
    // O par fechou a escrita: como o Swift, segue com o corpo que veio.
    match parse_request(raw, true).unwrap() {
        Parsed::Complete { request, .. } => assert_eq!(request.body, b"abc"),
        Parsed::Partial => panic!("no fim não há mais o que esperar"),
    }
}

#[test]
fn bytes_depois_do_corpo_ficam_para_o_canal() {
    let raw =
        b"GET /ui HTTP/1.1\r\nUpgrade: egeon-ndjson\r\n\r\n{\"id\":1,\"cmd\":\"list_terminals\"}\n";
    let (_, consumed) = complete(raw);
    assert_eq!(&raw[consumed..], b"{\"id\":1,\"cmd\":\"list_terminals\"}\n");
}

#[test]
fn cabecalho_malformado_e_ignorado_como_no_swift() {
    // Linha sem `:` não derruba o pedido: o Swift só procurava o
    // Content-Length e passava por cima do resto.
    let r = req("GET /about HTTP/1.1\r\nsem-dois-pontos\r\nHost: x\r\n\r\n");
    assert_eq!(r.path(), "/about");
    assert_eq!(r.header("host"), Some("x"));
    assert_eq!(route(&r), Ok(Route::About));
    let r = req("GET /about HTTP/1.1\r\nNome Com Espaco: x\r\n\r\n");
    assert_eq!(r.header("nome com espaco"), Some("x"));
}

#[test]
fn linha_de_requisicao_como_no_swift() {
    // Espaço duplo some no `split`.
    let r = req("GET  /about  HTTP/1.1\r\n\r\n");
    assert_eq!((r.method.as_str(), r.target.as_str()), ("GET", "/about"));
    // Alvo absoluto: as rotas de hoje casam por sufixo, e /about responde.
    let r = req("GET http://x/about HTTP/1.1\r\n\r\n");
    assert_eq!(route(&r), Ok(Route::About));
    // Sem versão, ou só o método: vira pedido sem rota, e a rota responde 404.
    let r = req("GET /about\r\n\r\n");
    assert_eq!(route(&r), Ok(Route::About));
    let r = req("GET\r\n\r\n");
    assert_eq!(r.target, "");
    assert!(matches!(route(&r), Err(Rejected { status: 404, .. })));
}

#[test]
fn content_length_ausente_ou_invalido_usa_o_que_chegou() {
    for raw in [
        "POST /trace HTTP/1.1\r\n\r\nola",
        "POST /trace HTTP/1.1\r\nContent-Length: dez\r\n\r\nola",
        "POST /trace HTTP/1.1\r\nContent-Length:\r\n\r\nola",
    ] {
        let (r, consumed) = complete(raw.as_bytes());
        assert_eq!(r.body, b"ola", "{raw:?}");
        assert_eq!(consumed, raw.len());
    }
    // Só a primeira linha de Content-Length conta, sem diferença de caixa.
    let r = req("POST /x HTTP/1.1\r\ncontent-LENGTH: 2\r\nContent-Length: 9\r\n\r\nabcdef");
    assert_eq!(r.body, b"ab");
}

#[test]
fn corpo_acima_do_teto_e_erro_antes_de_ler() {
    let raw = format!(
        "POST /x HTTP/1.1\r\nContent-Length: {}\r\n\r\n",
        super::http::MAX_BODY + 1
    );
    assert_eq!(
        parse_request(raw.as_bytes(), false).unwrap_err(),
        ProtocolError::BodyTooLarge(super::http::MAX_BODY + 1)
    );
}

#[test]
fn cabecalho_gigante_e_erro() {
    let mut raw = b"GET /x HTTP/1.1\r\nX: ".to_vec();
    raw.resize(super::http::MAX_HEAD + 10, b'a');
    assert_eq!(
        parse_request(&raw, false).unwrap_err(),
        ProtocolError::HeadTooLarge
    );
}

#[test]
fn conexao_fechada_antes_do_cabecalho_e_erro() {
    assert_eq!(
        parse_request(b"GET /ab", true).unwrap_err(),
        ProtocolError::Truncated
    );
}

#[test]
fn query_como_no_swift() {
    let q = parse_query("/x?a=1&b&c=&=d&e=um%20dois&f=%zz&g=a=b&h=+");
    assert_eq!(q.get("a").map(String::as_str), Some("1"));
    assert!(!q.contains_key("b"));
    assert!(!q.contains_key("c"));
    assert!(!q.contains_key(""));
    assert_eq!(q["e"], "um dois");
    assert_eq!(q["f"], "%zz", "escape quebrado fica como veio");
    assert_eq!(q["g"], "a=b");
    assert_eq!(q["h"], "+", "+ não vira espaço");
    assert!(parse_query("/x").is_empty());
    // Só o trecho entre o primeiro e o segundo `?`.
    assert_eq!(parse_query("/x?a=1?b=2").get("b"), None);
    // Nome de bancada com espaço e `+`, codificado pelo `enc` do shell.
    assert_eq!(
        parse_query("/x?target=SPEI%20%2B%20SPI%2Fbackend")["target"],
        "SPEI + SPI/backend"
    );
    // UTF-8 por bytes: `ç` são dois.
    assert_eq!(parse_query("/x?t=a%C3%A7o")["t"], "aço");
}

#[test]
fn resposta_json_tem_tamanho_e_fecha() {
    let out = String::from_utf8(json_response(404, &json!({"ok": false}))).unwrap();
    assert!(out.starts_with("HTTP/1.1 404 Not Found\r\n"));
    assert!(out.contains("Content-Type: application/json\r\n"));
    assert!(out.contains("Content-Length: 12\r\n"));
    assert!(out.contains("Connection: close\r\n\r\n"));
    assert!(out.ends_with("{\"ok\":false}"));
}

#[test]
fn upgrade_do_canal_ui() {
    let r = req("GET /ui HTTP/1.1\r\nConnection: Upgrade\r\nUpgrade: egeon-ndjson\r\n\r\n");
    assert!(r.is_ui_upgrade());
    assert_eq!(route(&r), Ok(Route::Ui));
    // Caixa e lista de protocolos não atrapalham.
    assert!(req("GET /ui HTTP/1.1\r\nupgrade: websocket, EGEON-NDJSON\r\n\r\n").is_ui_upgrade());

    let resp = String::from_utf8(upgrade_response()).unwrap();
    assert!(resp.starts_with("HTTP/1.1 101 Switching Protocols\r\n"));
    assert!(resp.contains("Upgrade: egeon-ndjson\r\n"));
    assert!(resp.ends_with("\r\n\r\n"));
}

#[test]
fn ui_sem_upgrade_ou_com_outro_protocolo_e_recusado() {
    for raw in [
        "GET /ui HTTP/1.1\r\n\r\n",
        "GET /ui HTTP/1.1\r\nUpgrade: websocket\r\n\r\n",
        "POST /ui HTTP/1.1\r\nUpgrade: egeon-ndjson\r\n\r\n",
    ] {
        let r = req(raw);
        assert!(!r.is_ui_upgrade(), "{raw:?}");
        assert!(
            matches!(route(&r), Err(Rejected { status: 400, .. })),
            "{raw:?}"
        );
    }
}

#[test]
fn rotas_do_terminal() {
    assert_eq!(route(&req("GET /about HTTP/1.1\r\n\r\n")), Ok(Route::About));
    assert_eq!(
        route(&req("GET /eg/about HTTP/1.1\r\n\r\n")),
        Ok(Route::About)
    );
    assert_eq!(
        route(&req("GET /terminals HTTP/1.1\r\n\r\n")),
        Ok(Route::ListTerminals)
    );
    assert_eq!(
        route(&req("POST /terminal HTTP/1.1\r\n\r\n")),
        Ok(Route::CreateTerminal(CreateTerminal::default()))
    );
    let body = r#"{"cwd":"/tmp","cmd":"htop"}"#;
    let raw = format!(
        "POST /terminal HTTP/1.1\r\nContent-Length: {}\r\n\r\n{body}",
        body.len()
    );
    assert_eq!(
        route(&req(&raw)),
        Ok(Route::CreateTerminal(CreateTerminal {
            cwd: Some("/tmp".into()),
            command: Some("htop".into()),
            ..Default::default()
        }))
    );
    assert!(matches!(
        route(&req(
            "POST /terminal HTTP/1.1\r\nContent-Length: 1\r\n\r\n{"
        )),
        Err(Rejected { status: 400, .. })
    ));
    assert_eq!(
        route(&req(
            "POST /terminal/t1/input HTTP/1.1\r\nContent-Length: 3\r\n\r\nls\n"
        )),
        Ok(Route::Input {
            node: NodeId::new("t1").unwrap(),
            bytes: b"ls\n".to_vec()
        })
    );
    assert!(matches!(
        route(&req("GET /terminal/t1/input HTTP/1.1\r\n\r\n")),
        Err(Rejected { status: 405, .. })
    ));
    assert!(matches!(
        route(&req("POST /terminal/a%20b/input HTTP/1.1\r\n\r\n")),
        Err(Rejected { status: 400, .. })
    ));
    assert!(matches!(
        route(&req("GET /nada HTTP/1.1\r\n\r\n")),
        Err(Rejected { status: 404, .. })
    ));
}

/// O `/peek` vai ao dispatch com a requisição inteira: endereço, vizinho e
/// linhas são decididos lá, como no Swift (ControlSocket.swift:744).
#[test]
fn peek_vai_ao_dispatch_com_a_requisicao() {
    let peek = |raw: &str| route(&req(raw));
    let Ok(Route::Feature { route, request }) =
        peek("GET /peek?target=deck%2Fb&lines=5 HTTP/1.1\r\n\r\n")
    else {
        panic!("não foi para o dispatch");
    };
    assert_eq!(route, FeatureRoute::Peek);
    assert_eq!(request.param("target"), Some("deck/b"));
    assert_eq!(request.param("lines"), Some("5"));
    // Como no Swift, `/peek` em qualquer lugar do alvo, query incluída, e
    // antes de `/about`.
    assert!(matches!(
        peek("GET /about?x=/peek HTTP/1.1\r\n\r\n"),
        Ok(Route::Feature {
            route: FeatureRoute::Peek,
            ..
        })
    ));
}

#[test]
fn node_id_valida() {
    assert!(NodeId::new("t1").is_ok());
    assert!(NodeId::new("claude-1.dev_2").is_ok());
    for bad in ["", "a/b", "a b", "ç", &"x".repeat(65)] {
        assert!(NodeId::new(bad).is_err(), "{bad:?}");
    }
}

#[test]
fn topicos() {
    assert_eq!(Topic::parse("terminals").unwrap(), Topic::Terminals);
    assert_eq!(
        Topic::parse("screen/t1").unwrap(),
        Topic::Screen(NodeId::new("t1").unwrap())
    );
    assert!(matches!(
        Topic::parse("screen/"),
        Err(ProtocolError::Id(crate::commons::ids::IdError::Node(_)))
    ));
    assert!(matches!(
        Topic::parse("inbox/x"),
        Err(ProtocolError::UnknownTopic(_))
    ));
}

#[test]
fn comando_invalido_guarda_o_id_para_a_resposta() {
    assert!(matches!(
        parse_command("{nada"),
        Err(ProtocolError::InvalidJson(_))
    ));
    assert_eq!(
        parse_command(r#"{"cmd":"list_terminals"}"#).unwrap_err(),
        ProtocolError::MissingId
    );
    assert!(matches!(
        parse_command(r#"{"id":9,"cmd":"voar"}"#),
        Err(ProtocolError::BadCommand { id: 9, .. })
    ));
    assert!(matches!(
        parse_command(r#"{"id":9,"cmd":"subscribe","topic":"inbox/x"}"#),
        Err(ProtocolError::BadCommand { id: 9, .. })
    ));
}

#[test]
fn linha_termina_em_quebra_e_nao_tem_outra() {
    let line = to_line(&Reply::ok(1)).unwrap();
    assert_eq!(line.last(), Some(&b'\n'));
    assert_eq!(line.iter().filter(|b| **b == b'\n').count(), 1);
    // Quebra de linha dentro do texto sai escapada.
    let line = to_line(&Reply::err(1, "a\nb")).unwrap();
    assert_eq!(line.iter().filter(|b| **b == b'\n').count(), 1);
}

#[test]
fn reply_with_nao_duplica_re_ok_e_error() {
    let r = Reply::with(1, &json!({"ok": false, "error": "x", "re": 9, "n": 2}));
    let value = serde_json::to_value(&r).unwrap();
    assert_eq!(value, json!({"re": 1, "ok": false, "error": "x", "n": 2}));
    // E volta a ler: sem campo duplicado no fio.
    let line = String::from_utf8(to_line(&r).unwrap()).unwrap();
    assert_eq!(serde_json::from_str::<Reply>(&line).unwrap(), r);

    let r = Reply::with(2, &json!({"ok": true, "version": "1"}));
    assert_eq!(
        serde_json::to_value(&r).unwrap(),
        json!({"re": 2, "ok": true, "version": "1"})
    );
    let r = Reply::with(3, &json!({"ok": false}));
    assert_eq!(r.error.as_deref(), Some("falhou"));
}

#[test]
fn reply_com_valor_que_nao_e_objeto() {
    let r = Reply::with(3, &vec![1, 2]);
    assert_eq!(
        serde_json::to_value(&r).unwrap(),
        json!({"re":3,"ok":true,"value":[1,2]})
    );
}

#[test]
fn cor_rgb_aceita_so_o_formato() {
    let c: Color = serde_json::from_value(json!("#0a0B0c")).unwrap();
    assert_eq!(c, Color::Rgb(RgbHex([10, 11, 12])));
    assert_eq!(serde_json::to_value(c).unwrap(), json!("#0a0b0c"));
    assert_eq!(
        serde_json::from_value::<Color>(json!(9)).unwrap(),
        Color::Palette(9)
    );
    for bad in [
        json!("0a0b0c"),
        json!("#0a0b"),
        json!("#zzzzzz"),
        json!(300),
    ] {
        assert!(
            serde_json::from_value::<Color>(bad.clone()).is_err(),
            "{bad}"
        );
    }
}

fn t1() -> NodeId {
    NodeId::new("t1").unwrap()
}

fn sample_frame(kind: FrameKind) -> Frame {
    Frame {
        kind,
        cols: 80,
        rows: 24,
        cursor: Cursor {
            row: 1,
            col: 2,
            visible: true,
            shape: CursorShape::Block,
        },
        scrollbar: (kind == FrameKind::Full).then_some(Scrollbar {
            total: 24,
            offset: 0,
            len: 24,
        }),
        lines: vec![
            Line {
                row: 0,
                spans: vec![
                    Span {
                        col: 0,
                        cells: 6,
                        text: "hello ".into(),
                        style: Style::default(),
                    },
                    Span {
                        col: 6,
                        cells: 5,
                        text: "world".into(),
                        style: Style {
                            fg: Some(Color::Palette(2)),
                            bold: true,
                            ..Default::default()
                        },
                    },
                    Span {
                        col: 11,
                        cells: 4,
                        text: "日本".into(),
                        style: Style {
                            fg: Some(Color::Rgb(RgbHex([0xff, 0x88, 0x00]))),
                            bg: Some(Color::Palette(236)),
                            italic: true,
                            underline: true,
                            ..Default::default()
                        },
                    },
                ],
                selection: Some([6, 10]),
            },
            Line {
                row: 1,
                spans: vec![Span {
                    col: 0,
                    cells: 2,
                    text: "$ ".into(),
                    style: Style {
                        dim: true,
                        strike: true,
                        inverse: true,
                        ..Default::default()
                    },
                }],
                selection: None,
            },
            Line {
                row: 2,
                spans: vec![],
                selection: None,
            },
        ],
    }
}

fn info(alive: bool) -> TerminalInfo {
    TerminalInfo {
        id: t1(),
        cwd: "/Users/eu/projeto".into(),
        command: if alive {
            None
        } else {
            Some("make test".into())
        },
        pid: 4242,
        cols: 80,
        rows: 24,
        alive,
        exit_code: if alive { None } else { Some(0) },
    }
}

fn commands() -> Vec<(&'static str, Command)> {
    let c = |id, kind| Command { id, kind };
    vec![
        (
            "subscribe_screen",
            c(
                1,
                CommandKind::Subscribe {
                    topic: Topic::Screen(t1()),
                },
            ),
        ),
        (
            "subscribe_terminals",
            c(
                2,
                CommandKind::Subscribe {
                    topic: Topic::Terminals,
                },
            ),
        ),
        (
            "unsubscribe",
            c(
                3,
                CommandKind::Unsubscribe {
                    topic: Topic::Screen(t1()),
                },
            ),
        ),
        (
            "create_terminal",
            c(
                4,
                CommandKind::CreateTerminal(CreateTerminal {
                    cwd: Some("/Users/eu/projeto".into()),
                    command: None,
                    cols: Some(80),
                    rows: Some(24),
                }),
            ),
        ),
        (
            "create_terminal_minimo",
            c(5, CommandKind::CreateTerminal(CreateTerminal::default())),
        ),
        (
            "input",
            c(
                6,
                CommandKind::Input {
                    node: t1(),
                    text: "echo oi\r".into(),
                },
            ),
        ),
        (
            "key_enter",
            c(
                7,
                CommandKind::Key {
                    node: t1(),
                    press: KeyPress {
                        key: Key::Named(NamedKey::Enter),
                        mods: Mods::default(),
                        text: None,
                    },
                },
            ),
        ),
        (
            "key_ctrl_c",
            c(
                8,
                CommandKind::Key {
                    node: t1(),
                    press: KeyPress {
                        key: Key::Char("c".into()),
                        mods: Mods {
                            ctrl: true,
                            ..Default::default()
                        },
                        text: None,
                    },
                },
            ),
        ),
        (
            "key_texto",
            c(
                9,
                CommandKind::Key {
                    node: t1(),
                    press: KeyPress {
                        key: Key::Char("a".into()),
                        mods: Mods {
                            shift: true,
                            ..Default::default()
                        },
                        text: Some("A".into()),
                    },
                },
            ),
        ),
        (
            "key_pageup_alt",
            c(
                10,
                CommandKind::Key {
                    node: t1(),
                    press: KeyPress {
                        key: Key::Named(NamedKey::PageUp),
                        mods: Mods {
                            alt: true,
                            meta: true,
                            ..Default::default()
                        },
                        text: None,
                    },
                },
            ),
        ),
        (
            "resize",
            c(
                11,
                CommandKind::Resize {
                    node: t1(),
                    cols: 120,
                    rows: 40,
                },
            ),
        ),
        ("list_terminals", c(12, CommandKind::ListTerminals)),
        (
            "close_terminal",
            c(13, CommandKind::CloseTerminal { node: t1() }),
        ),
        (
            "paste",
            c(
                14,
                CommandKind::Paste {
                    node: t1(),
                    text: "ls -la\necho 'colado'\n".into(),
                },
            ),
        ),
    ]
}

fn replies() -> Vec<(&'static str, Reply)> {
    vec![
        ("ok", Reply::ok(1)),
        ("erro", Reply::err(6, "terminal desconhecido 't9'")),
        ("terminal_criado", Reply::with(4, &info(true))),
        (
            "lista",
            Reply::with(12, &json!({"terminals": [info(true), info(false)]})),
        ),
    ]
}

fn events() -> Vec<(&'static str, Event)> {
    vec![
        (
            "screen_full",
            Event {
                topic: Topic::Screen(t1()),
                body: EventBody::Screen(sample_frame(FrameKind::Full)),
            },
        ),
        (
            "screen_delta",
            Event {
                topic: Topic::Screen(t1()),
                body: EventBody::Screen(Frame {
                    lines: sample_frame(FrameKind::Delta)
                        .lines
                        .into_iter()
                        .take(1)
                        .collect(),
                    ..sample_frame(FrameKind::Delta)
                }),
            },
        ),
        (
            "screen_so_cursor",
            Event {
                topic: Topic::Screen(t1()),
                body: EventBody::Screen(Frame {
                    lines: vec![],
                    cursor: Cursor {
                        row: 3,
                        col: 0,
                        visible: false,
                        shape: CursorShape::Bar,
                    },
                    ..sample_frame(FrameKind::Delta)
                }),
            },
        ),
        (
            "terminals",
            Event {
                topic: Topic::Terminals,
                body: EventBody::Terminals {
                    terminals: vec![info(true), info(false)],
                },
            },
        ),
    ]
}

fn fixtures_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("fixtures/protocol")
}

/// As fixtures são o contrato com a UI, que as lê no teste dela. Mudança de
/// formato no Rust falha aqui; quem muda de propósito regrava com
/// `EGEON_UPDATE_FIXTURES=1 cargo test -p egeon-core` e avisa a UI.
fn write_fixture(name: &str, entries: serde_json::Map<String, Value>) {
    let dir = fixtures_dir();
    let path = dir.join(name);
    let mut text = serde_json::to_string_pretty(&Value::Object(entries)).unwrap();
    text.push('\n');
    let current = std::fs::read_to_string(&path).ok();
    if current.as_deref() == Some(text.as_str()) {
        return;
    }
    if std::env::var_os("EGEON_UPDATE_FIXTURES").is_some() {
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(&path, text).unwrap();
        return;
    }
    panic!(
        "{} mudou: o contrato com a UI não bate com o Rust. Se a mudança é de \
         propósito, rode com EGEON_UPDATE_FIXTURES=1 e avise a UI.",
        path.display()
    );
}

#[test]
fn grava_fixtures_e_elas_voltam_iguais() {
    let mut map = serde_json::Map::new();
    for (name, cmd) in commands()
        .into_iter()
        .chain(super::org_fixtures::commands())
        .chain(super::org_fixtures::chat_commands())
        .chain(super::node_fixtures::commands())
        .chain(super::app_fixtures::commands())
    {
        let value = serde_json::to_value(&cmd).unwrap();
        let line = serde_json::to_string(&value).unwrap();
        assert_eq!(parse_command(&line).unwrap(), cmd, "comando {name}");
        map.insert(name.into(), value);
    }
    write_fixture("commands.json", map);

    let mut map = serde_json::Map::new();
    for (name, reply) in replies()
        .into_iter()
        .chain(super::org_fixtures::replies())
        .chain(super::node_fixtures::replies())
    {
        let value = serde_json::to_value(&reply).unwrap();
        assert_eq!(
            serde_json::from_value::<Reply>(value.clone()).unwrap(),
            reply,
            "resposta {name}"
        );
        map.insert(name.into(), value);
    }
    write_fixture("replies.json", map);

    let mut map = serde_json::Map::new();
    for (name, event) in events()
        .into_iter()
        .chain(super::org_fixtures::events())
        .chain(super::node_fixtures::events())
        .chain(super::app_fixtures::events())
    {
        let value = serde_json::to_value(&event).unwrap();
        assert_eq!(
            serde_json::from_value::<Event>(value.clone()).unwrap(),
            event,
            "evento {name}"
        );
        map.insert(name.into(), value);
    }
    write_fixture("events.json", map);
}

#[test]
fn formato_no_fio_do_evento_de_tela() {
    // Trava o formato que a UI lê, campo a campo: mudar aqui é mudar o contrato.
    let value = serde_json::to_value(&events()[0].1).unwrap();
    assert_eq!(value["topic"], "screen/t1");
    assert_eq!(value["kind"], "full");
    assert_eq!(value["cols"], 80);
    assert_eq!(
        value["cursor"],
        json!({"row":1,"col":2,"visible":true,"shape":"block"})
    );
    assert_eq!(
        value["lines"][0]["spans"][0],
        json!({"col":0,"cells":6,"text":"hello "})
    );
    assert_eq!(
        value["lines"][0]["spans"][1],
        json!({"col":6,"cells":5,"text":"world","fg":2,"bold":true})
    );
    assert_eq!(value["lines"][0]["spans"][2]["fg"], "#ff8800");
    assert_eq!(value["lines"][2], json!({"row":2,"spans":[]}));

    let key = serde_json::to_value(&commands()[7].1).unwrap();
    assert_eq!(
        key,
        json!({"id":8,"cmd":"key","node":"t1","key":"c","mods":{"ctrl":true}})
    );
    let key = serde_json::to_value(&commands()[9].1).unwrap();
    assert_eq!(key["key"], "pageup");
}

#[test]
fn tecla_sem_mods_e_aceita() {
    let cmd = parse_command(r#"{"id":1,"cmd":"key","node":"t1","key":"up"}"#).unwrap();
    assert_eq!(
        cmd.kind,
        CommandKind::Key {
            node: t1(),
            press: KeyPress {
                key: Key::Named(NamedKey::Up),
                mods: Mods::default(),
                text: None
            }
        }
    );
}

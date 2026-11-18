//! Exemplos do nó por dentro (decisão 31) e da tela do terminal (decisão
//! 26) que vão para as fixtures do `/ui`.

use serde_json::json;

use super::message::{Command, CommandKind, Event, EventBody, Reply, Topic};
use super::node::*;
use super::org::NodeKind;
use super::screen::{Effect, Mods, MouseButton, Pointer, PointerKind, Scroll};
use crate::commons::ids::{NodeId, WorkbenchId};

fn wb() -> WorkbenchId {
    WorkbenchId::new("1a2b3c4d").unwrap()
}

fn node(id: &str) -> NodeId {
    NodeId::new(id).unwrap()
}

fn at(id: &str) -> NodeTarget {
    NodeTarget {
        workbench: wb(),
        node: node(id),
    }
}

fn item(id: &str) -> QueueItemRef {
    QueueItemRef {
        workbench: wb(),
        node: node("fila"),
        item: id.into(),
    }
}

pub fn commands() -> Vec<(&'static str, Command)> {
    let c = |id, kind| Command { id, kind };
    let screen = || node("1a2b3c4d.claude");
    vec![
        (
            "subscribe_node",
            c(
                300,
                CommandKind::Subscribe {
                    topic: Topic::Node(wb(), node("claude")),
                },
            ),
        ),
        (
            "effort_move",
            c(
                301,
                CommandKind::EffortMove(EffortMove {
                    workbench: wb(),
                    node: node("claude"),
                    index: 3,
                }),
            ),
        ),
        (
            "effort_toggle_auto",
            c(302, CommandKind::EffortToggleAuto(at("claude"))),
        ),
        (
            "effort_settle",
            c(303, CommandKind::EffortSettle(at("claude"))),
        ),
        ("node_clear", c(304, CommandKind::NodeClear(at("claude")))),
        (
            "queue_add",
            c(
                305,
                CommandKind::QueueAdd(QueueAdd {
                    workbench: wb(),
                    node: node("fila"),
                    text: "roda os testes".into(),
                    after: Some("a1b2c3".into()),
                }),
            ),
        ),
        (
            "queue_update",
            c(
                306,
                CommandKind::QueueUpdate(QueueItemText {
                    workbench: wb(),
                    node: node("fila"),
                    item: "a1b2c3".into(),
                    text: "roda os testes do core".into(),
                }),
            ),
        ),
        (
            "queue_remove",
            c(307, CommandKind::QueueRemove(item("a1b2c3"))),
        ),
        (
            "queue_move",
            c(
                308,
                CommandKind::QueueMove(QueueMove {
                    workbench: wb(),
                    node: node("fila"),
                    item: "a1b2c3".into(),
                    to: 0,
                }),
            ),
        ),
        (
            "queue_toggle_done",
            c(309, CommandKind::QueueToggleDone(item("a1b2c3"))),
        ),
        (
            "queue_reopen",
            c(310, CommandKind::QueueReopen(item("a1b2c3"))),
        ),
        (
            "queue_send_proximo",
            c(
                311,
                CommandKind::QueueSend(QueueSend {
                    workbench: wb(),
                    node: node("fila"),
                    item: None,
                }),
            ),
        ),
        (
            "queue_reply",
            c(
                312,
                CommandKind::QueueReply(QueueItemText {
                    workbench: wb(),
                    node: node("fila"),
                    item: "a1b2c3".into(),
                    text: "sim, pode".into(),
                }),
            ),
        ),
        (
            "queue_set",
            c(
                313,
                CommandKind::QueueSet(QueueSet {
                    workbench: wb(),
                    node: node("fila"),
                    auto: Some(true),
                    target: Some(node("claude")),
                }),
            ),
        ),
        (
            "queue_clear_done",
            c(314, CommandKind::QueueClearDone(at("fila"))),
        ),
        (
            "queue_attach",
            c(
                315,
                CommandKind::QueueAttach(QueueAttach {
                    workbench: wb(),
                    node: node("fila"),
                    item: Some("a1b2c3".into()),
                    open: None,
                    path: Some("/Users/eu/Desktop/tela.png".into()),
                    png: None,
                }),
            ),
        ),
        (
            "queue_attach_colado",
            c(
                332,
                CommandKind::QueueAttach(QueueAttach {
                    workbench: wb(),
                    node: node("fila"),
                    item: Some("a1b2c3".into()),
                    open: None,
                    path: None,
                    png: Some("iVBORw0KGgo=".into()),
                }),
            ),
        ),
        (
            "queue_attach_solto",
            c(
                333,
                CommandKind::QueueAttach(QueueAttach {
                    workbench: wb(),
                    node: node("fila"),
                    item: None,
                    open: Some("d4e5f6".into()),
                    path: Some("/Users/eu/Desktop/tela.png".into()),
                    png: None,
                }),
            ),
        ),
        (
            "queue_detach",
            c(
                316,
                CommandKind::QueueDetach(QueueDetach {
                    workbench: wb(),
                    node: node("fila"),
                    item: "a1b2c3".into(),
                    image: "img-9f8e7d6c.png".into(),
                }),
            ),
        ),
        (
            "web_navigate",
            c(
                317,
                CommandKind::WebNavigate(WebNavigate {
                    workbench: wb(),
                    node: node("docs"),
                    typed: "docs.rs/tokio".into(),
                }),
            ),
        ),
        (
            "web_navigated",
            c(
                318,
                CommandKind::WebNavigated(WebNavigated {
                    workbench: wb(),
                    node: node("docs"),
                    url: "https://docs.rs/tokio/latest/tokio/".into(),
                }),
            ),
        ),
        (
            "web_set_profile",
            c(
                319,
                CommandKind::WebSetProfile(WebSetProfile {
                    workbench: wb(),
                    node: node("docs"),
                    profile: "trabalho".into(),
                }),
            ),
        ),
        (
            "scroll_linhas",
            c(
                320,
                CommandKind::Scroll(ScrollTo {
                    node: screen(),
                    to: Scroll::Rows(-3),
                }),
            ),
        ),
        (
            "scroll_fim",
            c(
                321,
                CommandKind::Scroll(ScrollTo {
                    node: screen(),
                    to: Scroll::Bottom,
                }),
            ),
        ),
        (
            "pointer_press",
            c(
                322,
                CommandKind::Pointer(PointerAt {
                    node: screen(),
                    pointer: Pointer {
                        kind: PointerKind::Press,
                        button: Some(MouseButton::Left),
                        x: 3.5,
                        y: 2.0,
                        mods: Mods::default(),
                        time_ms: 1_000,
                        lines: 0,
                    },
                }),
            ),
        ),
        (
            "pointer_release_meta",
            c(
                323,
                CommandKind::Pointer(PointerAt {
                    node: screen(),
                    pointer: Pointer {
                        kind: PointerKind::Release,
                        button: Some(MouseButton::Left),
                        x: 12.25,
                        y: 4.0,
                        mods: Mods {
                            meta: true,
                            ..Mods::default()
                        },
                        time_ms: 1_080,
                        lines: 0,
                    },
                }),
            ),
        ),
        (
            "ui_focus",
            c(
                330,
                CommandKind::UiFocus(UiFocus {
                    app_active: true,
                    node: Some(at("claude")),
                    window: Some(WindowSize {
                        w: 1440.0,
                        h: 900.0,
                    }),
                }),
            ),
        ),
        (
            "ui_focus_fundo",
            c(
                331,
                CommandKind::UiFocus(UiFocus {
                    app_active: false,
                    node: None,
                    window: None,
                }),
            ),
        ),
        (
            "ui_reply",
            c(
                333,
                CommandKind::UiReply(UiReply {
                    request: 7,
                    value: json!("chat"),
                }),
            ),
        ),
        (
            // Sem bancada na tela, o retrato vazio: 200 com `{}`, não o 404.
            "ui_reply_geometria_vazia",
            c(
                408,
                CommandKind::UiReply(UiReply {
                    request: 8,
                    value: json!({}),
                }),
            ),
        ),
        ("processes", c(334, CommandKind::Processes)),
        (
            "processes_reap_ensaio",
            c(
                335,
                CommandKind::ProcessesReap(ProcessesReap { dry_run: true }),
            ),
        ),
        (
            "processes_kill",
            c(
                336,
                CommandKind::ProcessesKill(ProcessesKill {
                    pids: vec![4242, 4243],
                    dry_run: false,
                }),
            ),
        ),
        (
            "select_all",
            c(324, CommandKind::SelectAll(ScreenRef { node: screen() })),
        ),
        (
            "copy",
            c(325, CommandKind::Copy(ScreenRef { node: screen() })),
        ),
        (
            "clipboard_reply",
            c(
                326,
                CommandKind::ClipboardReply(ClipboardReply {
                    node: screen(),
                    text: "o que estava copiado".into(),
                }),
            ),
        ),
        (
            "link_hover",
            c(
                327,
                CommandKind::LinkHover(LinkHover {
                    node: screen(),
                    x: 12.25,
                    y: 4.0,
                }),
            ),
        ),
        (
            "drop_caminhos",
            c(
                328,
                CommandKind::Drop(Drop {
                    node: screen(),
                    paths: vec!["/tmp/um arquivo.pdf".into(), "/tmp/outro.swift".into()],
                    png: None,
                }),
            ),
        ),
        (
            "drop_imagem",
            c(
                329,
                CommandKind::Drop(Drop {
                    node: screen(),
                    paths: vec![],
                    png: Some("iVBORw0KGgo=".into()),
                }),
            ),
        ),
    ]
}

pub fn replies() -> Vec<(&'static str, Reply)> {
    vec![
        ("copy", Reply::with(325, &json!({"text": "cargo test\nok"}))),
        ("queue_add", Reply::with(305, &json!({"item": "d4e5f6"}))),
        ("link_hover", Reply::with(327, &json!({"link": true}))),
        (
            "processes",
            Reply::with(
                334,
                &json!({
                    "processes": [
                        {"pid": 4242, "node": "deck/claude", "orphan": true, "age": "19 d 4 h",
                         "command": "node server.js"},
                        {"pid": 4243, "orphan": false, "age": "42 s", "command": "claude --resume abc"}
                    ],
                    "summary": "1 no app · 1 órfão · limpeza a cada 10 min",
                    "orphans": 1,
                    "enabled": true
                }),
            ),
        ),
        (
            "processes_reap_ensaio",
            Reply::with(
                335,
                &json!({"title": "Encerrar 1 processo órfão?",
                        "detail": "Recebem SIGTERM — o mesmo que fechar o terminal deles."}),
            ),
        ),
        (
            "processes_erro_leitura",
            Reply::err(334, "a leitura dos processos não terminou"),
        ),
        (
            "erro_fila",
            Reply::err(307, "item a1b2c3 não existe na fila"),
        ),
    ]
}

pub fn events() -> Vec<(&'static str, Event)> {
    let topic = |id: &str| Topic::Node(wb(), node(id));
    vec![
        (
            "usage",
            Event {
                topic: Topic::Usage(wb()),
                body: EventBody::Usage(Box::new(
                    serde_json::from_value(json!({
                        "workbench": "1a2b3c4d",
                        "pill": {"text": "US$ 1,23", "tooltip": "Consumo da bancada"},
                        "panel": {
                            "heading": "CONSUMO DA BANCADA",
                            "total": {"amount": "US$ 12,34", "tokens": "1,2M tokens"},
                            "split": [
                                {"key": "output", "title": "Saída", "amount": "US$ 6,00",
                                 "detail": "120K tokens", "dollars": 6.0},
                                {"key": "input", "title": "Entrada", "amount": "US$ 1,00",
                                 "detail": "200K tokens", "dollars": 1.0},
                                {"key": "cache_write", "title": "Cache gravado", "amount": "US$ 2,34",
                                 "detail": "300K tokens", "dollars": 2.34},
                                {"key": "cache_read", "title": "Cache lido", "amount": "US$ 3,00",
                                 "detail": "600K tokens", "dollars": 3.0}
                            ],
                            "agents": [{"name": "claude", "tag": "maestro", "amount": "US$ 10,00",
                                        "fraction": 1.0, "detail": "1,0M tokens"}],
                            "models": [{"name": "Opus 5.5", "family": "opus", "amount": "US$ 12,34",
                                        "fraction": 1.0, "detail": "1,2M tokens"}],
                            "prices": {
                                "open_note": "US$ por milhão de tokens",
                                "columns": ["", "Entrada", "Saída", "5 min", "1 h", "Lido"],
                                "rows": [{"name": "Opus 5.5", "lit": true, "edited": false,
                                          "values": ["5,00", "25,00", "6,25", "10,00", "0,500"]}],
                                "origin_note": "Preços públicos da Anthropic",
                                "rule_note": "Cache gravado: 1,25× (5 min) ou 2× (1 h)",
                                "file_note": "~/.egeon-next/pricing.json"
                            }
                        }
                    }))
                    .unwrap(),
                )),
            },
        ),
        (
            "app_ui_request",
            Event {
                topic: Topic::App,
                body: EventBody::AppEffect(super::app::AppEffect::UiRequest {
                    id: 7,
                    route: "layout".into(),
                    params: [("mode".to_owned(), "chat".to_owned())]
                        .into_iter()
                        .collect(),
                }),
            },
        ),
        (
            "node_agent",
            Event {
                topic: topic("claude"),
                body: EventBody::Node(Box::new(NodeDetail {
                    workbench: wb(),
                    node: node("claude"),
                    kind: NodeKind::Agent,
                    agent: Some(AgentDetail {
                        model_title: "Opus 5.5".into(),
                        model_hint: "padrão do CLI".into(),
                        offers_model: true,
                        models: vec![
                            ModelChoice {
                                label: "padrão".into(),
                                value: None,
                                group: ModelGroup::Standard,
                                selected: false,
                            },
                            ModelChoice {
                                label: "Opus 5.5".into(),
                                value: Some("opus".into()),
                                group: ModelGroup::Featured,
                                selected: true,
                            },
                            ModelChoice {
                                label: "Sonnet 5.5".into(),
                                value: Some("sonnet".into()),
                                group: ModelGroup::Alias,
                                selected: false,
                            },
                        ],
                        offers_effort: true,
                        dial: Dial {
                            levels: vec![
                                "low".into(),
                                "medium".into(),
                                "high".into(),
                                "xhigh".into(),
                                "max".into(),
                            ],
                            index: 2,
                            auto: false,
                            pending: false,
                            label: "high".into(),
                        },
                        ultracode: Some(Ultracode {
                            on: false,
                            available: true,
                        }),
                        context: Some(ContextUse {
                            used: Some(84_000),
                            window: Some(200_000),
                        }),
                        clearable: true,
                        clear_hint: "Conversa nova — a de agora fica no histórico".into(),
                        conversation: Some(Conversation {
                            id: "4d95e5e6-9c11-4512-bd29-48866ad41d0b".into(),
                            started: true,
                        }),
                    }),
                    queue: None,
                    web: None,
                })),
            },
        ),
        (
            "node_queue",
            Event {
                topic: topic("fila"),
                body: EventBody::Node(Box::new(NodeDetail {
                    workbench: wb(),
                    node: node("fila"),
                    kind: NodeKind::Queue,
                    agent: None,
                    queue: Some(QueueDetail {
                        items: vec![
                            QueueItemView {
                                id: "a1b2c3".into(),
                                text: "roda os testes".into(),
                                images: vec![],
                                status: QueueStatus::Sent,
                                sent_to: Some(node("claude")),
                                sent_at: Some("2026-11-18T03:12:00.000Z".into()),
                                thread: vec![QueueMessage {
                                    author: "claude".into(),
                                    kind: "question".into(),
                                    text: "Posso apagar o target?".into(),
                                    at: "2026-11-18T03:13:10.000Z".into(),
                                }],
                                awaiting: true,
                                locked: true,
                                empty: false,
                            },
                            QueueItemView {
                                id: "d4e5f6".into(),
                                text: "atualiza o CHANGELOG".into(),
                                images: vec!["img-9f8e7d6c.png".into()],
                                status: QueueStatus::Pending,
                                sent_to: None,
                                sent_at: None,
                                thread: vec![],
                                awaiting: false,
                                locked: false,
                                empty: false,
                            },
                        ],
                        auto: true,
                        target: Some(node("claude")),
                        destination: Some(node("claude")),
                        pending: 1,
                        asking: true,
                        summary: "? pergunta".into(),
                        subtitle: "1 pendente".into(),
                        image_extensions: ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
                            .map(str::to_owned)
                            .to_vec(),
                        targets: vec![QueueTarget {
                            id: node("claude"),
                            label: "claude".into(),
                        }],
                        blocker: Some("claude está trabalhando".into()),
                        images_dir: "/Users/eu/.egeon-next/workbenches/1a2b3c4d/queues/fila/images"
                            .into(),
                    }),
                    web: None,
                })),
            },
        ),
        (
            "node_web",
            Event {
                topic: topic("docs"),
                body: EventBody::Node(Box::new(NodeDetail {
                    workbench: wb(),
                    node: node("docs"),
                    kind: NodeKind::Web,
                    agent: None,
                    queue: None,
                    web: Some(WebDetail {
                        url: Some("https://docs.rs".into()),
                        profile: "padrão".into(),
                        profile_id: "3f2a9c1e-5b7d-4e8a-9c0b-1d2e3f4a5b6c".into(),
                        profiles: vec!["padrão".into(), "trabalho".into()],
                    }),
                })),
            },
        ),
        (
            "node_open_item",
            Event {
                topic: topic("fila"),
                body: EventBody::NodeEffect(NodeEffect::OpenItem {
                    item: "a1b2c3".into(),
                }),
            },
        ),
        (
            "node_draft",
            Event {
                topic: topic("fila"),
                body: EventBody::NodeEffect(NodeEffect::Draft {
                    text: "rascunho vindo do egeon".into(),
                }),
            },
        ),
        (
            "screen_bell",
            Event {
                topic: Topic::Screen(node("1a2b3c4d.claude")),
                body: EventBody::ScreenEffect(Effect::Bell),
            },
        ),
        (
            "screen_clipboard",
            Event {
                topic: Topic::Screen(node("1a2b3c4d.claude")),
                body: EventBody::ScreenEffect(Effect::Clipboard {
                    text: "copiado pelo programa".into(),
                }),
            },
        ),
        (
            "screen_clipboard_request",
            Event {
                topic: Topic::Screen(node("1a2b3c4d.claude")),
                body: EventBody::ScreenEffect(Effect::ClipboardRequest),
            },
        ),
    ]
}

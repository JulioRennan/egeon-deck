//! Exemplos do contrato de organização (decisão 24) que vão para as fixtures
//! do `/ui`: cada comando, as respostas com id criado e os dois tópicos.

use std::collections::BTreeMap;

use serde_json::json;

use super::message::{Command, CommandKind, Event, EventBody, Reply, Topic};
use super::org::*;
use crate::commons::ids::{NodeId, ProjectId, WorkbenchId, WorkspaceId};

fn wb() -> WorkbenchId {
    WorkbenchId::new("1a2b3c4d").unwrap()
}

fn ws() -> WorkspaceId {
    WorkspaceId::new("9f8e7d6c").unwrap()
}

fn pj(id: &str) -> ProjectId {
    ProjectId::new(id).unwrap()
}

fn node(id: &str) -> NodeId {
    NodeId::new(id).unwrap()
}

fn rect() -> Rect {
    Rect {
        x: 120.0,
        y: 80.5,
        w: 640.0,
        h: 420.0,
    }
}

pub fn commands() -> Vec<(&'static str, Command)> {
    let c = |id, kind| Command { id, kind };
    let here = || WorkbenchRef { workbench: wb() };
    let mv = |kind, id: &str, parent: Option<&str>, to| Move {
        kind,
        item: id.into(),
        parent: parent.map(Into::into),
        to,
    };
    vec![
        (
            "subscribe_workspaces",
            c(
                100,
                CommandKind::Subscribe {
                    topic: Topic::Workspaces,
                },
            ),
        ),
        (
            "subscribe_nodes",
            c(
                101,
                CommandKind::Subscribe {
                    topic: Topic::Nodes(wb()),
                },
            ),
        ),
        ("open_workbench", c(102, CommandKind::OpenWorkbench(here()))),
        (
            "activate_workbench",
            c(103, CommandKind::ActivateWorkbench(here())),
        ),
        (
            "close_workbench",
            c(104, CommandKind::CloseWorkbench(here())),
        ),
        (
            "move_tab",
            c(
                105,
                CommandKind::MoveTab(MoveTab {
                    workbench: wb(),
                    to: 0,
                }),
            ),
        ),
        (
            "move_workbench",
            c(
                106,
                CommandKind::Move(mv(MoveKind::Workbench, "1a2b3c4d", Some("p1"), 2)),
            ),
        ),
        (
            "move_store",
            c(
                107,
                CommandKind::Move(mv(MoveKind::Store, "p2", Some("9f8e7d6c"), 1)),
            ),
        ),
        (
            "move_drawer",
            c(
                108,
                CommandKind::Move(mv(MoveKind::Drawer, "9f8e7d6c", None, 0)),
            ),
        ),
        (
            "plan_move",
            c(
                109,
                CommandKind::PlanMove(mv(MoveKind::Project, "p2", Some("9f8e7d6c"), 1)),
            ),
        ),
        (
            "create_workspace",
            c(
                110,
                CommandKind::CreateWorkspace(CreateWorkspace {
                    name: "Agro".into(),
                    icon: None,
                }),
            ),
        ),
        (
            "set_workspace",
            c(
                111,
                CommandKind::SetWorkspace(SetWorkspace {
                    workspace: ws(),
                    name: Some("Agro e afins".into()),
                    icon: Some(None),
                    collapsed: Some(true),
                    stored_open: None,
                }),
            ),
        ),
        (
            "remove_workspace",
            c(
                112,
                CommandKind::RemoveWorkspace(RemoveWorkspace {
                    workspace: ws(),
                    dry_run: true,
                }),
            ),
        ),
        (
            "save_workspace",
            c(
                136,
                CommandKind::SaveWorkspace(SaveWorkspace {
                    workspace: Some(ws()),
                    name: "Agro".into(),
                    icon: Some(Some("/Users/eu/Desktop/agro.png".into())),
                    folders: vec![
                        "~/Documents/agro/nexus-backend".into(),
                        "~/Documents/agro/nexus-front".into(),
                    ],
                    multis: vec![MultiDraft {
                        id: None,
                        name: "nexus".into(),
                        folders: vec![
                            "~/Documents/agro/nexus-backend".into(),
                            "~/Documents/agro/nexus-front".into(),
                        ],
                    }],
                }),
            ),
        ),
        (
            "multi_name",
            c(
                138,
                CommandKind::MultiName(MultiName {
                    workspace: Some(ws()),
                    folders: vec![
                        "~/Documents/agro/nexus-backend".into(),
                        "~/Documents/agro/nexus-front".into(),
                    ],
                }),
            ),
        ),
        (
            "multi_name_workspace_novo",
            c(
                143,
                CommandKind::MultiName(MultiName {
                    workspace: None,
                    folders: vec![
                        "~/Documents/agro/nexus-backend".into(),
                        "~/Documents/agro/nexus-front".into(),
                    ],
                }),
            ),
        ),
        (
            "save_workspace_multi_sem_nome",
            c(
                144,
                CommandKind::SaveWorkspace(SaveWorkspace {
                    workspace: None,
                    name: "Agro".into(),
                    icon: None,
                    folders: vec![
                        "~/Documents/agro/nexus-backend".into(),
                        "~/Documents/agro/nexus-front".into(),
                    ],
                    multis: vec![MultiDraft {
                        id: None,
                        name: String::new(),
                        folders: vec![
                            "~/Documents/agro/nexus-backend".into(),
                            "~/Documents/agro/nexus-front".into(),
                        ],
                    }],
                }),
            ),
        ),
        (
            "suggest_parent",
            c(
                137,
                CommandKind::SuggestParent(WorkspaceRef { workspace: ws() }),
            ),
        ),
        (
            "create_project",
            c(
                113,
                CommandKind::CreateProject(CreateProject {
                    workspace: ws(),
                    name: "nexus-api".into(),
                    parent: Some("~/Documents/agro".into()),
                    git: true,
                }),
            ),
        ),
        (
            "add_project",
            c(
                114,
                CommandKind::AddProject(AddProject {
                    workspace: ws(),
                    path: "~/Documents/agro/nexus-backend".into(),
                    name: None,
                }),
            ),
        ),
        (
            "set_project",
            c(
                115,
                CommandKind::SetProject(SetProject {
                    project: pj("p1"),
                    name: None,
                    collapsed: Some(false),
                }),
            ),
        ),
        (
            "remove_project",
            c(
                116,
                CommandKind::RemoveProject(RemoveProject {
                    project: pj("p2"),
                    dry_run: false,
                }),
            ),
        ),
        (
            "multi_project",
            c(
                117,
                CommandKind::MultiProject(MultiProject {
                    workspace: ws(),
                    name: "nexus".into(),
                    members: vec![pj("p1"), pj("p2")],
                }),
            ),
        ),
        (
            "create_workbench",
            c(
                118,
                CommandKind::CreateWorkbench(CreateWorkbench {
                    path: "~/Documents/agro/nexus-backend".into(),
                    name: None,
                    project: Some(pj("p1")),
                    template: Some("dupla".into()),
                    color: None,
                }),
            ),
        ),
        (
            "set_workbench",
            c(
                119,
                CommandKind::SetWorkbench(SetWorkbench {
                    workbench: wb(),
                    name: Some("deck".into()),
                    color: Some("teal".into()),
                    view: Some(ViewMode::Chat),
                }),
            ),
        ),
        (
            "set_workbench_rules",
            c(
                120,
                CommandKind::SetWorkbenchRules(SetWorkbenchRules {
                    workbench: wb(),
                    rules: Some("não commite sem me perguntar".into()),
                }),
            ),
        ),
        (
            "set_workbench_rules_apaga",
            c(
                121,
                CommandKind::SetWorkbenchRules(SetWorkbenchRules {
                    workbench: wb(),
                    rules: None,
                }),
            ),
        ),
        (
            "remove_workbench",
            c(
                122,
                CommandKind::RemoveWorkbench(RemoveWorkbench {
                    workbench: wb(),
                    worktrees: true,
                }),
            ),
        ),
        (
            "plan_remove_workbench",
            c(
                135,
                CommandKind::PlanRemoveWorkbench(WorkbenchRef { workbench: wb() }),
            ),
        ),
        (
            "clear_workbench",
            c(123, CommandKind::ClearWorkbench(here())),
        ),
        (
            "worktree",
            c(
                124,
                CommandKind::Worktree(Worktree {
                    workbench: Some(wb()),
                    path: None,
                    project: None,
                    branch: "feature/PROJ-1234".into(),
                    nodes: BTreeMap::from([
                        (node("back"), "fix/api".into()),
                        (node("sub"), String::new()),
                    ]),
                    destination: WorktreeDestination::MoveCurrent,
                    template: None,
                }),
            ),
        ),
        (
            "worktree_de_pasta",
            c(
                145,
                CommandKind::Worktree(Worktree {
                    workbench: None,
                    path: Some("~/Documents/agro/nexus-backend".into()),
                    project: Some(pj("p1")),
                    branch: "feature/PROJ-1234".into(),
                    nodes: BTreeMap::new(),
                    destination: WorktreeDestination::NewWorkbench,
                    template: Some("dupla".into()),
                }),
            ),
        ),
        ("templates", c(139, CommandKind::Templates)),
        (
            "worktree_info",
            c(
                140,
                CommandKind::WorktreeInfo(WorkbenchRef { workbench: wb() }),
            ),
        ),
        (
            "worktree_plan",
            c(
                141,
                CommandKind::WorktreePlan(WorktreePlanRequest {
                    workbench: wb(),
                    branch: "feature/PROJ-1234".into(),
                }),
            ),
        ),
        (
            "create_node",
            c(
                125,
                CommandKind::CreateNode(CreateNode {
                    workbench: wb(),
                    kind: NodeKind::Agent,
                    frame: Some(rect()),
                    component: Some("revisor".into()),
                    agent: Some("claude".into()),
                    cwd: None,
                    cmd: None,
                    url: None,
                }),
            ),
        ),
        (
            "create_node_web",
            c(
                126,
                CommandKind::CreateNode(CreateNode {
                    workbench: wb(),
                    kind: NodeKind::Web,
                    frame: Some(rect()),
                    component: None,
                    agent: None,
                    cwd: None,
                    cmd: None,
                    url: Some("https://docs.rs".into()),
                }),
            ),
        ),
        (
            "set_node",
            c(
                127,
                CommandKind::SetNode(SetNode {
                    workbench: wb(),
                    node: node("claude"),
                    model: Some(Some("sonnet".into())),
                    effort: Some(None),
                    ultracode: None,
                    role: Some(Some("revisor do lado Rust".into())),
                    rules: None,
                    cwd: None,
                    cmd: None,
                    maestro: Some(false),
                }),
            ),
        ),
        (
            "move_node",
            c(
                128,
                CommandKind::MoveNode(MoveNode {
                    workbench: wb(),
                    node: node("claude"),
                    frame: rect(),
                }),
            ),
        ),
        (
            "remove_node",
            c(
                129,
                CommandKind::RemoveNode(NodeRef {
                    workbench: wb(),
                    node: node("sh"),
                }),
            ),
        ),
        (
            "link",
            c(
                130,
                CommandKind::Link(Link {
                    workbench: wb(),
                    from: node("claude"),
                    to: node("rev"),
                    both: false,
                    max_sends: None,
                }),
            ),
        ),
        (
            "link_ida_e_volta",
            c(
                131,
                CommandKind::Link(Link {
                    workbench: wb(),
                    from: node("claude"),
                    to: node("rev"),
                    both: true,
                    max_sends: Some(3),
                }),
            ),
        ),
        (
            "unlink",
            c(
                132,
                CommandKind::Unlink(Unlink {
                    workbench: wb(),
                    from: node("claude"),
                    to: node("rev"),
                    both: true,
                }),
            ),
        ),
        (
            "set_edge_ciclo",
            c(
                133,
                CommandKind::SetEdge(SetEdge {
                    workbench: wb(),
                    from: node("claude"),
                    to: node("rev"),
                    direction: Some(Direction::Cycle),
                    max_sends: None,
                }),
            ),
        ),
        (
            "set_edge_sem_limite",
            c(
                134,
                CommandKind::SetEdge(SetEdge {
                    workbench: wb(),
                    from: node("claude"),
                    to: node("rev"),
                    direction: Some(Direction::Both),
                    max_sends: Some(None),
                }),
            ),
        ),
    ]
}

/// Os comandos do chat (decisão 29). O evento do tópico é o `ChatUpdate` do
/// `features::chat`, com fixtures próprias em `fixtures/chat/`.
pub fn chat_commands() -> Vec<(&'static str, Command)> {
    use super::chat::*;
    let c = |id, kind| Command { id, kind };
    let here = || ChatRef { workbench: wb() };
    vec![
        (
            "subscribe_chat",
            c(
                200,
                CommandKind::Subscribe {
                    topic: Topic::Chat(wb()),
                },
            ),
        ),
        ("chat_snapshot", c(201, CommandKind::ChatSnapshot(here()))),
        (
            "chat_step",
            c(
                202,
                CommandKind::ChatStep(ChatStep {
                    workbench: wb(),
                    block: "b|u1|2".into(),
                }),
            ),
        ),
        ("chat_more", c(203, CommandKind::ChatMore(here()))),
        ("chat_clear", c(204, CommandKind::ChatClear(here()))),
        (
            "chat_send",
            c(
                205,
                CommandKind::ChatSend(ChatSend {
                    workbench: wb(),
                    to: vec![node("claude"), node("rev")],
                    text: "revisa o delta da US-105".into(),
                    quote: Some("r|u1".into()),
                }),
            ),
        ),
        (
            "chat_complete",
            c(
                209,
                CommandKind::ChatComplete(ChatComplete {
                    workbench: wb(),
                    text: "pede ao @re".into(),
                    caret: 11,
                    to: None,
                    search: None,
                }),
            ),
        ),
        (
            "access_open_settings",
            c(
                406,
                CommandKind::AccessOpenSettings(WorkbenchRef { workbench: wb() }),
            ),
        ),
        (
            "access_ask_again",
            c(
                407,
                CommandKind::AccessAskAgain(WorkbenchRef { workbench: wb() }),
            ),
        ),
        (
            "chat_new_queue",
            c(
                405,
                CommandKind::ChatNewQueue(crate::protocol::chat::ChatNewQueue {
                    workbench: wb(),
                    agent: Some(crate::commons::ids::NodeId::new("claude").unwrap()),
                }),
            ),
        ),
        (
            "permission_answer",
            c(
                206,
                CommandKind::PermissionAnswer(PermissionAnswer {
                    workbench: wb(),
                    request: "p7".into(),
                    answer: Some(PermissionChoice::Always),
                    choice: None,
                    answers: None,
                }),
            ),
        ),
        (
            "permission_answer_escolha",
            c(
                207,
                CommandKind::PermissionAnswer(PermissionAnswer {
                    workbench: wb(),
                    request: "p8".into(),
                    answer: None,
                    choice: "Sim, e não pergunte de novo".to_owned().into(),
                    answers: None,
                }),
            ),
        ),
        (
            "permission_answer_varias",
            c(
                208,
                CommandKind::PermissionAnswer(PermissionAnswer {
                    workbench: wb(),
                    request: "p9".into(),
                    answer: None,
                    choice: None,
                    answers: Some(BTreeMap::from([
                        ("Qual banco?".to_owned(), vec!["Postgres".to_owned()]),
                        (
                            "Quais testes?".to_owned(),
                            vec!["unidade".to_owned(), "contrato".to_owned()],
                        ),
                    ])),
                }),
            ),
        ),
    ]
}

pub fn replies() -> Vec<(&'static str, Reply)> {
    vec![
        (
            "workspace_criado",
            Reply::with(110, &json!({"workspace": "9f8e7d6c"})),
        ),
        (
            "projeto_criado",
            Reply::with(113, &json!({"project": "p3"})),
        ),
        (
            "bancada_criada",
            Reply::with(118, &json!({"workbench": "5e6f7a8b"})),
        ),
        ("no_criado", Reply::with(125, &json!({"node": "revisor"}))),
        (
            "plan_remove_workbench",
            Reply::with(135, &json!({"live": true, "worktrees": 2})),
        ),
        (
            "multi_name",
            Reply::with(138, &json!({"name": "nexus-backend + nexus-front"})),
        ),
        (
            "chat_complete",
            Reply::with(
                209,
                &json!({"items": [{"label": "rev", "insert": "@rev ", "detail": "revisor", "kind": "mention"}],
                        "range": [8, 11]}),
            ),
        ),
        (
            "chat_snapshot",
            Reply::with(201, &json!({"rev": 42, "blocks": []})),
        ),
        (
            "suggest_parent",
            Reply::with(137, &json!({"parent": "~/Documents/agro"})),
        ),
        (
            "erro_workspace_com_bancadas",
            Reply::err(
                112,
                "\"Agro\" ainda tem 2 bancada(s). Remova as bancadas antes de remover o workspace.",
            ),
        ),
        (
            "plan_move",
            Reply::with(
                109,
                &json!({"lands": Lands { parent: Some("9f8e7d6c".into()), to: 1 }}),
            ),
        ),
        (
            "templates",
            Reply::with(
                139,
                &json!({"templates": [TemplateView {
                    name: "dupla".into(),
                    nodes: 2,
                    base_path: Some("~/Documents/agro".into()),
                    view: Some(ViewMode::Chat),
                }]}),
            ),
        ),
        (
            "worktree_info",
            Reply::with(
                140,
                &WorktreeInfo {
                    summary: "nexus-backend · main · limpo · 2 worktrees".into(),
                    suggested_branch: "main-2".into(),
                    nodes: vec![
                        WorktreeNode {
                            node: node("back"),
                            branch: Some("fix/api".into()),
                            state: WorktreeNodeState::OwnWorktree,
                        },
                        WorktreeNode {
                            node: node("claude"),
                            branch: None,
                            state: WorktreeNodeState::FollowsWorkbench,
                        },
                        WorktreeNode {
                            node: node("docs"),
                            branch: None,
                            state: WorktreeNodeState::NoRepo,
                        },
                    ],
                },
            ),
        ),
        (
            "worktree_plan",
            Reply::with(
                141,
                &WorktreePlan {
                    verdict: BranchVerdict::FollowRemote,
                    folder: "~/Documents/worktrees/nexus-backend/feature-PROJ-1234".into(),
                    message: Some("segue origin/feature/PROJ-1234".into()),
                },
            ),
        ),
        (
            "chat_new_queue",
            Reply::with(405, &json!({"node": "fila1"})),
        ),
        (
            "access_ask_again",
            Reply::with(
                407,
                &json!({"access": "denied",
                        "message": "Sem acesso a a pasta Documentos: libere o Egeon Deck em Ajustes › Privacidade › Arquivos e Pastas."}),
            ),
        ),
        (
            "worktree_criada",
            Reply::with(124, &json!({"workbench": "5e6f7a8b"})),
        ),
        (
            "erro_bancada",
            Reply::err(103, "bancada desconhecida '1a2b3c4d'"),
        ),
    ]
}

fn bench(id: &str, name: &str, tab_order: Option<u32>, tab_active: bool) -> WorkbenchView {
    WorkbenchView {
        id: WorkbenchId::new(id).unwrap(),
        name: name.into(),
        path: format!("~/Documents/agro/{name}"),
        project: Some(pj("p1")),
        template: None,
        color: Some("teal".into()),
        view: ViewMode::Canvas,
        tab_order,
        tab_active,
        exists: true,
        live: tab_order.is_some(),
        removing: false,
        rules: None,
        activity: ActivityCounts::default(),
        agents: 2,
        clock: None,
        access: None,
    }
}

pub fn events() -> Vec<(&'static str, Event)> {
    let orphan = WorkbenchView {
        project: None,
        color: None,
        view: ViewMode::Chat,
        exists: false,
        removing: true,
        rules: Some("só leitura".into()),
        activity: ActivityCounts {
            working: 1,
            starting: 0,
            attention: 1,
            done: 2,
            background: 0,
        },
        clock: Some(WorkbenchClock {
            running: 754,
            waiting: 120,
            failed: 0,
            ticking: vec![ClockState::Running],
        }),
        access: Some(AccessLock {
            folder: Some("Documentos".into()),
            message: "Sem acesso a a pasta Documentos: libere o Egeon Deck em Ajustes › Privacidade › Arquivos e Pastas.".into(),
        }),
        ..bench("0c0c0c0c", "solta", None, false)
    };
    let shell = NodeView {
        id: node("sh"),
        kind: NodeKind::Shell,
        agent: None,
        cwd: Some("../nexus-backend".into()),
        dir: "~/Documents/agro/deck".into(),
        cmd: None,
        model: None,
        effort: None,
        ultracode: None,
        url: None,
        role: None,
        rules: None,
        component: None,
        maestro: false,
        frame: None,
        screen: Some(node("1a2b3c4d.sh")),
        alive: true,
        activity: Some(NodeActivity {
            state: "working".into(),
            needs_attention: false,
            waiting_on: vec![],
            error: None,
            attempt: None,
            label: Some("trabalhando".into()),
            glyph: Some("spinner".into()),
            tone: None,
            pending: 2,
        }),
        exists: false,
        port: true,
        linkable: vec![node("claude")],
    };
    let agent = NodeView {
        id: node("claude"),
        kind: NodeKind::Agent,
        agent: Some("claude".into()),
        cwd: None,
        model: Some("opus".into()),
        effort: Some("high".into()),
        ultracode: Some(false),
        role: Some("dono do core".into()),
        rules: Some("português".into()),
        component: Some("core".into()),
        maestro: true,
        frame: Some(rect()),
        screen: Some(node("1a2b3c4d.claude")),
        activity: Some(NodeActivity {
            state: "asking".into(),
            needs_attention: true,
            waiting_on: vec![],
            error: None,
            attempt: None,
            label: Some("precisa de você".into()),
            glyph: Some("dot".into()),
            tone: Some("orange".into()),
            pending: 0,
        }),
        exists: true,
        port: true,
        linkable: vec![node("sh")],
        ..shell.clone()
    };
    let web = NodeView {
        id: node("docs"),
        kind: NodeKind::Web,
        url: Some("https://docs.rs".into()),
        cwd: None,
        screen: None,
        alive: false,
        activity: None,
        exists: true,
        port: false,
        linkable: vec![],
        frame: Some(rect()),
        ..shell.clone()
    };
    vec![
        (
            "workspaces",
            Event {
                topic: Topic::Workspaces,
                body: EventBody::Workspaces(WorkspacesState {
                    workspaces: vec![WorkspaceView {
                        id: ws(),
                        name: "Agro".into(),
                        icon: Some("icon.png".into()),
                        collapsed: false,
                        stored_open: true,
                        projects: vec![
                            ProjectView {
                                id: pj("p1"),
                                name: "nexus-backend".into(),
                                path: "~/Documents/agro/nexus-backend".into(),
                                exists: true,
                                collapsed: false,
                                stored: false,
                                members: None,
                                workbenches: vec![wb(), WorkbenchId::new("5e6f7a8b").unwrap()],
                                activity: ActivityCounts {
                                    working: 1,
                                    attention: 1,
                                    ..ActivityCounts::default()
                                },
                            },
                            ProjectView {
                                id: pj("p9"),
                                name: "nexus".into(),
                                path: "~/.egeon-next/projects/p9".into(),
                                exists: false,
                                collapsed: true,
                                stored: true,
                                members: Some(vec![pj("p1"), pj("p2")]),
                                workbenches: vec![],
                                activity: ActivityCounts::default(),
                            },
                        ],
                        activity: ActivityCounts {
                            working: 1,
                            attention: 1,
                            ..ActivityCounts::default()
                        },
                    }],
                    orphans: vec![WorkbenchId::new("0c0c0c0c").unwrap()],
                    workbenches: vec![
                        bench("1a2b3c4d", "deck", Some(0), true),
                        bench("5e6f7a8b", "deck-2", Some(1), false),
                        orphan,
                    ],
                    active: vec![
                        ActiveEntry {
                            workbench: wb(),
                            state: ActiveState::Recent,
                        },
                        ActiveEntry {
                            workbench: WorkbenchId::new("0c0c0c0c").unwrap(),
                            state: ActiveState::Stale,
                        },
                    ],
                }),
            },
        ),
        (
            "nodes",
            Event {
                topic: Topic::Nodes(wb()),
                body: EventBody::Nodes(NodesState {
                    workbench: wb(),
                    nodes: vec![agent, shell, web],
                    links: vec![
                        LinkView {
                            a: node("claude"),
                            b: node("sh"),
                            a_to_b: true,
                            b_to_a: false,
                            max_sends: None,
                        },
                        LinkView {
                            a: node("claude"),
                            b: node("docs"),
                            a_to_b: true,
                            b_to_a: true,
                            max_sends: Some(2),
                        },
                    ],
                }),
            },
        ),
    ]
}

#[test]
fn topicos_de_organizacao_vao_e_voltam_pelo_texto() {
    for raw in ["workspaces", "workbench/1a2b3c4d/nodes"] {
        assert_eq!(String::from(Topic::parse(raw).unwrap()), raw);
    }
    assert_eq!(
        Topic::parse("workbench/1a2b3c4d/nodes").unwrap(),
        Topic::Nodes(wb())
    );
    for bad in [
        "workbench//nodes",
        "workbench/../nodes",
        "workbench/x",
        "workbench/x/edges",
    ] {
        assert!(Topic::parse(bad).is_err(), "{bad:?}");
    }
}

/// `null` apaga e ausente não mexe: os dois têm de sobreviver ao fio.
#[test]
fn nulo_e_ausente_sao_diferentes() {
    let line =
        r#"{"id":1,"cmd":"set_edge","workbench":"1a2b3c4d","from":"a","to":"b","max_sends":null}"#;
    let CommandKind::SetEdge(edge) = super::message::parse_command(line).unwrap().kind else {
        panic!("não é set_edge");
    };
    assert_eq!(edge.max_sends, Some(None));
    let line = r#"{"id":1,"cmd":"set_edge","workbench":"1a2b3c4d","from":"a","to":"b"}"#;
    let CommandKind::SetEdge(edge) = super::message::parse_command(line).unwrap().kind else {
        panic!("não é set_edge");
    };
    assert_eq!(edge.max_sends, None);
}

//! A tabela de rotas: de uma requisição HTTP para o que o runtime tem de
//! fazer. Pura — quem atende é o runtime.
//!
//! O casamento segue o do Swift onde a rota já existia (`/about` por sufixo,
//! `/peek` por conter); as rotas novas do terminal casam pelo caminho exato.

use super::handler::RouteRequest;
use super::http::Request;
use super::message::{CreateTerminal, NodeId};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Route {
    About,
    ListTerminals,
    CreateTerminal(CreateTerminal),
    Input {
        node: NodeId,
        bytes: Vec<u8>,
    },
    /// Upgrade para o canal `/ui`.
    Ui,
    /// Uma rota do Swift cujo handler é de uma feature: o runtime entrega a
    /// requisição ao arquivo do dono (`runtime/actor/<x>_commands.rs`).
    Feature {
        route: FeatureRoute,
        request: RouteRequest,
    },
}

/// As rotas do `ControlSocket.swift`, na ordem em que ele casa. O nome diz o
/// caso; o casamento está em [`swift_route`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeatureRoute {
    Targets,
    Conversation,
    PermissionAnswer,
    Permissions,
    PermissionOpen,
    PermissionPoll,
    Activity,
    Retry,
    Message,
    Maestro,
    MaestroGuide,
    Trace,
    Tasks,
    Task,
    ProjectNew,
    NodeClear,
    WorkbenchClear,
    ChatClear,
    Move,
    WorkbenchColor,
    Tabs,
    Apps,
    ProcessesReap,
    ProcessesKill,
    Processes,
    Workspaces,
    Peers,
    Status,
    Geometry,
    Compose,
    Chat,
    Update,
    Queue,
    Peek,
    Activate,
    Worktree,
    Edge,
    Remove,
    Model,
    Usage,
    About,
    Layout,
    Sidebar,
    Shot,
    Dispatch,
}

/// O `switch` de `ControlSocket.handle` (ControlSocket.swift:205-967), caso
/// a caso e na mesma ordem: `contains` no alvo inteiro (query incluída),
/// `hasSuffix`/`hasPrefix` onde o Swift usa, e o método de cada um. A ordem
/// importa — `/queue?target=x/peek` é da fila, não do `peek`.
pub fn swift_route(method: &str, target: &str) -> Option<FeatureRoute> {
    use FeatureRoute::*;
    let bare = target.split('?').next().unwrap_or(target);
    let (get, post) = (method == "GET", method == "POST");
    let has = |needle: &str| target.contains(needle);
    let ends = |suffix: &str| bare.ends_with(suffix);
    let cases: [(bool, FeatureRoute); 45] = [
        (get && ends("/targets"), Targets),
        (
            post && (has("/conversation") || has("/session")),
            Conversation,
        ),
        (post && has("/permission/answer"), PermissionAnswer),
        (get && ends("/permissions"), Permissions),
        (post && ends("/permission"), PermissionOpen),
        (get && ends("/permission"), PermissionPoll),
        (post && has("/activity"), Activity),
        (post && has("/retry"), Retry),
        (post && has("/message"), Message),
        (bare.starts_with("/maestro/"), Maestro),
        (get && bare == "/maestro", MaestroGuide),
        (post && has("/trace"), Trace),
        (get && target.starts_with("/tasks"), Tasks),
        (post && target.starts_with("/task?"), Task),
        (post && has("/project/new"), ProjectNew),
        (post && has("/node/clear"), NodeClear),
        (post && has("/workbench/clear"), WorkbenchClear),
        (post && has("/chat/clear"), ChatClear),
        (get && has("/move"), Move),
        (get && has("/workbench/color"), WorkbenchColor),
        (get && has("/tabs"), Tabs),
        (get && ends("/apps"), Apps),
        (post && ends("/processes/reap"), ProcessesReap),
        (post && ends("/processes/kill"), ProcessesKill),
        (get && ends("/processes"), Processes),
        (get && has("/workspaces"), Workspaces),
        (get && has("/peers"), Peers),
        (get && has("/status"), Status),
        (get && has("/geometry"), Geometry),
        (post && has("/compose"), Compose),
        (get && has("/chat"), Chat),
        (get && target.starts_with("/update"), Update),
        (get && has("/queue"), Queue),
        (get && has("/peek"), Peek),
        (get && has("/activate"), Activate),
        (get && has("/worktree"), Worktree),
        (get && has("/edge"), Edge),
        (get && has("/remove"), Remove),
        (get && has("/model"), Model),
        (get && ends("/usage"), Usage),
        (get && ends("/about"), About),
        (get && has("/layout"), Layout),
        (get && has("/sidebar"), Sidebar),
        (get && has("/shot"), Shot),
        (post && ends("/dispatch"), Dispatch),
    ];
    cases
        .into_iter()
        .find(|(hit, _)| *hit)
        .map(|(_, route)| route)
}

/// O 404 do Swift, palavra por palavra: scripts de hoje leem este texto.
pub const NOT_FOUND: &str = "use GET /targets, POST /dispatch, POST /message ou POST /conversation";

/// Rota que não deu: o status e a mensagem que vão no JSON de erro.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rejected {
    pub status: u16,
    pub error: String,
}

impl Rejected {
    fn new(status: u16, error: impl Into<String>) -> Self {
        Self {
            status,
            error: error.into(),
        }
    }
}

pub fn route(req: &Request) -> Result<Route, Rejected> {
    let path = req.path();
    let method = req.method.as_str();

    if path == "/ui" {
        if req.is_ui_upgrade() {
            return Ok(Route::Ui);
        }
        return Err(Rejected::new(
            400,
            "o canal /ui pede GET com Upgrade: egeon-ndjson",
        ));
    }

    if let Some(rest) = path.strip_prefix("/terminal/") {
        let Some(raw) = rest.strip_suffix("/input") else {
            return Err(Rejected::new(404, "use POST /terminal/<id>/input"));
        };
        if method != "POST" {
            return Err(Rejected::new(405, "use POST /terminal/<id>/input"));
        }
        let node = NodeId::new(raw).map_err(|e| Rejected::new(400, e.to_string()))?;
        return Ok(Route::Input {
            node,
            bytes: req.body.clone(),
        });
    }

    // As rotas novas do terminal (marco 1) casam pelo caminho exato, antes
    // do Swift: nenhum caso de lá casaria com elas.
    match method {
        "POST" if path == "/terminal" => {
            // Corpo vazio vale: é o shell do usuário na pasta padrão.
            let spec = if req.body.iter().all(u8::is_ascii_whitespace) {
                CreateTerminal::default()
            } else {
                serde_json::from_slice(&req.body)
                    .map_err(|e| Rejected::new(400, format!("json inválido: {e}")))?
            };
            Ok(Route::CreateTerminal(spec))
        }
        "GET" if path == "/terminals" => Ok(Route::ListTerminals),
        _ => swift(req),
    }
}

fn swift(req: &Request) -> Result<Route, Rejected> {
    match swift_route(&req.method, &req.target) {
        Some(FeatureRoute::About) => Ok(Route::About),
        Some(route) => Ok(Route::Feature {
            route,
            request: RouteRequest::from_http(req, None),
        }),
        None => Err(Rejected::new(404, NOT_FOUND)),
    }
}

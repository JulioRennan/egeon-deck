//! As mensagens do canal `/ui` (decisão 16): depois do `101`, uma mensagem
//! JSON por linha nos dois sentidos.
//!
//! - comando, do cliente: `{"id":7,"cmd":"subscribe","topic":"screen/t1"}`
//! - resposta, do core: `{"re":7,"ok":true,…}` ou `{"re":7,"ok":false,"error":"…"}`
//! - evento, do core: `{"topic":"screen/t1",…}`
//!
//! O cliente casa a resposta com o comando pelo `re`, nunca pela ordem: a
//! ordem das respostas não é parte do contrato.
//!
//! Quando o core fecha a conexão (o cliente não leu a fila a tempo, ou o core
//! está saindo), o cliente reconecta e assina de novo; cada assinatura manda o
//! estado inteiro do tópico.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use super::ProtocolError;
use super::app::{AppEffect, AppState, OpenUrl, ReaperEnabled, UpdateAnswer, UpdateAuto};
use super::chat::{ChatComplete, ChatNewQueue, ChatRef, ChatSend, ChatStep, PermissionAnswer};
use super::node::{
    ClipboardReply, Drop, EffortMove, LinkHover, NodeDetail, NodeEffect, NodeTarget, PointerAt,
    ProcessesKill, ProcessesReap, QueueAdd, QueueAttach, QueueDetach, QueueItemRef, QueueItemText,
    QueueMove, QueueSend, QueueSet, RetryNode, ScreenRef, ScrollTo, UiFocus, UiReply, UsageState,
    WebNavigate, WebNavigated, WebSetProfile,
};
use super::org::{
    AddProject, ApplyNode, CreateNode, CreateProject, CreateWorkbench, CreateWorkspace, Link, Move,
    MoveNode, MoveTab, MultiName, MultiProject, NodeFolder, NodeForm, NodeFormScreen, NodeRef,
    NodesState, RemoveProject, RemoveWorkbench, RemoveWorkspace, SaveTemplate, SaveWorkspace,
    SetEdge, SetNode, SetProject, SetWorkbench, SetWorkbenchRules, SetWorkspace, Unlink,
    WorkbenchRef, WorkspaceRef, WorkspacesState, Worktree, WorktreePlanRequest, WorktreeSource,
};
use super::screen::{Effect, Frame, KeyPress, Size};

pub use crate::commons::ids::NodeId;
use crate::commons::ids::WorkbenchId;

/// Tópico que o cliente assina: `terminals` (a lista), `screen/<id>` (a tela
/// de um nó), `workspaces` (a árvore da barra lateral e as abas) e
/// `workbench/<id>/nodes` (os nós e as ligações de uma bancada).
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub enum Topic {
    Terminals,
    Screen(NodeId),
    Workspaces,
    Nodes(WorkbenchId),
    /// `chat/<wb id>`: o chat de uma bancada (decisão 29).
    Chat(WorkbenchId),
    /// `node/<wb id>/<node id>`: o nó por dentro (decisão 31).
    Node(WorkbenchId, NodeId),
    /// `workbench/<wb id>/usage`: o consumo da bancada (decisão 37).
    Usage(WorkbenchId),
    /// `app`: a atualização, a limpeza de órfãos e os efeitos do app (decisão 34).
    App,
}

impl Topic {
    pub fn parse(raw: &str) -> Result<Self, ProtocolError> {
        match raw {
            "terminals" => return Ok(Self::Terminals),
            "workspaces" => return Ok(Self::Workspaces),
            "app" => return Ok(Self::App),
            _ => {}
        }
        if let Some(id) = raw.strip_prefix("screen/") {
            return Ok(Self::Screen(NodeId::new(id)?));
        }
        if let Some(id) = raw.strip_prefix("chat/") {
            return Ok(Self::Chat(WorkbenchId::new(id)?));
        }
        if let Some((bench, node)) = raw.strip_prefix("node/").and_then(|r| r.split_once('/')) {
            return Ok(Self::Node(WorkbenchId::new(bench)?, NodeId::new(node)?));
        }
        let bench = raw.strip_prefix("workbench/");
        if let Some(id) = bench.and_then(|rest| rest.strip_suffix("/usage")) {
            return Ok(Self::Usage(WorkbenchId::new(id)?));
        }
        match bench.and_then(|rest| rest.strip_suffix("/nodes")) {
            Some(id) => Ok(Self::Nodes(WorkbenchId::new(id)?)),
            None => Err(ProtocolError::UnknownTopic(raw.to_owned())),
        }
    }
}

impl TryFrom<String> for Topic {
    type Error = ProtocolError;
    fn try_from(raw: String) -> Result<Self, Self::Error> {
        Self::parse(&raw)
    }
}

impl From<Topic> for String {
    fn from(topic: Topic) -> Self {
        match topic {
            Topic::Terminals => "terminals".to_owned(),
            Topic::Screen(id) => format!("screen/{id}"),
            Topic::Workspaces => "workspaces".to_owned(),
            Topic::Nodes(id) => format!("workbench/{id}/nodes"),
            Topic::Chat(id) => format!("chat/{id}"),
            Topic::Node(bench, node) => format!("node/{bench}/{node}"),
            Topic::Usage(id) => format!("workbench/{id}/usage"),
            Topic::App => "app".to_owned(),
        }
    }
}

/// Comando do cliente. O `id` é dele, e volta como `re` na resposta.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Command {
    pub id: u64,
    #[serde(flatten)]
    pub kind: CommandKind,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum CommandKind {
    /// Assinar: a resposta vem antes, e logo depois um evento com o estado
    /// atual inteiro do tópico.
    Subscribe {
        topic: Topic,
    },
    Unsubscribe {
        topic: Topic,
    },
    /// Abre um terminal novo. Sem `command`, o shell interativo do usuário.
    CreateTerminal(CreateTerminal),
    /// Bytes crus para o pty, como vieram (texto injetado, IME).
    Input {
        node: NodeId,
        text: String,
    },
    /// Colagem (decisão 20): o core embrulha em `ESC[200~…ESC[201~` quando o
    /// programa ligou o bracketed paste, e manda cru quando não. A UI não sabe
    /// o modo da tela; quem sabe é o terminal.
    Paste {
        node: NodeId,
        text: String,
    },
    /// Uma tecla, que o terminal codifica conforme o modo da tela.
    Key {
        node: NodeId,
        #[serde(flatten)]
        press: KeyPress,
    },
    Resize {
        node: NodeId,
        cols: u16,
        rows: u16,
    },
    ListTerminals,
    CloseTerminal {
        node: NodeId,
    },
    // Organização (decisão 24): os payloads estão em `protocol::org`.
    /// Põe na faixa de abas, sobe os terminais e traz para a frente.
    OpenWorkbench(WorkbenchRef),
    ActivateWorkbench(WorkbenchRef),
    /// Tira da faixa sem encerrar a bancada.
    CloseWorkbench(WorkbenchRef),
    MoveTab(MoveTab),
    Move(Move),
    /// Onde o `move` cairia, sem aplicar: o realce durante o arrasto.
    PlanMove(Move),
    CreateWorkspace(CreateWorkspace),
    SetWorkspace(SetWorkspace),
    RemoveWorkspace(RemoveWorkspace),
    /// O formulário do workspace inteiro de uma vez, como o Swift aplica:
    /// nome, ícone, pastas e multi-projetos. Sem `workspace`, cria.
    SaveWorkspace(SaveWorkspace),
    /// A pasta-mãe que o "Novo projeto…" sugere: `{parent}`.
    SuggestParent(WorkspaceRef),
    CreateProject(CreateProject),
    AddProject(AddProject),
    SetProject(SetProject),
    RemoveProject(RemoveProject),
    MultiProject(MultiProject),
    MultiName(MultiName),
    /// Os templates de bancada: `{templates:[TemplateView]}`.
    Templates,
    /// O formulário de worktree: `WorktreeInfo`. Sem `workbench`, parte de
    /// `path` ou `project`.
    WorktreeInfo(WorktreeSource),
    /// O veredito do nome da branch, sem criar: `WorktreePlan`.
    WorktreePlan(WorktreePlanRequest),
    /// Salva o canvas como template de bancada: `{template}`, ou
    /// `TemplatePlan` com `dry_run`.
    SaveTemplate(SaveTemplate),
    /// "Abrir Ajustes" da cortina: o painel de privacidade do sistema.
    AccessOpenSettings(WorkbenchRef),
    /// "Pedir de novo": zera a recusa e confere; responde
    /// `{access: ok|missing|denied, message?}`.
    AccessAskAgain(WorkbenchRef),
    CreateWorkbench(CreateWorkbench),
    SetWorkbench(SetWorkbench),
    SetWorkbenchRules(SetWorkbenchRules),
    /// O que a remoção vai levar, para o diálogo: `{live, worktrees}`.
    PlanRemoveWorkbench(WorkbenchRef),
    /// O texto da 2ª confirmação, com a caixa de apagar marcada: `{losses}`.
    /// A bancada fica com a cortina "Conferindo o que se perde…" enquanto isso.
    RemovalLosses(WorkbenchRef),
    RemoveWorkbench(RemoveWorkbench),
    ClearWorkbench(WorkbenchRef),
    /// "Zerar cronômetro" do relógio da bancada: o tempo volta a zero e o
    /// estado novo sai no tópico `workspaces`.
    ResetClock(WorkbenchRef),
    Worktree(Worktree),
    CreateNode(CreateNode),
    SetNode(SetNode),
    /// Abre o formulário de terminal: `NodeFormView`.
    NodeForm(NodeForm),
    /// A tela do formulário para um CLI: `NodeScreenView`.
    NodeFormScreen(Box<NodeFormScreen>),
    /// O + da pasta do formulário: `{cwd, shown}`.
    NodeFolder(NodeFolder),
    /// Aplica o formulário a um nó: `{node}` com o id final.
    ApplyNode(Box<ApplyNode>),
    /// Os componentes salvos: `{components:[ComponentView]}`.
    Components,
    MoveNode(MoveNode),
    RemoveNode(NodeRef),
    Link(Link),
    Unlink(Unlink),
    SetEdge(SetEdge),
    // Chat (decisão 29): os payloads estão em `protocol::chat`.
    /// O retrato inteiro: `{rev, blocks}`.
    ChatSnapshot(ChatRef),
    ChatStep(ChatStep),
    /// Mais 60 mensagens para trás.
    ChatMore(ChatRef),
    /// Arquiva a conversa (`chat.jsonl` → `chat-archive/`); não é o limpar
    /// dos agentes.
    ChatClear(ChatRef),
    ChatSend(ChatSend),
    ChatComplete(ChatComplete),
    // O nó por dentro (decisão 31): os payloads estão em `protocol::node`.
    EffortMove(EffortMove),
    EffortToggleAuto(NodeTarget),
    /// Aplica o nível mexido; a UI manda 1 s depois da última mexida.
    EffortSettle(NodeTarget),
    /// O `/node/clear` do Swift: conversa nova no agente.
    NodeClear(NodeTarget),
    /// "Tentar agora" / "Cancelar tentativa": `{ok}`, ou erro sem tentativa
    /// agendada nesse nó.
    Retry(RetryNode),
    /// O ⌘-clique no subtítulo do card: a pasta em que o terminal abriu, no
    /// Finder. Só shell e agente têm pasta.
    OpenNodeFolder(NodeTarget),
    QueueAdd(QueueAdd),
    QueueUpdate(QueueItemText),
    QueueRemove(QueueItemRef),
    QueueMove(QueueMove),
    QueueToggleDone(QueueItemRef),
    QueueReopen(QueueItemRef),
    QueueSend(QueueSend),
    QueueReply(QueueItemText),
    QueueSet(QueueSet),
    QueueClearDone(NodeTarget),
    QueueAttach(QueueAttach),
    QueueDetach(QueueDetach),
    /// Abre o print da tarefa no app do sistema; o mesmo endereço do
    /// `queue_detach`.
    QueueOpenImage(QueueDetach),
    WebNavigate(WebNavigate),
    WebNavigated(WebNavigated),
    WebSetProfile(WebSetProfile),
    UiFocus(UiFocus),
    UiReply(UiReply),
    /// A janela "Processos": `{processes, summary, orphans, enabled}`.
    Processes,
    ProcessesReap(ProcessesReap),
    ProcessesKill(ProcessesKill),
    // A tela do terminal (decisão 26) e o ⌘-clique e o arrasto de arquivo.
    Scroll(ScrollTo),
    Pointer(PointerAt),
    SelectAll(ScreenRef),
    /// O texto selecionado: `{text}`.
    Copy(ScreenRef),
    ClipboardReply(ClipboardReply),
    LinkHover(LinkHover),
    Drop(Drop),
    PermissionAnswer(PermissionAnswer),
    ChatNewQueue(ChatNewQueue),
    // O app (decisão 34): o menu de atualização e a limpeza de órfãos.
    UpdateMenu,
    UpdateAnswer(UpdateAnswer),
    UpdateAuto(UpdateAuto),
    ReaperEnabled(ReaperEnabled),
    /// "Copiar alvos de dispatch" (⇧⌘T): `{text}`, um endereço por linha,
    /// para a UI pôr na área de transferência.
    CopyTargets,
    /// O link da resposta do chat, no navegador do sistema.
    OpenUrl(OpenUrl),
}

impl CommandKind {
    /// O nome no fio (`cmd`), para mensagens de erro.
    pub fn name(&self) -> String {
        serde_json::to_value(self)
            .ok()
            .and_then(|v| v.get("cmd").and_then(Value::as_str).map(str::to_owned))
            .unwrap_or_default()
    }
}

/// Pedido de terminal novo, o mesmo no `/ui` e no corpo de `POST /terminal`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateTerminal {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", alias = "cmd")]
    pub command: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cols: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rows: Option<u16>,
}

/// Um nó de terminal como aparece na lista e na resposta de criação.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TerminalInfo {
    pub id: NodeId,
    pub cwd: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub command: Option<String>,
    pub pid: u32,
    pub cols: u16,
    pub rows: u16,
    pub alive: bool,
    /// Presente só depois que o processo saiu.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
}

impl TerminalInfo {
    pub fn size(&self) -> Size {
        Size {
            cols: self.cols,
            rows: self.rows,
        }
    }
}

/// Resposta a um comando. Os campos de `data` vão no mesmo nível de `re` e
/// `ok`, como nas respostas HTTP de hoje.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Reply {
    pub re: u64,
    pub ok: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(flatten)]
    pub data: Map<String, Value>,
}

impl Reply {
    pub fn ok(re: u64) -> Self {
        Self {
            re,
            ok: true,
            error: None,
            data: Map::new(),
        }
    }

    /// Resposta com dados. Um valor que não é objeto JSON vai inteiro em
    /// `value`, para nunca se perder no achatamento.
    ///
    /// `re`, `ok` e `error` que venham nos dados não vão duplicados para o fio:
    /// o `re` é sempre o do comando, e um `ok`/`error` do corpo (os corpos do
    /// Swift quase sempre trazem `ok`) vira o da resposta.
    pub fn with<T: Serialize>(re: u64, data: &T) -> Self {
        let mut data = match serde_json::to_value(data) {
            Ok(Value::Object(map)) => map,
            Ok(other) => Map::from_iter([("value".to_owned(), other)]),
            Err(err) => return Self::err(re, format!("resposta sem serializar: {err}")),
        };
        data.remove("re");
        let ok = data.remove("ok").and_then(|v| v.as_bool()).unwrap_or(true);
        let error = data.remove("error").map(|v| match v {
            Value::String(text) => text,
            other => other.to_string(),
        });
        let error = match (ok, error) {
            (false, None) => Some("falhou".to_owned()),
            (_, error) => error,
        };
        Self {
            re,
            ok,
            error,
            data,
        }
    }

    pub fn err(re: u64, error: impl Into<String>) -> Self {
        Self {
            re,
            ok: false,
            error: Some(error.into()),
            data: Map::new(),
        }
    }
}

/// Evento empurrado pelo core para quem assinou o tópico.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Event {
    pub topic: Topic,
    #[serde(flatten)]
    pub body: EventBody,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum EventBody {
    Screen(Frame),
    Terminals {
        terminals: Vec<TerminalInfo>,
    },
    Workspaces(WorkspacesState),
    Nodes(NodesState),
    /// Em caixa: o agente tem muitos campos, e sem ela todo evento de tela
    /// carregaria o tamanho dele.
    Node(Box<NodeDetail>),
    /// Em caixa pelo mesmo motivo do nó: o painel é grande.
    Usage(Box<UsageState>),
    /// `{"effect":"open_item"|"draft",…}` no tópico do nó.
    NodeEffect(NodeEffect),
    /// O estado do tópico `app`.
    App(AppState),
    /// `{"effect":"update_prompt"|"update_message"|"terminate"|"show_processes",…}`
    /// no tópico `app`.
    AppEffect(AppEffect),
    /// `{"effect":"bell"|"clipboard"|"clipboard_request",…}` no tópico da
    /// tela.
    ScreenEffect(Effect),
}

/// O que chega numa linha do lado do core: só comando.
pub fn parse_command(line: &str) -> Result<Command, ProtocolError> {
    let value: Value =
        serde_json::from_str(line).map_err(|e| ProtocolError::InvalidJson(e.to_string()))?;
    // O `id` primeiro: com ele, até um comando desconhecido ganha resposta de
    // erro endereçada a quem perguntou.
    let id = value.get("id").and_then(Value::as_u64);
    serde_json::from_value(value).map_err(|e| match id {
        Some(id) => ProtocolError::BadCommand {
            id,
            reason: e.to_string(),
        },
        None => ProtocolError::MissingId,
    })
}

/// Serializa uma mensagem como uma linha do canal, já com o `\n`.
pub fn to_line<T: Serialize>(msg: &T) -> Result<Vec<u8>, ProtocolError> {
    let mut out = serde_json::to_vec(msg).map_err(|e| ProtocolError::Encode(e.to_string()))?;
    out.push(b'\n');
    Ok(out)
}

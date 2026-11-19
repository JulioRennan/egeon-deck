//! O nó por dentro (decisão 31): o tópico `node/<wb id>/<node id>` com o
//! estado do agente, da fila ou do nó web, e os comandos de cada um. Mais os
//! comandos da tela do terminal (decisão 26) e do ⌘-clique e do arrasto de
//! arquivo para o terminal.
//!
//! O tópico é separado de `workbench/<id>/nodes`: o medidor de contexto e a
//! fila mudam o tempo todo, e reenviar a bancada inteira a cada token seria
//! tráfego à toa.

use serde::{Deserialize, Serialize};

use super::org::NodeKind;
use super::screen::{Pointer, Scroll};
use crate::commons::ids::{NodeId, WorkbenchId};

// ---- Estado: tópico `node/<wb>/<node>` ----

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NodeDetail {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub kind: NodeKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent: Option<AgentDetail>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub queue: Option<QueueDetail>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub web: Option<WebDetail>,
}

/// O cabeçalho do nó de agente, já decidido no core: a UI desenha o que vem.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentDetail {
    pub model_title: String,
    pub model_hint: String,
    /// O seletor de modelo aparece (`offersModelChoice` do Swift): o perfil
    /// oferece e há apelido, catálogo ou modelo escolhido. Falso, `models`
    /// não se mostra.
    pub offers_model: bool,
    pub models: Vec<ModelChoice>,
    pub offers_effort: bool,
    pub dial: Dial,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ultracode: Option<Ultracode>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<ContextUse>,
    /// O "limpar" da conversa está disponível.
    pub clearable: bool,
    pub clear_hint: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub conversation: Option<Conversation>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelChoice {
    pub label: String,
    /// `None` é o padrão do CLI.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    pub group: ModelGroup,
    pub selected: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ModelGroup {
    Featured,
    Older,
    Alias,
    Standard,
}

/// O seletor de esforço, do `EffortDialState` do core.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Dial {
    pub levels: Vec<String>,
    /// A marca no slider; em auto, o nível que o modelo usa.
    pub index: usize,
    pub auto: bool,
    /// Mexido e ainda não assentado: o `effort_settle` aplica.
    pub pending: bool,
    pub label: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ultracode {
    pub on: bool,
    pub available: bool,
}

/// O medidor de contexto, em tokens; a cor e o texto a UI tira daqui. O
/// grupo aparece sempre que há catálogo (`context` presente); sem leitura
/// ainda, `used` e `window` vêm nulos e a UI mostra o anel vazio e o "—".
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContextUse {
    pub used: Option<u64>,
    pub window: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Conversation {
    pub id: String,
    pub started: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueDetail {
    pub items: Vec<QueueItemView>,
    pub auto: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<NodeId>,
    /// Para quem a fila manda de fato: o alvo escolhido se ainda está ligado
    /// por aresta, senão o primeiro ligado. A UI só mostra (o seletor).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub destination: Option<NodeId>,
    /// Quantas tarefas esperam: pendentes que não estão em branco.
    #[serde(default)]
    pub pending: usize,
    /// O agente perguntou numa tarefa e espera você.
    #[serde(default)]
    pub asking: bool,
    /// O texto da coluna FILAS do chat, pronto: "? pergunta", "N pendentes",
    /// "com <agente>"… (`ChatQueue::summary`).
    #[serde(default)]
    pub summary: String,
    /// O subtítulo do nó de fila: "nada pendente" ou "N pendente(s)".
    #[serde(default)]
    pub subtitle: String,
    /// As extensões que contam como imagem ao colar ou arrastar (minúsculas,
    /// sem ponto). Arquivo de outra extensão não é anexado.
    #[serde(default)]
    pub image_extensions: Vec<String>,
    pub targets: Vec<QueueTarget>,
    /// Por que a fila não anda agora ("o alvo está ocupado"…).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub blocker: Option<String>,
    /// Pasta das imagens da fila: os `images` dos itens são nomes dentro
    /// dela, e a UI monta o caminho para mostrar a miniatura.
    pub images_dir: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueItemView {
    pub id: String,
    pub text: String,
    pub images: Vec<String>,
    pub status: QueueStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_to: Option<NodeId>,
    /// ISO-8601 UTC com milissegundos, como as datas do chat.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sent_at: Option<String>,
    pub thread: Vec<QueueMessage>,
    /// O agente perguntou e espera a resposta.
    pub awaiting: bool,
    /// Já foi a um agente: texto e prints viram registro do que foi pedido e
    /// não se editam mais — a conversa segue pela thread.
    #[serde(default)]
    pub locked: bool,
    /// A tarefa em branco: a que você está escrevendo, que não conta como
    /// pendente nem se envia.
    #[serde(default)]
    pub empty: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum QueueStatus {
    Pending,
    Sent,
    Done,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueMessage {
    pub author: String,
    pub kind: String,
    pub text: String,
    pub at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueTarget {
    pub id: NodeId,
    pub label: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebDetail {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    pub profile: String,
    /// O UUID do perfil em `web-profiles.json`: é o identificador do
    /// armazenamento do navegador, e sem ele um perfil do Swift não reabre
    /// com a sessão.
    pub profile_id: String,
    pub profiles: Vec<String>,
}

/// O estado de tela que o `egeon` dirige de fora (`/queue?open=&draft=`): sai
/// como evento no tópico do nó, porque item aberto e rascunho moram na UI
/// (decisão 3).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "effect", rename_all = "snake_case")]
pub enum NodeEffect {
    OpenItem { item: String },
    Draft { text: String },
}

// ---- Comandos ----

/// "Tentar agora" (`now`) ou "Cancelar tentativa" no estado de tentativa
/// agendada do card: o mesmo do `POST /retry?target=&now=1` (ADR-072).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RetryNode {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub now: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NodeTarget {
    pub workbench: WorkbenchId,
    pub node: NodeId,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EffortMove {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub index: usize,
}

/// A resposta traz `{item}`: o id da tarefa nova, para a UI abri-la.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueAdd {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub text: String,
    /// Entra logo depois deste item; sem ele, no fim.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub after: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueItemRef {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub item: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueItemText {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub item: String,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueMove {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub item: String,
    pub to: usize,
}

/// Sem `item`, o próximo da fila.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueSend {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub item: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueSet {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target: Option<NodeId>,
}

/// Anexa ao item o arquivo em `path`, ou o PNG (base64) de um print colado
/// sem arquivo — o core grava a imagem, como no `drop`. Sem `item`, a regra
/// do `drop` do Swift: a tarefa que a UI diz estar aberta em `open` (se ainda
/// existe e não foi enviada) recebe o print; senão nasce uma tarefa em branco.
/// A resposta traz o `item` que ficou com a imagem, para a UI abri-lo.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueAttach {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub item: Option<String>,
    /// A tarefa aberta na UI, usada só quando falta `item`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub open: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub png: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QueueDetach {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub item: String,
    pub image: String,
}

/// O que se digitou na barra: o core normaliza como o Swift (URL, busca,
/// caminho).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebNavigate {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub typed: String,
}

/// A página foi para `url`; o core grava no nó, como o main.swift:3969.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebNavigated {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub url: String,
}

/// Perfil que não existe nasce, com UUID novo, no `web-profiles.json`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebSetProfile {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub profile: String,
}

/// Decisão 33: o app foi para a frente ou para trás, e qual terminal tem o
/// foco — o `NSApp.isActive` e o first responder do Swift. Decide se o aviso
/// vira notificação e se a tecla é do usuário.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UiFocus {
    pub app_active: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node: Option<NodeTarget>,
    /// O tamanho do canvas (decisão 39): é com ele que o layout padrão
    /// empilha os nós sem frame, como o `defaultFrames` do Swift. Ausente,
    /// fica o último recebido; nunca recebido, vale o mínimo de 900x600.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub window: Option<WindowSize>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct WindowSize {
    pub w: f64,
    pub h: f64,
}

/// A resposta da UI a um `ui_request` (decisão 35): só o que o `AppControl`
/// do Swift devolvia, e o core monta o status e o corpo HTTP.
///
/// - `layout`: o modo aplicado (`"canvas"`/`"chat"`), ou `null`;
/// - `sidebar`: com `tab`, a aba aplicada, ou `null`; senão, o recolhido
///   (`true`/`false`), ou `null`;
/// - `geometry`: o retrato do canvas (objeto);
/// - `shot`: o caminho gravado, ou o texto `"erro: …"`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UiReply {
    pub request: u64,
    #[serde(default)]
    pub value: serde_json::Value,
}

// ---- Uso (decisão 37) ----

/// O consumo de uma bancada, pronto para a tela: a pílula e o painel do
/// `UsageText` do Swift (montados em `features::usage::panel`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UsageState {
    pub workbench: WorkbenchId,
    pub pill: crate::features::usage::panel::Pill,
    pub panel: crate::features::usage::panel::Panel,
}

// ---- Processos (decisão 37) ----

/// Encerrar os órfãos: o botão da janela "Processos" do Swift — todos os
/// órfãos, sem a idade mínima da limpeza periódica, e sem contar como
/// "última limpeza" (não é o `/processes/reap`). `dry_run` só devolve a
/// confirmação `{title, detail}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProcessesReap {
    #[serde(default)]
    pub dry_run: bool,
}

/// Encerrar os selecionados (SIGTERM, só o que a leitura confirma ser do
/// Egeon). `dry_run` só devolve a confirmação `{title, detail}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProcessesKill {
    pub pids: Vec<u32>,
    #[serde(default)]
    pub dry_run: bool,
}

// ---- Tela do terminal (decisão 26) ----

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ScrollTo {
    pub node: NodeId,
    pub to: Scroll,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PointerAt {
    pub node: NodeId,
    #[serde(flatten)]
    pub pointer: Pointer,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScreenRef {
    pub node: NodeId,
}

/// A resposta da UI a um `clipboard_request` (OSC 52 com `?`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipboardReply {
    pub node: NodeId,
    pub text: String,
}

/// Hover com ⌘: há destino que abre na célula (`x`, `y` em células da
/// vista)? A resposta é `{link: bool}` — a UI põe a mão.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LinkHover {
    pub node: NodeId,
    pub x: f32,
    pub y: f32,
}

/// Soltar no terminal: os caminhos do arrasto, ou o PNG (base64) de uma
/// imagem sem arquivo, que o core grava numa pasta temporária.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Drop {
    pub node: NodeId,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub paths: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub png: Option<String>,
}

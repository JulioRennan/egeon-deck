//! O contrato `/ui` de organização (decisão 24): a árvore de workspaces,
//! projetos e bancadas, os nós de cada bancada e os comandos que mexem
//! neles.
//!
//! Os tópicos mandam o estado inteiro do item na assinatura e a cada mudança,
//! sem delta: são listas pequenas. Comando que muda algo responde só
//! `{re, ok}` (e o id criado); o estado novo chega pelo tópico. A bancada é
//! sempre identificada pelo id, que é estável; o nome, renomeável, só entra
//! no endereço de dispatch.

use std::collections::BTreeMap;

use serde::{Deserialize, Deserializer, Serialize};

use crate::commons::ids::{NodeId, ProjectId, WorkbenchId, WorkspaceId};

/// Campo que pode vir ausente (não mexe), `null` (volta ao padrão) ou com
/// valor.
pub type Patch<T> = Option<Option<T>>;

fn patch<'de, D, T>(deserializer: D) -> Result<Patch<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer).map(Some)
}

// ---- Estado: tópico `workspaces` ----

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkspacesState {
    pub workspaces: Vec<WorkspaceView>,
    /// Bancadas sem projeto conhecido; a barra as mostra em "Geral".
    pub orphans: Vec<WorkbenchId>,
    pub workbenches: Vec<WorkbenchView>,
    /// A lista "Ativas" da barra lateral.
    pub active: Vec<ActiveEntry>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkspaceView {
    pub id: WorkspaceId,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
    pub collapsed: bool,
    /// A gaveta de projetos guardados está aberta.
    pub stored_open: bool,
    pub projects: Vec<ProjectView>,
    /// A soma das bancadas dos projetos, para a linha do grupo.
    #[serde(default)]
    pub activity: ActivityCounts,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectView {
    pub id: ProjectId,
    pub name: String,
    pub path: String,
    /// A pasta do projeto existe em disco.
    pub exists: bool,
    pub collapsed: bool,
    /// Na gaveta.
    pub stored: bool,
    /// Presente só no multi-projeto: os projetos que ele junta.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub members: Option<Vec<ProjectId>>,
    /// As bancadas do projeto, na ordem da árvore.
    pub workbenches: Vec<WorkbenchId>,
    /// A soma das bancadas do projeto, para a linha do grupo.
    #[serde(default)]
    pub activity: ActivityCounts,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ViewMode {
    #[default]
    Canvas,
    Chat,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkbenchView {
    pub id: WorkbenchId,
    pub name: String,
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub project: Option<ProjectId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    pub view: ViewMode,
    /// Posição na faixa de abas; ausente é bancada fechada.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tab_order: Option<u32>,
    /// A aba da frente.
    pub tab_active: bool,
    /// A pasta da bancada existe em disco.
    pub exists: bool,
    /// Os terminais dela estão de pé (já foi aberta nesta sessão).
    pub live: bool,
    /// Sendo removida: o `worktree remove` ainda corre.
    pub removing: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rules: Option<String>,
    pub activity: ActivityCounts,
    /// Quantos nós de agente: o "limpar" confirma com o número.
    pub agents: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub clock: Option<WorkbenchClock>,
    /// A cortina "sem acesso" (decisão 39): o macOS não deixa ler a pasta.
    /// Ausente, dá para ler.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub access: Option<AccessLock>,
}

/// Por que a bancada está travada: a pasta protegida do macOS, quando é uma
/// delas, e o aviso pronto (`FolderAccess.message`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AccessLock {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub folder: Option<String>,
    pub message: String,
}

/// O relógio da bancada (`WorkbenchClock`), em segundos: a UI só formata.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkbenchClock {
    pub running: u64,
    pub waiting: u64,
    pub failed: u64,
    /// Os que estão correndo agora.
    pub ticking: Vec<ClockState>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClockState {
    Running,
    Waiting,
    Failed,
}

/// Quantos nós da bancada estão em cada estado, para o resumo na aba e na
/// barra.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ActivityCounts {
    pub working: u32,
    pub starting: u32,
    pub attention: u32,
    pub done: u32,
    pub background: u32,
}

impl std::ops::Add for ActivityCounts {
    type Output = Self;

    fn add(self, other: Self) -> Self {
        Self {
            working: self.working + other.working,
            starting: self.starting + other.starting,
            attention: self.attention + other.attention,
            done: self.done + other.done,
            background: self.background + other.background,
        }
    }
}

impl std::iter::Sum for ActivityCounts {
    fn sum<I: Iterator<Item = Self>>(iter: I) -> Self {
        iter.fold(Self::default(), |a, b| a + b)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActiveEntry {
    pub workbench: WorkbenchId,
    pub state: ActiveState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActiveState {
    Recent,
    Stale,
}

// ---- Estado: tópico `workbench/<id>/nodes` ----

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NodesState {
    pub workbench: WorkbenchId,
    pub nodes: Vec<NodeView>,
    /// As ligações já colapsadas por par, como o `EdgeLink` do Swift: uma
    /// linha na tela, com as duas pontas.
    pub links: Vec<LinkView>,
}

/// Os tipos de nó do `NodeKind` do Swift.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NodeKind {
    Shell,
    Agent,
    Web,
    Queue,
}

/// Posição e tamanho de um card no documento do canvas.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NodeView {
    pub id: NodeId,
    #[serde(rename = "type")]
    pub kind: NodeKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    /// Onde o processo abre, já resolvido e com `~`: o subtítulo do card.
    pub dir: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cmd: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ultracode: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    /// O papel do nó (o `prompt` do Swift).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rules: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub component: Option<String>,
    pub maestro: bool,
    /// Ausente até o primeiro arranjo: quem posiciona é o canvas, que grava
    /// com `move_node`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frame: Option<Rect>,
    /// O id que a UI assina em `screen/<id>` para ver a tela do terminal.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub screen: Option<NodeId>,
    /// O processo do nó está de pé.
    pub alive: bool,
    /// O que o terminal está fazendo, do dispatch. Ausente em nó sem
    /// terminal (web, fila) ou que ainda não foi registrado.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub activity: Option<NodeActivity>,
    /// O `cwd` resolve para uma pasta que existe. Falso, o terminal abre na
    /// raiz da bancada, como no Swift — e a tela diz, em vez de calar.
    pub exists: bool,
    /// O cartão tem a porta "+" na borda (terminal e fila). Independe de haver
    /// com quem ligar agora: quem já está ligado a todos continua com a porta.
    #[serde(default)]
    pub port: bool,
    /// Com quem este nó pode ligar agora (a regra do arrasto da porta): os
    /// terminais ainda sem ligação com ele, em qualquer sentido. Vazio em quem
    /// não tem porta (web) e em quem já ligou com todos.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub linkable: Vec<NodeId>,
}

/// A atividade de um terminal (`Activity` do Swift), já com a regra de
/// atenção decidida no core: a UI acende a borda e não repete a regra.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NodeActivity {
    /// `starting`, `ready`, `working`, `waiting`, `asking`, `background`,
    /// `awaiting`, `retrying`, `failed` ou `dead`.
    pub state: String,
    /// Interrompe: borda e som (`Activity.needsAttention`).
    pub needs_attention: bool,
    /// Em `awaiting`: os vizinhos que ainda não responderam.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub waiting_on: Vec<String>,
    /// Em `failed`: o erro da API.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// Em `retrying`: a tentativa em curso.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attempt: Option<u32>,
    /// O texto do cabeçalho do card, pronto (`Activity.label` do Swift, sem
    /// o glifo): "trabalhando", "precisa de você", "tentando de novo às
    /// 14:05 (2/3)". Ausente em `ready`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    /// O glifo que vai antes do texto, que a UI anima: `spinner`,
    /// `hourglass`, `dot`, `retry` ou `cross`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub glyph: Option<String>,
    /// A cor do texto: `green` (terminou), `orange` (depende de você) ou
    /// `red` (falhou, encerrado). Ausente mantém o acento do tipo de nó.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tone: Option<String>,
    /// Mensagens na fila do terminal; o cabeçalho mostra "N na fila".
    #[serde(default)]
    pub pending: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkView {
    pub a: NodeId,
    pub b: NodeId,
    /// `a` pode acionar `b`: ponta do lado de `b`.
    pub a_to_b: bool,
    /// `b` pode acionar `a`: ponta do lado de `a`.
    pub b_to_a: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_sends: Option<u32>,
}

// ---- Comandos ----

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkbenchRef {
    pub workbench: WorkbenchId,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MoveTab {
    pub workbench: WorkbenchId,
    pub to: u32,
}

/// O `kind` do `/move` do Swift.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MoveKind {
    Workspace,
    Project,
    Workbench,
    Store,
    Unstore,
    Drawer,
}

/// Em `store`/`unstore`, `to` é a posição dentro da gaveta (ou fora dela),
/// num comando só (decisão 24). Em `drawer`, `to` não conta.
///
/// O `/move` do Swift sem tirar nem pôr: `item` é o `id` de lá — de
/// workspace, projeto ou bancada conforme o `kind` — e `parent` é o destino
/// (workspace do projeto, projeto da bancada). Aqui não pode se chamar `id`:
/// esse é o do comando.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Move {
    pub kind: MoveKind,
    pub item: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent: Option<String>,
    #[serde(default)]
    pub to: i32,
}

/// Onde o item cairia: a resposta do `plan_move`, que não aplica nada.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Lands {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent: Option<String>,
    pub to: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateWorkspace {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetWorkspace {
    pub workspace: WorkspaceId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// O caminho do arquivo escolhido; o core copia para a pasta do
    /// workspace. `null` tira o ícone.
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub icon: Patch<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub collapsed: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stored_open: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceRef {
    pub workspace: WorkspaceId,
}

/// O nome padrão que o formulário mostra para um multi-projeto com estas
/// pastas (`pasta1 + pasta2`, como o Swift): a resposta é `{name}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MultiName {
    /// Ausente no formulário de um workspace que ainda não existe: o nome
    /// padrão só depende das pastas.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace: Option<WorkspaceId>,
    pub folders: Vec<String>,
}

/// Um multi-projeto do formulário. Sem `id`, nasce.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MultiDraft {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<ProjectId>,
    /// Vazio ou ausente: o core dá o nome padrão (`pasta1 + pasta2`) a um
    /// multi-projeto novo e mantém o nome de um que já existe.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    pub folders: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SaveWorkspace {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace: Option<WorkspaceId>,
    pub name: String,
    /// O caminho do arquivo escolhido; o core copia para a pasta do
    /// workspace. `null` tira o ícone; ausente não mexe.
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub icon: Patch<String>,
    pub folders: Vec<String>,
    #[serde(default)]
    pub multis: Vec<MultiDraft>,
}

/// `dry_run` só confere: a recusa é a mesma do Swift ("\"X\" ainda tem N
/// bancada(s)…"), sem remover nada.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemoveWorkspace {
    pub workspace: WorkspaceId,
    #[serde(default)]
    pub dry_run: bool,
}

/// O "Novo projeto…" (`/project/new`): cria a pasta `name` dentro de
/// `parent` e a põe no workspace.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateProject {
    pub workspace: WorkspaceId,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent: Option<String>,
    /// `git init` na pasta nova; o Swift o faz a menos que peçam `git=0`.
    #[serde(default = "yes")]
    pub git: bool,
}

fn yes() -> bool {
    true
}

/// Uma pasta que já existe vira projeto do workspace.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AddProject {
    pub workspace: WorkspaceId,
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetProject {
    pub project: ProjectId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub collapsed: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemoveProject {
    pub project: ProjectId,
    #[serde(default)]
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MultiProject {
    pub workspace: WorkspaceId,
    pub name: String,
    pub members: Vec<ProjectId>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateWorkbench {
    pub path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub project: Option<ProjectId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
}

/// Renomear passa pelo nome livre, como no Swift: o pedido é a sugestão.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetWorkbench {
    pub workbench: WorkbenchId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub view: Option<ViewMode>,
}

/// As regras da bancada; `null` apaga.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetWorkbenchRules {
    pub workbench: WorkbenchId,
    pub rules: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemoveWorkbench {
    pub workbench: WorkbenchId,
    /// Apaga também as worktrees do disco. O padrão é não apagar.
    #[serde(default)]
    pub worktrees: bool,
}

/// Worktree da bancada inteira, ou de terminais escolhidos com a branch de
/// cada um em `nodes` (vazio é a branch da bancada). `destination` é o
/// rádio do formulário do Swift: abrir uma bancada nova na worktree ou
/// mudar esta para ela. A resposta traz `{workbench}`: o id da bancada.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Worktree {
    /// Ausente: bancada nova a partir de uma pasta, sem origem — `path` ou
    /// `project` dizem de onde sai o repositório.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workbench: Option<WorkbenchId>,
    /// Sem `workbench`: a pasta do repositório (`~` aceito).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    /// Sem `workbench`: o projeto da barra lateral em que a bancada nasce.
    /// Sem `path`, o repositório é a pasta dele; multi-projeto abre uma
    /// worktree por repositório.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub project: Option<ProjectId>,
    pub branch: String,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub nodes: BTreeMap<NodeId, String>,
    #[serde(default)]
    pub destination: WorktreeDestination,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub template: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorktreeDestination {
    #[default]
    NewWorkbench,
    MoveCurrent,
}

/// O resumo do formulário de worktree (decisão 37): o repositório, a
/// branch sugerida e o que acontece com cada terminal. Resposta de
/// `worktree_info`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorktreeInfo {
    pub summary: String,
    pub suggested_branch: String,
    pub nodes: Vec<WorktreeNode>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorktreeNode {
    pub node: NodeId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    pub state: WorktreeNodeState,
}

/// O terminal ganha worktree própria, vai junto com a da bancada, ou não
/// está num repositório.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorktreeNodeState {
    OwnWorktree,
    FollowsWorkbench,
    NoRepo,
}

/// O veredito do nome da branch (ADR-018), sem criar nada: resposta de
/// `worktree_plan`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorktreePlan {
    pub verdict: BranchVerdict,
    pub folder: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BranchVerdict {
    Create,
    OpenExisting,
    FollowRemote,
    AlreadyOpen,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorktreePlanRequest {
    pub workbench: WorkbenchId,
    pub branch: String,
}

/// Um template de bancada (`templates.json`), para o formulário de bancada
/// nova: resposta de `templates`, em `{templates:[…]}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplateView {
    pub name: String,
    pub nodes: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub base_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub view: Option<ViewMode>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CreateNode {
    pub workbench: WorkbenchId,
    #[serde(rename = "type")]
    pub kind: NodeKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub frame: Option<Rect>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub component: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cmd: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

/// Os campos do formulário do nó. Ausente não mexe; `null` volta ao padrão
/// (o modelo do CLI, sem papel). O que reinicia o terminal segue o Swift.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetNode {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub model: Patch<String>,
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub effort: Patch<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ultracode: Option<bool>,
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub role: Patch<String>,
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub rules: Patch<String>,
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub cwd: Patch<String>,
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub cmd: Patch<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub maestro: Option<bool>,
}

/// Mandado ao soltar o arrasto ou o redimensionamento, não a cada quadro.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MoveNode {
    pub workbench: WorkbenchId,
    pub node: NodeId,
    pub frame: Rect,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NodeRef {
    pub workbench: WorkbenchId,
    pub node: NodeId,
}

/// Cria a aresta `from → to` como o arrasto da porta "+" cria; `both` liga
/// os dois sentidos.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Link {
    pub workbench: WorkbenchId,
    pub from: NodeId,
    pub to: NodeId,
    #[serde(default)]
    pub both: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_sends: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Unlink {
    pub workbench: WorkbenchId,
    pub from: NodeId,
    pub to: NodeId,
    #[serde(default)]
    pub both: bool,
}

/// A direção do par, como o `direction` do `/edge`: `cycle` é o botão da
/// linha e `none` desliga os dois sentidos.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Direction {
    #[serde(rename = "->")]
    Forward,
    #[serde(rename = "<-")]
    Backward,
    #[serde(rename = "<->")]
    Both,
    #[serde(rename = "cycle")]
    Cycle,
    #[serde(rename = "none")]
    None,
}

/// Muda o par `from`/`to`: a direção, o limite (`null` tira), ou os dois.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetEdge {
    pub workbench: WorkbenchId,
    pub from: NodeId,
    pub to: NodeId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub direction: Option<Direction>,
    #[serde(
        default,
        deserialize_with = "patch",
        skip_serializing_if = "Option::is_none"
    )]
    pub max_sends: Patch<u32>,
}

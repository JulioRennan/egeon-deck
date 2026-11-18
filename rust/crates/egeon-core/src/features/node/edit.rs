//! Criar, editar e remover um nó da bancada: as regras que o `main.swift` aplica
//! em `addNode`, `place`, `editNode` e `remove(_:)`, sem tela e sem processo.
//! Quem sobe e derruba o terminal é o ator.

use super::model::{Frame, NodeConfig, NodeKind};
use crate::features::edge::EdgeConfig;
use crate::features::workbench::model::WorkbenchConfig;

/// A página que um nó web abre quando nasce (`WebNode.homeURL`).
pub const WEB_HOME_URL: &str = "https://www.google.com";
/// O perfil de navegação padrão (`WebProfileStore.defaultName`).
pub const DEFAULT_WEB_PROFILE: &str = "pessoal";

/// `sh`, `sh-2`, `sh-3`… O id entra no endereço de dispatch, então precisa ser
/// único dentro da bancada.
pub fn next_id(prefix: &str, config: &WorkbenchConfig) -> String {
    let taken = |id: &str| config.nodes.iter().any(|n| n.id == id);
    if !taken(prefix) {
        return prefix.to_owned();
    }
    let mut n = 2;
    while taken(&format!("{prefix}-{n}")) {
        n += 1;
    }
    format!("{prefix}-{n}")
}

/// A base do id de um nó novo sem componente (`CanvasTool.idPrefix`): segue a
/// convenção que já está no `workbenches.json`.
pub fn id_prefix(kind: NodeKind, agent: Option<&str>) -> String {
    match kind {
        NodeKind::Web => "web".to_owned(),
        NodeKind::Queue => "fila".to_owned(),
        NodeKind::Agent => agent.filter(|a| !a.is_empty()).unwrap_or("sh").to_owned(),
        NodeKind::Shell => "sh".to_owned(),
    }
}

/// O que um nó novo, sem componente, pede.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct NewNode {
    pub agent: Option<String>,
    pub cwd: Option<String>,
    pub cmd: Option<String>,
    pub url: Option<String>,
    pub frame: Option<Frame>,
}

/// Um nó novo do tipo dado, com id livre. O web nasce na página inicial e no
/// perfil padrão.
pub fn new_node(kind: NodeKind, spec: NewNode, config: &WorkbenchConfig) -> NodeConfig {
    let prefix = id_prefix(kind, spec.agent.as_deref());
    let mut node = NodeConfig::new(kind, next_id(&prefix, config));
    node.agent = spec.agent.filter(|_| kind == NodeKind::Agent);
    node.cwd = spec.cwd.filter(|c| !c.is_empty());
    node.cmd = spec.cmd.filter(|c| !c.is_empty());
    if kind == NodeKind::Web {
        node.url = Some(spec.url.unwrap_or_else(|| WEB_HOME_URL.to_owned()));
        node.profile = Some(DEFAULT_WEB_PROFILE.to_owned());
    }
    if let Some(frame) = spec.frame {
        node.set_frame(frame);
    }
    node
}

/// Um campo do formulário: ausente não mexe, `null` volta ao padrão, valor
/// grava. Texto vazio conta como `null`.
pub type Patch<T> = Option<Option<T>>;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NodePatch {
    pub model: Patch<String>,
    pub effort: Patch<String>,
    pub ultracode: Option<bool>,
    pub role: Patch<String>,
    pub rules: Patch<String>,
    pub cwd: Patch<String>,
    pub cmd: Patch<String>,
    pub maestro: Option<bool>,
}

fn apply(field: &mut Option<String>, patch: &Patch<String>) {
    if let Some(value) = patch {
        *field = value.clone().filter(|v| !v.is_empty());
    }
}

/// O texto efetivo é o do CLI em uso quando ele tem um próprio; mexer só no
/// geral não mudaria o que sobe. Então o campo vai para onde o efetivo mora.
fn apply_text(node: &mut NodeConfig, patch: &Patch<String>, rules: bool) {
    let Some(value) = patch else { return };
    let value = value.clone().filter(|v| !v.is_empty());
    let own = node
        .agent
        .clone()
        .and_then(|a| node.by_agent.as_mut().and_then(|m| m.get_mut(&a)));
    if let Some(over) = own {
        let slot = if rules {
            &mut over.rules
        } else {
            &mut over.prompt
        };
        if slot.is_some() {
            *slot = value.clone();
            if value.is_none() {
                // `null` volta ao padrão: o geral também sai.
            } else {
                return;
            }
        }
    }
    let general = if rules {
        &mut node.rules
    } else {
        &mut node.prompt
    };
    *general = value;
}

/// Os campos do nó depois do formulário, e se o processo precisa recomeçar.
///
/// Nome, comando, agente e pasta definem como o processo foi lançado, então
/// mudá-los exige um processo novo — não há como reconfigurar um pty em
/// andamento. O que NÃO reinicia: o ultracode (o Swift não o compara), e o
/// que não entra na linha de comando nem no system prompt.
pub fn apply_patch(current: &NodeConfig, patch: &NodePatch) -> (NodeConfig, bool) {
    let mut updated = current.clone();
    apply(&mut updated.model, &patch.model);
    apply(&mut updated.effort, &patch.effort);
    apply(&mut updated.cwd, &patch.cwd);
    apply(&mut updated.cmd, &patch.cmd);
    if let Some(ultracode) = patch.ultracode {
        updated.ultracode = ultracode.then_some(true);
    }
    if let Some(maestro) = patch.maestro {
        updated.maestro = maestro.then_some(true);
    }
    apply_text(&mut updated, &patch.role, false);
    apply_text(&mut updated, &patch.rules, true);

    let same_process = updated.kind == current.kind
        && updated.agent == current.agent
        && updated.model == current.model
        && updated.effort == current.effort
        && updated.cmd == current.cmd
        && updated.config == current.config
        && updated.cwd == current.cwd
        // O EFETIVO, não o geral: mudar só a exceção do CLI em uso muda o
        // system prompt, e ele só é lido no arranque.
        && updated.effective_prompt() == current.effective_prompt()
        && updated.effective_rules() == current.effective_rules()
        // O maestro tem uma seção própria no system prompt (ADR-066).
        && updated.is_maestro() == current.is_maestro()
        && updated.approves_team_permissions() == current.approves_team_permissions();
    (updated, !same_process)
}

/// O que tirar um nó leva junto da bancada.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Removed {
    /// As ligações que apontavam para ele.
    pub edges: usize,
}

/// Tira o nó e as ligações que apontam para ele: aresta para nó que não existe
/// mais viraria alvo morto no catálogo do agente — ele leria um endereço e o
/// dispatch recusaria. `None` quando o nó não existe.
pub fn remove_node(config: &mut WorkbenchConfig, id: &str) -> Option<Removed> {
    let before = config.nodes.len();
    config.nodes.retain(|n| n.id != id);
    if config.nodes.len() == before {
        return None;
    }
    let orphans = config
        .edge_list()
        .iter()
        .filter(|e| e.from == id || e.to == id)
        .count();
    if orphans > 0 {
        let kept: Vec<EdgeConfig> = config
            .edge_list()
            .iter()
            .filter(|e| e.from != id && e.to != id)
            .cloned()
            .collect();
        config.edges = Some(kept);
    }
    Some(Removed { edges: orphans })
}

/// Um agente que guarda conversa ganha o id dela antes de subir, uma vez: é
/// o que permite retomar depois de um rebuild, e dois agentes na mesma worktree
/// terem conversas separadas (`prepared` do `main.swift`). `true` quando um id
/// foi dado e a bancada precisa ser gravada. O id é o `UUID().uuidString` do
/// Swift, em maiúsculas.
pub fn prepare_conversation(
    node: &mut NodeConfig,
    profile: Option<&crate::features::agent::model::AgentProfile>,
) -> bool {
    let keeps = node.kind == NodeKind::Agent && profile.is_some_and(|p| p.keeps_conversation());
    if !keeps || node.conversation_id.is_some() {
        return false;
    }
    node.conversation_id = Some(uuid::Uuid::new_v4().to_string().to_uppercase());
    true
}

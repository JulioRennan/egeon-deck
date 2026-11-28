//! Regras do componente: capturar um nó como preset e instanciar o preset como
//! nó. Porte dos métodos estáticos do `NodeTemplateStore`.
//!
//! O id que sai do nome do componente é `NodeId::slug`, em `commons::ids`.

use super::model::{NodeConfig, NodeKind, NodeTemplate};

/// Converte um nó já existente em componente ("salvar este terminal como
/// componente").
///
/// O que o nó tem de CLI entra no mapa do CLI dele; o resto é o papel. As
/// regras do nó viram as gerais: quem captura um terminal não está dizendo que
/// elas valem só ali (ADR-057).
pub fn capture(node: &NodeConfig, name: &str) -> NodeTemplate {
    // O que vale agora é do CLI em uso; o que os outros tinham vem junto.
    let mut by_agent = node.by_agent.clone().unwrap_or_default();
    if let Some(key) = &node.agent {
        let mut over = by_agent.get(key).cloned().unwrap_or_default();
        over.cmd = node.cmd.clone();
        over.config = node.config.clone();
        over.model = node.model.clone();
        over.effort = node.effort.clone();
        if over.is_empty() {
            by_agent.remove(key);
        } else {
            by_agent.insert(key.clone(), over);
        }
    }
    let mut template = NodeTemplate::new(name, node.kind);
    template.agent = node.agent.clone();
    template.cwd = node.cwd.clone();
    template.prompt = node.prompt.clone();
    template.rules = node.rules.clone();
    template.by_agent = if by_agent.is_empty() {
        None
    } else {
        Some(by_agent)
    };
    template.command = if node.kind == NodeKind::Shell {
        node.cmd.clone()
    } else {
        None
    };
    template.maestro = if node.is_maestro() { Some(true) } else { None };
    template
}

/// Instancia o componente como nó, com `id` único dentro da bancada. O que é
/// do CLI sai do mapa dele; o resto é o papel, e vale igual em qualquer um.
pub fn instantiate(component: &NodeTemplate, id: &str) -> NodeConfig {
    let resolved = component.resolved(component.agent.as_deref());
    let mut node = NodeConfig::new(component.kind, id);
    node.agent = component.agent.clone();
    node.cmd = if component.kind == NodeKind::Shell {
        component.command.clone()
    } else {
        resolved.cmd
    };
    node.config = resolved.config;
    node.model = resolved.model;
    node.effort = resolved.effort;
    node.cwd = component.cwd.clone();
    // Os GERAIS: a exceção de cada CLI vai no mapa, e o efetivo sai dos dois
    // na hora de subir.
    node.prompt = component.prompt.clone();
    node.rules = component.rules.clone();
    // A memória dos outros CLIs viaja com o nó: é o que faz voltar para o
    // Claude Code depois de mexer no Codex devolver o que era.
    node.by_agent = component.by_agent.clone();
    node.component = Some(component.name.clone());
    node.maestro = if component.kind == NodeKind::Agent && component.maestro == Some(true) {
        Some(true)
    } else {
        None
    };
    node
}

/// Um item do popup de configuração do CLI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigItem {
    pub title: String,
    /// `None` é o padrão da CLI, gravado vazio.
    pub value: Option<String>,
}

/// O texto do item padrão quando o perfil não diz onde o CLI guarda a config.
pub const DEFAULT_CONFIG_OPTION: &str = "padrão da CLI";

/// Os itens do popup de configuração.
///
/// O primeiro é o padrão, mostrado pelo caminho que o CLI usa sem a variável
/// (`~/.claude`), e gravado vazio — é a mesma pasta, e não escrever nada no
/// ambiente deixa o CLI decidir. Por isso ela não se repete entre as
/// descobertas.
///
/// O valor gravado no nó pode não existir aqui: componente que veio de outra
/// máquina, ou pasta renomeada. Some da lista descoberta, e sem este item a
/// escolha viraria o padrão em silêncio.
pub fn config_items(
    default: Option<&str>,
    discovered: &[String],
    current: Option<&str>,
    home: &str,
) -> Vec<ConfigItem> {
    use crate::features::worktree::node::short;
    let mut items = vec![ConfigItem {
        title: default.map_or_else(|| DEFAULT_CONFIG_OPTION.to_owned(), |p| short(p, home)),
        value: None,
    }];
    items.extend(
        discovered
            .iter()
            .filter(|d| Some(d.as_str()) != default)
            .map(|d| ConfigItem {
                title: short(d, home),
                value: Some(d.clone()),
            }),
    );
    if let Some(current) = current
        && Some(current) != default
        && !items.iter().any(|i| i.value.as_deref() == Some(current))
    {
        items.push(ConfigItem {
            title: short(current, home),
            value: Some(current.to_owned()),
        });
    }
    items
}

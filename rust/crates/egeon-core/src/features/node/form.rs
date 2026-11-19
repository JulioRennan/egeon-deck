//! O formulário de terminal, o mesmo para criar e para editar: porte das regras
//! do `NodeTemplateDialog` (listas de modelo, esforço, configuração e pasta, o
//! que ele grava ao confirmar) e do "mesmo processo" do `editNode`.
//!
//! Sem tela: a UI pergunta o que mostrar e devolve o que está nela.

use std::collections::BTreeMap;
use std::path::Path;

use super::model::{NodeConfig, NodeKind, NodeTemplate, Resolved};
use super::service::{ConfigItem, config_items};
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::ModelCatalog;
use crate::features::path_text::{abbreviate_tilde, expand_tilde, standardize};

/// O primeiro item de modelo e de esforço: não passar nada ao CLI.
pub const DEFAULT_MODEL_OPTION: &str = "padrão do CLI";

/// O que estava na tela para um CLI quando ele saiu dela.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Shown {
    pub cli: String,
    pub model: Option<String>,
    pub effort: Option<String>,
    pub config: Option<String>,
    pub prompt: Option<String>,
    pub rules: Option<String>,
}

/// Os campos de cima do formulário, que não são de CLI nenhum.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormFields {
    pub name: String,
    pub kind: NodeKind,
    pub agent: Option<String>,
    pub cwd: String,
    pub cmd: Option<String>,
    pub maestro: bool,
}

/// Um item do popup de modelo. `None` é o padrão do CLI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelItem {
    pub label: String,
    pub id: Option<String>,
}

/// O que a tela mostra para um CLI: os valores e as listas de onde escolhê-los.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Screen {
    pub template: NodeTemplate,
    pub fields: Resolved,
    pub models: Vec<ModelItem>,
    /// Os níveis, sem o padrão (que é o primeiro item na tela).
    pub efforts: Vec<String>,
    pub config_env: Option<String>,
    pub config_items: Vec<ConfigItem>,
}

/// O que o pedido de tela traz.
pub struct ScreenRequest<'a> {
    pub template: &'a NodeTemplate,
    pub shown: Option<&'a Shown>,
    pub cli: Option<&'a str>,
    /// A configuração escolhida agora no + do campo.
    pub picked_config: Option<&'a str>,
    /// A última configuração de cada CLI no workspace. Vazio ao editar — ali
    /// vale a do nó.
    pub suggested_configs: &'a BTreeMap<String, String>,
}

/// O texto sem espaço nas pontas, ou nulo quando sobra nada.
fn trimmed(text: Option<&str>) -> Option<String> {
    text.map(str::trim)
        .filter(|t| !t.is_empty())
        .map(str::to_owned)
}

/// Guarda o que está na tela no CLI que estava selecionado. O comando do CLI
/// não está na tela: vai o que ele já tinha, para não ser apagado (ADR-057).
pub fn remember_shown(template: &NodeTemplate, shown: &Shown) -> NodeTemplate {
    let cli = Some(shown.cli.as_str());
    template.remembering(
        cli,
        Resolved {
            cmd: template.overrides(cli).cmd,
            config: shown.config.clone(),
            model: shown.model.clone(),
            effort: shown.effort.clone(),
            prompt: trimmed(shown.prompt.as_deref()),
            rules: trimmed(shown.rules.as_deref()),
        },
    )
}

/// Os itens do popup de modelo e o escolhido.
///
/// A lista vem do perfil: trocar de CLI troca os modelos. A escolha anterior só
/// volta se o CLI novo a conhecer — `opus` não diz nada ao Codex. Modelo
/// escrito à mão no `components.json` continua valendo: só é descartado quando
/// o CLI declara uma lista e o valor não está nela. Com catálogo, os modelos
/// vêm com nome de gente e os apelidos seguem depois.
pub fn model_items(
    profile: Option<&AgentProfile>,
    catalog: Option<&ModelCatalog>,
    value: Option<&str>,
) -> (Vec<ModelItem>, Option<String>) {
    let mut items = vec![ModelItem {
        label: DEFAULT_MODEL_OPTION.to_owned(),
        id: None,
    }];
    let aliases: Vec<String> = profile.and_then(|p| p.models.clone()).unwrap_or_default();
    let catalog = catalog.filter(|c| !c.models.is_empty());
    let mut ids = aliases.clone();
    if let Some(catalog) = catalog {
        for model in catalog.featured().into_iter().chain(catalog.older()) {
            items.push(ModelItem {
                label: model.label.clone(),
                id: Some(model.id.clone()),
            });
        }
        ids.extend(catalog.models.iter().map(|m| m.id.clone()));
    }
    for alias in &aliases {
        items.push(ModelItem {
            label: alias.clone(),
            id: Some(alias.clone()),
        });
    }
    if let Some(value) = value.filter(|v| !v.is_empty())
        && !ids.iter().any(|id| id == value)
        && aliases.is_empty()
        && catalog.is_none()
    {
        items.push(ModelItem {
            label: value.to_owned(),
            id: Some(value.to_owned()),
        });
    }
    let chosen = value.and_then(|v| items.iter().find(|i| i.id.as_deref() == Some(v)));
    let selected = chosen.and_then(|i| i.id.clone());
    (items, selected)
}

/// Os níveis de esforço e o escolhido: a mesma regra do modelo — a lista é do
/// perfil, e um nível que o CLI novo não declara não é levado junto.
pub fn effort_items(
    profile: Option<&AgentProfile>,
    value: Option<&str>,
) -> (Vec<String>, Option<String>) {
    let known: Vec<String> = profile.and_then(|p| p.efforts.clone()).unwrap_or_default();
    let mut options = known.clone();
    if let Some(value) = value.filter(|v| !v.is_empty())
        && !options.iter().any(|o| o == value)
        && known.is_empty()
    {
        options.push(value.to_owned());
    }
    let selected = value.filter(|v| options.iter().any(|o| o == v));
    let selected = selected.map(str::to_owned);
    (options, selected)
}

/// O que a tela mostra para `cli`, depois de guardar o que estava nela.
///
/// Trocar de CLI troca o conjunto de configurações: as do Claude Code não
/// dizem nada ao Codex. A configuração entra a do nó; sem ela, a sugerida pelo
/// workspace.
pub fn screen(
    request: ScreenRequest<'_>,
    profiles: &BTreeMap<String, AgentProfile>,
    catalog: &dyn Fn(&AgentProfile) -> Option<ModelCatalog>,
    home: &str,
) -> Screen {
    let template = match request.shown {
        Some(shown) => remember_shown(request.template, shown),
        None => request.template.clone(),
    };
    let cli = request.cli;
    let resolved = template.resolved(cli);
    let profile = cli.and_then(|c| profiles.get(c));
    // O seletor da UI devolve `~`; as descobertas e o nó gravam absoluto.
    let picked = request.picked_config.map(|c| expand_tilde(c, home));
    let config = picked.or_else(|| {
        resolved
            .config
            .clone()
            .or_else(|| cli.and_then(|c| request.suggested_configs.get(c).cloned()))
    });

    let default_config = profile
        .and_then(|p| p.default_config_path(Path::new(home)))
        .map(|p| p.to_string_lossy().into_owned());
    let discovered: Vec<String> = profile
        .map(|p| p.discovered_configs(Path::new(home)))
        .unwrap_or_default()
        .iter()
        .map(|p| p.to_string_lossy().into_owned())
        .collect();
    let items = config_items(
        default_config.as_deref(),
        &discovered,
        config.as_deref(),
        home,
    );
    // O padrão gravado no nó é o mesmo que não gravar nada.
    let chosen = config.filter(|c| Some(c) != default_config.as_ref());
    let config = chosen.filter(|c| items.iter().any(|i| i.value.as_ref() == Some(c)));

    let catalog = profile.and_then(catalog);
    let (models, model) = model_items(profile, catalog.as_ref(), resolved.model.as_deref());
    let (efforts, effort) = effort_items(profile, resolved.effort.as_deref());
    Screen {
        fields: Resolved {
            cmd: resolved.cmd,
            config,
            model,
            effort,
            prompt: resolved.prompt,
            rules: resolved.rules,
        },
        template,
        models,
        efforts,
        config_env: profile.and_then(|p| p.config_env.clone()),
        config_items: items,
    }
}

/// O que o + da pasta grava.
///
/// Dentro da raiz da bancada, RELATIVO — é o que faz o nó valer em qualquer
/// checkout. A própria raiz grava vazio. Fora dela, absoluto encurtado para
/// `~`. Nunca `..`: o mesmo texto significaria pastas diferentes em checkouts
/// diferentes (ADR-017).
pub fn stored_folder(path: &str, root: Option<&str>, home: &str) -> String {
    let path = standardize(&expand_tilde(path, home));
    let Some(root) = root.map(|r| standardize(&expand_tilde(r, home))) else {
        return abbreviate_tilde(&path, home);
    };
    if path == root {
        return String::new();
    }
    match path.strip_prefix(&format!("{}/", root.trim_end_matches('/'))) {
        Some(rest) => rest.to_owned(),
        None => abbreviate_tilde(&path, home),
    }
}

/// O que a pasta grava ao confirmar. Relativo continua relativo; absoluto
/// continua absoluto, encurtado para `~`.
pub fn normalized_folder(path: &str, home: &str) -> String {
    if !(path.starts_with('/') || path.starts_with('~')) {
        return path.to_owned();
    }
    abbreviate_tilde(&expand_tilde(path, home), home)
}

/// O componente que sai do formulário confirmado.
///
/// Nome em branco vira um padrão em vez de cancelar: confirmar e não ver nada
/// acontecer é o pior desfecho de um formulário. Shell não tem CLI, papel nem
/// regra — e não pode carregar o mapa de um agente que deixou de ser.
pub fn finish(template: &NodeTemplate, fields: &FormFields, shown: Option<&Shown>) -> NodeTemplate {
    let agent_kind = fields.kind == NodeKind::Agent;
    let name = match fields.name.trim() {
        "" if agent_kind => fields.agent.clone().unwrap_or_else(|| "agente".to_owned()),
        "" => "sh".to_owned(),
        typed => typed.to_owned(),
    };
    let mut out = match shown {
        Some(shown) => remember_shown(template, shown),
        None => template.clone(),
    };
    out.name = name;
    out.kind = if agent_kind {
        NodeKind::Agent
    } else {
        NodeKind::Shell
    };
    out.agent = if agent_kind {
        fields.agent.clone()
    } else {
        None
    };
    out.cwd = if fields.cwd.is_empty() {
        None
    } else {
        Some(fields.cwd.clone())
    };
    out.maestro = if agent_kind && fields.maestro {
        Some(true)
    } else {
        None
    };
    if agent_kind {
        out.command = None;
    } else {
        out.command = trimmed(fields.cmd.as_deref());
        out.prompt = None;
        out.rules = None;
        out.by_agent = None;
    }
    out
}

/// Aplicar a edição deixa o mesmo processo de pé? Nome, comando, agente,
/// modelo, pasta, configuração, papel e regras definem como ele foi lançado.
pub fn same_process(updated: &NodeConfig, current: &NodeConfig) -> bool {
    updated.kind == current.kind
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
        && updated.approves_team_permissions() == current.approves_team_permissions()
}

/// A configuração do formulário vira a sugestão do workspace para aquele CLI:
/// `Some` quando há o que lembrar.
pub fn config_to_remember(component: &NodeTemplate) -> Option<(String, Option<String>)> {
    if component.kind != NodeKind::Agent {
        return None;
    }
    let agent = component.agent.clone()?;
    let config = component.resolved(Some(&agent)).config;
    Some((agent, config))
}

/// O subtítulo do card de um componente salvo: o CLI dele, ou "Shell".
pub fn subtitle(component: &NodeTemplate, profiles: &BTreeMap<String, AgentProfile>) -> String {
    if component.kind != NodeKind::Agent {
        return "Shell".to_owned();
    }
    match &component.agent {
        Some(agent) => profiles
            .get(agent)
            .map_or_else(|| agent.clone(), |p| p.display_name.clone()),
        None => "Shell".to_owned(),
    }
}

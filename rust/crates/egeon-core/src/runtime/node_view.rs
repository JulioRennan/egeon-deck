//! O nó por dentro, montado para o fio (decisão 31): o cabeçalho do agente
//! (o `ModelRow` do Swift) e o nó web. Funções puras: quem guarda o estado do
//! dial e lê o catálogo e o transcript é o ator.

use std::collections::BTreeMap;

use crate::features::agent::effort_dial::EffortDialState;
use crate::features::agent::gauge::ContextGauge;
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::{CatalogModel, ModelCatalog};
use crate::features::node::model::NodeConfig;
use crate::protocol::node::{
    AgentDetail, ContextUse, Conversation, Dial, ModelChoice, ModelGroup, Ultracode, WebDetail,
};

/// O que o agente respondeu por último, lido do transcript: o modelo
/// literal e os tokens de contexto em uso (com o modelo pedido, que o `[1m]`
/// muda).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Reading {
    /// O modelo da última resposta depois que o terminal subiu.
    pub model: Option<String>,
    pub tokens: Option<i64>,
    /// O `model` do `settings.json` da config em uso: o que "padrão"
    /// significa para este CLI (`defaultModelName`).
    pub default_model: Option<String>,
}

/// O modelo que manda nos níveis: o pedido, senão o que respondeu.
pub fn effective_model<'a>(
    catalog: Option<&'a ModelCatalog>,
    node: &NodeConfig,
    reading: &Reading,
) -> Option<&'a CatalogModel> {
    let catalog = catalog?;
    catalog
        .model_for(node.model.as_deref())
        .or_else(|| catalog.model_for(reading.model.as_deref()))
}

/// O dial novo para o modelo que manda agora: os níveis dele (ou os do
/// perfil), o nível escolhido no nó e o "auto" do modelo.
pub fn dial_for(
    profile: &AgentProfile,
    node: &NodeConfig,
    model: Option<&CatalogModel>,
) -> EffortDialState {
    let levels: Vec<String> = model
        .map(|m| m.efforts.clone())
        .or_else(|| profile.efforts.clone())
        .unwrap_or_default();
    EffortDialState::new(
        &levels,
        node.effort.as_deref(),
        model.and_then(|m| m.default_effort.as_deref()),
    )
}

fn display_name(catalog: Option<&ModelCatalog>, name: &str) -> String {
    if let Some(catalog) = catalog
        && catalog.models.iter().any(|m| name.starts_with(&m.id))
        && let Some(label) = catalog.label_for(Some(name))
    {
        return label.to_owned();
    }
    name.strip_prefix("claude-").unwrap_or(name).to_owned()
}

/// O título do seletor: quem respondeu, com o pedido entre parênteses
/// quando é outro (`Opus 5.5 (opusplan)`); antes do primeiro turno, o pedido.
pub fn model_title(
    catalog: Option<&ModelCatalog>,
    chosen: Option<&str>,
    literal: Option<&str>,
) -> String {
    let same = match (literal, chosen) {
        (Some(literal), Some(chosen)) => {
            literal.contains(chosen)
                || catalog.is_some_and(|c| {
                    // Id pedido e id que respondeu são o mesmo modelo; apelido
                    // não conta.
                    c.models.iter().any(|m| m.id == chosen)
                        && c.model_for(Some(literal)).map(|m| &m.id)
                            == c.model_for(Some(chosen)).map(|m| &m.id)
                })
        }
        _ => false,
    };
    let literal = literal.map(|l| display_name(catalog, l));
    let chosen = chosen.map(|c| display_name(catalog, c));
    match (literal, chosen) {
        (Some(literal), Some(chosen)) if !same => format!("{literal} ({chosen})"),
        (Some(literal), _) => literal,
        (None, Some(chosen)) => chosen,
        (None, None) => "padrão".to_owned(),
    }
}

/// O menu de modelos, na ordem do Swift: os do catálogo (e as versões
/// anteriores), os apelidos do perfil — com o modelo escolhido fora deles —,
/// e o padrão do CLI. Sem catálogo, só apelidos e padrão.
pub fn model_choices(
    catalog: Option<&ModelCatalog>,
    profile: &AgentProfile,
    chosen: Option<&str>,
) -> Vec<ModelChoice> {
    let choice = |label: String, value: Option<String>, group| ModelChoice {
        selected: value.as_deref() == chosen,
        label,
        value,
        group,
    };
    let mut out = Vec::new();
    if let Some(catalog) = catalog {
        for model in catalog.featured() {
            out.push(choice(
                model.label.clone(),
                Some(model.id.clone()),
                ModelGroup::Featured,
            ));
        }
        for model in catalog.older() {
            out.push(choice(
                model.label.clone(),
                Some(model.id.clone()),
                ModelGroup::Older,
            ));
        }
    }
    let mut aliases = profile.models.clone().unwrap_or_default();
    if let Some(chosen) = chosen.filter(|c| !c.is_empty())
        && !aliases.iter().any(|a| a == chosen)
        && !catalog.is_some_and(|c| c.models.iter().any(|m| m.id == chosen))
    {
        aliases.push(chosen.to_owned());
    }
    for alias in aliases {
        let label = match catalog.and_then(|c| c.model_for(Some(&alias))) {
            Some(model) => format!("{alias} — {}", model.label),
            None => alias.clone(),
        };
        out.push(choice(label, Some(alias), ModelGroup::Alias));
    }
    out.push(choice(
        "padrão do CLI".to_owned(),
        None,
        ModelGroup::Standard,
    ));
    out
}

pub fn agent_detail(
    profile: &AgentProfile,
    node: &NodeConfig,
    dial: &EffortDialState,
    catalog: Option<&ModelCatalog>,
    reading: &Reading,
) -> AgentDetail {
    let chosen = node.model.as_deref();
    // O `literalModel` do Swift (main.swift:3692): a linha nova do transcript;
    // sem ela e sem modelo escolhido, o padrão da config.
    let literal = reading.model.as_deref().or_else(|| {
        chosen
            .is_none()
            .then_some(reading.default_model.as_deref())
            .flatten()
    });
    let effective = effective_model(catalog, node, reading);
    let offers_effort = profile.offers_efforts();
    // O medidor é do modelo que respondeu, porque é a janela dele que está
    // em uso; só o catálogo sabe o tamanho dela.
    // O pedido que liga o `[1m]` é o escolhido, senão o padrão da config.
    let context = catalog.map(|c| {
        let model = c.model_for(literal).or_else(|| c.model_for(chosen));
        let requested = chosen.or(reading.default_model.as_deref());
        let gauge = reading
            .tokens
            .and_then(|tokens| ContextGauge::new(tokens, requested, model));
        ContextUse {
            used: gauge.as_ref().and_then(|g| u64::try_from(g.used).ok()),
            window: gauge.as_ref().and_then(|g| u64::try_from(g.window).ok()),
        }
    });
    AgentDetail {
        model_title: model_title(catalog, chosen, literal),
        model_hint: format!(
            "Modelo em uso: {} — escolher outro reinicia o terminal, a conversa continua",
            literal.or(chosen).unwrap_or("padrão do CLI")
        ),
        offers_model: profile.offers_model_choice(catalog, chosen),
        models: model_choices(catalog, profile, chosen),
        offers_effort,
        dial: Dial {
            levels: dial.levels().to_vec(),
            index: dial.slider_index(),
            auto: dial.is_auto(),
            pending: dial.is_pending(),
            label: dial.label(),
        },
        // Modelo sem esforço não tem ultracode ("isn't available on …").
        ultracode: (profile.ultracode.is_some() && offers_effort).then(|| Ultracode {
            on: node.ultracode == Some(true),
            available: effective.is_none_or(|m| !m.efforts.is_empty()),
        }),
        context,
        clearable: profile.clear.is_some(),
        clear_hint: format!(
            "Limpa a conversa deste agente com o {} do CLI. Pede confirmação",
            profile.clear.as_deref().unwrap_or("")
        ),
        conversation: node.conversation_id.as_ref().map(|id| Conversation {
            id: id.clone(),
            started: node.has_started_conversation(),
        }),
    }
}

/// A página do nó web sem URL gravada (`WebNode.homeURL`).
pub const HOME_URL: &str = "https://www.google.com";

/// O perfil de navegação padrão (`WebProfileStore.defaultName`).
pub const DEFAULT_WEB_PROFILE: &str = "pessoal";

/// O nó web: a URL gravada, o perfil e o UUID dele em `web-profiles.json`.
pub fn web_detail(
    node: &NodeConfig,
    profiles: &BTreeMap<String, String>,
    profile_id: String,
) -> WebDetail {
    let profile = node
        .profile
        .clone()
        .unwrap_or_else(|| DEFAULT_WEB_PROFILE.to_owned());
    // `names` do Swift: em ordem, e o padrão quando não há nenhum; o do nó
    // entra mesmo que o arquivo não o tenha.
    let mut names: Vec<String> = if profiles.is_empty() {
        vec![DEFAULT_WEB_PROFILE.to_owned()]
    } else {
        profiles.keys().cloned().collect()
    };
    if !names.contains(&profile) {
        names.push(profile.clone());
        names.sort();
    }
    WebDetail {
        // Sem URL gravada, o Swift abre a página inicial (WebNode.swift:96).
        url: Some(node.url.clone().unwrap_or_else(|| HOME_URL.to_owned())),
        profile,
        profile_id,
        profiles: names,
    }
}

/// O que se digitou na barra vira URL, como o `WebNode.normalize`: com
/// esquema vale como está; o que parece host ganha `https://`; o resto vira
/// busca.
pub fn normalize_url(raw: &str) -> Option<String> {
    let text = raw.trim();
    if text.is_empty() {
        return None;
    }
    // O `URL(string:)` do Swift recusa espaço: aí cai no teste de host e na
    // busca.
    if text.contains("://") && !text.contains(char::is_whitespace) {
        return Some(text.to_owned());
    }
    let head = text.split('/').next().unwrap_or(text);
    let host = !head.contains(' ')
        && (head.contains('.') || head.starts_with("localhost") || head.starts_with("127.0.0.1"));
    if host {
        return Some(format!("https://{text}"));
    }
    // O `urlQueryAllowed` do Foundation: letras, dígitos e
    // `!$&'()*+,-./:;=?@_~` passam; o resto, inclusive o espaço, vira `%XX`.
    let query: String = text
        .bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"!$&'()*+,-./:;=?@_~".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect();
    Some(format!("https://www.google.com/search?q={query}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn titulo_como_o_model_row() {
        assert_eq!(model_title(None, None, None), "padrão");
        assert_eq!(model_title(None, Some("opus"), None), "opus");
        assert_eq!(
            model_title(None, Some("opusplan"), Some("claude-opus-5-5")),
            "opus-5-5 (opusplan)"
        );
        assert_eq!(
            model_title(None, Some("opus"), Some("claude-opus-5-5")),
            "opus-5-5"
        );
    }

    #[test]
    fn menu_sem_catalogo_traz_apelidos_o_escolhido_e_o_padrao() {
        let profile: AgentProfile = serde_json::from_value(serde_json::json!({
            "displayName": "Claude", "command": ["claude"], "models": ["opus", "sonnet"]
        }))
        .unwrap();
        let menu = model_choices(None, &profile, Some("haiku"));
        let labels: Vec<&str> = menu.iter().map(|c| c.label.as_str()).collect();
        assert_eq!(labels, ["opus", "sonnet", "haiku", "padrão do CLI"]);
        assert!(menu[2].selected);
        assert_eq!(menu[3].value, None);
        assert_eq!(menu[3].group, ModelGroup::Standard);
    }

    #[test]
    fn seletor_de_modelo_so_quando_o_perfil_oferece() {
        let profile: AgentProfile = serde_json::from_value(serde_json::json!({
            "displayName": "Codex", "command": ["codex"], "offersModels": false
        }))
        .unwrap();
        let node: NodeConfig = serde_json::from_value(serde_json::json!({
            "type": "agent", "id": "x", "agent": "codex"
        }))
        .unwrap();
        let dial = dial_for(&profile, &node, None);
        let detail = agent_detail(&profile, &node, &dial, None, &Reading::default());
        assert!(!detail.offers_model);
    }

    #[test]
    fn sem_linha_nova_vale_o_padrao_da_config() {
        let profile: AgentProfile = serde_json::from_value(serde_json::json!({
            "displayName": "Claude", "command": ["claude"]
        }))
        .unwrap();
        let node: NodeConfig = serde_json::from_value(serde_json::json!({
            "type": "agent", "id": "x", "agent": "claude"
        }))
        .unwrap();
        let dial = dial_for(&profile, &node, None);
        let reading = Reading {
            default_model: Some("claude-sonnet-5-5".into()),
            ..Reading::default()
        };
        let detail = agent_detail(&profile, &node, &dial, None, &reading);
        assert_eq!(detail.model_title, "sonnet-5-5");
        // Com catálogo e sem leitura: o grupo aparece, vazio.
        let catalog = ModelCatalog::new(vec![], None);
        let detail = agent_detail(&profile, &node, &dial, Some(&catalog), &reading);
        assert_eq!(
            detail.context,
            Some(ContextUse {
                used: None,
                window: None
            })
        );
    }

    #[test]
    fn web_normaliza_como_o_swift() {
        assert_eq!(
            normalize_url("a://b c").as_deref(),
            Some("https://www.google.com/search?q=a://b%20c")
        );
        assert_eq!(normalize_url("  "), None);
        assert_eq!(
            normalize_url("https://a.b/c").as_deref(),
            Some("https://a.b/c")
        );
        assert_eq!(
            normalize_url("docs.rs/tokio").as_deref(),
            Some("https://docs.rs/tokio")
        );
        assert_eq!(
            normalize_url("localhost:3000").as_deref(),
            Some("https://localhost:3000")
        );
        assert_eq!(
            normalize_url("rust async").as_deref(),
            Some("https://www.google.com/search?q=rust%20async")
        );
    }

    #[test]
    fn perfis_web_em_ordem_com_o_padrao_e_o_do_no() {
        let node: NodeConfig = serde_json::from_value(serde_json::json!({
            "type": "web", "id": "docs", "profile": "trabalho"
        }))
        .unwrap();
        let detail = web_detail(&node, &BTreeMap::new(), "ID".into());
        assert_eq!(detail.profiles, ["pessoal", "trabalho"]);
        assert_eq!(detail.profile, "trabalho");
    }
}

//! Os modelos que um CLI conhece, com nome de gente e o esforço que cada um
//! aceita. É o que deixa o menu dizer "Opus 5.5" em vez de `opus`, e o slider
//! mostrar só os níveis que o modelo escolhido tem.
//!
//! Genérico de propósito: quem sabe montar um é o submódulo do CLI (o Claude
//! Code lê do próprio binário). Sem catálogo, o nó fica com os apelidos e a
//! lista de níveis do perfil.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::features::usage::ModelPrice;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogModel {
    /// O que vai na flag: `claude-opus-5-5`.
    pub id: String,
    pub family: String,
    /// `Opus 5.5`.
    pub label: String,
    /// Níveis aceitos, do menor para o maior. Vazio = o modelo não tem esforço,
    /// e o slider fica desligado.
    #[serde(default)]
    pub efforts: Vec<String>,
    /// O que o CLI usa quando não se passa `--effort` — o "auto".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default_effort: Option<String>,
    /// A faixa de preço que o CLI atribui ao modelo (`tier_4_20_…`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pricing: Option<String>,
    /// O tamanho da janela de contexto, em tokens.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_window: Option<i64>,
}

impl CatalogModel {
    pub fn new(id: &str, family: &str, label: &str) -> Self {
        CatalogModel {
            id: id.to_owned(),
            family: family.to_owned(),
            label: label.to_owned(),
            efforts: Vec::new(),
            default_effort: None,
            pricing: None,
            context_window: None,
        }
    }

    /// `claude-opus-5-5` → [5, 5]; `claude-3-5-haiku` → [3, 5]. Data de snapshot
    /// (`20251001`) não é versão.
    pub fn version(&self) -> Vec<u64> {
        self.id
            .split('-')
            .filter(|part| part.chars().count() < 8)
            .filter_map(|part| part.parse().ok())
            .collect()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ModelCatalog {
    #[serde(default)]
    pub models: Vec<CatalogModel>,
    /// Preço por chave de tarifa (`PriceTable::key`), quando o CLI traz. `None`
    /// é cache de antes da leitura de preços — pede releitura; vazio é "o
    /// binário não tem tabela".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prices: Option<BTreeMap<String, ModelPrice>>,
    /// Campo novo no modelo não pede releitura sozinho: o binário não mudou, e o
    /// cache continuaria valendo sem ele. `None` é cache de antes deste número.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub schema: Option<u32>,
}

impl ModelCatalog {
    pub const CURRENT_SCHEMA: u32 = 1;

    /// Ordem do menu: as famílias que se usa no dia a dia primeiro.
    pub const FAMILY_ORDER: [&'static str; 5] = ["fable", "opus", "sonnet", "haiku", "mythos"];

    /// Apelidos que o CLI resolve para uma família — `opusplan` planeja com Opus.
    pub const ALIAS_FAMILY: [(&'static str, &'static str); 1] = [("opusplan", "opus")];

    pub fn new(models: Vec<CatalogModel>, prices: Option<BTreeMap<String, ModelPrice>>) -> Self {
        ModelCatalog {
            models,
            prices,
            schema: Some(Self::CURRENT_SCHEMA),
        }
    }

    fn newest_first<'a>(models: impl Iterator<Item = &'a CatalogModel>) -> Vec<&'a CatalogModel> {
        let mut list: Vec<&CatalogModel> = models.collect();
        list.sort_by_key(|m| std::cmp::Reverse(m.version()));
        list
    }

    fn families(&self) -> Vec<String> {
        let present: BTreeSet<&str> = self.models.iter().map(|m| m.family.as_str()).collect();
        let mut out: Vec<String> = Self::FAMILY_ORDER
            .iter()
            .filter(|f| present.contains(*f))
            .map(|f| (*f).to_owned())
            .collect();
        out.extend(
            present
                .iter()
                .filter(|f| !Self::FAMILY_ORDER.contains(f))
                .map(|f| (*f).to_owned()),
        );
        out
    }

    /// O mais novo de cada família, na ordem do menu.
    pub fn featured(&self) -> Vec<&CatalogModel> {
        self.families()
            .iter()
            .filter_map(|family| {
                Self::newest_first(self.models.iter().filter(|m| &m.family == family))
                    .first()
                    .copied()
            })
            .collect()
    }

    /// O resto, por família e do mais novo ao mais velho — vai num submenu.
    pub fn older(&self) -> Vec<&CatalogModel> {
        let top: BTreeSet<&str> = self.featured().iter().map(|m| m.id.as_str()).collect();
        self.families()
            .iter()
            .flat_map(|family| {
                Self::newest_first(
                    self.models
                        .iter()
                        .filter(|m| &m.family == family && !top.contains(m.id.as_str())),
                )
            })
            .collect()
    }

    /// O modelo por trás do que o nó pediu ou do que o transcript gravou.
    ///
    /// Aceita o id exato, o id com data de snapshot (`claude-haiku-4-5-20251001`)
    /// ou sufixo (`[1m]`), e apelido de família (`opus` → o Opus mais novo, que é
    /// o que o CLI resolve).
    pub fn model_for(&self, name: Option<&str>) -> Option<&CatalogModel> {
        let raw = name?.to_lowercase();
        if raw.is_empty() {
            return None;
        }
        let name = raw.split('[').next().unwrap_or(&raw).to_owned();
        if let Some(exact) = self.models.iter().find(|m| m.id == name) {
            return Some(exact);
        }
        let prefixed = self
            .models
            .iter()
            .filter(|m| name.starts_with(&format!("{}-", m.id)))
            .fold(None::<&CatalogModel>, |best, m| match best {
                Some(b) if b.id.chars().count() >= m.id.chars().count() => Some(b),
                _ => Some(m),
            });
        if prefixed.is_some() {
            return prefixed;
        }
        let family = Self::ALIAS_FAMILY
            .iter()
            .find(|(alias, _)| *alias == name)
            .map_or(name.as_str(), |(_, family)| *family);
        Self::newest_first(self.models.iter().filter(|m| m.family == family))
            .first()
            .copied()
    }

    /// Nome de gente para um id ou apelido; `None` quando o catálogo não conhece.
    pub fn label_for(&self, name: Option<&str>) -> Option<&str> {
        self.model_for(name).map(|m| m.label.as_str())
    }
}

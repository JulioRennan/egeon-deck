//! A tabela de preços, em camadas: a embutida, o catálogo do Claude Code
//! instalado por cima (atualiza com ele) e o `pricing.json` por cima de tudo —
//! só as exceções que o usuário quiser forçar.
//!
//! O preço é aplicado quando o gasto ENTRA, não na hora de mostrar: tabela que
//! muda vale dali para frente (`Spend`).
//!
//! Uma chave por TARIFA, não por modelo: o modo rápido custa o dobro e o Haiku
//! 5.5 muda de preço com prompt acima de 100K — a requisição precisa ser
//! classificada quando é lida, porque depois só sobra a soma.

use std::collections::BTreeMap;

use super::model::{ModelPrice, TariffCost, TokenUsage, UsageByPrice, UsageEntry};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Origin {
    BuiltIn,
    ClaudeCode,
    File,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PriceTable {
    pub models: BTreeMap<String, ModelPrice>,
    pub origin: BTreeMap<String, Origin>,
}

/// O modo rápido custa o dobro (Opus 5.5: US$ 8 / 40).
pub const FAST_FACTOR: f64 = 2.0;
/// A partir daqui o prompt do Haiku 5.5 sai na faixa cara.
pub const LONG_PROMPT_THRESHOLD: i64 = 100_000;

/// Tabela oficial da Anthropic, API de primeira parte, em 2026-10-06. É a
/// reserva: vale para o que o catálogo do Claude Code não trouxer.
pub fn built_in() -> BTreeMap<String, ModelPrice> {
    let p = ModelPrice::new;
    let mut haiku_long = p("Haiku 5.5 (prompt > 100K)", 0.5, 2.5, 0.05);
    haiku_long.long_above = Some(100_000);
    [
        ("claude-fable-5-1", p("Fable 5.1", 10.0, 50.0, 0.25)),
        ("claude-mythos-5-1", p("Mythos 5.1", 10.0, 50.0, 0.25)),
        ("claude-fable-5", p("Fable 5", 10.0, 50.0, 1.0)),
        ("claude-mythos-5", p("Mythos 5", 10.0, 50.0, 1.0)),
        ("claude-opus-5-5", p("Opus 5.5", 4.0, 20.0, 0.2)),
        ("claude-opus-5", p("Opus 5", 5.0, 25.0, 0.5)),
        ("claude-opus-4-8", p("Opus 4.8", 5.0, 25.0, 0.5)),
        ("claude-opus-4-7", p("Opus 4.7", 5.0, 25.0, 0.5)),
        ("claude-opus-4-6", p("Opus 4.6", 5.0, 25.0, 0.5)),
        ("claude-sonnet-5-5", p("Sonnet 5.5", 2.0, 10.0, 0.2)),
        ("claude-sonnet-5", p("Sonnet 5", 2.0, 10.0, 0.2)),
        ("claude-sonnet-4-6", p("Sonnet 4.6", 3.0, 15.0, 0.3)),
        ("claude-haiku-5-5", p("Haiku 5.5", 0.1, 0.5, 0.01)),
        ("claude-haiku-5-5#long", haiku_long),
        ("claude-haiku-4-5", p("Haiku 4.5", 1.0, 5.0, 0.1)),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_owned(), v))
    .collect()
}

impl PriceTable {
    /// Só a embutida — o que os testes do Swift chamam de
    /// `PriceTable(models: PriceTable.builtIn)`.
    pub fn from_built_in() -> PriceTable {
        let models = built_in();
        let origin = models
            .keys()
            .map(|k| (k.clone(), Origin::BuiltIn))
            .collect();
        PriceTable { models, origin }
    }

    /// As três camadas juntas. `catalog` é o que o Claude Code instalado traz;
    /// `overrides`, o `pricing.json` (já sem a cópia semeada, ver
    /// [`file_overrides`]).
    pub fn layered(
        catalog: &BTreeMap<String, ModelPrice>,
        overrides: &BTreeMap<String, ModelPrice>,
    ) -> PriceTable {
        let mut table = PriceTable::from_built_in();
        table.overlay(catalog, Origin::ClaudeCode);
        table.overlay(overrides, Origin::File);
        table
    }

    fn overlay(&mut self, layer: &BTreeMap<String, ModelPrice>, source: Origin) {
        for (key, price) in layer {
            self.models.insert(key.clone(), price.clone());
            self.origin.insert(key.clone(), source);
        }
    }

    pub fn key(&self, entry: &UsageEntry) -> String {
        let model = canonical(&entry.model);
        if entry.fast {
            return format!("{model}#fast");
        }
        let long_key = format!("{model}#long");
        if let Some(long) = self.models.get(&long_key)
            && entry.usage.prompt() > long.long_above.unwrap_or(LONG_PROMPT_THRESHOLD)
        {
            return long_key;
        }
        model
    }

    /// `None` quando o modelo não está na tabela: melhor mostrar só os tokens
    /// que inventar um preço.
    pub fn price(&self, key: &str) -> Option<ModelPrice> {
        if let Some(price) = self.models.get(key) {
            return Some(price.clone());
        }
        let base = key.strip_suffix("#fast")?;
        self.models
            .get(base)
            .map(|p| p.scaled(FAST_FACTOR, " (rápido)"))
    }

    /// O custo congelado, mais o pendente pelo preço de agora — quando já
    /// houver um. O segundo valor é `true` quando sobrou token sem preço.
    pub fn cost(&self, usage: &UsageByPrice) -> (f64, bool) {
        let mut dollars = 0.0;
        let mut unpriced = false;
        for (key, spend) in usage {
            dollars += spend.cost.total();
            if spend.pending.is_empty() {
                continue;
            }
            match self.price(key) {
                Some(price) => dollars += price.cost(&spend.pending),
                None => unpriced = true,
            }
        }
        (dollars, unpriced)
    }

    /// Sem o que não tem preço.
    pub fn split(&self, usage: &UsageByPrice) -> TariffCost {
        usage
            .iter()
            .fold(TariffCost::default(), |total, (key, spend)| {
                let pending = self
                    .price(key)
                    .map(|p| p.split(&spend.pending))
                    .unwrap_or_default();
                total + spend.cost + pending
            })
    }

    /// O modelo em que mais se gastou — o que identifica o agente no detalhe.
    pub fn main_model(&self, usage: &UsageByPrice) -> Option<String> {
        let dollars = |key: &String, spend: &super::model::Spend| {
            self.cost(&BTreeMap::from([(key.clone(), *spend)])).0
        };
        let mut best: Option<(&String, f64)> = None;
        for (key, spend) in usage {
            let value = dollars(key, spend);
            if best.is_none_or(|(_, top)| value > top) {
                best = Some((key, value));
            }
        }
        best.map(|(key, _)| self.name(key))
    }

    pub fn name(&self, key: &str) -> String {
        self.price(key)
            .map(|p| p.name)
            .unwrap_or_else(|| key.to_owned())
    }
}

/// Id com data (`claude-haiku-4-5-20251001`) cai no modelo sem ela.
pub fn canonical(model: &str) -> String {
    let parts: Vec<&str> = model.split('-').filter(|p| !p.is_empty()).collect();
    if let Some(last) = parts.last()
        && last.len() == 8
        && last.chars().all(|c| c.is_ascii_digit())
    {
        return parts[..parts.len() - 1].join("-");
    }
    model.to_owned()
}

/// A cópia que a versão anterior semeou — sem o `longAbove`, que ela não tinha.
/// Cópia intacta da embutida não é escolha do usuário: congelaria os preços por
/// cima de qualquer atualização.
pub fn is_seed_copy(custom: &BTreeMap<String, ModelPrice>) -> bool {
    fn plain(table: &BTreeMap<String, ModelPrice>) -> BTreeMap<String, ModelPrice> {
        table
            .iter()
            .map(|(k, v)| {
                let mut v = v.clone();
                v.long_above = None;
                (k.clone(), v)
            })
            .collect()
    }
    plain(custom) == plain(&built_in())
}

/// As exceções do `pricing.json`, ou vazio quando o arquivo é a cópia semeada.
pub fn file_overrides(custom: BTreeMap<String, ModelPrice>) -> BTreeMap<String, ModelPrice> {
    if is_seed_copy(&custom) {
        BTreeMap::new()
    } else {
        custom
    }
}

/// Tokens de uma tarifa vazia, para os testes e para quem monta entrada.
pub fn entry(id: &str, model: &str, usage: TokenUsage) -> UsageEntry {
    UsageEntry {
        id: id.to_owned(),
        model: model.to_owned(),
        fast: false,
        usage,
    }
}

//! Tokens, tarifas e preço. Os nomes de chave do JSON são os do Swift: o
//! `usage.json` e o `pricing.json` de hoje abrem como estão.

use std::collections::BTreeMap;
use std::ops::{Add, AddAssign};

use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::prices::PriceTable;

/// `i64` e não `u64`: o `Int` do Swift aceita um negativo editado à mão, e um
/// campo mais estreito faria o `usage.json` inteiro ser recusado e recontado.
/// Tokens gastos, nas quatro tarifas em que o preço se divide. Escrita de cache
/// vem em duas: a de 5 minutos custa 1,25× a entrada e a de 1 hora, 2× — somá-las
/// juntas erraria o custo.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TokenUsage {
    pub input: i64,
    pub output: i64,
    pub cache_write5m: i64,
    pub cache_write1h: i64,
    pub cache_read: i64,
}

impl TokenUsage {
    pub fn cache_write(&self) -> i64 {
        self.cache_write5m + self.cache_write1h
    }

    pub fn total(&self) -> i64 {
        self.input + self.output + self.cache_write() + self.cache_read
    }

    /// O tamanho do prompt da requisição — é por ele que o Haiku 5.5 muda de
    /// faixa de preço.
    pub fn prompt(&self) -> i64 {
        self.input + self.cache_write() + self.cache_read
    }

    pub fn is_empty(&self) -> bool {
        self.total() == 0
    }
}

impl Add for TokenUsage {
    type Output = TokenUsage;

    fn add(self, b: TokenUsage) -> TokenUsage {
        TokenUsage {
            input: self.input + b.input,
            output: self.output + b.output,
            cache_write5m: self.cache_write5m + b.cache_write5m,
            cache_write1h: self.cache_write1h + b.cache_write1h,
            cache_read: self.cache_read + b.cache_read,
        }
    }
}

impl AddAssign for TokenUsage {
    fn add_assign(&mut self, b: TokenUsage) {
        *self = *self + b;
    }
}

/// Uma resposta do modelo, como o transcript a registra. O `id` é o da
/// mensagem: o CLI grava uma linha por bloco de conteúdo, todas com o mesmo
/// uso, e somar cada linha contaria a resposta várias vezes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsageEntry {
    pub id: String,
    pub model: String,
    pub fast: bool,
    pub usage: TokenUsage,
}

/// Dólares por tarifa.
#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct TariffCost {
    pub input: f64,
    pub output: f64,
    pub cache_write: f64,
    pub cache_read: f64,
}

impl TariffCost {
    pub fn total(&self) -> f64 {
        self.input + self.output + self.cache_write + self.cache_read
    }
}

impl Add for TariffCost {
    type Output = TariffCost;

    fn add(self, b: TariffCost) -> TariffCost {
        TariffCost {
            input: self.input + b.input,
            output: self.output + b.output,
            cache_write: self.cache_write + b.cache_write,
            cache_read: self.cache_read + b.cache_read,
        }
    }
}

/// Preço de um modelo, em US$ por milhão de tokens.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelPrice {
    pub name: String,
    pub input: f64,
    pub output: f64,
    /// Cache lido. Não é uma fração fixa da entrada: 0,1× na maioria, 0,05×
    /// no Opus 5.5, 0,025× no Fable 5.1.
    pub cache_read: f64,
    /// Escrita de cache: 1,25× a entrada no de 5 minutos, 2× no de 1 hora.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_write5m: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_write1h: Option<f64>,
    /// Só na tarifa `#long`: a partir de quantos tokens de prompt ela vale.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub long_above: Option<i64>,
}

impl ModelPrice {
    pub fn new(name: &str, input: f64, output: f64, cache_read: f64) -> Self {
        ModelPrice {
            name: name.to_owned(),
            input,
            output,
            cache_read,
            cache_write5m: None,
            cache_write1h: None,
            long_above: None,
        }
    }

    pub fn cost(&self, usage: &TokenUsage) -> f64 {
        self.split(usage).total()
    }

    /// O custo em cada tarifa — o que a barra do detalhe desenha.
    pub fn split(&self, usage: &TokenUsage) -> TariffCost {
        let write5m = self.cache_write5m.unwrap_or(self.input * 1.25);
        let write1h = self.cache_write1h.unwrap_or(self.input * 2.0);
        let write = usage.cache_write5m as f64 * write5m + usage.cache_write1h as f64 * write1h;
        TariffCost {
            input: usage.input as f64 * self.input / 1_000_000.0,
            output: usage.output as f64 * self.output / 1_000_000.0,
            cache_write: write / 1_000_000.0,
            cache_read: usage.cache_read as f64 * self.cache_read / 1_000_000.0,
        }
    }

    pub fn scaled(&self, factor: f64, name_suffix: &str) -> ModelPrice {
        ModelPrice {
            name: format!("{}{name_suffix}", self.name),
            input: self.input * factor,
            output: self.output * factor,
            cache_read: self.cache_read * factor,
            cache_write5m: self.cache_write5m.map(|v| v * factor),
            cache_write1h: self.cache_write1h.map(|v| v * factor),
            long_above: self.long_above,
        }
    }
}

/// O que se gastou numa tarifa: os tokens e o custo CONGELADO no preço do
/// momento em que entraram. Preço novo vale dali para frente — o passado não se
/// recalcula. `pending` é o que entrou sem preço conhecido: ganha preço (e
/// congela) quando a tabela passar a ter o modelo.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Spend {
    pub tokens: TokenUsage,
    pub cost: TariffCost,
    pub pending: TokenUsage,
}

impl Add for Spend {
    type Output = Spend;

    fn add(self, b: Spend) -> Spend {
        Spend {
            tokens: self.tokens + b.tokens,
            cost: self.cost + b.cost,
            pending: self.pending + b.pending,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SpendOut<'a> {
    tokens: &'a TokenUsage,
    cost: &'a TariffCost,
    #[serde(skip_serializing_if = "Option::is_none")]
    pending: Option<&'a TokenUsage>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", default)]
#[derive(Default)]
struct SpendIn {
    tokens: TokenUsage,
    cost: TariffCost,
    pending: TokenUsage,
}

impl Serialize for Spend {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        SpendOut {
            tokens: &self.tokens,
            cost: &self.cost,
            pending: (!self.pending.is_empty()).then_some(&self.pending),
        }
        .serialize(s)
    }
}

impl<'de> Deserialize<'de> for Spend {
    /// O formato de antes era só os tokens: entram como pendentes, e quem lê o
    /// arquivo congela com o preço em vigor (`settled`).
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let value = serde_json::Value::deserialize(d)?;
        let has_tokens = value.get("tokens").is_some();
        if has_tokens {
            let parsed: SpendIn =
                serde_json::from_value(value).map_err(serde::de::Error::custom)?;
            return Ok(Spend {
                tokens: parsed.tokens,
                cost: parsed.cost,
                pending: parsed.pending,
            });
        }
        let tokens: TokenUsage = serde_json::from_value(value).map_err(serde::de::Error::custom)?;
        Ok(Spend {
            tokens,
            cost: TariffCost::default(),
            pending: tokens,
        })
    }
}

/// Uso agrupado pela chave de preço (`PriceTable::key`).
pub type UsageByPrice = BTreeMap<String, Spend>;

/// Soma o gasto de uma resposta: congela o custo quando há preço, senão deixa
/// pendente.
pub fn add_entry(usage: &mut UsageByPrice, entry: &UsageEntry, prices: &PriceTable) {
    let key = prices.key(entry);
    let spend = usage.entry(key.clone()).or_default();
    spend.tokens += entry.usage;
    match prices.price(&key) {
        Some(price) => spend.cost = spend.cost + price.split(&entry.usage),
        None => spend.pending += entry.usage,
    }
}

/// O pendente que agora tem preço passa a ter custo congelado.
pub fn settled(usage: &UsageByPrice, prices: &PriceTable) -> UsageByPrice {
    let mut out = usage.clone();
    for (key, spend) in usage {
        if spend.pending.is_empty() {
            continue;
        }
        let Some(price) = prices.price(key) else {
            continue;
        };
        out.insert(
            key.clone(),
            Spend {
                tokens: spend.tokens,
                cost: spend.cost + price.split(&spend.pending),
                pending: TokenUsage::default(),
            },
        );
    }
    out
}

pub fn total_usage(usage: &UsageByPrice) -> TokenUsage {
    usage
        .values()
        .fold(TokenUsage::default(), |acc, s| acc + s.tokens)
}

pub fn merge_usage(a: &UsageByPrice, b: &UsageByPrice) -> UsageByPrice {
    let mut out = a.clone();
    for (key, spend) in b {
        let slot = out.entry(key.clone()).or_default();
        *slot = *slot + *spend;
    }
    out
}

//! O catálogo de modelos lido de dentro do binário do Claude Code.
//!
//! O CLI carrega no próprio JavaScript uma tabela de modelos — id, família, nome
//! de exibição, capacidades e esforço padrão — e é dela que o `/model` e o
//! `/effort` da TUI saem. Não há comando que a imprima nem API sem chave, então
//! lê-se a tabela no binário: atualizar o Claude Code atualiza o catálogo junto.
//!
//! É código minificado e interno: o formato pode mudar numa versão qualquer.
//! Leitura que não acha nada devolve vazio, e o nó volta para os apelidos.

use std::collections::{BTreeMap, HashSet};
use std::sync::LazyLock;

use regex::Regex;

use super::binary_source::Bytes;
use super::{latin1, regex};
use crate::features::agent::model_catalog::CatalogModel;
use crate::features::usage::ModelPrice;

const ENTRY_START: &[u8] = br#"{id:"claude-"#;
/// Até onde uma entrada vai: a de hoje tem ~1,3 KB.
const WINDOW: usize = 4096;

static ENTRY_HEAD: LazyLock<Regex> = LazyLock::new(|| {
    regex(r#"^\{id:"(claude-[a-z0-9-]+)",family:"([a-z0-9]+)",display_name:"([^"]+)""#)
});
static CAPABILITIES: LazyLock<Regex> = LazyLock::new(|| regex(r"capabilities:\[([^\]]*)\]"));
static DEFAULT_EFFORT: LazyLock<Regex> = LazyLock::new(|| regex(r#"default_effort:"([a-z]+)""#));
static PRICING: LazyLock<Regex> = LazyLock::new(|| regex(r#"pricing:"([A-Za-z0-9_]+)""#));
static CONTEXT_WINDOW: LazyLock<Regex> =
    LazyLock::new(|| regex(r"context:\{(?:[^}]*,)?window:([0-9.]+(?:e[+-]?[0-9]+)?)"));
static FIELD: LazyLock<Regex> =
    LazyLock::new(|| regex(r"([a-z0-9_]+):(-?[0-9.]+(?:e[+-]?[0-9]+)?)"));

/// Níveis na ordem do slider, e a capacidade que libera cada um. Os três
/// primeiros vêm com `effort`; `xhigh` e `max` são capacidades à parte — o Opus
/// 4.6 tem `max` e não tem `xhigh`.
const LEVELS: [(&str, &str); 5] = [
    ("low", "effort"),
    ("medium", "effort"),
    ("high", "effort"),
    ("xhigh", "xhigh_effort"),
    ("max", "max_effort"),
];

pub fn parse_binary(data: &[u8]) -> Vec<CatalogModel> {
    parse_source(&mut { data })
}

pub fn parse_source(source: &mut impl Bytes) -> Vec<CatalogModel> {
    let mut found = Vec::new();
    let mut seen = HashSet::new();
    let mut cursor = 0;
    while let Some(start) = source.find(ENTRY_START, cursor) {
        cursor = start + ENTRY_START.len();
        let text = latin1(&source.slice(start, start + WINDOW));
        if let Some(model) = parse_entry(&text)
            && seen.insert(model.id.clone())
        {
            found.push(model);
        }
    }
    found
}

fn capture<'a>(re: &Regex, text: &'a str) -> Option<&'a str> {
    re.captures(text)?.get(1).map(|m| m.as_str())
}

/// Uma entrada, a partir do `{id:"claude-`. `None` quando o trecho não é da
/// tabela de modelos — o mesmo começo aparece em outras tabelas do CLI.
pub fn parse_entry(text: &str) -> Option<CatalogModel> {
    let head = ENTRY_HEAD.captures(text)?;
    let id = head.get(1)?.as_str();
    let family = head.get(2)?.as_str();
    let label = head.get(3)?;
    // Só até a próxima entrada: as capacidades da vizinha não são desta.
    let mut body = &text[label.end()..];
    if let Some(next) = body.find(r#"{id:"claude-"#) {
        body = &body[..next];
    }
    let caps: HashSet<String> = capture(&CAPABILITIES, body)
        .map(|list| {
            list.replace('"', "")
                .split(',')
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    let efforts: Vec<String> = if caps.contains("effort") {
        LEVELS
            .iter()
            .filter(|(_, capability)| caps.contains(*capability))
            .map(|(level, _)| (*level).to_owned())
            .collect()
    } else {
        Vec::new()
    };
    let fallback = capture(&DEFAULT_EFFORT, body).map(str::to_owned);
    let window = capture(&CONTEXT_WINDOW, body)
        .and_then(|w| w.parse::<f64>().ok())
        .map(|w| w as i64);
    Some(CatalogModel {
        id: id.to_owned(),
        family: family.to_owned(),
        label: label.as_str().to_owned(),
        default_effort: if efforts.is_empty() { None } else { fallback },
        efforts,
        pricing: capture(&PRICING, body).map(str::to_owned),
        context_window: window,
    })
}

/// Os preços que o `/cost` do CLI usa: `pricing_tiers:{tier:{input:…}}` em US$
/// por milhão, e cada modelo apontando para a sua faixa. A faixa pode ter
/// `long_prompt:{above_prompt_tokens:…}` — vira a tarifa `#long`.
pub fn prices_from_binary(data: &[u8], models: &[CatalogModel]) -> BTreeMap<String, ModelPrice> {
    prices_from_source(&mut { data }, models)
}

pub fn prices_from_source(
    source: &mut impl Bytes,
    models: &[CatalogModel],
) -> BTreeMap<String, ModelPrice> {
    const MARK: &[u8] = b"pricing_tiers:{";
    let Some(start) = source.find(MARK, 0) else {
        return BTreeMap::new();
    };
    let from = start + MARK.len();
    let text = latin1(&source.slice(from, from + 16_384));
    prices(&tiers(&text), models)
}

pub type Tiers = BTreeMap<String, BTreeMap<String, f64>>;

pub fn prices(tiers: &Tiers, models: &[CatalogModel]) -> BTreeMap<String, ModelPrice> {
    let mut out = BTreeMap::new();
    for model in models {
        let Some(tier) = model.pricing.as_ref().and_then(|name| tiers.get(name)) else {
            continue;
        };
        let Some(price) = price_of(tier, "", &model.label) else {
            continue;
        };
        out.insert(model.id.clone(), price);
        if let Some(above) = tier.get("long.above_prompt_tokens") {
            let above = *above as i64;
            let name = format!("{} (prompt > {}K)", model.label, above / 1000);
            if let Some(mut long) = price_of(tier, "long.", &name) {
                long.long_above = Some(above);
                out.insert(format!("{}#long", model.id), long);
            }
        }
    }
    out
}

fn price_of(tier: &BTreeMap<String, f64>, prefix: &str, name: &str) -> Option<ModelPrice> {
    let get = |key: &str| tier.get(&format!("{prefix}{key}")).copied();
    let mut price = ModelPrice::new(name, get("input")?, get("output")?, get("cache_read")?);
    price.cache_write5m = get("cache_write_5m");
    price.cache_write1h = get("cache_write_1h");
    Some(price)
}

/// As faixas, do texto logo depois de `pricing_tiers:{`. Os campos de
/// `long_prompt` vêm com o prefixo `long.`.
pub fn tiers(text: &str) -> Tiers {
    let mut out = Tiers::new();
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        // Fim do objeto das faixas.
        if chars[i] == '}' {
            break;
        }
        let mut name = String::new();
        while i < chars.len() && chars[i] != ':' {
            name.push(chars[i]);
            i += 1;
        }
        let name = name.trim_matches(|c| c == ',' || c == ' ').to_owned();
        if !(i + 1 < chars.len() && chars[i + 1] == '{') {
            break;
        }
        i += 2;
        let mut depth = 1;
        let mut body = String::new();
        while i < chars.len() && depth > 0 {
            if chars[i] == '{' {
                depth += 1;
            }
            if chars[i] == '}' {
                depth -= 1;
            }
            if depth > 0 {
                body.push(chars[i]);
            }
            i += 1;
        }
        let mut main = body.clone();
        let mut long = String::new();
        if let Some(open) = body.find("long_prompt:{") {
            let inner = open + "long_prompt:{".len();
            if let Some(close) = body[inner..].find('}').map(|c| inner + c) {
                long = body[inner..close].to_owned();
                main = format!("{}{}", &body[..open], &body[close + 1..]);
            }
        }
        let mut fields = numbers(&main);
        for (key, value) in numbers(&long) {
            fields.insert(format!("long.{key}"), value);
        }
        if !name.is_empty() && !fields.is_empty() {
            out.insert(name, fields);
        }
        if i < chars.len() && chars[i] == ',' {
            i += 1;
        }
    }
    out
}

fn numbers(text: &str) -> BTreeMap<String, f64> {
    FIELD
        .captures_iter(text)
        .filter_map(|m| {
            let value = m.get(2)?.as_str().parse::<f64>().ok()?;
            Some((m.get(1)?.as_str().to_owned(), value))
        })
        .collect()
}

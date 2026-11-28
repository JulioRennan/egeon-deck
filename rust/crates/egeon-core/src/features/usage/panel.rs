//! O consumo de uma bancada já formatado para a tela (o `UsagePanel` e a
//! pílula do Swift): a UI recebe texto pronto e fração de barra, não faz conta.
//!
//! Cor não vai aqui: a barra das tarifas usa `key`, a das famílias usa
//! `family` e a do agente sai do nome dele — quem desenha escolhe a paleta.

use std::cmp::Ordering;
use std::collections::BTreeSet;
use std::path::Path;

use serde::{Deserialize, Serialize};

use super::ledger::UsageLedger;
use super::model::{ModelPrice, Spend, TariffCost, TokenUsage, UsageByPrice, total_usage};
use super::prices::{Origin, PriceTable};
use super::text;

/// A pílula da barra lateral, da barra do canvas e do chat.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Pill {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tooltip: Option<String>,
    /// Nada consumido ainda: a linha da barra lateral não mostra custo
    /// (`refreshUsage` só põe na lista o que tem total).
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub empty: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Total {
    pub amount: String,
    pub tokens: String,
}

/// Uma das quatro tarifas, na ordem em que a barra as empilha.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Split {
    /// `output`, `input`, `cache_write` ou `cache_read`.
    pub key: String,
    pub title: String,
    pub amount: String,
    pub detail: String,
    /// O valor cru: a largura do segmento é proporcional a ele.
    pub dollars: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentRow {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tag: Option<String>,
    pub amount: String,
    /// Em relação ao maior da lista, de 0 a 1.
    pub fraction: f64,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ModelRow {
    pub name: String,
    /// `opus`, `sonnet`, `haiku`, `fable` ou `other`.
    pub family: String,
    pub amount: String,
    pub fraction: f64,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PriceRow {
    pub name: String,
    /// O modelo que a bancada usou: aparece destacado.
    pub lit: bool,
    /// O preço vem do `pricing.json` do usuário.
    pub edited: bool,
    pub values: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Prices {
    pub open_note: String,
    pub columns: Vec<String>,
    pub rows: Vec<PriceRow>,
    pub origin_note: String,
    pub rule_note: String,
    pub file_note: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Panel {
    pub heading: String,
    pub total: Total,
    pub split: Vec<Split>,
    pub agents: Vec<AgentRow>,
    pub models: Vec<ModelRow>,
    pub prices: Prices,
}

/// Bancada sem gasto mostra "US$ 0,00" e, como no Swift, a dica com tudo zerado.
pub fn pill(ledger: &UsageLedger, prices: &PriceTable) -> Pill {
    let total = ledger.total();
    let amount = if total.is_empty() {
        "US$ 0,00".to_owned()
    } else {
        text::cost(&total, prices)
    };
    Pill {
        text: amount,
        tooltip: Some(format!(
            "Consumo da bancada: {}",
            text::breakdown(&total_usage(&total))
        )),
        empty: total.is_empty(),
    }
}

/// `pricing_file` e `user_home` só servem para a nota de rodapé, que mostra o
/// caminho com `~`.
pub fn panel(
    title: &str,
    ledger: &UsageLedger,
    prices: &PriceTable,
    pricing_file: &Path,
    user_home: &Path,
) -> Panel {
    let total = ledger.total();
    let tokens = total_usage(&total);
    let split = prices.split(&total);
    Panel {
        heading: title.to_uppercase(),
        total: Total {
            amount: text::cost(&total, prices),
            tokens: format!("{} tokens", text::tokens(tokens.total())),
        },
        split: splits(&split, &tokens),
        agents: agents(ledger, prices),
        models: models(&total, prices),
        prices: price_sheet(&total, prices, pricing_file, user_home),
    }
}

fn splits(cost: &TariffCost, tokens: &TokenUsage) -> Vec<Split> {
    let row = |key: &str, title: &str, dollars: f64, count: i64| Split {
        key: key.to_owned(),
        title: title.to_owned(),
        amount: text::dollars(dollars),
        detail: format!("{} tokens", text::tokens(count)),
        dollars,
    };
    vec![
        row("output", "Saída", cost.output, tokens.output),
        row("input", "Entrada", cost.input, tokens.input),
        row(
            "cache_write",
            "Cache escrito",
            cost.cache_write,
            tokens.cache_write(),
        ),
        row(
            "cache_read",
            "Cache lido",
            cost.cache_read,
            tokens.cache_read,
        ),
    ]
}

fn agents(ledger: &UsageLedger, prices: &PriceTable) -> Vec<AgentRow> {
    let mut rows: Vec<(&String, &UsageByPrice, f64)> = ledger
        .by_node
        .iter()
        .map(|(node, usage)| (node, usage, prices.cost(usage).0))
        .collect();
    rows.sort_by(|a, b| by_cost_desc(a.2, b.2));
    let top = top_of(rows.first().map(|row| row.2));
    rows.into_iter()
        .map(|(node, usage, cost)| AgentRow {
            name: node.clone(),
            tag: prices.main_model(usage),
            amount: text::cost(usage, prices),
            fraction: fraction(cost, top),
            detail: detail(&total_usage(usage)),
        })
        .collect()
}

fn models(total: &UsageByPrice, prices: &PriceTable) -> Vec<ModelRow> {
    let mut rows: Vec<(&String, Spend, f64)> = total
        .iter()
        .map(|(key, spend)| {
            let cost = prices.cost(&UsageByPrice::from([(key.clone(), *spend)])).0;
            (key, *spend, cost)
        })
        .collect();
    rows.sort_by(|a, b| by_cost_desc(a.2, b.2));
    let top = top_of(rows.first().map(|row| row.2));
    rows.into_iter()
        .map(|(key, spend, cost)| ModelRow {
            name: prices.name(key),
            family: family(key).to_owned(),
            amount: text::cost(&UsageByPrice::from([(key.clone(), spend)]), prices),
            fraction: fraction(cost, top),
            detail: detail(&spend.tokens),
        })
        .collect()
}

fn price_sheet(
    total: &UsageByPrice,
    prices: &PriceTable,
    pricing_file: &Path,
    user_home: &Path,
) -> Prices {
    let used: BTreeSet<&String> = total.keys().collect();
    let mut rows: Vec<(&String, &ModelPrice)> = prices
        .models
        .iter()
        .filter(|(key, _)| !key.ends_with("#long") || used.contains(key))
        .collect();
    rows.sort_by(|a, b| {
        used.contains(b.0)
            .cmp(&used.contains(a.0))
            .then_with(|| b.1.input.partial_cmp(&a.1.input).unwrap_or(Ordering::Equal))
            .then_with(|| a.1.name.cmp(&b.1.name))
    });
    let rows = rows
        .into_iter()
        .map(|(key, price)| PriceRow {
            name: price.name.clone(),
            lit: used.contains(key),
            edited: prices.origin.get(key) == Some(&Origin::File),
            values: [
                price.input,
                price.output,
                price.cache_write5m.unwrap_or(price.input * 1.25),
                price.cache_write1h.unwrap_or(price.input * 2.0),
                price.cache_read,
            ]
            .into_iter()
            .map(money)
            .collect(),
        })
        .collect();

    let has = |origin| prices.origin.values().any(|o| *o == origin);
    let origin = if has(Origin::ClaudeCode) {
        "Preços do Claude Code instalado"
    } else {
        "Preços da tabela embutida"
    };
    let edited = if has(Origin::File) {
        " · ✎ = seu pricing.json"
    } else {
        ""
    };
    let path = pricing_file.to_string_lossy();
    let home = user_home.to_string_lossy();
    Prices {
        open_note: "US$ por milhão de tokens".to_owned(),
        columns: ["", "Entrada", "Saída", "5 min", "1 h", "Lido"]
            .map(str::to_owned)
            .to_vec(),
        rows,
        origin_note: format!("{origin}{edited} · modo rápido custa 2×"),
        rule_note: "Custo no preço do dia do gasto: tabela nova vale daqui para frente.".to_owned(),
        file_note: format!("Exceções em {}", path.replace(home.as_ref(), "~")),
    }
}

fn money(value: f64) -> String {
    let fixed = if value >= 1.0 {
        format!("{value:.2}")
    } else {
        format!("{value:.3}")
    };
    fixed.replace('.', ",")
}

/// O maior da lista, com piso: lista de custo zero não divide por zero.
fn top_of(first: Option<f64>) -> f64 {
    first.unwrap_or(0.0).max(0.0001)
}

fn fraction(cost: f64, top: f64) -> f64 {
    (cost / top).clamp(0.0, 1.0)
}

fn by_cost_desc(a: f64, b: f64) -> Ordering {
    b.partial_cmp(&a).unwrap_or(Ordering::Equal)
}

fn detail(usage: &TokenUsage) -> String {
    format!(
        "saída {} · cache lido {} · escrito {} · entrada {}",
        text::tokens(usage.output),
        text::tokens(usage.cache_read),
        text::tokens(usage.cache_write()),
        text::tokens(usage.input),
    )
}

/// Família pelo nome da chave: quem olha a lista reconhece Opus, Sonnet e
/// Haiku sem ler o nome.
fn family(key: &str) -> &'static str {
    if key.contains("opus") {
        "opus"
    } else if key.contains("sonnet") {
        "sonnet"
    } else if key.contains("haiku") {
        "haiku"
    } else if key.contains("fable") || key.contains("mythos") {
        "fable"
    } else {
        "other"
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::super::prices::entry;
    use super::*;

    fn usage(input: i64, output: i64, read: i64) -> TokenUsage {
        TokenUsage {
            input,
            output,
            cache_read: read,
            ..TokenUsage::default()
        }
    }

    fn ledger(prices: &PriceTable) -> UsageLedger {
        let mut ledger = UsageLedger::default();
        ledger.absorb(
            &[entry("a", "claude-opus-5-5", usage(1_000_000, 100_000, 0))],
            "wb/a",
            prices,
        );
        ledger.absorb(
            &[entry(
                "b",
                "claude-sonnet-5-5",
                usage(100_000, 10_000, 5_000),
            )],
            "wb/b",
            prices,
        );
        ledger
    }

    fn build(ledger: &UsageLedger, prices: &PriceTable) -> Panel {
        panel(
            "Consumo · app",
            ledger,
            prices,
            &PathBuf::from("/home/u/.egeon/pricing.json"),
            &PathBuf::from("/home/u"),
        )
    }

    #[test]
    fn pilula_da_bancada_sem_gasto_mostra_zero_com_a_dica() {
        let pill = pill(&UsageLedger::default(), &PriceTable::from_built_in());
        assert_eq!(pill.text, "US$ 0,00");
        assert!(
            pill.tooltip
                .is_some_and(|t| t.starts_with("Consumo da bancada: entrada 0"))
        );
    }

    #[test]
    fn pilula_e_cabecalho_seguem_o_swift() {
        let prices = PriceTable::from_built_in();
        let ledger = ledger(&prices);
        let pill = pill(&ledger, &prices);
        assert_eq!(pill.text, text::cost(&ledger.total(), &prices));
        let panel = build(&ledger, &prices);
        assert_eq!(panel.heading, "CONSUMO · APP");
        assert_eq!(panel.total.amount, pill.text);
        assert!(panel.total.tokens.ends_with(" tokens"));
    }

    #[test]
    fn as_quatro_tarifas_na_ordem_da_barra() {
        let prices = PriceTable::from_built_in();
        let panel = build(&ledger(&prices), &prices);
        let keys: Vec<_> = panel.split.iter().map(|s| s.key.as_str()).collect();
        assert_eq!(keys, ["output", "input", "cache_write", "cache_read"]);
        let sum: f64 = panel.split.iter().map(|s| s.dollars).sum();
        assert!((sum - prices.cost(&ledger(&prices).total()).0).abs() < 1e-9);
    }

    #[test]
    fn agentes_e_modelos_do_mais_caro_ao_mais_barato_com_fracao_do_maior() {
        let prices = PriceTable::from_built_in();
        let panel = build(&ledger(&prices), &prices);
        let names: Vec<_> = panel.agents.iter().map(|a| a.name.as_str()).collect();
        assert_eq!(names, ["wb/a", "wb/b"]);
        assert!((panel.agents[0].fraction - 1.0).abs() < 1e-12);
        assert!(panel.agents[1].fraction < 0.2);
        assert!(panel.agents[0].tag.is_some());
        let families: Vec<_> = panel.models.iter().map(|m| m.family.as_str()).collect();
        assert_eq!(families, ["opus", "sonnet"]);
        assert!(panel.models[0].detail.starts_with("saída "));
    }

    #[test]
    fn bancada_vazia_nao_tem_linhas_nem_divide_por_zero() {
        let prices = PriceTable::from_built_in();
        let panel = build(&UsageLedger::default(), &prices);
        assert!(panel.agents.is_empty() && panel.models.is_empty());
        assert_eq!(panel.total.tokens, "0 tokens");
        assert!(panel.split.iter().all(|s| s.dollars == 0.0));
    }

    #[test]
    fn tabela_de_precos_acende_o_usado_e_esconde_a_faixa_longa_sem_uso() {
        let prices = PriceTable::from_built_in();
        let panel = build(&ledger(&prices), &prices);
        let sheet = &panel.prices;
        assert_eq!(
            sheet.columns,
            ["", "Entrada", "Saída", "5 min", "1 h", "Lido"]
        );
        let lit: Vec<_> = sheet.rows.iter().take_while(|r| r.lit).collect();
        assert_eq!(lit.len(), 2);
        assert!(sheet.rows.iter().skip(2).all(|r| !r.lit));
        assert!(sheet.rows.iter().all(|r| r.values.len() == 5));
        let hidden = prices
            .models
            .keys()
            .filter(|k| k.ends_with("#long"))
            .count();
        assert_eq!(sheet.rows.len(), prices.models.len() - hidden);
    }

    #[test]
    fn dinheiro_da_tabela_tem_duas_casas_a_partir_de_um_dolar_e_tres_abaixo() {
        assert_eq!(money(15.0), "15,00");
        assert_eq!(money(1.25), "1,25");
        assert_eq!(money(0.3), "0,300");
        assert_eq!(money(0.025), "0,025");
    }

    #[test]
    fn notas_do_rodape_dizem_de_onde_vem_o_preco() {
        let mut prices = PriceTable::from_built_in();
        let embedded = build(&UsageLedger::default(), &prices).prices;
        assert_eq!(
            embedded.origin_note,
            "Preços da tabela embutida · modo rápido custa 2×"
        );
        assert_eq!(embedded.file_note, "Exceções em ~/.egeon/pricing.json");

        let key = "claude-opus-5-5".to_owned();
        prices.origin.insert(key, Origin::ClaudeCode);
        prices
            .origin
            .insert("claude-haiku-4-5".to_owned(), Origin::File);
        let layered = build(&UsageLedger::default(), &prices).prices;
        assert_eq!(
            layered.origin_note,
            "Preços do Claude Code instalado · ✎ = seu pricing.json · modo rápido custa 2×"
        );
        assert!(
            layered
                .rows
                .iter()
                .any(|r| r.edited && r.name.contains("Haiku"))
        );
    }

    #[test]
    fn o_json_volta_igual() {
        let prices = PriceTable::from_built_in();
        let panel = build(&ledger(&prices), &prices);
        let json = serde_json::to_string(&panel).expect("serializa");
        let back: Panel = serde_json::from_str(&json).expect("lê de volta");
        assert_eq!(back, panel);
        let pill = pill(&ledger(&prices), &prices);
        let back: Pill = serde_json::from_str(&serde_json::to_string(&pill).expect("serializa"))
            .expect("lê de volta");
        assert_eq!(back, pill);
    }

    #[test]
    fn familia_pelo_nome_da_chave() {
        assert_eq!(family("claude-opus-5-5#fast"), "opus");
        assert_eq!(family("claude-fable-5-1"), "fable");
        assert_eq!(family("claude-mythos-1"), "fable");
        assert_eq!(family("gpt"), "other");
    }
}

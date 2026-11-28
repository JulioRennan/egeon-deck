//! Como o dinheiro e os tokens aparecem na tela (pt-BR).

use super::model::{TokenUsage, UsageByPrice};
use super::prices::PriceTable;

/// `US$ 1.234,50`; abaixo de um centavo, `< US$ 0,01`.
pub fn dollars(value: f64) -> String {
    if value > 0.0 && value < 0.01 {
        return "< US$ 0,01".to_owned();
    }
    let fixed = format!("{value:.2}");
    let (whole, cents) = fixed.split_once('.').unwrap_or((&fixed, "00"));
    let (sign, digits) = match whole.strip_prefix('-') {
        Some(rest) => ("-", rest),
        None => ("", whole),
    };
    let mut grouped = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            grouped.push('.');
        }
        grouped.push(c);
    }
    format!("US$ {sign}{grouped},{cents}")
}

pub fn tokens(value: i64) -> String {
    match value {
        ..1_000 => value.to_string(),
        1_000..1_000_000 => format!("{:.1}K", value as f64 / 1_000.0).replace('.', ","),
        _ => format!("{:.2}M", value as f64 / 1_000_000.0).replace('.', ","),
    }
}

/// "US$ 1,23" ou, com modelo sem preço, "US$ 1,23+".
pub fn cost(usage: &UsageByPrice, prices: &PriceTable) -> String {
    let (value, unpriced) = prices.cost(usage);
    format!("{}{}", dollars(value), if unpriced { "+" } else { "" })
}

/// As quatro tarifas numa linha, para dica de tela.
pub fn breakdown(usage: &TokenUsage) -> String {
    format!(
        "entrada {} · saída {} · cache escrito {} · cache lido {}",
        tokens(usage.input),
        tokens(usage.output),
        tokens(usage.cache_write()),
        tokens(usage.cache_read)
    )
}

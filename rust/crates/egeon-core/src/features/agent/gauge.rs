//! Quanto da janela de contexto do modelo está em uso.

use super::model_catalog::CatalogModel;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ContextGauge {
    pub used: i64,
    pub window: i64,
}

impl ContextGauge {
    /// `[1m]` é pedido explícito da janela grande e não aparece no transcript,
    /// que grava só o id. Uso acima da janela do catálogo é o CLI usando a
    /// grande sem ninguém ter pedido, o que alguns planos fazem sozinhos.
    pub fn new(tokens: i64, requested: Option<&str>, model: Option<&CatalogModel>) -> Option<Self> {
        const LARGE: i64 = 1_000_000;
        let asked = if requested.is_some_and(|r| r.to_lowercase().contains("[1m]")) {
            Some(LARGE)
        } else {
            model.and_then(|m| m.context_window)
        };
        let asked = asked.filter(|w| *w > 0)?;
        let window = if tokens > asked {
            asked.max(LARGE)
        } else {
            asked
        };
        Some(ContextGauge {
            used: tokens,
            window,
        })
    }

    pub fn fraction(&self) -> f64 {
        (self.used as f64 / self.window as f64).min(1.0)
    }

    /// Para cima: dizer "0%" com a conversa já ocupando algo seria mentira, e
    /// "100%" só quando a janela encheu de fato é o que o arredondamento garante.
    pub fn used_percent(&self) -> i64 {
        ((self.fraction() * 100.0).ceil() as i64).min(100)
    }

    /// Do verde (120°) ao vermelho (0°), passando pelo amarelo na metade.
    pub fn hue(&self) -> f64 {
        120.0 * (1.0 - self.fraction())
    }

    pub fn text(&self) -> String {
        format!("{}%", self.used_percent())
    }

    pub fn detail(&self) -> String {
        format!(
            "{} de {} em uso",
            Self::short(self.used),
            Self::short(self.window)
        )
    }

    pub fn short(tokens: i64) -> String {
        if tokens >= 1_000_000 {
            let value = tokens as f64 / 1_000_000.0;
            return if value == value.round() {
                format!("{}M", value as i64)
            } else {
                format!("{value:.1}M")
            };
        }
        if tokens >= 1000 {
            format!("{}K", tokens / 1000)
        } else {
            tokens.to_string()
        }
    }
}

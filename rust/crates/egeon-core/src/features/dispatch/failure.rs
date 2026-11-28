//! O turno que morreu por erro da API, como o gancho `StopFailure` conta
//! (ADR-072). Porte de `ApiFailure.swift`.
//!
//! Erro passageiro tenta de novo sozinho; limite de uso também, esperando
//! mais; conta, login e pedido inválido não melhoram repetindo — param e
//! chamam você.

use std::collections::HashMap;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiFailure {
    /// O `error` do payload, como o CLI manda (`overloaded`, `rate_limit`…).
    pub error: String,
    /// O `error_details`, quando vem.
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FailureKind {
    Transient,
    RateLimit,
    /// Repetir não resolve.
    Fatal,
}

pub const MAX_ATTEMPTS: u32 = 3;

impl ApiFailure {
    pub fn new(error: impl Into<String>) -> Self {
        Self {
            error: error.into(),
            detail: None,
        }
    }

    /// Lido da query de `/activity?event=failure`: `error` e `detail`.
    pub fn from_query(query: &HashMap<String, String>) -> Option<Self> {
        let error = query.get("error").filter(|e| !e.is_empty())?;
        Some(Self {
            error: error.clone(),
            detail: query.get("detail").filter(|d| !d.is_empty()).cloned(),
        })
    }

    pub fn kind(&self) -> FailureKind {
        match self.error.as_str() {
            "overloaded" | "server_error" | "unknown" => FailureKind::Transient,
            "rate_limit" => FailureKind::RateLimit,
            _ => FailureKind::Fatal,
        }
    }

    /// Quanto esperar antes da tentativa `attempt` (1, 2, 3…). `None` é
    /// desistir: erro sem volta, ou as tentativas acabaram.
    pub fn delay(&self, attempt: u32) -> Option<Duration> {
        let schedule: [u64; 3] = match self.kind() {
            FailureKind::Transient => [30, 120, 300],
            // Limite de uso volta em minutos, às vezes horas: tentar a cada 30s
            // só gastaria tentativa.
            FailureKind::RateLimit => [120, 600, 1800],
            FailureKind::Fatal => return None,
        };
        let index = usize::try_from(attempt.checked_sub(1)?).ok()?;
        schedule.get(index).map(|s| Duration::from_secs(*s))
    }

    /// Em português, para o card e o chat.
    pub fn label(&self) -> &str {
        match self.error.as_str() {
            "overloaded" => "API sobrecarregada",
            "server_error" => "erro no servidor da API",
            "rate_limit" => "limite de uso",
            "authentication_failed" => "login falhou",
            "billing_error" => "problema de cobrança",
            "account_on_hold" => "conta suspensa",
            "invalid_request" => "pedido inválido",
            "model_not_found" => "modelo não encontrado",
            "max_output_tokens" => "resposta passou do limite",
            "unknown" => "erro desconhecido",
            other => other,
        }
    }

    /// O "oi" que você mandava, dizendo por quê.
    pub fn retry_prompt(&self) -> String {
        format!(
            "A última chamada à API falhou ({}). Continue de onde parou.",
            self.label()
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kinds() {
        assert_eq!(ApiFailure::new("overloaded").kind(), FailureKind::Transient);
        assert_eq!(
            ApiFailure::new("server_error").kind(),
            FailureKind::Transient
        );
        assert_eq!(ApiFailure::new("unknown").kind(), FailureKind::Transient);
        assert_eq!(ApiFailure::new("rate_limit").kind(), FailureKind::RateLimit);
        for fatal in [
            "authentication_failed",
            "billing_error",
            "invalid_request",
            "model_not_found",
            "novo_erro",
        ] {
            assert_eq!(ApiFailure::new(fatal).kind(), FailureKind::Fatal, "{fatal}");
        }
    }

    #[test]
    fn schedule_and_giving_up() {
        let busy = ApiFailure::new("overloaded");
        let secs: Vec<_> = (1..=3)
            .map(|a| busy.delay(a).map(|d| d.as_secs()))
            .collect();
        assert_eq!(secs, [Some(30), Some(120), Some(300)]);
        assert_eq!(busy.delay(4), None);
        assert_eq!(busy.delay(0), None);
        assert_eq!(
            ApiFailure::new("rate_limit").delay(1),
            Some(Duration::from_secs(120))
        );
        assert_eq!(ApiFailure::new("billing_error").delay(1), None);
    }

    #[test]
    fn read_from_query_and_wording() {
        let query: HashMap<String, String> = [("error", "overloaded"), ("detail", "Overloaded")]
            .into_iter()
            .map(|(k, v)| (k.to_owned(), v.to_owned()))
            .collect();
        let failure = ApiFailure::from_query(&query);
        assert_eq!(
            failure,
            Some(ApiFailure {
                error: "overloaded".into(),
                detail: Some("Overloaded".into())
            })
        );
        assert_eq!(ApiFailure::from_query(&HashMap::new()), None);
        assert!(
            failure
                .unwrap()
                .retry_prompt()
                .contains("API sobrecarregada")
        );
    }
}

//! O que o Dispatcher precisa do perfil do agente: tempos, injeção e atenção.
//! Os tipos são os do `AgentProfile` (feature `agent`); aqui só o recorte.

use std::time::Duration;

use crate::features::agent::model::AgentProfile;
pub use crate::features::agent::model::{AttentionConfig, InjectConfig};

/// O perfil de um terminal com IA. Terminal sem perfil é shell.
#[derive(Debug, Clone, PartialEq)]
pub struct TargetProfile {
    pub display_name: String,
    /// Silêncio que conta como ocioso (`idle.ms`, 1500 por padrão).
    pub idle: Duration,
    /// Aquecimento antes de a bancada ser utilizável (`idle.warmupMs`).
    pub warmup: Duration,
    pub inject: InjectConfig,
    pub attention: AttentionConfig,
}

impl TargetProfile {
    /// Com os padrões do Swift, para teste e para CLI sem `agents.json`.
    pub fn new(display_name: impl Into<String>) -> Self {
        Self {
            display_name: display_name.into(),
            idle: Duration::from_millis(1500),
            warmup: Duration::from_millis(4000),
            inject: InjectConfig::default(),
            attention: AttentionConfig::default(),
        }
    }

    pub fn from_agent(profile: &AgentProfile) -> Self {
        Self {
            display_name: profile.display_name.clone(),
            idle: profile.idle_interval(),
            warmup: profile.warmup_interval(),
            inject: profile.inject_config(),
            attention: profile.attention_config(),
        }
    }
}

/// Terminal sem perfil é shell: bracketed paste no zsh devolve os marcadores
/// literais e o comando nunca executa.
pub fn shell_inject() -> InjectConfig {
    InjectConfig {
        mode: "plain".to_owned(),
        ..InjectConfig::default()
    }
}

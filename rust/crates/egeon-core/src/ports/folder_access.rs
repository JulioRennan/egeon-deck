//! A decisão do sistema sobre o acesso a pastas protegidas (TCC, no macOS).
//!
//! Detectar que a pasta não se lê é portável (`read_dir` devolve
//! `PermissionDenied`) e fica no core; zerar a decisão para o sistema voltar a
//! perguntar é do sistema.

pub trait FolderPermissions: Send + Sync {
    /// Zera a decisão do usuário sobre `service` para o app, e a leitura
    /// seguinte volta a fazer o sistema perguntar. `false` quando não há o que
    /// zerar — fora de um `.app` — ou o comando não rodou.
    fn reset(&self, service: &str) -> bool;

    /// A URL do painel de privacidade onde o usuário libera a pasta, para o core
    /// abrir pelo `Opener`. `None` onde o sistema não tem esse painel.
    fn settings_url(&self) -> Option<String>;
}

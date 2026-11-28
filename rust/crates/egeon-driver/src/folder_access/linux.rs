//! O Linux não tem TCC: pasta que não se lê é permissão comum do sistema de
//! arquivos, que o app não zera, e não há painel de privacidade a abrir.

pub(super) fn settings_url() -> Option<String> {
    None
}

pub(super) fn reset(_service: &str) -> bool {
    false
}

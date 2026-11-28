//! `NSWorkspace.open` e `NSBeep`.

use egeon_core::ports::opener::OpenTarget;
use objc2::rc::Retained;
use objc2_app_kit::{NSBeep, NSWorkspace};
use objc2_foundation::{NSString, NSURL};

pub(super) fn open(target: &OpenTarget) -> bool {
    match url_of(target) {
        Some(url) => NSWorkspace::sharedWorkspace().openURL(&url),
        None => false,
    }
}

/// O `NSURL` do alvo, como o `URL(string:)` do Swift o faz: texto inválido
/// (espaço no host, caractere de controle) dá `None`, e o que só está mal
/// escapado no caminho vira escapado.
fn url_of(target: &OpenTarget) -> Option<Retained<NSURL>> {
    match target {
        OpenTarget::File(path) => Some(NSURL::fileURLWithPath(&NSString::from_str(
            &path.to_string_lossy(),
        ))),
        OpenTarget::Url(text) => NSURL::URLWithString(&NSString::from_str(text)),
    }
}

/// Na thread principal, como o Swift: o alerta é do AppKit, e o core chama de
/// uma thread de fundo.
pub(super) fn beep() {
    crate::main_loop::on_main(|| NSBeep());
}

#[cfg(test)]
mod tests {
    use super::*;

    fn url(text: &str) -> Option<String> {
        url_of(&OpenTarget::Url(text.into()))
            .and_then(|u| u.absoluteString().map(|s| s.to_string()))
    }

    /// Resolve sem abrir: `open` num `https` válido abriria o navegador.
    #[test]
    fn host_invalido_nao_vira_url_e_caminho_mal_escrito_e_escapado() {
        assert_eq!(url("https://exa mple.com"), None);
        assert_eq!(url("https://a\u{7}b.com"), None);
        assert_eq!(
            url("https://example.com/a b").as_deref(),
            Some("https://example.com/a%20b")
        );
        assert_eq!(
            url("https://example.com/\n").as_deref(),
            Some("https://example.com/%0A")
        );
    }
}

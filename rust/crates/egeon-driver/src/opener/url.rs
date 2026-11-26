//! A URL como o `URL(string:)` do Swift a aceita, no Linux e no Windows (o
//! macOS usa a do sistema).

/// A URL como o `URL(string:)` do Swift a aceita: com esquema, sem espaço nem
/// controle no host, e com o que só está mal escapado no resto escapado.
pub(super) fn url_of(text: &str) -> Option<String> {
    let (scheme, rest) = text.split_once(':')?;
    let mut chars = scheme.chars();
    let valid_scheme = chars.next().is_some_and(|c| c.is_ascii_alphabetic())
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'));
    if !valid_scheme {
        return None;
    }
    let (authority, path) = match rest.strip_prefix("//") {
        Some(after) => {
            let end = after.find(['/', '?', '#']).unwrap_or(after.len());
            (Some(&after[..end]), &after[end..])
        }
        None => (None, rest),
    };
    if authority.is_some_and(|host| host.chars().any(|c| c.is_whitespace() || c.is_control())) {
        return None;
    }
    let mut url = format!("{scheme}:");
    if let Some(host) = authority {
        url.push_str("//");
        url.push_str(host);
    }
    for byte in path.bytes() {
        if byte <= b' ' || byte >= 0x7f {
            url.push_str(&format!("%{byte:02X}"));
        } else {
            url.push(char::from(byte));
        }
    }
    Some(url)
}

pub(super) fn scheme_of(url: &str) -> &str {
    url.split(':').next().unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Resolve sem abrir: `open` num `https` válido abriria o navegador.
    #[test]
    fn host_invalido_nao_vira_url_e_caminho_mal_escrito_e_escapado() {
        assert_eq!(url_of("https://exa mple.com"), None);
        assert_eq!(url_of("https://a\u{7}b.com"), None);
        assert_eq!(
            url_of("https://example.com/a b").as_deref(),
            Some("https://example.com/a%20b")
        );
        assert_eq!(
            url_of("https://example.com/\n").as_deref(),
            Some("https://example.com/%0A")
        );
        assert_eq!(url_of("isto nao e url"), None);
        assert_eq!(url_of("1http://x"), None);
        assert_eq!(url_of("mailto:a@b.com").as_deref(), Some("mailto:a@b.com"));
    }
}

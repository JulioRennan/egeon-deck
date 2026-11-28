//! Codificação de URL dos comandos e dos ganchos.
//!
//! Um só conjunto de bytes livres serve aos dois: o `enc()` do bash e o
//! `urllib.parse.quote` do python deixavam passar os mesmos caracteres
//! (letras, dígitos e `._~-`), e só divergiam na barra.

use std::fmt::Write;

/// Escapa byte a byte, em maiúsculas. `keep_slash` é a diferença entre
/// `quote(s)` (barra livre) e `quote(s, safe="")`.
pub fn percent(raw: &[u8], keep_slash: bool) -> String {
    let mut out = String::with_capacity(raw.len());
    for &byte in raw {
        let free = byte.is_ascii_alphanumeric()
            || matches!(byte, b'.' | b'_' | b'~' | b'-')
            || (keep_slash && byte == b'/');
        if free {
            out.push(char::from(byte));
        } else {
            // `write!` em `String` não falha.
            let _ = write!(out, "%{byte:02X}");
        }
    }
    out
}

/// O `enc()` que o script `egeon` carrega: barra livre, o resto escapado.
pub fn enc(raw: &[u8]) -> String {
    percent(raw, true)
}

/// `urllib.parse.quote(texto)` — a barra continua livre.
pub fn quote(text: &str) -> String {
    percent(text.as_bytes(), true)
}

/// `urllib.parse.quote(texto, safe="")` — a barra também é escapada.
pub fn quote_all(text: &str) -> String {
    percent(text.as_bytes(), false)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Porte de ShellEncoderTests: bancada com espaço e `+` no nome quebrava a
    // linha HTTP do gancho, e o alvo chegava como "SPEI".
    #[test]
    fn espaco_mais_e_utf8_byte_a_byte() {
        assert_eq!(
            enc("SPEI + SPI/backend".as_bytes()),
            "SPEI%20%2B%20SPI/backend"
        );
        assert_eq!(enc("deck/revisor".as_bytes()), "deck/revisor");
        assert_eq!(enc("ação/x".as_bytes()), "a%C3%A7%C3%A3o/x");
        assert_eq!(enc("a&b=c?d".as_bytes()), "a%26b%3Dc%3Fd");
    }

    // O bash 3.2 estendia o sinal de byte ≥ 0x80 e imprimia `FFFFFFFFFFFFFFC3`;
    // aqui o byte é sempre dois dígitos, mesmo fora de UTF-8.
    #[test]
    fn byte_solto_fora_de_utf8_vira_dois_digitos() {
        assert_eq!(enc(&[0xC3, 0x28, 0xFF, 0x00, b'\n']), "%C3%28%FF%00%0A");
    }

    #[test]
    fn quote_diferencia_a_barra() {
        assert_eq!(quote("/a b/c"), "/a%20b/c");
        assert_eq!(quote_all("/a b/c"), "%2Fa%20b%2Fc");
        assert_eq!(quote_all("~._-"), "~._-");
    }
}

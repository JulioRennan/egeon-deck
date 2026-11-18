//! O que o composer lê do que está sendo digitado: o `/` do comando e o `@` da
//! menção. Offsets em UTF-16 porque é a moeda do campo de texto (o `NSRange` de
//! onde vieram e o `String` do Dart).

use super::markdown::Utf16Range;

fn units(text: &str) -> Vec<u16> {
    text.encode_utf16().collect()
}

fn text_of(units: &[u16]) -> String {
    String::from_utf16_lossy(units)
}

// ---- Comando em digitação -------------------------------------------------

/// O `/` que abre a lista de comandos: só no começo da mensagem, e só até o
/// primeiro espaço — é como o CLI lê. `/` no meio do texto é caminho de arquivo,
/// não comando.
pub mod slash {
    use super::{text_of, units};

    /// O que já foi digitado depois da barra, ou `None` quando não há comando
    /// aberto antes do cursor.
    pub fn active_query(text: &str, caret: usize) -> Option<String> {
        let chars = units(text);
        if caret < 1 || caret > chars.len() || chars[0] != u16::from(b'/') {
            return None;
        }
        let typed = text_of(&chars[1..caret]);
        if typed.chars().any(char::is_whitespace) {
            return None;
        }
        Some(typed)
    }

    /// O texto com o comando escolhido no lugar do digitado — o resto da
    /// mensagem fica — e onde o cursor cai (em UTF-16).
    pub fn insert(name: &str, text: &str) -> (String, usize) {
        let rest = text.trim_start_matches(|c: char| !c.is_whitespace());
        let command = format!("/{name} ");
        let tail = rest.trim_start_matches(' ');
        let caret = command.encode_utf16().count();
        (format!("{command}{tail}"), caret)
    }
}

// ---- Menção em digitação --------------------------------------------------

pub mod mention {
    use super::{Utf16Range, text_of, units};

    /// A menção que está sendo digitada.
    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct Active {
        /// Do `@` (inclusive) até o cursor — o trecho a substituir na escolha.
        pub range: Utf16Range,
        /// O que já foi digitado depois do `@`, para filtrar a lista.
        pub query: String,
    }

    /// Pontuação como o `CharacterSet.punctuationCharacters` do Foundation
    /// (categorias P*): o `std` não expõe categoria geral, então vão as ASCII, as
    /// do Latin-1 e os blocos de pontuação geral e CJK. Símbolos (`$`, `+`, `<`,
    /// `=`, `>`, `^`, `` ` ``, `|`, `~`) não entram, como no Foundation.
    fn is_punctuation(c: char) -> bool {
        matches!(
            c,
            '!' | '"'
                | '#'
                | '%'
                | '&'
                | '\''
                | '('
                | ')'
                | '*'
                | ','
                | '-'
                | '.'
                | '/'
                | ':'
                | ';'
                | '?'
                | '@'
                | '['
                | '\\'
                | ']'
                | '_'
                | '{'
                | '}'
                | '¡'
                | '§'
                | '«'
                | '¶'
                | '·'
                | '»'
                | '¿'
                | '\u{2010}'..='\u{2027}'
                | '\u{2030}'..='\u{205e}'
                | '\u{3001}'..='\u{3003}'
                | '\u{3008}'..='\u{3011}'
        )
    }

    /// Acha a menção que está sendo digitada: o `@` aberto imediatamente antes do
    /// cursor.
    pub fn active_mention(text: &str, caret: usize) -> Option<Active> {
        let chars = units(text);
        if caret > chars.len() {
            return None;
        }
        let mut index = caret;
        while index > 0 {
            index -= 1;
            // Meia surrogate sozinha não é caractere: o Swift desiste.
            let scalar = char::from_u32(u32::from(chars[index]))?;
            if scalar == '@' {
                // `@` no meio de palavra é e-mail ou código, não menção.
                if index > 0 {
                    let previous = char::from_u32(u32::from(chars[index - 1]));
                    if let Some(p) = previous
                        && !p.is_whitespace()
                        && !is_punctuation(p)
                    {
                        return None;
                    }
                }
                return Some(Active {
                    range: Utf16Range {
                        location: index,
                        length: caret - index,
                    },
                    query: text_of(&chars[index + 1..caret]),
                });
            }
            // Espaço fecha a menção: depois dele o `@` de trás já não está ativo.
            if scalar.is_whitespace() {
                return None;
            }
        }
        None
    }

    /// O texto com a menção escolhida no lugar da digitada, e onde o cursor cai
    /// (em UTF-16).
    pub fn insert(name: &str, text: &str, replacing: Utf16Range) -> (String, usize) {
        let mention = format!("@{name} ");
        let chars = units(text);
        let start = replacing.location.min(chars.len());
        let end = (replacing.location + replacing.length).min(chars.len());
        let mut out: Vec<u16> = chars[..start].to_vec();
        out.extend(mention.encode_utf16());
        out.extend_from_slice(&chars[end..]);
        let caret = replacing.location + mention.encode_utf16().count();
        (text_of(&out), caret)
    }

    /// Quem da lista casa com o que foi digitado. Query vazia lista todos.
    pub fn candidates(names: &[String], query: &str) -> Vec<String> {
        if query.is_empty() {
            return names.to_vec();
        }
        let needle = query.to_lowercase();
        names
            .iter()
            .filter(|n| n.to_lowercase().contains(&needle))
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::mention::{self, Active};
    use super::slash;
    use super::*;

    #[test]
    fn comando_so_no_comeco_e_antes_do_espaco() {
        assert_eq!(slash::active_query("/", 1).as_deref(), Some(""));
        assert_eq!(slash::active_query("/cle", 4).as_deref(), Some("cle"));
        assert_eq!(
            slash::active_query("/figma:use", 10).as_deref(),
            Some("figma:use")
        );
        assert_eq!(slash::active_query("/clear agora", 12), None);
        assert_eq!(slash::active_query("veja /tmp", 9), None);
        assert_eq!(slash::active_query("", 0), None);
        assert_eq!(slash::active_query("/x", 0), None);
        assert_eq!(slash::active_query("/x", 9), None, "cursor depois do fim");
        // Só o que está antes do cursor conta.
        assert_eq!(
            slash::active_query("/clear agora", 3).as_deref(),
            Some("cl")
        );
    }

    #[test]
    fn inserir_mantem_o_resto_da_mensagem() {
        assert_eq!(slash::insert("clear", "/cl").0, "/clear ");
        assert_eq!(slash::insert("clear", "/cl").1, 7);
        assert_eq!(slash::insert("review", "/rev 243").0, "/review 243");
        assert_eq!(slash::insert("😀", "/x").1, 4, "o cursor é em UTF-16");
    }

    #[test]
    fn mencao_no_cursor_com_consulta() {
        let active = mention::active_mention("veja com o @ba", 14);
        assert_eq!(
            active,
            Some(Active {
                range: Utf16Range {
                    location: 11,
                    length: 3
                },
                query: "ba".into()
            })
        );
    }

    #[test]
    fn arroba_sozinho_abre_consulta_vazia() {
        let active = mention::active_mention("@", 1).expect("menção");
        assert_eq!(active.query, "");
        assert_eq!(
            active.range,
            Utf16Range {
                location: 0,
                length: 1
            }
        );
    }

    /// Espaço fecha a menção; o `@` de trás já não conta.
    #[test]
    fn espaco_fecha_a_mencao() {
        assert_eq!(mention::active_mention("@back veja", 10), None);
    }

    /// `@` colado em palavra é e-mail ou código, não menção.
    #[test]
    fn arroba_dentro_de_palavra_nao_e_mencao() {
        assert_eq!(mention::active_mention("julio@agro", 10), None);
        // Depois de pontuação continua valendo.
        assert!(mention::active_mention("(@ba", 4).is_some());
        assert!(mention::active_mention("olá,@ba", 7).is_some());
        assert!(
            mention::active_mention("a$@ba", 5).is_none(),
            "`$` é símbolo, não pontuação"
        );
    }

    #[test]
    fn cursor_antes_do_arroba_nao_e_mencao() {
        assert_eq!(mention::active_mention("@back", 0), None);
        assert_eq!(mention::active_mention("@back", 99), None);
    }

    #[test]
    fn inserir_troca_a_mencao_digitada() {
        let (text, caret) = mention::insert(
            "back",
            "veja com o @ba isso",
            Utf16Range {
                location: 11,
                length: 3,
            },
        );
        assert_eq!(text, "veja com o @back  isso");
        assert_eq!(caret, 17);
        // Offsets são em UTF-16: o emoji vale 2.
        let (text, _) = mention::insert(
            "a",
            "😀 @b",
            Utf16Range {
                location: 3,
                length: 2,
            },
        );
        assert_eq!(text, "😀 @a ");
    }

    #[test]
    fn candidatos_sem_caixa() {
        let names: Vec<String> = ["front", "back", "revisor"].map(String::from).to_vec();
        assert_eq!(mention::candidates(&names, ""), names);
        assert_eq!(mention::candidates(&names, "BA"), ["back"]);
        assert_eq!(mention::candidates(&names, "r"), ["front", "revisor"]);
    }
}

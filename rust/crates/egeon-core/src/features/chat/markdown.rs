//! Markdown mínimo para a bolha.
//!
//! O agente escreve Markdown, e a TUI renderiza; a bolha mostrava os
//! asteriscos. Isto cobre o que aparece em resposta de agente — negrito, código
//! inline, título, lista, bloco de código e link — e nada mais: tabela e imagem
//! ficam como texto. Não é um parser de Markdown; é o suficiente para a bolha
//! ler como o terminal (ADR-039).
//!
//! O Swift devolvia `NSAttributedString` (fonte, cor, tamanho do título). Aqui
//! a saída é o dado — [`Block`] e [`Span`], serializáveis — e a UI Flutter
//! decide o desenho. O que dá para provar sem desenhar fica aqui: o texto que a
//! bolha mostra ([`plain_text`]), onde estão os links ([`rendered_links`]) e a
//! URL solta que vira link ([`linkify`]). Todos os offsets são em unidades
//! UTF-16, que é a moeda do `String` do Dart e do `NSRange` de onde vieram.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Span {
    Text {
        text: String,
    },
    Bold {
        text: String,
    },
    Code {
        text: String,
    },
    /// `[rótulo](url)`: o rótulo aparece, a URL vai no clique.
    Link {
        label: String,
        url: String,
    },
}

impl Span {
    fn text(text: &str) -> Span {
        Span::Text {
            text: text.to_owned(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Block {
    Paragraph {
        spans: Vec<Span>,
    },
    Heading {
        level: u8,
        spans: Vec<Span>,
    },
    Bullet {
        spans: Vec<Span>,
    },
    /// "1. item" — o número já é o marcador; não ganha "•".
    Numbered {
        spans: Vec<Span>,
    },
    /// O rótulo do fence (```python) é a linguagem; sem rótulo, sem cor.
    Code {
        language: Option<String>,
        text: String,
    },
}

/// Um trecho do texto exibido, em unidades UTF-16.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Utf16Range {
    pub location: usize,
    pub length: usize,
}

/// Um link: onde ele está no texto exibido e para onde leva.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkRange {
    pub range: Utf16Range,
    pub url: String,
}

/// `.whitespaces` do Foundation: espaços Unicode e tab, sem quebra de linha.
fn is_blank(c: char) -> bool {
    matches!(
        c,
        '\t' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}' | '\u{202f}' | '\u{205f}' | '\u{3000}'
    )
}

fn trim_blank(text: &str) -> &str {
    text.trim_matches(is_blank)
}

pub fn blocks(text: &str) -> Vec<Block> {
    let mut out: Vec<Block> = Vec::new();
    let mut paragraph: Vec<&str> = Vec::new();
    let mut fence: Option<Vec<&str>> = None;
    let mut fence_language: Option<String> = None;

    fn flush(out: &mut Vec<Block>, paragraph: &mut Vec<&str>) {
        if paragraph.is_empty() {
            return;
        }
        out.push(Block::Paragraph {
            spans: spans(&paragraph.join("\n")),
        });
        paragraph.clear();
    }

    for line in text.split('\n') {
        if let Some(open) = fence.as_mut() {
            if trim_blank(line).starts_with("```") {
                out.push(Block::Code {
                    language: fence_language.clone(),
                    text: open.join("\n"),
                });
                fence = None;
            } else {
                open.push(line);
            }
            continue;
        }
        let trimmed = trim_blank(line);
        if let Some(label) = trimmed.strip_prefix("```") {
            flush(&mut out, &mut paragraph);
            fence = Some(Vec::new());
            let label = trim_blank(label);
            fence_language = (!label.is_empty()).then(|| label.to_owned());
        } else if trimmed.is_empty() {
            flush(&mut out, &mut paragraph);
        } else if let Some(block) = heading(trimmed) {
            flush(&mut out, &mut paragraph);
            out.push(block);
        } else if let Some(block) = bullet(trimmed) {
            flush(&mut out, &mut paragraph);
            out.push(block);
        } else {
            paragraph.push(line);
        }
    }
    if let Some(open) = fence {
        out.push(Block::Code {
            language: fence_language,
            text: open.join("\n"),
        });
    }
    flush(&mut out, &mut paragraph);
    out
}

fn heading(line: &str) -> Option<Block> {
    let level = line.chars().take_while(|c| *c == '#').count();
    if level == 0 || level > 6 {
        return None;
    }
    let rest = &line[level..];
    let body = rest.strip_prefix(' ')?;
    Some(Block::Heading {
        level: level as u8,
        spans: spans(body),
    })
}

fn bullet(line: &str) -> Option<Block> {
    for marker in ["- ", "* ", "• "] {
        if let Some(rest) = line.strip_prefix(marker) {
            return Some(Block::Bullet { spans: spans(rest) });
        }
    }
    // "1. item" — o número fica: a ordem é parte do que foi dito.
    let digits: usize = line
        .chars()
        .take_while(|c| c.is_numeric())
        .map(char::len_utf8)
        .sum();
    if digits > 0 && line[digits..].starts_with(". ") {
        return Some(Block::Numbered { spans: spans(line) });
    }
    None
}

/// Esquema de URL válido: letra, depois letras, dígitos, `+`, `-` ou `.`, e `:`.
/// É o que o `URL(string:)` do Swift exige para devolver um esquema.
fn has_scheme(url: &str) -> bool {
    let Some((scheme, _)) = url.split_once(':') else {
        return false;
    };
    let mut chars = scheme.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic())
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'))
}

/// O `URL(string:)` recusa o que o RFC 3986 não deixa passar cru.
fn is_url_text(url: &str) -> bool {
    let bytes = url.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        if b <= 0x20
            || matches!(
                b,
                b'"' | b'<' | b'>' | b'\\' | b'^' | b'`' | b'{' | b'|' | b'}'
            )
        {
            return false;
        }
        if b == b'%' {
            let ok = bytes.get(i + 1).is_some_and(u8::is_ascii_hexdigit)
                && bytes.get(i + 2).is_some_and(u8::is_ascii_hexdigit);
            if !ok {
                return false;
            }
        }
        i += 1;
    }
    true
}

/// `[rótulo](url)` começando em `start` (o `[`). Só URL com esquema — `[1](2)`
/// em texto comum não é link. Devolve o rótulo, a URL e onde o link termina.
fn link(text: &str, start: usize) -> Option<(&str, &str, usize)> {
    let after_bracket = start + 1;
    let close = after_bracket + text[after_bracket..].find(']')?;
    if close == after_bracket {
        return None;
    }
    let open = close + 1;
    if !text[open..].starts_with('(') {
        return None;
    }
    let end = open + text[open..].find(')')?;
    let url = trim_blank(&text[open + 1..end]);
    if !has_scheme(url) || !is_url_text(url) {
        return None;
    }
    Some((&text[after_bracket..close], url, end + 1))
}

/// `**negrito**` e `` `código` `` dentro de uma linha. Código ganha do negrito:
/// `**` dentro de crase é literal.
pub fn spans(text: &str) -> Vec<Span> {
    let mut out: Vec<Span> = Vec::new();
    let mut plain = String::new();
    let mut index = 0;

    fn flush(out: &mut Vec<Span>, plain: &mut String) {
        if !plain.is_empty() {
            out.push(Span::text(plain));
            plain.clear();
        }
    }

    while index < text.len() {
        let Some(c) = text[index..].chars().next() else {
            break;
        };
        let rest = &text[index + c.len_utf8()..];
        if c == '`'
            && let Some(close) = rest.find('`')
        {
            flush(&mut out, &mut plain);
            out.push(Span::Code {
                text: rest[..close].to_owned(),
            });
            index += 1 + close + 1;
        } else if c == '['
            && let Some((label, url, end)) = link(text, index)
        {
            flush(&mut out, &mut plain);
            out.push(Span::Link {
                label: label.to_owned(),
                url: url.to_owned(),
            });
            index = end;
        } else if text[index..].starts_with("**")
            && let Some(close) = text[index + 2..].find("**")
            && close > 0
        {
            flush(&mut out, &mut plain);
            out.push(Span::Bold {
                text: text[index + 2..index + 2 + close].to_owned(),
            });
            index += 2 + close + 2;
        } else {
            plain.push(c);
            index += c.len_utf8();
        }
    }
    flush(&mut out, &mut plain);
    out
}

fn span_text(span: &Span) -> &str {
    match span {
        Span::Text { text } | Span::Bold { text } | Span::Code { text } => text,
        Span::Link { label, .. } => label,
    }
}

fn utf16_len(text: &str) -> usize {
    text.encode_utf16().count()
}

/// O texto que a bolha mostra: blocos separados por linha em branco, `•` na
/// frente da lista, rótulo no lugar do link, o código como veio. É o `.string`
/// do texto atribuído que o Swift montava.
pub fn plain_text(blocks: &[Block]) -> String {
    layout(blocks).0
}

/// Onde cada link `[rótulo](url)` ficou no [`plain_text`].
pub fn rendered_links(blocks: &[Block]) -> Vec<LinkRange> {
    layout(blocks).1
}

fn layout(blocks: &[Block]) -> (String, Vec<LinkRange>) {
    let mut out = String::new();
    let mut offset = 0;
    let mut links = Vec::new();

    let push = |out: &mut String, offset: &mut usize, text: &str| {
        out.push_str(text);
        *offset += utf16_len(text);
    };

    for (i, block) in blocks.iter().enumerate() {
        if i > 0 {
            push(&mut out, &mut offset, "\n\n");
        }
        let spans = match block {
            Block::Paragraph { spans } | Block::Numbered { spans } => spans,
            Block::Heading { spans, .. } => spans,
            Block::Bullet { spans } => {
                push(&mut out, &mut offset, "•  ");
                spans
            }
            Block::Code { text, .. } => {
                push(&mut out, &mut offset, text);
                continue;
            }
        };
        for span in spans {
            let text = span_text(span);
            if let Span::Link { url, .. } = span {
                links.push(LinkRange {
                    range: Utf16Range {
                        location: offset,
                        length: utf16_len(text),
                    },
                    url: url.clone(),
                });
            }
            push(&mut out, &mut offset, text);
        }
    }
    (out, links)
}

/// Os blocos de uma resposta, de uma vez: o que a bolha mostra e onde estão os
/// links `[rótulo](url)`.
pub fn render(text: &str) -> (String, Vec<LinkRange>) {
    layout(&blocks(text))
}

/// URL solta no texto vira link — a do agente quase nunca vem em
/// `[rótulo](url)`. Não mexe no que já é link: `existing` são os trechos que já
/// levam um. Só `http` e `https` (um `www.` solto vira `http://www.…`, como o
/// detector de links do sistema fazia).
pub fn linkify(text: &str, existing: &[Utf16Range]) -> Vec<LinkRange> {
    let chars: Vec<char> = text.chars().collect();
    // Início de cada caractere em UTF-16, para devolver os offsets na moeda da UI.
    let mut unit_at = Vec::with_capacity(chars.len() + 1);
    let mut units = 0;
    for c in &chars {
        unit_at.push(units);
        units += c.len_utf16();
    }
    unit_at.push(units);

    let lower: Vec<char> = chars.iter().flat_map(|c| c.to_lowercase()).collect();
    // `to_lowercase` pode mudar a quantidade de caracteres (raro); então o
    // alinhamento por índice só vale se o texto não mudou de tamanho.
    let aligned = lower.len() == chars.len();

    let starts_with = |at: usize, prefix: &str| {
        aligned
            && prefix
                .chars()
                .enumerate()
                .all(|(k, p)| lower.get(at + k) == Some(&p))
    };

    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let boundary = i == 0 || !chars[i - 1].is_alphanumeric();
        let scheme = if !boundary {
            None
        } else if starts_with(i, "https://") || starts_with(i, "http://") {
            Some(false)
        } else if starts_with(i, "www.") && chars.get(i + 4).is_some_and(|c| c.is_alphanumeric()) {
            Some(true)
        } else {
            None
        };
        let Some(bare_www) = scheme else {
            i += 1;
            continue;
        };
        let mut end = i;
        while end < chars.len()
            && !chars[end].is_whitespace()
            && !matches!(chars[end], '<' | '>' | '"')
        {
            end += 1;
        }
        // Pontuação de fim de frase não é da URL; fecha-parêntese só se abriu.
        while end > i {
            let last = chars[end - 1];
            let opens = |open: char| chars[i..end].iter().filter(|c| **c == open).count();
            let closes = |close: char| chars[i..end].iter().filter(|c| **c == close).count();
            let drop = matches!(last, '.' | ',' | ';' | ':' | '!' | '?' | '\'')
                || (last == ')' && closes(')') > opens('('))
                || (last == ']' && closes(']') > opens('['))
                || (last == '}' && closes('}') > opens('{'));
            if !drop {
                break;
            }
            end -= 1;
        }
        let matched: String = chars[i..end].iter().collect();
        let range = Utf16Range {
            location: unit_at[i],
            length: unit_at[end] - unit_at[i],
        };
        // A URL de verdade precisa ter algo depois do esquema.
        let useful = if bare_www {
            end - i > 4
        } else {
            matched.find("//").is_some_and(|at| matched.len() > at + 2)
        };
        let linked = existing
            .iter()
            .any(|e| e.location <= range.location && range.location < e.location + e.length);
        if useful && !linked {
            out.push(LinkRange {
                range,
                url: if bare_www {
                    format!("http://{matched}")
                } else {
                    matched
                },
            });
        }
        i = end.max(i + 1);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(t: &str) -> Span {
        Span::text(t)
    }

    fn code(t: &str) -> Span {
        Span::Code { text: t.to_owned() }
    }

    fn bold(t: &str) -> Span {
        Span::Bold { text: t.to_owned() }
    }

    fn link_span(label: &str, url: &str) -> Span {
        Span::Link {
            label: label.to_owned(),
            url: url.to_owned(),
        }
    }

    /// Cada link como (trecho exibido, url), lendo o texto pelos offsets UTF-16.
    fn shown(text: &str, links: &[LinkRange]) -> Vec<(String, String)> {
        let units: Vec<u16> = text.encode_utf16().collect();
        links
            .iter()
            .map(|l| {
                let slice = &units[l.range.location..l.range.location + l.range.length];
                (String::from_utf16_lossy(slice), l.url.clone())
            })
            .collect()
    }

    #[test]
    fn link_mostra_o_rotulo_e_leva_a_url() {
        assert_eq!(
            spans("veja [o PR](https://github.com/a/b/pull/1) agora"),
            [
                text("veja "),
                link_span("o PR", "https://github.com/a/b/pull/1"),
                text(" agora")
            ]
        );
        let (shown_text, links) = render("veja [o PR](https://x.dev/p)");
        assert_eq!(shown_text, "veja o PR");
        assert_eq!(
            shown(&shown_text, &links),
            [("o PR".to_owned(), "https://x.dev/p".to_owned())]
        );
    }

    #[test]
    fn colchetes_sem_esquema_ficam_texto() {
        assert_eq!(spans("[1](2) e [a] (b)"), [text("[1](2) e [a] (b)")]);
    }

    #[test]
    fn url_solta_vira_link() {
        let plain = "abre http://localhost:3000/x e https://x.dev.";
        let found = linkify(plain, &[]);
        assert_eq!(
            shown(plain, &found)
                .into_iter()
                .map(|(label, _)| label)
                .collect::<Vec<_>>(),
            ["http://localhost:3000/x", "https://x.dev"]
        );
    }

    #[test]
    fn linkify_respeita_o_link_que_ja_existe() {
        let (shown_text, links) = render("[docs](https://x.dev/a)");
        assert_eq!(links.len(), 1);
        assert_eq!(links[0].url, "https://x.dev/a");
        // O rótulo é a própria URL: continua sendo o link que já era.
        let again = "[https://x.dev/a](https://x.dev/a)";
        let (shown_again, own) = render(again);
        let own_ranges: Vec<Utf16Range> = own.iter().map(|l| l.range).collect();
        assert!(linkify(&shown_again, &own_ranges).is_empty());
        assert_eq!(shown_text, "docs");
    }

    #[test]
    fn linkify_pontuacao_www_e_offsets_em_utf16() {
        let plain = "ação: (https://a.dev/x) e www.exemplo.com, fim";
        let found = linkify(plain, &[]);
        assert_eq!(
            shown(plain, &found),
            [
                ("https://a.dev/x".to_owned(), "https://a.dev/x".to_owned()),
                (
                    "www.exemplo.com".to_owned(),
                    "http://www.exemplo.com".to_owned()
                ),
            ]
        );
        // Sem nada depois do esquema não é URL; no meio de palavra também não.
        assert!(linkify("http:// e xhttps://a.dev", &[]).is_empty());
        // Emoji ocupa duas unidades UTF-16: o offset acompanha.
        let emoji = "😀 https://a.dev";
        assert_eq!(
            linkify(emoji, &[])[0].range,
            Utf16Range {
                location: 3,
                length: 13
            }
        );
    }

    #[test]
    fn blocos_titulo_lista_codigo_e_negrito() {
        let source = "## Título\nVou **listar** os `arquivos`.\n\n- um\n- dois\n3. três\n```\nlet x = 1\n```";
        assert_eq!(
            blocks(source),
            [
                Block::Heading {
                    level: 2,
                    spans: vec![text("Título")]
                },
                Block::Paragraph {
                    spans: vec![
                        text("Vou "),
                        bold("listar"),
                        text(" os "),
                        code("arquivos"),
                        text(".")
                    ]
                },
                Block::Bullet {
                    spans: vec![text("um")]
                },
                Block::Bullet {
                    spans: vec![text("dois")]
                },
                Block::Numbered {
                    spans: vec![text("3. três")]
                },
                Block::Code {
                    language: None,
                    text: "let x = 1".to_owned()
                },
            ]
        );
        // `**` dentro de crase é literal; `**` sem par também.
        assert_eq!(
            spans("`a**b` e **solto"),
            [code("a**b"), text(" e **solto")]
        );
        assert_eq!(render("**x**").0, "x");
        assert_eq!(spans("****"), [text("****")], "negrito vazio não é negrito");
    }

    #[test]
    fn bloco_com_rotulo_guarda_a_linguagem() {
        assert_eq!(
            blocks("```python\nx = 1\n```"),
            [Block::Code {
                language: Some("python".to_owned()),
                text: "x = 1".to_owned()
            }]
        );
        // Bloco sem fechamento vale até o fim.
        assert_eq!(
            blocks("```\nsem fim"),
            [Block::Code {
                language: None,
                text: "sem fim".to_owned()
            }]
        );
    }

    #[test]
    fn texto_exibido_separa_blocos_e_poe_marcador_na_lista() {
        let (shown_text, _) = render("# Oi\n- a\n- b\n\n1. x");
        assert_eq!(shown_text, "Oi\n\n•  a\n\n•  b\n\n1. x");
    }

    #[test]
    fn titulo_exige_espaco_e_ate_seis_marcas() {
        assert_eq!(
            blocks("#sem espaço\n####### sete"),
            [Block::Paragraph {
                spans: vec![text("#sem espaço\n####### sete")]
            }]
        );
        assert_eq!(
            blocks("###### seis"),
            [Block::Heading {
                level: 6,
                spans: vec![text("seis")]
            }]
        );
    }

    #[test]
    fn serializa_com_tipo_para_a_ui() {
        let value = serde_json::to_value(spans("a **b**")).expect("json");
        assert_eq!(
            value,
            serde_json::json!([{"kind": "text", "text": "a "}, {"kind": "bold", "text": "b"}])
        );
    }
}

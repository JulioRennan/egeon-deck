//! O texto de link sob uma célula: o link implícito (URL ou caminho) que o
//! SwiftTerm 1.18 acha com a regex do Ghostty, e o nome solto que o
//! `TerminalLink.word` do app de hoje pega quando a regex não acha nada.
//!
//! Porte de `implicitLinkMatch` e vizinhos (`Terminal.swift`) e de
//! `TerminalLink.word` (`TerminalLink.swift`), sem mudar a regra.

use std::sync::LazyLock;

use fancy_regex::Regex;

use crate::line::Cell;

/// Uma linha da vista, como a busca de link a lê.
pub(crate) struct LinkRow {
    pub cells: Vec<Cell>,
    /// A linha continua a de cima, que o terminal quebrou por falta de espaço.
    pub continued: bool,
}

/// Uma célula com a coluna dela; a cauda de um caractere largo não entra.
struct Placed<'a> {
    col: usize,
    width: usize,
    ch: &'a str,
}

fn placed(row: &LinkRow) -> Vec<Placed<'_>> {
    let mut col = 0;
    row.cells
        .iter()
        .map(|c| {
            let p = Placed {
                col,
                width: usize::from(c.width.max(1)),
                ch: c.shown(),
            };
            col += p.width;
            p
        })
        .collect()
}

fn is_blank(ch: &str) -> bool {
    ch.chars().all(char::is_whitespace)
}

/// Até onde a linha tem texto, em colunas (o `getTrimmedLength`).
fn trimmed_len(cells: &[Placed]) -> usize {
    cells
        .iter()
        .rev()
        .find(|c| !is_blank(c.ch))
        .map_or(0, |c| c.col + c.width)
}

// A regex de URL e caminho do Ghostty, na versão para ICU do SwiftTerm, com as
// duas correções de retrocesso catastrófico que ele fez (ver o comentário em
// `ghosttyImplicitLinkRegex`).
static IMPLICIT: LazyLock<Option<Regex>> = LazyLock::new(|| {
    let url_schemes = r"https?://|mailto:|ftp://|file:|ssh:|git://|ssh://|tel:|magnet:|ipfs://|ipns://|gemini://|gopher://|news:";
    let ipv6_url = r"(?:\[[:0-9a-fA-F]+\](?::[0-9]+)?)";
    let scheme_url_chars = r"[\w\-.~:/?#@!$&*+,;=%]";
    let path_chars = r"[\w\-.~:\/?#@!$&*+;=%]";
    let no_trailing_punctuation = r"(?<![,.])";
    let no_trailing_colon = r"(?<!:)";
    let trailing_spaces_at_eol = r"(?: +(?= *$))?";
    let dotted_path_lookahead = r"(?=[\w\-.~:\/?#@!$&*+;=%]*\.)";
    let non_dotted_path_lookahead = r"(?![\w\-.~:\/?#@!$&*+;=%]*\.)";
    let dotted_path_space_segments = r"(?:(?<!:) (?!\w+:\/\/)[\w\-.~:\/?#@!$&*+;=%]*[\/.])*";
    let any_path_space_segments = r"(?:(?<!:) (?!\w+:\/\/)[\w\-.~:\/?#@!$&*+;=%]+)*";
    let bracketed_word_suffix = r"(?:[\(\[]\w*[\)\]])";
    let scheme_url_token = format!("(?:{ipv6_url}|{scheme_url_chars}(?:{bracketed_word_suffix})?)");
    let scheme_url_branch =
        format!("(?:{url_schemes}){scheme_url_token}+{no_trailing_punctuation}");
    let rooted_or_relative_prefix = r"(?:\.\.\/|\.\/|(?<!\w)~\/|(?:[\w][\w\-.]*\/)*(?<!\w)\$[A-Za-z_]\w*\/|\.[\w][\w\-.]*\/|(?<![\w~\/])\/(?!\/))";
    let rooted_or_relative_branch = format!(
        "{rooted_or_relative_prefix}(?:{dotted_path_lookahead}{path_chars}+{dotted_path_space_segments}{no_trailing_colon}{trailing_spaces_at_eol}|{non_dotted_path_lookahead}{path_chars}+{any_path_space_segments}{no_trailing_colon}{trailing_spaces_at_eol})"
    );
    let bare_relative_prefix = r"(?<!\w)[\w][\w\-.]*\/";
    let bare_relative_branch = format!(
        "{dotted_path_lookahead}{bare_relative_prefix}{path_chars}+{dotted_path_space_segments}{no_trailing_colon}{trailing_spaces_at_eol}"
    );
    Regex::new(&format!(
        "{scheme_url_branch}|{rooted_or_relative_branch}|{bare_relative_branch}"
    ))
    .ok()
});

/// Os casamentos da regex em `text`, em bytes. O Ghostty usa `(?<!\$\d*)`, que
/// o ICU não tem; o SwiftTerm descarta o casamento precedido de `$`, e aqui
/// também. Erro da regex (limite de retrocesso) conta como não ter achado.
fn matches(text: &str) -> Vec<(usize, usize)> {
    let Some(re) = IMPLICIT.as_ref() else {
        return Vec::new();
    };
    re.find_iter(text)
        .map_while(Result::ok)
        .filter(|m| m.start() < m.end() && !text[..m.start()].ends_with('$'))
        .map(|m| (m.start(), m.end()))
        .collect()
}

const CONTINUATION: &str =
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:/?#[]@!$&*+,;=%()";

struct Edges<'a> {
    first_col: usize,
    first: &'a str,
    last_col: usize,
    last: &'a str,
}

fn edges<'a>(cells: &'a [Placed<'a>]) -> Option<Edges<'a>> {
    let limit = trimmed_len(cells);
    let inside = || {
        cells
            .iter()
            .filter(move |c| c.col < limit && !is_blank(c.ch))
    };
    let first = inside().next()?;
    let last = inside().next_back()?;
    Some(Edges {
        first_col: first.col,
        first: first.ch,
        last_col: last.col,
        last: last.ch,
    })
}

fn segment(cells: &[Placed], start: usize, end: usize) -> String {
    cells
        .iter()
        .filter(|c| c.col >= start && c.col < end)
        .map(|c| c.ch)
        .collect()
}

/// As duas linhas parecem um link que a TUI quebrou na borda (o terminal não
/// marcou a quebra): a de cima chega perto da borda direita, a emenda é de
/// caracteres de URL, e a regex casa um link atravessando a emenda.
fn can_join(rows: &[Vec<Placed>], upper: usize, lower: usize, cols: usize) -> bool {
    let (Some(up), Some(low)) = (edges(&rows[upper]), edges(&rows[lower])) else {
        return false;
    };
    let threshold = cols.saturating_sub(2.max(cols / 5));
    if up.last_col < threshold {
        return false;
    }
    let continues = |s: &str| !s.is_empty() && s.chars().all(|c| CONTINUATION.contains(c));
    if !continues(up.last) || !continues(low.first) {
        return false;
    }

    let upper_limit = cols.min(up.last_col + 1);
    let upper_text = segment(&rows[upper], upper_limit.saturating_sub(96), upper_limit);
    let lower_limit = trimmed_len(&rows[lower]);
    if upper_text.is_empty() || low.first_col >= lower_limit {
        return false;
    }
    let lower_text = segment(
        &rows[lower],
        low.first_col,
        lower_limit.min(low.first_col + 96),
    );
    if lower_text.is_empty() {
        return false;
    }
    let seam = upper_text.len();
    let candidate = upper_text + &lower_text;
    matches(&candidate)
        .into_iter()
        .any(|(start, end)| start < seam && end > seam)
}

/// O link implícito que cobre a célula `(row, col)` da vista, se houver.
pub(crate) fn implicit(rows: &[LinkRow], cols: u16, row: usize, col: u16) -> Option<String> {
    let cols = usize::from(cols);
    let col = usize::from(col);
    let grid: Vec<Vec<Placed>> = rows.iter().map(placed).collect();
    if grid.get(row)?.is_empty() {
        return None;
    }

    let (mut start, mut end) = (row, row);
    while start > 0 && rows[start].continued {
        start -= 1;
    }
    while end + 1 < rows.len() && rows[end + 1].continued {
        end += 1;
    }
    if start == row && end == row {
        while start > 0 && can_join(&grid, start - 1, start, cols) {
            start -= 1;
        }
        while end + 1 < rows.len() && can_join(&grid, end, end + 1, cols) {
            end += 1;
        }
    }

    // O texto da linha lógica e, para cada célula dele, onde ela está.
    let mut text = String::new();
    let mut map: Vec<(usize, usize, usize, usize)> = Vec::new(); // (byte, row, col, width)
    let mut target_inside = false;
    for (r, cells) in grid.iter().enumerate().take(end + 1).skip(start) {
        let limit = trimmed_len(cells);
        if limit == 0 {
            continue;
        }
        let continuation = r > start && (rows[r].continued || can_join(&grid, r - 1, r, cols));
        let first = if continuation {
            cells
                .iter()
                .find(|c| c.col < limit && !is_blank(c.ch))
                .map_or(limit, |c| c.col)
        } else {
            0
        };
        if first >= limit {
            continue;
        }
        if r == row && col >= first && col < limit {
            target_inside = true;
        }
        for c in cells.iter().filter(|c| c.col >= first && c.col < limit) {
            map.push((text.len(), r, c.col, c.width));
            text.push_str(c.ch);
        }
    }
    if text.is_empty() || !target_inside {
        return None;
    }

    for (s, e) in matches(&text) {
        let covered = map
            .iter()
            .filter(|(byte, ..)| *byte >= s && *byte < e)
            .any(|&(_, r, c, w)| r == row && col >= c && col < c + w);
        if covered {
            return Some(text[s..e].to_owned());
        }
    }
    None
}

/// A palavra sob a coluna, para o ⌘-clique num nome solto (`README.md`,
/// `main.swift:42`) que a regex não pega, porque exige barra. Palavra é o que
/// cabe num caminho; sem ponto nem barra é palavra comum, não arquivo.
pub(crate) fn word(line: &str, column: usize) -> Option<String> {
    let chars: Vec<char> = line.chars().collect();
    if column >= chars.len() || !is_path_char(chars[column]) {
        return None;
    }
    let mut start = column;
    let mut end = column;
    while start > 0 && is_path_char(chars[start - 1]) {
        start -= 1;
    }
    while end + 1 < chars.len() && is_path_char(chars[end + 1]) {
        end += 1;
    }
    let word: String = chars[start..=end].iter().collect();
    let word = trimming_prose(&word);
    (word.contains('.') || word.contains('/')).then(|| word.to_owned())
}

fn is_path_char(c: char) -> bool {
    c.is_alphanumeric() || "_-.~/:@+#%".contains(c)
}

/// Tira o que a frase gruda no caminho: aspas, crase, parênteses e a
/// pontuação do fim (`TerminalLink.trimmingProse`).
fn trimming_prose(text: &str) -> &str {
    text.trim_start_matches(|c| "([{<'\"`".contains(c))
        .trim_end_matches(|c| ".,;:!?)]}>'\"`".contains(c))
}

#[cfg(test)]
mod tests {
    use egeon_core::protocol::screen::Style;

    use super::*;

    fn row(text: &str, continued: bool) -> LinkRow {
        LinkRow {
            cells: text
                .chars()
                .map(|c| Cell {
                    text: c.to_string(),
                    width: 1,
                    style: Style::default(),
                })
                .collect(),
            continued,
        }
    }

    // TerminalLinkTests.testWordUnderTheColumn
    #[test]
    fn palavra_sob_a_coluna() {
        let line = "veja README.md, e main.swift:42 (resposta)";
        assert_eq!(word(line, 7).as_deref(), Some("README.md"));
        assert_eq!(word(line, 22).as_deref(), Some("main.swift:42"));
        // Palavra comum, espaço e fora da linha não são arquivo.
        assert_eq!(word(line, 1), None);
        assert_eq!(word(line, 4), None);
        assert_eq!(word(line, 35), None);
        assert_eq!(word(line, 200), None);
    }

    // TerminalLinkTests.testBareNameResolvesThroughTheWord (a metade da palavra;
    // a resolução é do core).
    #[test]
    fn pontuacao_da_frase_sai_da_palavra() {
        assert_eq!(word("abra README.md.", 8).as_deref(), Some("README.md"));
    }

    #[test]
    fn url_e_caminho_sao_achados_pela_coluna() {
        let rows = [row(
            "veja https://example.com/a?b=1, e ./src/main.rs:3 aqui",
            false,
        )];
        assert_eq!(
            implicit(&rows, 80, 0, 10).as_deref(),
            Some("https://example.com/a?b=1")
        );
        assert_eq!(
            implicit(&rows, 80, 0, 40).as_deref(),
            Some("./src/main.rs:3")
        );
        assert_eq!(implicit(&rows, 80, 0, 1), None);
    }

    #[test]
    fn caminho_com_variavel_de_ambiente_e_link() {
        // O ramo `$VAR/` da regex do Ghostty.
        let rows = [row("x $HOME/b.txt", false)];
        assert_eq!(implicit(&rows, 80, 0, 5).as_deref(), Some("$HOME/b.txt"));
    }

    #[test]
    fn linha_quebrada_pelo_terminal_junta() {
        let rows = [
            row("abra /Users/eu/proj", false),
            row("eto/arquivo.md ok", true),
        ];
        let want = Some("/Users/eu/projeto/arquivo.md");
        assert_eq!(implicit(&rows, 19, 0, 8).as_deref(), want);
        assert_eq!(implicit(&rows, 19, 1, 3).as_deref(), want);
    }

    #[test]
    fn quebra_feita_pela_tui_junta_pela_heuristica() {
        // Sem marca de quebra: a de cima vai até a borda e a emenda é um link.
        let rows = [
            row("ver https://example.com/um/caminho", false),
            row("  /longo/demais.html fim", false),
        ];
        assert_eq!(
            implicit(&rows, 34, 1, 5).as_deref(),
            Some("https://example.com/um/caminho/longo/demais.html")
        );
        // Longe da borda não junta.
        assert_eq!(
            implicit(&rows, 80, 1, 5).as_deref(),
            Some("/longo/demais.html")
        );
    }

    #[test]
    fn retrocesso_patologico_nao_trava() {
        let line = format!("https://example.com/a/b/c{}", ".".repeat(200));
        let rows = [row(&line, false)];
        assert_eq!(
            implicit(&rows, 400, 0, 3).as_deref(),
            Some("https://example.com/a/b/c")
        );
    }
}

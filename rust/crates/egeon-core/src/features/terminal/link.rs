//! O que o ⌘-clique no terminal abre: o texto achado na tela vira o arquivo
//! que existe, ou passa como URL. Porte de `TerminalLink.resolve` (o
//! `word` mora na tela, em `egeon-terminal`).

use std::path::{Component, Path, PathBuf};
use std::sync::LazyLock;

use regex::Regex;

use crate::ports::opener::OpenTarget;

static SCHEME: LazyLock<Option<Regex>> =
    LazyLock::new(|| Regex::new(r"^[a-zA-Z][a-zA-Z0-9+.\-]*://").ok());
static LOCATION: LazyLock<Option<Regex>> = LazyLock::new(|| Regex::new(r"(:\d+){1,2}:?$").ok());

/// `directories` em ordem de preferência: a pasta onde o processo da frente
/// está agora, depois a pasta em que o nó abriu. `None` quando nada existe:
/// abrir um caminho que não existe não tem o que mostrar.
pub fn resolve(
    text: &str,
    directories: &[&Path],
    home: &Path,
    exists: impl Fn(&Path) -> bool,
) -> Option<OpenTarget> {
    // O `.whitespaces` do Swift: espaço horizontal (tab, nbsp…), não quebra
    // de linha.
    let raw = text.trim_matches(|c: char| c.is_whitespace() && !is_line_break(c));
    if raw.is_empty() {
        return None;
    }
    // Esquema só com `://` ou dos que o SwiftTerm reconhece sem barra: um
    // `a.swift:42` casaria com "esquema qualquer seguido de `:`".
    let schemed = SCHEME.as_ref().is_some_and(|re| re.is_match(raw))
        || ["mailto:", "tel:", "news:", "magnet:", "file:"]
            .iter()
            .any(|p| raw.starts_with(p));
    if schemed {
        return Some(OpenTarget::Url(raw.to_owned()));
    }

    // O nome cru primeiro: `:` é legal em nome de arquivo, e só quando ele não
    // existe o sufixo é lido como `:linha:coluna`. A pontuação da frase vem
    // depois.
    let trimmed = trimming_prose(raw);
    let mut candidates: Vec<String> = Vec::new();
    for c in [
        raw.to_owned(),
        strip_location(raw),
        trimmed.to_owned(),
        strip_location(trimmed),
    ] {
        if !c.is_empty() && !candidates.contains(&c) {
            candidates.push(c);
        }
    }
    for candidate in candidates {
        let expanded = expand_home(&candidate, home);
        // `has_root`, não `is_absolute`: no Windows o `/x` digitado também é
        // da raiz (do disco atual), como no unix.
        if Path::new(&expanded).has_root() {
            let path = standardize(Path::new(&expanded));
            if exists(&path) {
                return Some(OpenTarget::File(path));
            }
            continue;
        }
        for dir in directories.iter().filter(|d| !d.as_os_str().is_empty()) {
            let path = standardize(&dir.join(&expanded));
            if exists(&path) {
                return Some(OpenTarget::File(path));
            }
        }
    }
    None
}

fn is_line_break(c: char) -> bool {
    matches!(
        c,
        '\n' | '\r' | '\u{0B}' | '\u{0C}' | '\u{85}' | '\u{2028}' | '\u{2029}'
    )
}

/// Tira o que a frase gruda no caminho: aspas, crase, parênteses e a
/// pontuação do fim.
fn trimming_prose(text: &str) -> &str {
    text.trim_start_matches(|c| "([{<'\"`".contains(c))
        .trim_end_matches(|c| ".,;:!?)]}>'\"`".contains(c))
}

/// Sem o `:linha` ou `:linha:coluna` de compilador e grep.
fn strip_location(text: &str) -> String {
    match LOCATION.as_ref() {
        Some(re) => re.replace(text, "").into_owned(),
        None => text.to_owned(),
    }
}

fn expand_home(path: &str, home: &Path) -> String {
    let rest = path
        .strip_prefix("$HOME/")
        .or_else(|| path.strip_prefix("~/"));
    if let Some(rest) = rest {
        return home.join(rest).to_string_lossy().into_owned();
    }
    if path == "~" {
        return home.to_string_lossy().into_owned();
    }
    path.to_owned()
}

/// `standardizingPath`: `.` e `..` resolvidos no texto, sem tocar o disco.
fn standardize(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                if out.parent().is_some() {
                    out.pop();
                }
            }
            other => out.push(other),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    const HOME: &str = "/Users/eu";

    fn resolve_in(text: &str, dirs: &[&str]) -> Option<String> {
        let disk: HashSet<&str> = [
            "/repo/app/Sources/a.swift",
            "/repo/README.md",
            "/repo/weird:1",
            "/Users/eu/notas.md",
        ]
        .into();
        let dirs: Vec<&Path> = dirs.iter().map(Path::new).collect();
        // O disco de mentira é escrito com `/`; no Windows o caminho montado
        // sai com `\`.
        let text_of = |p: &Path| p.to_string_lossy().replace('\\', "/");
        match resolve(text, &dirs, Path::new(HOME), |p| {
            disk.contains(text_of(p).as_str())
        })? {
            OpenTarget::File(p) => Some(text_of(&p)),
            OpenTarget::Url(u) => Some(u),
        }
    }

    fn r(text: &str) -> Option<String> {
        resolve_in(text, &["/repo/app", "/repo"])
    }

    // testRelativePathResolvesAgainstTheDirectoriesInOrder
    #[test]
    fn relativo_resolve_nas_pastas_em_ordem() {
        assert_eq!(
            r("Sources/a.swift").as_deref(),
            Some("/repo/app/Sources/a.swift")
        );
        assert_eq!(
            r("./Sources/a.swift").as_deref(),
            Some("/repo/app/Sources/a.swift")
        );
        // Não está na primeira pasta, está na segunda.
        assert_eq!(r("README.md").as_deref(), Some("/repo/README.md"));
        assert_eq!(
            resolve_in("../README.md", &["/repo/app"]).as_deref(),
            Some("/repo/README.md")
        );
    }

    // testLineAndColumnSuffixIsDropped
    #[test]
    fn sufixo_de_linha_e_coluna_sai() {
        assert_eq!(
            r("Sources/a.swift:42").as_deref(),
            Some("/repo/app/Sources/a.swift")
        );
        assert_eq!(
            r("Sources/a.swift:42:7:").as_deref(),
            Some("/repo/app/Sources/a.swift")
        );
        assert_eq!(
            r("/repo/app/Sources/a.swift:3").as_deref(),
            Some("/repo/app/Sources/a.swift")
        );
    }

    // testAFileWhoseNameEndsInColonDigitsWinsOverTheSuffix
    #[test]
    fn arquivo_com_dois_pontos_no_nome_vence_o_sufixo() {
        assert_eq!(r("/repo/weird:1").as_deref(), Some("/repo/weird:1"));
    }

    // testHomeIsExpanded
    #[test]
    fn home_e_expandida() {
        assert_eq!(r("~/notas.md").as_deref(), Some("/Users/eu/notas.md"));
        assert_eq!(r("$HOME/notas.md").as_deref(), Some("/Users/eu/notas.md"));
    }

    // testMissingFileOpensNothing
    #[test]
    fn arquivo_que_nao_existe_nao_abre_nada() {
        assert_eq!(r("Sources/nao-existe.swift"), None);
        assert_eq!(r("   "), None);
    }

    #[test]
    fn espaco_horizontal_nas_pontas_sai_como_no_swift() {
        assert_eq!(r("\tREADME.md\u{a0}").as_deref(), Some("/repo/README.md"));
        assert_eq!(r("README.md\n"), None);
    }

    // testUrlsPassThroughUntouched
    #[test]
    fn url_passa_intacta() {
        let none = |_: &Path| false;
        let home = Path::new(HOME);
        assert_eq!(
            resolve("https://example.com/a", &[], home, none),
            Some(OpenTarget::Url("https://example.com/a".into()))
        );
        assert_eq!(
            resolve("mailto:x@y.z", &[], home, none),
            Some(OpenTarget::Url("mailto:x@y.z".into()))
        );
    }

    // testProsePunctuationIsDropped
    #[test]
    fn pontuacao_da_frase_sai() {
        assert_eq!(
            r("Sources/a.swift.").as_deref(),
            Some("/repo/app/Sources/a.swift")
        );
        assert_eq!(
            r("Sources/a.swift:42,").as_deref(),
            Some("/repo/app/Sources/a.swift")
        );
        assert_eq!(r("(README.md)").as_deref(), Some("/repo/README.md"));
        assert_eq!(
            r("`Sources/a.swift`").as_deref(),
            Some("/repo/app/Sources/a.swift")
        );
    }

    // testBareNameResolvesThroughTheWord (a metade da resolução; a palavra é
    // achada na tela)
    #[test]
    fn nome_solto_resolve() {
        assert_eq!(r("README.md").as_deref(), Some("/repo/README.md"));
    }
}

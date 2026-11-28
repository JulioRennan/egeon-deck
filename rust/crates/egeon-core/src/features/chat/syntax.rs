//! Realce mínimo, por linha.
//!
//! Tokenizador por regras simples — palavra-chave, tipo (identificador com
//! maiúscula), string, comentário, número; e um modo de marcação para HTML (tag,
//! atributo). Uma linha por vez, sem estado entre linhas: é o que a vista de
//! diff desenha, e é o mesmo limite que o GitHub tinha antes do tree-sitter. Não
//! é um parser: é o suficiente para o olho achar o que mudou. Linguagem nova é
//! uma [`Spec`] a mais (ADR-041).
//!
//! A cor é da UI: aqui sai só o tipo de cada pedaço ([`TokenKind`]).

use serde::{Deserialize, Serialize};

/// Que linguagem é este arquivo. Decidida pela extensão, e só por ela: ler o
/// texto para adivinhar é o que o Linguist do GitHub faz por cima, e não paga o
/// custo aqui — o passo já traz o caminho. Sem extensão conhecida é `Plain`,
/// sem cor.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Language {
    Python,
    Html,
    Dart,
    Typescript,
    Json,
    Swift,
    Shell,
    Plain,
}

impl Language {
    pub fn detect_path(path: &str) -> Language {
        let name = path
            .split(crate::features::path_text::is_separator)
            .rfind(|s| !s.is_empty())
            .unwrap_or(path);
        let Some(dot) = name.rfind('.').filter(|d| *d != 0) else {
            return Language::Plain;
        };
        match name[dot + 1..].to_lowercase().as_str() {
            "py" | "pyi" => Language::Python,
            "html" | "htm" | "xhtml" => Language::Html,
            "dart" => Language::Dart,
            "ts" | "tsx" | "js" | "jsx" | "mjs" | "cjs" => Language::Typescript,
            "json" | "jsonc" => Language::Json,
            "swift" => Language::Swift,
            "sh" | "bash" | "zsh" => Language::Shell,
            _ => Language::Plain,
        }
    }

    /// Pelo rótulo do bloco de código (```python): é a "extensão" da prosa.
    pub fn named(name: &str) -> Language {
        match name.to_lowercase().as_str() {
            "python" | "py" => Language::Python,
            "html" | "htm" => Language::Html,
            "dart" => Language::Dart,
            "typescript" | "ts" | "tsx" | "javascript" | "js" | "jsx" => Language::Typescript,
            "json" | "jsonc" => Language::Json,
            "swift" => Language::Swift,
            "sh" | "bash" | "shell" | "zsh" => Language::Shell,
            _ => Language::Plain,
        }
    }

    /// A linguagem da saída de um comando: a do primeiro arquivo com extensão
    /// conhecida citado nele (`cat config.json`, `head -20 app.py`). Continua
    /// sendo extensão, não leitura do texto (ADR-041).
    pub fn detect_in_command(command: &str) -> Language {
        command
            .split([' ', '\n', '\t'])
            .filter(|w| !w.is_empty())
            .map(|word| Language::detect_path(word.trim_matches(|c| "\"'`;|&()".contains(c))))
            .find(|l| *l != Language::Plain)
            .unwrap_or(Language::Plain)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TokenKind {
    Plain,
    Keyword,
    Type,
    String,
    Comment,
    Number,
    Tag,
    Attribute,
}

/// Um pedaço de uma linha, classificado. `Plain` é o que não tem cor.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Token {
    pub kind: TokenKind,
    pub text: String,
}

fn token(kind: TokenKind, text: impl Into<String>) -> Token {
    Token {
        kind,
        text: text.into(),
    }
}

pub struct Spec {
    keywords: &'static [&'static str],
    line_comment: Option<&'static str>,
    quotes: &'static [char],
    markup: bool,
}

const QUOTES: &[char] = &['"', '\''];
const QUOTES_TICK: &[char] = &['"', '\'', '`'];

const PYTHON: &[&str] = &[
    "def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or",
    "import", "from", "as", "try", "except", "finally", "with", "lambda", "yield", "pass", "break",
    "continue", "raise", "None", "True", "False", "self", "async", "await", "global", "is", "del",
];
const DART: &[&str] = &[
    "class",
    "extends",
    "implements",
    "with",
    "abstract",
    "final",
    "const",
    "var",
    "late",
    "void",
    "return",
    "if",
    "else",
    "for",
    "while",
    "in",
    "switch",
    "case",
    "default",
    "break",
    "continue",
    "new",
    "this",
    "super",
    "import",
    "export",
    "library",
    "part",
    "static",
    "async",
    "await",
    "yield",
    "try",
    "catch",
    "finally",
    "throw",
    "null",
    "true",
    "false",
    "is",
    "as",
    "get",
    "set",
    "override",
    "required",
    "enum",
    "mixin",
    "int",
    "double",
    "bool",
    "String",
    "dynamic",
    "Future",
    "Widget",
];
const TYPESCRIPT: &[&str] = &[
    "const",
    "let",
    "var",
    "function",
    "return",
    "if",
    "else",
    "for",
    "while",
    "do",
    "switch",
    "case",
    "default",
    "break",
    "continue",
    "new",
    "this",
    "class",
    "extends",
    "implements",
    "interface",
    "type",
    "enum",
    "import",
    "export",
    "from",
    "as",
    "async",
    "await",
    "yield",
    "try",
    "catch",
    "finally",
    "throw",
    "null",
    "undefined",
    "true",
    "false",
    "typeof",
    "instanceof",
    "in",
    "of",
    "void",
    "delete",
    "public",
    "private",
    "protected",
    "readonly",
    "static",
    "declare",
    "namespace",
    "string",
    "number",
    "boolean",
    "any",
    "never",
    "unknown",
];
const SWIFT: &[&str] = &[
    "func",
    "var",
    "let",
    "class",
    "struct",
    "enum",
    "protocol",
    "extension",
    "init",
    "deinit",
    "self",
    "super",
    "return",
    "if",
    "else",
    "guard",
    "for",
    "in",
    "while",
    "repeat",
    "switch",
    "case",
    "default",
    "break",
    "continue",
    "fallthrough",
    "where",
    "do",
    "try",
    "catch",
    "throw",
    "throws",
    "rethrows",
    "defer",
    "import",
    "typealias",
    "associatedtype",
    "some",
    "any",
    "as",
    "is",
    "nil",
    "true",
    "false",
    "public",
    "private",
    "fileprivate",
    "internal",
    "open",
    "static",
    "final",
    "lazy",
    "weak",
    "unowned",
    "override",
    "mutating",
    "inout",
    "async",
    "await",
    "actor",
    "convenience",
    "required",
    "subscript",
    "willSet",
    "didSet",
    "get",
    "set",
    "operator",
    "indirect",
];
const SHELL: &[&str] = &[
    "if", "then", "elif", "else", "fi", "for", "in", "do", "done", "while", "until", "case",
    "esac", "function", "return", "local", "export", "set", "unset", "echo", "cd", "exit",
    "source", "trap", "read", "shift", "eval", "true", "false",
];
const JSON: &[&str] = &["true", "false", "null"];

pub fn spec_for(language: Language) -> Option<Spec> {
    let code = |keywords, line_comment, quotes| Spec {
        keywords,
        line_comment,
        quotes,
        markup: false,
    };
    match language {
        Language::Python => Some(code(PYTHON, Some("#"), QUOTES)),
        Language::Dart => Some(code(DART, Some("//"), QUOTES)),
        Language::Typescript => Some(code(TYPESCRIPT, Some("//"), QUOTES_TICK)),
        Language::Swift => Some(code(SWIFT, Some("//"), QUOTES)),
        Language::Shell => Some(code(SHELL, Some("#"), QUOTES_TICK)),
        Language::Json => Some(code(JSON, None, QUOTES)),
        Language::Html => Some(Spec {
            keywords: &[],
            line_comment: None,
            quotes: QUOTES,
            markup: true,
        }),
        Language::Plain => None,
    }
}

pub fn tokens(line: &str, language: Language) -> Vec<Token> {
    match spec_for(language) {
        None => vec![token(TokenKind::Plain, line)],
        Some(spec) if spec.markup => markup(line),
        Some(spec) => code(line, &spec),
    }
}

fn is_word(c: char) -> bool {
    c.is_alphabetic() || c.is_numeric() || c == '_' || c == '$'
}

fn has_prefix(chars: &[char], at: usize, prefix: &str) -> bool {
    prefix
        .chars()
        .enumerate()
        .all(|(k, p)| chars.get(at + k) == Some(&p))
}

fn collect(chars: &[char], from: usize, to: usize) -> String {
    chars[from..to].iter().collect()
}

fn code(line: &str, spec: &Spec) -> Vec<Token> {
    let mut out: Vec<Token> = Vec::new();
    let mut plain = String::new();
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;

    fn flush(out: &mut Vec<Token>, plain: &mut String) {
        if !plain.is_empty() {
            out.push(token(TokenKind::Plain, std::mem::take(plain)));
        }
    }

    while i < chars.len() {
        let c = chars[i];
        if let Some(comment) = spec.line_comment
            && has_prefix(&chars, i, comment)
        {
            flush(&mut out, &mut plain);
            out.push(token(TokenKind::Comment, collect(&chars, i, chars.len())));
            return out;
        }
        if spec.quotes.contains(&c) {
            flush(&mut out, &mut plain);
            let mut j = i + 1;
            while j < chars.len() && chars[j] != c {
                if chars[j] == '\\' {
                    j += 1;
                }
                j += 1;
            }
            let end = (j + 1).min(chars.len());
            out.push(token(TokenKind::String, collect(&chars, i, end)));
            i = end;
            continue;
        }
        if c.is_numeric() && (i == 0 || !is_word(chars[i - 1])) {
            flush(&mut out, &mut plain);
            let mut j = i;
            while j < chars.len() && (chars[j].is_numeric() || chars[j] == '.' || chars[j] == '_') {
                j += 1;
            }
            out.push(token(TokenKind::Number, collect(&chars, i, j)));
            i = j;
            continue;
        }
        if is_word(c) && !c.is_numeric() {
            let mut j = i;
            while j < chars.len() && is_word(chars[j]) {
                j += 1;
            }
            let word = collect(&chars, i, j);
            if spec.keywords.contains(&word.as_str()) {
                flush(&mut out, &mut plain);
                out.push(token(TokenKind::Keyword, word));
            } else if c.is_uppercase() && word.chars().count() > 1 {
                flush(&mut out, &mut plain);
                out.push(token(TokenKind::Type, word));
            } else {
                plain.push_str(&word);
            }
            i = j;
            continue;
        }
        plain.push(c);
        i += 1;
    }
    flush(&mut out, &mut plain);
    out
}

/// Fora de tag é texto; `<!-- … -->` é comentário; `<nome` e `>` são tag; dentro
/// da tag, palavra é atributo e aspas são valor.
fn markup(line: &str) -> Vec<Token> {
    let mut out: Vec<Token> = Vec::new();
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;
    let mut text = String::new();

    fn flush(out: &mut Vec<Token>, text: &mut String) {
        if !text.is_empty() {
            out.push(token(TokenKind::Plain, std::mem::take(text)));
        }
    }
    let name_char = |c: char| is_word(c) || c == '-' || c == ':';
    let attr_char = |c: char| name_char(c) || c == '@';

    while i < chars.len() {
        if has_prefix(&chars, i, "<!--") {
            flush(&mut out, &mut text);
            let mut j = i + 4;
            while j < chars.len() && !has_prefix(&chars, j, "-->") {
                j += 1;
            }
            let end = (j + 3).min(chars.len());
            out.push(token(TokenKind::Comment, collect(&chars, i, end)));
            i = end;
            continue;
        }
        if chars[i] == '<' {
            flush(&mut out, &mut text);
            let mut j = i + 1;
            if chars.get(j) == Some(&'/') {
                j += 1;
            }
            while j < chars.len() && name_char(chars[j]) {
                j += 1;
            }
            out.push(token(TokenKind::Tag, collect(&chars, i, j)));
            i = j;
            // Dentro da tag até o `>`.
            while i < chars.len() && chars[i] != '>' {
                let c = chars[i];
                if c == '"' || c == '\'' {
                    let mut k = i + 1;
                    while k < chars.len() && chars[k] != c {
                        k += 1;
                    }
                    let end = (k + 1).min(chars.len());
                    out.push(token(TokenKind::String, collect(&chars, i, end)));
                    i = end;
                } else if attr_char(c) {
                    let mut k = i;
                    while k < chars.len() && attr_char(chars[k]) {
                        k += 1;
                    }
                    out.push(token(TokenKind::Attribute, collect(&chars, i, k)));
                    i = k;
                } else {
                    out.push(token(TokenKind::Plain, c.to_string()));
                    i += 1;
                }
            }
            if i < chars.len() {
                out.push(token(TokenKind::Tag, ">"));
                i += 1;
            }
            continue;
        }
        text.push(chars[i]);
        i += 1;
    }
    flush(&mut out, &mut text);
    merged(out)
}

/// Tokens vizinhos do mesmo tipo viram um só: menos coisa para desenhar.
fn merged(tokens: Vec<Token>) -> Vec<Token> {
    let mut out: Vec<Token> = Vec::new();
    for t in tokens {
        match out.last_mut() {
            Some(last) if last.kind == t.kind => last.text.push_str(&t.text),
            _ => out.push(t),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::chat::markdown::{self, Block};

    fn of_kind(tokens: &[Token], kind: TokenKind) -> Vec<&str> {
        tokens
            .iter()
            .filter(|t| t.kind == kind)
            .map(|t| t.text.as_str())
            .collect()
    }

    fn has(tokens: &[Token], kind: TokenKind, text: &str) -> bool {
        tokens.contains(&token(kind, text))
    }

    #[test]
    fn linguagem_vem_so_da_extensao() {
        assert_eq!(Language::detect_path("app/main.py"), Language::Python);
        assert_eq!(
            Language::detect_path("lib/widgets/home.dart"),
            Language::Dart
        );
        assert_eq!(Language::detect_path("src/App.tsx"), Language::Typescript);
        assert_eq!(Language::detect_path("index.HTML"), Language::Html);
        assert_eq!(Language::detect_path("config.json"), Language::Json);
        assert_eq!(
            Language::detect_path("Sources/EgeonDeck/ChatBlock.swift"),
            Language::Swift
        );
        assert_eq!(Language::detect_path("app/dev.sh"), Language::Shell);
        assert_eq!(Language::detect_path("Makefile"), Language::Plain);
        assert_eq!(Language::detect_path(".env"), Language::Plain);
    }

    #[test]
    fn linguagem_pelo_rotulo_e_pelo_comando() {
        assert_eq!(Language::named("python"), Language::Python);
        assert_eq!(Language::named("TS"), Language::Typescript);
        assert_eq!(Language::named("swift"), Language::Swift);
        assert_eq!(Language::named("bash"), Language::Shell);
        assert_eq!(Language::named("cobol"), Language::Plain);
        assert_eq!(
            Language::detect_in_command("cat app/build/x/config.json"),
            Language::Json
        );
        assert_eq!(
            Language::detect_in_command("head -20 'lib/main.dart' | grep x"),
            Language::Dart
        );
        assert_eq!(Language::detect_in_command("ls -la"), Language::Plain);
        // O passo de leitura: a linguagem sai do arquivo citado no título.
        assert_eq!(
            Language::detect_in_command("read Chat/Models/ChatBlock.swift"),
            Language::Swift
        );
        assert_eq!(
            Language::detect_in_command("git log --oneline -2"),
            Language::Plain
        );
    }

    #[test]
    fn tokens_de_swift_e_shell() {
        let swift = tokens("private let name = \"oi\"  // nota", Language::Swift);
        assert_eq!(of_kind(&swift, TokenKind::Keyword), ["private", "let"]);
        assert_eq!(of_kind(&swift, TokenKind::String), ["\"oi\""]);
        assert_eq!(of_kind(&swift, TokenKind::Comment), ["// nota"]);

        let shell = tokens("for f in *.swift; do echo 1; done  # laço", Language::Shell);
        assert_eq!(
            of_kind(&shell, TokenKind::Keyword),
            ["for", "in", "do", "echo", "done"]
        );
        assert_eq!(of_kind(&shell, TokenKind::Comment), ["# laço"]);
    }

    #[test]
    fn bloco_cercado_guarda_o_rotulo() {
        assert_eq!(
            markdown::blocks("```python\nx = 1\n```"),
            [Block::Code {
                language: Some("python".into()),
                text: "x = 1".into()
            }]
        );
    }

    #[test]
    fn python() {
        let toks = tokens("def load(path: str) -> None:  # abre", Language::Python);
        assert_eq!(toks.first(), Some(&token(TokenKind::Keyword, "def")));
        assert!(has(&toks, TokenKind::Keyword, "None"));
        assert_eq!(toks.last(), Some(&token(TokenKind::Comment, "# abre")));
        assert!(
            of_kind(
                &tokens("x = \"a # não é comentário\"", Language::Python),
                TokenKind::Comment
            )
            .is_empty()
        );
    }

    #[test]
    fn typescript_e_dart() {
        let ts = tokens(
            "const total: number = items.length + 2; // soma",
            Language::Typescript,
        );
        assert_eq!(ts.first(), Some(&token(TokenKind::Keyword, "const")));
        assert!(has(&ts, TokenKind::Number, "2"));
        assert_eq!(ts.last(), Some(&token(TokenKind::Comment, "// soma")));
        assert!(has(
            &tokens("const s = `tpl ${x}`;", Language::Typescript),
            TokenKind::String,
            "`tpl ${x}`"
        ));
        let dart = tokens("final Widget child = Text('oi');", Language::Dart);
        assert_eq!(dart[0], token(TokenKind::Keyword, "final"));
        assert!(has(&dart, TokenKind::Type, "Text"));
        assert!(has(&dart, TokenKind::String, "'oi'"));
    }

    #[test]
    fn html() {
        let toks = tokens("<a href=\"/x\" class='b'>Oi</a><!-- c -->", Language::Html);
        assert_eq!(toks[0], token(TokenKind::Tag, "<a"));
        assert!(has(&toks, TokenKind::Attribute, "href"));
        assert!(has(&toks, TokenKind::String, "\"/x\""));
        assert!(has(&toks, TokenKind::Plain, "Oi"));
        assert!(has(&toks, TokenKind::Tag, "</a>"));
        assert_eq!(toks.last(), Some(&token(TokenKind::Comment, "<!-- c -->")));
    }

    #[test]
    fn json_e_plain() {
        let json = tokens("  \"debug\": true, \"port\": 8392,", Language::Json);
        assert!(has(&json, TokenKind::String, "\"debug\""));
        assert!(has(&json, TokenKind::Keyword, "true"));
        assert!(has(&json, TokenKind::Number, "8392"));
        assert_eq!(
            tokens("qualquer coisa", Language::Plain),
            [token(TokenKind::Plain, "qualquer coisa")]
        );
        // Identificador com dígito não é número: `x2` fica inteiro.
        assert_eq!(
            tokens("x2 = 3", Language::Python),
            [
                token(TokenKind::Plain, "x2 = "),
                token(TokenKind::Number, "3")
            ]
        );
    }

    #[test]
    fn string_sem_fechar_vai_ate_o_fim_da_linha() {
        let toks = tokens("x = \"abre \\\" e nunca fecha", Language::Python);
        assert_eq!(
            toks.last(),
            Some(&token(TokenKind::String, "\"abre \\\" e nunca fecha"))
        );
    }
}

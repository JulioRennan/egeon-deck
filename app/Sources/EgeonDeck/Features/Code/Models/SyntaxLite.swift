import Foundation

// MARK: - Realce mínimo, por linha

/// Um pedaço de uma linha, classificado. `plain` é o que não tem cor.
struct Token: Equatable {
    enum Kind: Equatable { case plain, keyword, type, string, comment, number, tag, attribute }
    let kind: Kind
    let text: String
}

/// Tokenizador por regras simples — palavra-chave, tipo (identificador com
/// maiúscula), string, comentário, número; e um modo de marcação para HTML
/// (tag, atributo). Uma linha por vez, sem estado entre linhas: é o que a
/// vista de diff desenha, e é o mesmo limite que o GitHub tinha antes do
/// tree-sitter. Não é um parser: é o suficiente para o olho achar o que
/// mudou. Linguagem nova é uma `Spec` a mais (ADR-041).
enum SyntaxLite {
    struct Spec {
        var keywords: Set<String> = []
        var lineComment: String? = nil
        var quotes: Set<Character> = ["\"", "'"]
        var markup = false
    }

    static func spec(for language: Language) -> Spec? {
        switch language {
        case .python:
            return Spec(keywords: ["def", "class", "return", "if", "elif", "else", "for", "while", "in",
                                   "not", "and", "or", "import", "from", "as", "try", "except", "finally",
                                   "with", "lambda", "yield", "pass", "break", "continue", "raise",
                                   "None", "True", "False", "self", "async", "await", "global", "is", "del"],
                        lineComment: "#")
        case .dart:
            return Spec(keywords: ["class", "extends", "implements", "with", "abstract", "final", "const",
                                   "var", "late", "void", "return", "if", "else", "for", "while", "in",
                                   "switch", "case", "default", "break", "continue", "new", "this", "super",
                                   "import", "export", "library", "part", "static", "async", "await",
                                   "yield", "try", "catch", "finally", "throw", "null", "true", "false",
                                   "is", "as", "get", "set", "override", "required", "enum", "mixin",
                                   "int", "double", "bool", "String", "dynamic", "Future", "Widget"],
                        lineComment: "//")
        case .typescript:
            return Spec(keywords: ["const", "let", "var", "function", "return", "if", "else", "for",
                                   "while", "do", "switch", "case", "default", "break", "continue", "new",
                                   "this", "class", "extends", "implements", "interface", "type", "enum",
                                   "import", "export", "from", "as", "async", "await", "yield", "try",
                                   "catch", "finally", "throw", "null", "undefined", "true", "false",
                                   "typeof", "instanceof", "in", "of", "void", "delete", "public",
                                   "private", "protected", "readonly", "static", "declare", "namespace",
                                   "string", "number", "boolean", "any", "never", "unknown"],
                        lineComment: "//", quotes: ["\"", "'", "`"])
        case .json:
            return Spec(keywords: ["true", "false", "null"])
        case .html:
            return Spec(markup: true)
        case .plain:
            return nil
        }
    }

    static func tokens(_ line: String, language: Language) -> [Token] {
        guard let spec = spec(for: language) else { return [Token(kind: .plain, text: line)] }
        return spec.markup ? markup(line) : code(line, spec: spec)
    }

    // MARK: Código

    private static func code(_ line: String, spec: Spec) -> [Token] {
        var out: [Token] = []
        var plain = ""
        let chars = Array(line)
        var i = 0

        func flush() {
            if !plain.isEmpty { out.append(Token(kind: .plain, text: plain)); plain = "" }
        }

        while i < chars.count {
            let c = chars[i]
            if let comment = spec.lineComment, hasPrefix(chars, at: i, comment) {
                flush()
                out.append(Token(kind: .comment, text: String(chars[i...])))
                return out
            }
            if spec.quotes.contains(c) {
                flush()
                var j = i + 1
                while j < chars.count, chars[j] != c {
                    if chars[j] == "\\" { j += 1 }
                    j += 1
                }
                let end = min(j + 1, chars.count)
                out.append(Token(kind: .string, text: String(chars[i..<end])))
                i = end
                continue
            }
            if c.isNumber, i == 0 || !isWord(chars[i - 1]) {
                flush()
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." || chars[j] == "_" { j += 1 }
                out.append(Token(kind: .number, text: String(chars[i..<j])))
                i = j
                continue
            }
            if isWord(c), !c.isNumber {
                var j = i
                while j < chars.count, isWord(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                if spec.keywords.contains(word) {
                    flush(); out.append(Token(kind: .keyword, text: word))
                } else if word.first?.isUppercase == true, word.count > 1 {
                    flush(); out.append(Token(kind: .type, text: word))
                } else {
                    plain += word
                }
                i = j
                continue
            }
            plain.append(c)
            i += 1
        }
        flush()
        return out
    }

    // MARK: Marcação (HTML)

    /// Fora de tag é texto; `<!-- … -->` é comentário; `<nome` e `>` são tag;
    /// dentro da tag, palavra é atributo e aspas são valor.
    private static func markup(_ line: String) -> [Token] {
        var out: [Token] = []
        let chars = Array(line)
        var i = 0
        var text = ""

        func flush() {
            if !text.isEmpty { out.append(Token(kind: .plain, text: text)); text = "" }
        }

        while i < chars.count {
            if hasPrefix(chars, at: i, "<!--") {
                flush()
                var j = i + 4
                while j < chars.count, !hasPrefix(chars, at: j, "-->") { j += 1 }
                let end = min(j + 3, chars.count)
                out.append(Token(kind: .comment, text: String(chars[i..<end])))
                i = end
                continue
            }
            if chars[i] == "<" {
                flush()
                var j = i + 1
                if j < chars.count, chars[j] == "/" { j += 1 }
                while j < chars.count, isWord(chars[j]) || chars[j] == "-" || chars[j] == ":" { j += 1 }
                out.append(Token(kind: .tag, text: String(chars[i..<j])))
                i = j
                // Dentro da tag até o `>`.
                while i < chars.count, chars[i] != ">" {
                    let c = chars[i]
                    if c == "\"" || c == "'" {
                        var k = i + 1
                        while k < chars.count, chars[k] != c { k += 1 }
                        let end = min(k + 1, chars.count)
                        out.append(Token(kind: .string, text: String(chars[i..<end])))
                        i = end
                    } else if isWord(c) || c == "-" || c == ":" || c == "@" {
                        var k = i
                        while k < chars.count, isWord(chars[k]) || chars[k] == "-" || chars[k] == ":" || chars[k] == "@" { k += 1 }
                        out.append(Token(kind: .attribute, text: String(chars[i..<k])))
                        i = k
                    } else {
                        out.append(Token(kind: .plain, text: String(c)))
                        i += 1
                    }
                }
                if i < chars.count {
                    out.append(Token(kind: .tag, text: ">"))
                    i += 1
                }
                continue
            }
            text.append(chars[i])
            i += 1
        }
        flush()
        return merged(out)
    }

    /// Tokens vizinhos do mesmo tipo viram um só: menos coisa para desenhar.
    private static func merged(_ tokens: [Token]) -> [Token] {
        var out: [Token] = []
        for token in tokens {
            if let last = out.last, last.kind == token.kind {
                out[out.count - 1] = Token(kind: last.kind, text: last.text + token.text)
            } else {
                out.append(token)
            }
        }
        return out
    }

    private static func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }

    private static func hasPrefix(_ chars: [Character], at i: Int, _ prefix: String) -> Bool {
        let p = Array(prefix)
        guard i + p.count <= chars.count else { return false }
        return Array(chars[i..<(i + p.count)]) == p
    }
}

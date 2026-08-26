import AppKit

// MARK: - Markdown mínimo para a bolha

/// O agente escreve Markdown, e a TUI renderiza; a bolha mostrava os
/// asteriscos. Isto cobre o que aparece em resposta de agente — negrito,
/// código inline, título, lista, bloco de código — e nada mais: link, tabela
/// e imagem ficam como texto. Não é um parser de Markdown; é o suficiente
/// para a bolha ler como o terminal (ADR-039).
enum MarkdownLite {
    enum Span: Equatable {
        case text(String)
        case bold(String)
        case code(String)
    }

    enum Block: Equatable {
        case paragraph([Span])
        case heading(level: Int, spans: [Span])
        case bullet([Span])
        /// "1. item" — o número já é o marcador; não ganha "•".
        case numbered([Span])
        /// O rótulo do fence (```python) é a linguagem; sem rótulo, sem cor.
        case code(language: String?, text: String)
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var fence: [String]?
        var fenceLanguage: String?

        func flush() {
            guard !paragraph.isEmpty else { return }
            out.append(.paragraph(spans(paragraph.joined(separator: "\n"))))
            paragraph = []
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let open = fence {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    out.append(.code(language: fenceLanguage, text: open.joined(separator: "\n")))
                    fence = nil
                } else {
                    fence = open + [line]
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                fence = []
                let label = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                fenceLanguage = label.isEmpty ? nil : label
            } else if trimmed.isEmpty {
                flush()
            } else if let heading = heading(trimmed) {
                flush()
                out.append(heading)
            } else if let item = bullet(trimmed) {
                flush()
                out.append(item)
            } else {
                paragraph.append(line)
            }
        }
        if let fence { out.append(.code(language: fenceLanguage, text: fence.joined(separator: "\n"))) }
        flush()
        return out
    }

    private static func heading(_ line: String) -> Block? {
        var level = 0
        for char in line { if char == "#" { level += 1 } else { break } }
        guard level > 0, level <= 6, line.dropFirst(level).first == " " else { return nil }
        return .heading(level: level, spans: spans(String(line.dropFirst(level + 1))))
    }

    private static func bullet(_ line: String) -> Block? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return .bullet(spans(String(line.dropFirst(2))))
        }
        // "1. item" — o número fica: a ordem é parte do que foi dito.
        var digits = 0
        for char in line { if char.isNumber { digits += 1 } else { break } }
        if digits > 0, line.dropFirst(digits).hasPrefix(". ") { return .numbered(spans(line)) }
        return nil
    }

    /// `**negrito**` e `` `código` `` dentro de uma linha. Código ganha do
    /// negrito: `**` dentro de crase é literal.
    static func spans(_ text: String) -> [Span] {
        var out: [Span] = []
        var plain = ""
        var index = text.startIndex

        func flushPlain() {
            if !plain.isEmpty { out.append(.text(plain)); plain = "" }
        }

        while index < text.endIndex {
            let char = text[index]
            if char == "`", let close = text[text.index(after: index)...].firstIndex(of: "`") {
                flushPlain()
                out.append(.code(String(text[text.index(after: index)..<close])))
                index = text.index(after: close)
            } else if text[index...].hasPrefix("**"),
                      let close = text.range(of: "**", range: text.index(index, offsetBy: 2)..<text.endIndex),
                      close.lowerBound > text.index(index, offsetBy: 2) {
                flushPlain()
                out.append(.bold(String(text[text.index(index, offsetBy: 2)..<close.lowerBound])))
                index = close.upperBound
            } else {
                plain.append(char)
                index = text.index(after: index)
            }
        }
        flushPlain()
        return out
    }

    /// O texto atribuído, com a fonte e a cor base da bolha.
    static func render(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        render(blocks(text), font: font, color: color)
    }

    /// Um bloco de código sozinho, já colorido pelo rótulo — para a bolha pôr
    /// numa caixa própria, como a de um passo.
    static func renderCode(_ language: String?, _ code: String, font: NSFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lang = language.map(Language.named) ?? .plain
        let base = NSColor(calibratedWhite: 0.78, alpha: 1)
        for (n, l) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if n > 0 { out.append(NSAttributedString(string: "\n", attributes: [.font: font])) }
            out.append(CodePalette.attributed(String(l), language: lang, font: font, base: base))
        }
        return out
    }

    static func render(_ blocks: [Block], font: NSFont, color: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
        let codeColor = NSColor(calibratedRed: 0.85, green: 0.78, blue: 0.62, alpha: 1)

        func append(_ spans: [Span], base: NSFont) {
            for span in spans {
                switch span {
                case .text(let s):
                    out.append(NSAttributedString(string: s, attributes: [.font: base, .foregroundColor: color]))
                case .bold(let s):
                    let bold = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
                    out.append(NSAttributedString(string: s, attributes: [.font: bold, .foregroundColor: color]))
                case .code(let s):
                    out.append(NSAttributedString(string: s, attributes: [.font: mono, .foregroundColor: codeColor]))
                }
            }
        }

        for (i, block) in blocks.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n\n", attributes: [.font: font])) }
            switch block {
            case .paragraph(let spans):
                append(spans, base: font)
            case .heading(let level, let spans):
                let size = font.pointSize + max(0, CGFloat(4 - level)) * 1.5
                append(spans, base: .boldSystemFont(ofSize: size))
            case .bullet(let spans):
                out.append(NSAttributedString(string: "•  ", attributes: [.font: font, .foregroundColor: color]))
                append(spans, base: font)
            case .numbered(let spans):
                append(spans, base: font)
            case .code(let language, let code):
                let lang = language.map(Language.named) ?? .plain
                for (n, l) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    if n > 0 { out.append(NSAttributedString(string: "\n", attributes: [.font: mono])) }
                    out.append(CodePalette.attributed(String(l), language: lang, font: mono, base: codeColor))
                }
            }
        }
        return out
    }
}

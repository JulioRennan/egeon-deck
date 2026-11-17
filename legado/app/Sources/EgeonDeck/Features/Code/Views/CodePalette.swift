import AppKit

// MARK: - A cor de cada token, e a linha já atribuída

/// Uma paleta só para tudo que mostra código como texto — diff, saída de
/// comando, bloco de código da prosa. Discreta de propósito: onde há fundo
/// verde/vermelho, o fundo diz o que mudou e a cor diz o que é.
enum CodePalette {
    static func color(for kind: Token.Kind, base: NSColor) -> NSColor {
        switch kind {
        case .plain:     return base
        case .keyword:   return NSColor(calibratedRed: 0.80, green: 0.58, blue: 0.96, alpha: 1)
        case .type:      return NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.85, alpha: 1)
        case .string:    return NSColor(calibratedRed: 0.87, green: 0.78, blue: 0.60, alpha: 1)
        case .comment:   return NSColor(calibratedWhite: 0.48, alpha: 1)
        case .number:    return NSColor(calibratedRed: 0.90, green: 0.68, blue: 0.48, alpha: 1)
        case .tag:       return NSColor(calibratedRed: 0.45, green: 0.75, blue: 0.98, alpha: 1)
        case .attribute: return NSColor(calibratedRed: 0.62, green: 0.82, blue: 0.62, alpha: 1)
        }
    }

    /// Uma linha de código com as cores dos tokens. `plain` volta como texto
    /// na cor base — sem custo de tokenizar.
    static func attributed(_ line: String, language: Language, font: NSFont,
                           base: NSColor) -> NSAttributedString {
        guard language != .plain else {
            return NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: base])
        }
        let out = NSMutableAttributedString()
        for token in SyntaxLite.tokens(line, language: language) {
            out.append(NSAttributedString(string: token.text, attributes: [
                .font: font, .foregroundColor: color(for: token.kind, base: base)]))
        }
        return out
    }
}

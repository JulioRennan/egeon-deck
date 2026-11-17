import Foundation

// MARK: - Menção em digitação

/// Acha a menção que está sendo digitada: o `@` aberto imediatamente antes do
/// cursor. Offsets em UTF-16 porque é a moeda do NSTextView (`selectedRange`).
enum MentionParser {
    struct Active: Equatable {
        /// Do `@` (inclusive) até o cursor — o trecho a substituir na escolha.
        let range: NSRange
        /// O que já foi digitado depois do `@`, para filtrar a lista.
        let query: String
    }

    static func activeMention(in text: String, caret: Int) -> Active? {
        let chars = Array(text.utf16)
        guard caret >= 0, caret <= chars.count else { return nil }

        var index = caret - 1
        while index >= 0 {
            guard let scalar = Unicode.Scalar(chars[index]) else { return nil }
            if scalar == "@" {
                // `@` no meio de palavra é e-mail ou código, não menção.
                if index > 0, let previous = Unicode.Scalar(chars[index - 1]),
                   !CharacterSet.whitespacesAndNewlines.contains(previous),
                   !CharacterSet.punctuationCharacters.contains(previous) {
                    return nil
                }
                let queryUnits = chars[(index + 1)..<caret]
                let query = String(utf16CodeUnits: Array(queryUnits), count: queryUnits.count)
                return Active(range: NSRange(location: index, length: caret - index),
                              query: query)
            }
            // Espaço fecha a menção: depois dele o `@` de trás já não está ativo.
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return nil }
            index -= 1
        }
        return nil
    }

    /// O texto com a menção escolhida no lugar da digitada, e onde o cursor cai.
    static func insert(_ name: String, into text: String,
                       replacing range: NSRange) -> (text: String, caret: Int) {
        let mention = "@\(name) "
        let result = (text as NSString).replacingCharacters(in: range, with: mention)
        return (result, range.location + (mention as NSString).length)
    }

    /// Quem da lista casa com o que foi digitado. Query vazia lista todos.
    static func candidates(_ names: [String], query: String) -> [String] {
        guard !query.isEmpty else { return names }
        return names.filter { $0.range(of: query, options: .caseInsensitive) != nil }
    }
}

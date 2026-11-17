import Foundation

// MARK: - Comando em digitação

/// O `/` que abre a lista de comandos: só no começo da mensagem, e só até o
/// primeiro espaço — é como o CLI lê. `/` no meio do texto é caminho de
/// arquivo, não comando.
enum SlashParser {
    /// O que já foi digitado depois da barra, ou `nil` quando não há comando
    /// aberto antes do cursor.
    static func activeQuery(in text: String, caret: Int) -> String? {
        let chars = Array(text.utf16)
        guard caret >= 1, caret <= chars.count, chars[0] == UInt16(UInt8(ascii: "/")) else { return nil }
        let typed = String(utf16CodeUnits: Array(chars[1..<caret]), count: caret - 1)
        guard typed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return typed
    }

    /// O texto com o comando escolhido no lugar do digitado — o resto da
    /// mensagem fica — e onde o cursor cai.
    static func insert(_ name: String, into text: String) -> (text: String, caret: Int) {
        let rest = text.drop { !$0.isWhitespace && !$0.isNewline }
        let command = "/\(name) "
        let tail = rest.drop { $0 == " " }
        return (command + tail, (command as NSString).length)
    }
}

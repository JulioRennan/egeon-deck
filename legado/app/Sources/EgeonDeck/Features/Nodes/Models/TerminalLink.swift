import Foundation

/// O que o ⌘-clique no terminal abre. O SwiftTerm já acha o caminho na tela (a
/// mesma regex do Ghostty) e entrega o texto cru; o padrão dele é
/// `URL(string:)`, que para `Sources/a.swift:42` vira URL sem esquema e o
/// `NSWorkspace` recusa calado. Aqui o texto vira arquivo de verdade.
enum TerminalLink {
    /// `directories` em ordem de preferência — a pasta onde o processo da frente
    /// está agora, depois a pasta em que o nó abriu. Nil quando nada existe: abrir
    /// um caminho que não existe não tem o que mostrar.
    static func resolve(_ text: String, in directories: [String],
                        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
        let raw = text.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        // Esquema só com `://` ou dos que o SwiftTerm reconhece sem barra: um
        // `a.swift:42` casaria com "esquema qualquer seguido de `:`".
        if raw.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://"#, options: .regularExpression) != nil
            || ["mailto:", "tel:", "news:", "magnet:", "file:"].contains(where: raw.hasPrefix) {
            return URL(string: raw)
        }

        // O nome cru primeiro: `:` é legal em nome de arquivo, e só quando ele não
        // existe o sufixo é lido como `:linha:coluna` de compilador e grep. A
        // pontuação da frase vem depois — a regex do SwiftTerm só a corta de URL,
        // e "veja docs/a.md." chegava com o ponto final.
        let trimmed = trimmingProse(raw)
        var candidates: [String] = []
        for candidate in [raw, stripLocation(raw), trimmed, stripLocation(trimmed)]
            where !candidate.isEmpty && !candidates.contains(candidate) {
            candidates.append(candidate)
        }
        for candidate in candidates {
            let expanded = expandHome(candidate)
            if expanded.hasPrefix("/") {
                let path = (expanded as NSString).standardizingPath
                if exists(path) { return URL(fileURLWithPath: path) }
                continue
            }
            for directory in directories where !directory.isEmpty {
                let path = ((directory as NSString).appendingPathComponent(expanded) as NSString)
                    .standardizingPath
                if exists(path) { return URL(fileURLWithPath: path) }
            }
        }
        return nil
    }

    /// Tira o que a frase gruda no caminho: aspas, crase, parênteses e a
    /// pontuação do fim.
    static func trimmingProse(_ text: String) -> String {
        var out = Substring(text)
        while let first = out.first, "([{<'\"`".contains(first) { out = out.dropFirst() }
        while let last = out.last, ".,;:!?)]}>'\"`".contains(last) { out = out.dropLast() }
        return String(out)
    }

    /// A palavra sob a coluna, para o ⌘-clique num nome solto (`README.md`,
    /// `main.swift:42`) que a regex do SwiftTerm não pega — ela exige barra.
    /// Palavra aqui é o que cabe num caminho; o resto separa.
    static func word(in line: String, at column: Int) -> String? {
        let chars = Array(line)
        guard column >= 0, column < chars.count, isPathChar(chars[column]) else { return nil }
        var start = column
        var end = column
        while start > 0, isPathChar(chars[start - 1]) { start -= 1 }
        while end < chars.count - 1, isPathChar(chars[end + 1]) { end += 1 }
        let word = trimmingProse(String(chars[start...end]))
        // Sem ponto nem barra é palavra comum, não arquivo: abrir "resposta"
        // porque existe uma pasta com esse nome surpreende mais do que ajuda.
        guard word.contains(".") || word.contains("/") else { return nil }
        return word
    }

    private static func isPathChar(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || "_-.~/:@+#%".contains(char)
    }

    static func stripLocation(_ text: String) -> String {
        text.replacingOccurrences(of: #"(:\d+){1,2}:?$"#, with: "", options: .regularExpression)
    }

    private static func expandHome(_ path: String) -> String {
        if path.hasPrefix("$HOME/") { return NSHomeDirectory() + path.dropFirst("$HOME".count) }
        return (path as NSString).expandingTildeInPath
    }
}

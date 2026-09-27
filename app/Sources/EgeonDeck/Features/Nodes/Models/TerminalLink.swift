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
        // existe o sufixo é lido como `:linha:coluna` de compilador e grep.
        for candidate in [raw, stripLocation(raw)] where !candidate.isEmpty {
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

    static func stripLocation(_ text: String) -> String {
        text.replacingOccurrences(of: #"(:\d+){1,2}:?$"#, with: "", options: .regularExpression)
    }

    private static func expandHome(_ path: String) -> String {
        if path.hasPrefix("$HOME/") { return NSHomeDirectory() + path.dropFirst("$HOME".count) }
        return (path as NSString).expandingTildeInPath
    }
}

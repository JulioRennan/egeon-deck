import Foundation


enum WorkbenchStore {
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("workbenches.json").path)

    /// Onde o arquivo morava quando bancada se chamava sessão. Lido só quando o novo
    /// não existe, e nunca escrito: a primeira gravação já sai com o nome novo.
    private static let legacyURL = URL(fileURLWithPath:
        Flavor.current.config("sessions.json").path)

    static func load() -> [WorkbenchConfig] {
        if let list = decode(configURL) { return list }
        if let list = decode(legacyURL) {
            Log.write("bancadas: lidas do sessions.json antigo; "
                      + "a próxima gravação vai para \(configURL.lastPathComponent)")
            return list
        }

        // Sem nada para carregar, começa vazio: chutar caminhos de projeto só
        // produz bancadas quebradas que o usuário tem de limpar.
        return []
    }

    private static func decode(_ url: URL) -> [WorkbenchConfig]? {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WorkbenchConfig].self, from: data),
              !list.isEmpty else { return nil }
        // Arquivo gravado antes do rename traz `sessionId`/`sessionStarted`. Sem
        // absorver aqui, todo agente perderia a conversa no primeiro arranque desta
        // versão — o terminal subiria limpo e o thread do chat nasceria vazio.
        return list.map { config in
            var copy = config
            copy.nodes = config.nodes.map(\.migratingLegacyNames)
            return copy
        }
    }

    static func save(_ list: [WorkbenchConfig]) {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(list).write(to: configURL)
    }

    /// Nome livre derivado da pasta: `deck`, `deck-2`, `deck-3`…
    /// O nome é a primeira parte do endereço de dispatch, então precisa ser único.
    static func availableName(basedOn suggestion: String, taken: [String]) -> String {
        let base = suggestion.isEmpty ? "bancada" : suggestion
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}

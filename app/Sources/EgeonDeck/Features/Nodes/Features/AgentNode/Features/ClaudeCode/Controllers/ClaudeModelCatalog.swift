import Foundation

/// O catálogo do Claude Code instalado, com cache por binário.
///
/// Ler a tabela é varrer um executável de ~200 MB — coisa de segundo. O
/// resultado vai para `claude-models.json` com o caminho, o tamanho e a data do
/// binário; enquanto os três baterem, é só ler o JSON. O Claude Code se
/// atualiza quase todo dia, e aí a releitura roda em segundo plano: quem
/// perguntar antes dela acabar fica com o catálogo anterior, e `onUpdate` avisa
/// quando o novo chega.
enum ClaudeModelCatalog {
    static let cacheURL = Flavor.current.config("claude-models.json")

    /// O catálogo novo chegou. Chamado na main.
    static var onUpdate: ((ModelCatalog) -> Void)?

    private struct Cache: Codable {
        let binary: String
        let size: Int
        let modified: Date
        let catalog: ModelCatalog
    }

    private static var memo: Cache?
    private static var refreshing: Set<String> = []

    /// O catálogo vale para o perfil que roda o `claude` — outro binário no
    /// comando não tem tabela nenhuma para ler.
    static func applies(to profile: AgentProfile) -> Bool {
        profile.command.first == "claude"
    }

    /// O catálogo do binário que o perfil roda, ou nil quando ainda não se leu
    /// nenhum (ou a leitura não achou tabela). Só na main.
    static func current(for profile: AgentProfile) -> ModelCatalog? {
        guard applies(to: profile), let name = profile.command.first,
              let binary = resolve(name), let stamp = stamp(of: binary) else { return nil }
        if memo == nil { memo = loadCache() }
        if let memo, memo.binary == binary.path, memo.size == stamp.size,
           memo.modified == stamp.modified {
            return memo.catalog
        }
        refresh(binary: binary, stamp: stamp)
        // O anterior serve enquanto o novo não chega: modelo raramente some.
        return memo?.catalog
    }

    private static func refresh(binary: URL, stamp: (size: Int, modified: Date)) {
        guard refreshing.insert(binary.path).inserted else { return }
        DispatchQueue.global(qos: .utility).async {
            let started = Date()
            let data = try? Data(contentsOf: binary, options: .alwaysMapped)
            let models = data.map(ClaudeModelRegistry.parse(binary:)) ?? []
            DispatchQueue.main.async {
                refreshing.remove(binary.path)
                let elapsed = String(format: "%.1fs", Date().timeIntervalSince(started))
                guard !models.isEmpty else {
                    Log.write("catálogo de modelos: nenhuma tabela em \(binary.path) (\(elapsed)) — "
                              + "ficam os apelidos do agents.json")
                    return
                }
                let cache = Cache(binary: binary.path, size: stamp.size, modified: stamp.modified,
                                  catalog: ModelCatalog(models: models))
                memo = cache
                save(cache)
                Log.write("catálogo de modelos: \(models.count) modelos lidos de "
                          + "\(binary.lastPathComponent) (\(elapsed))")
                onUpdate?(cache.catalog)
            }
        }
    }

    /// O executável de verdade: o `claude` do PATH costuma ser um link para
    /// `~/.local/share/claude/versions/<versão>`, e é o destino que muda.
    static func resolve(_ name: String) -> URL? {
        let path = AppEnvironment.enrichedPath(ProcessInfo.processInfo.environment["PATH"])
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.resolvingSymlinksInPath()
            }
        }
        return nil
    }

    private static func stamp(of binary: URL) -> (size: Int, modified: Date)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: binary.path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return (size, modified)
    }

    private static func loadCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Cache.self, from: data)
    }

    private static func save(_ cache: Cache) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        try? encoder.encode(cache).write(to: cacheURL)
    }
}

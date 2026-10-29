import Foundation

/// O que o Claude Code oferece no `/` de um terminal.
///
/// Sem perguntar ao CLI: a lista só existe dentro da TUI, e a saída
/// `stream-json` que a traz custa uma chamada à API. Junta-se o que ele junta,
/// de onde ele lê — a pasta de configuração DO NÓ (cada um escolhe a sua,
/// ADR-054), o `.claude/` do diretório e dos pais até a raiz do repositório, os
/// plugins habilitados e o que vem sincronizado do claude.ai —, mais a
/// `skill_listing` do transcript (as skills que a sessão carregou de fato,
/// inclusive as do binário) e os embutidos lidos do binário. Relido a cada
/// abertura da lista, para skill instalada agora aparecer sem reiniciar nada.
enum ClaudeSlashCatalog {
    /// A lista do nó, pela configuração que ele sobe: a escolhida no nó, senão
    /// a do perfil, senão o `~/.claude`. `nil` quando o perfil não é Claude Code.
    static func commands(profile: AgentProfile, nodeConfig: String?, cwd: String,
                         transcript: String?) -> [SlashCommand]? {
        guard ClaudeModelCatalog.applies(to: profile) else { return nil }
        let chosen = nodeConfig ?? profile.configEnv.flatMap { profile.resolvedEnvironment[$0] }
        guard let path = chosen.map({ ($0 as NSString).expandingTildeInPath }) ?? profile.defaultConfigPath
        else { return nil }
        return commands(configDir: URL(fileURLWithPath: path), cwd: URL(fileURLWithPath: cwd),
                        loaded: transcript.map { skillListing(at: URL(fileURLWithPath: $0)) },
                        binary: ClaudeModelCatalog.commands(for: profile))
    }

    /// `loaded` é a `skill_listing` da sessão (nil sem transcript); `binary`,
    /// o que se leu do executável (nil antes da primeira leitura).
    static func commands(configDir: URL, cwd: URL?, loaded: [(name: String, detail: String)]? = nil,
                         binary: ClaudeCommandRegistry? = nil) -> [SlashCommand] {
        var out: [SlashCommand] = []
        // A `skill_listing` traz também quem o disco tira do `/`.
        var hidden = Set(binary?.hidden ?? [])
        for root in cwd.map(projectRoots) ?? [] {
            out += scan(root, source: .project, prefix: nil, hidden: &hidden)
        }
        out += scan(configDir, source: .user, prefix: nil, hidden: &hidden)
        for (plugin, root) in enabledPlugins(configDir: configDir, cwd: cwd) + syncedPlugins(configDir: configDir) {
            out += scan(root, source: .plugin(plugin), prefix: plugin, hidden: &hidden)
        }
        out += syncedSkills(configDir: configDir, hidden: &hidden)

        for skill in loaded ?? [] where !hidden.contains(skill.name) {
            let prefix = skill.name.split(separator: ":", maxSplits: 1).dropLast().first.map(String.init)
            out.append(SlashCommand(name: skill.name, detail: skill.detail,
                                    source: prefix.map { .plugin($0) } ?? .bundled))
        }
        // Com a lista da sessão, só as do binário que ela nunca traz: as que
        // rodam só digitadas. Sem ela, todas — melhor sobrar que faltar.
        for skill in binary?.skills ?? [] where loaded == nil || skill.userOnly {
            out.append(SlashCommand(name: skill.name, detail: skill.detail, source: .bundled,
                                    aliases: skill.aliases ?? []))
        }

        let read = binary?.builtins ?? []
        let ours = Dictionary(builtins.map { ($0.name, $0.detail) }, uniquingKeysWith: { a, _ in a })
        out += read.isEmpty ? builtins : read.map {
            SlashCommand(name: $0.name, detail: ours[$0.name] ?? $0.detail, source: .builtin,
                         aliases: $0.aliases ?? [])
        }
        // O primeiro vence: projeto sobre o seu, o seu sobre o embutido — a
        // mesma precedência do CLI.
        var seen = Set<String>()
        return out.filter { seen.insert($0.name).inserted }
    }

    /// O `.claude/` do diretório e de cada pai até a raiz do repositório — o
    /// mais perto primeiro. Fora de repositório, só o do diretório.
    static func projectRoots(from cwd: URL) -> [URL] {
        let fm = FileManager.default
        var roots: [URL] = []
        var dir = cwd.standardizedFileURL
        while true {
            roots.append(dir.appendingPathComponent(".claude"))
            // `.git` arquivo é worktree: a busca para nela, como no CLI.
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return roots }
            // No `/`, o pai de URL vira `/..` em vez de parar.
            if dir.pathComponents.count <= 1 { return [roots[0]] }
            dir = dir.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// `commands/*.md` (subpasta vira `pasta:nome`), `skills/<nome>/SKILL.md` e
    /// o `SKILL.md` na raiz, que é o de plugin de uma skill só.
    static func scan(_ root: URL, source: SlashCommand.Source, prefix: String?,
                     hidden: inout Set<String>) -> [SlashCommand] {
        let fm = FileManager.default
        var found: [SlashCommand] = []
        func named(_ name: String) -> String { prefix.map { "\($0):\(name)" } ?? name }

        let commands = root.appendingPathComponent("commands").standardizedFileURL
        if let walker = fm.enumerator(at: commands, includingPropertiesForKeys: nil) {
            for case let file as URL in walker where file.pathExtension == "md" {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let meta = ClaudeFrontmatter(text)
                let relative = file.standardizedFileURL.deletingPathExtension().pathComponents
                    .dropFirst(commands.pathComponents.count)
                let name = named(relative.joined(separator: ":"))
                guard meta.invocable else { hidden.insert(name); continue }
                found.append(SlashCommand(name: name,
                                          detail: meta.description ?? meta.firstLine ?? "",
                                          source: source))
            }
        }

        found += skills(in: root.appendingPathComponent("skills"), source: source, prefix: prefix, hidden: &hidden)
        if prefix != nil, let text = try? String(contentsOf: root.appendingPathComponent("SKILL.md"), encoding: .utf8) {
            let meta = ClaudeFrontmatter(text)
            let name = named(meta.name ?? root.lastPathComponent)
            if meta.invocable {
                found.append(SlashCommand(name: name, detail: meta.description ?? "", source: source))
            } else {
                hidden.insert(name)
            }
        }
        return found.sorted { $0.name < $1.name }
    }

    /// Cada `<pasta>/SKILL.md` de um diretório.
    static func skills(in folder: URL, source: SlashCommand.Source, prefix: String?,
                       hidden: inout Set<String>) -> [SlashCommand] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var found: [SlashCommand] = []
        for folder in folders {
            guard let text = try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8)
            else { continue }
            let meta = ClaudeFrontmatter(text)
            let base = meta.name ?? folder.lastPathComponent
            let name = prefix.map { "\($0):\(base)" } ?? base
            guard meta.invocable else { hidden.insert(name); continue }
            found.append(SlashCommand(name: name, detail: meta.description ?? "", source: source))
        }
        return found
    }

    private static func json(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// Os plugins ligados — no `settings.json` da configuração e nos do
    /// projeto, que vencem —, com a pasta instalada de cada um. O nome no `/`
    /// é o do plugin sem o `@marketplace`.
    static func enabledPlugins(configDir: URL, cwd: URL? = nil) -> [(String, URL)] {
        var enabled = json(configDir.appendingPathComponent("settings.json"))?["enabledPlugins"] as? [String: Any] ?? [:]
        if let cwd {
            for file in ["settings.json", "settings.local.json"] {
                let project = json(cwd.appendingPathComponent(".claude/\(file)"))?["enabledPlugins"] as? [String: Any]
                enabled.merge(project ?? [:]) { _, new in new }
            }
        }
        let installed = json(configDir.appendingPathComponent("plugins/installed_plugins.json"))?["plugins"]
            as? [String: Any] ?? [:]
        return enabled.keys.sorted().compactMap { key in
            guard enabled[key] as? Bool == true,
                  let entries = installed[key] as? [[String: Any]],
                  let path = installPath(entries, projects: cwd.map(projectRoots) ?? []) else { return nil }
            let name = String(key.split(separator: "@").first ?? Substring(key))
            return (name, URL(fileURLWithPath: path))
        }
    }

    /// A instalação que vale aqui: a deste projeto (o diretório ou um pai até
    /// a raiz do repositório), senão a do usuário, senão a primeira. Instalação
    /// de projeto num pai mais acima — a home, por exemplo — não é deste.
    static func installPath(_ entries: [[String: Any]], projects: [URL]) -> String? {
        let here = Set(projects.map { $0.deletingLastPathComponent().standardizedFileURL.path })
        let project = entries.first { entry in
            guard entry["scope"] as? String == "project", let root = entry["projectPath"] as? String else { return false }
            return here.contains(URL(fileURLWithPath: root).standardizedFileURL.path)
        }
        let chosen = project ?? entries.first { $0["scope"] as? String == "user" } ?? entries.first
        return chosen?["installPath"] as? String
    }

    /// As pastas de sincronização do claude.ai: `<raiz>/<conta>/manifest.json`.
    private static func syncedBuckets(_ root: URL) -> [(URL, [String: Any])] {
        let buckets = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return buckets.sorted { $0.path < $1.path }.compactMap { bucket in
            json(bucket.appendingPathComponent("manifest.json")).map { (bucket, $0) }
        }
    }

    /// As skills da conta do claude.ai, que o CLI chama de `anthropic-skills:`.
    static func syncedSkills(configDir: URL, hidden: inout Set<String>) -> [SlashCommand] {
        var found: [SlashCommand] = []
        for (bucket, manifest) in syncedBuckets(configDir.appendingPathComponent("skills/synced")) {
            let listed = Set((manifest["skills"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
            found += skills(in: bucket, source: .plugin("anthropic-skills"), prefix: "anthropic-skills", hidden: &hidden)
                .filter { listed.contains(String($0.name.dropFirst("anthropic-skills:".count))) }
        }
        return found.sorted { $0.name < $1.name }
    }

    /// Os plugins da conta do claude.ai. Cada geração nova desce numa pasta
    /// `<nome>~g<n>` ao lado da anterior; vale a do manifesto.
    static func syncedPlugins(configDir: URL) -> [(String, URL)] {
        syncedBuckets(configDir.appendingPathComponent("plugins/synced")).flatMap { bucket, manifest in
            (manifest["plugins"] as? [[String: Any]] ?? []).compactMap { plugin -> (String, URL)? in
                guard let name = plugin["name"] as? String else { return nil }
                let generation = (plugin["generation"] as? Int).map { bucket.appendingPathComponent("\(name)~g\($0)") }
                let folder = generation.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                    ?? bucket.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: folder.path) ? (name, folder) : nil
            }
        }
    }

    private static let listingMark = Data("\"skill_listing\"".utf8)

    /// As skills que a sessão carregou, da `skill_listing` do transcript — a
    /// primeira (`isInitial`) e as que chegam depois somando. É a lista do
    /// modelo, não do menu: quem tem `user-invocable: false` também vem.
    static func skillListing(at url: URL) -> [(name: String, detail: String)] {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        return skillListing(in: data)
    }

    static func skillListing(in data: Data) -> [(name: String, detail: String)] {
        var order: [String] = []
        var details: [String: String] = [:]
        var cursor = data.startIndex
        while let hit = data.range(of: listingMark, in: cursor..<data.endIndex) {
            let start = data[..<hit.lowerBound].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
            let end = data[hit.upperBound...].firstIndex(of: 0x0A) ?? data.endIndex
            cursor = end
            guard let line = try? JSONSerialization.jsonObject(with: data[start..<end]) as? [String: Any],
                  let attachment = line["attachment"] as? [String: Any],
                  attachment["type"] as? String == "skill_listing" else { continue }
            if attachment["isInitial"] as? Bool == true { order = []; details = [:] }
            var described: [String: String] = [:]
            for row in (attachment["content"] as? String ?? "").components(separatedBy: "\n")
            where row.hasPrefix("- ") {
                guard let colon = row.range(of: ": ") else { continue }
                described[String(row[row.index(row.startIndex, offsetBy: 2)..<colon.lowerBound])] =
                    String(row[colon.upperBound...])
            }
            let names = attachment["names"] as? [String] ?? Array(described.keys).sorted()
            for name in names where details[name] == nil {
                order.append(name)
                details[name] = described[name] ?? ""
            }
        }
        return order.map { ($0, details[$0] ?? "") }
    }

    /// Os embutidos de uso comum, com legenda em português. Valem sozinhos
    /// enquanto o binário não foi lido; depois, só emprestam a legenda.
    static let builtins: [SlashCommand] = [
        ("clear", "Limpa a conversa e começa do zero"),
        ("compact", "Resume a conversa para liberar contexto"),
        ("context", "Mostra quanto do contexto está ocupado"),
        ("model", "Troca o modelo"),
        ("config", "Abre as configurações"),
        ("cost", "Custo e duração da sessão"),
        ("usage", "Uso do plano e limites"),
        ("status", "Versão, modelo, conta e conexões"),
        ("resume", "Retoma uma conversa anterior"),
        ("rewind", "Volta a conversa ou o código a um ponto anterior"),
        ("memory", "Edita os arquivos de memória (CLAUDE.md)"),
        ("init", "Cria o CLAUDE.md do projeto"),
        ("review", "Revisa um pull request"),
        ("security-review", "Revisão de segurança das mudanças pendentes"),
        ("permissions", "Regras de permissão de ferramentas"),
        ("agents", "Gerencia subagentes"),
        ("mcp", "Servidores MCP"),
        ("hooks", "Ganchos configurados"),
        ("plugin", "Gerencia plugins"),
        ("add-dir", "Adiciona outra pasta de trabalho"),
        ("export", "Exporta a conversa"),
        ("doctor", "Diagnóstico da instalação"),
        ("help", "Ajuda e lista de comandos"),
    ].map { SlashCommand(name: $0.0, detail: $0.1, source: .builtin) }
}

/// O cabeçalho `---` de um comando ou skill — só as chaves que a lista usa.
struct ClaudeFrontmatter {
    var name: String?
    var description: String?
    /// `user-invocable: false` tira a skill do `/` (ela só roda pelo modelo).
    var invocable = true
    /// Para comando sem `description`: a primeira linha de texto do corpo.
    var firstLine: String?

    init(_ text: String) {
        var lines = text.components(separatedBy: .newlines)[...]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = lines.dropFirst()
            var folding: String?
            var folded: [String] = []
            while let line = lines.first {
                lines = lines.dropFirst()
                if line.trimmingCharacters(in: .whitespaces) == "---" { break }
                // `description: >-` e afins: o valor vem nas linhas recuadas.
                if folding != nil, line.hasPrefix(" ") || line.hasPrefix("\t") {
                    folded.append(line.trimmingCharacters(in: .whitespaces))
                    continue
                }
                if let key = folding { set(key, folded.joined(separator: " ")); folding = nil; folded = [] }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if [">", ">-", "|", "|-", ""].contains(value) { folding = key; continue }
                set(key, value)
            }
            if let key = folding { set(key, folded.joined(separator: " ")) }
        }
        firstLine = lines.lazy
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces)) }
            .first { !$0.isEmpty }
    }

    private mutating func set(_ key: String, _ raw: String) {
        let value = raw.count >= 2 && (raw.hasPrefix("\"") && raw.hasSuffix("\"")
                                       || raw.hasPrefix("'") && raw.hasSuffix("'"))
            ? String(raw.dropFirst().dropLast()) : raw
        switch key {
        case "name": name = value.isEmpty ? nil : value
        case "description": description = value.isEmpty ? nil : value
        case "user-invocable": invocable = value.lowercased() != "false"
        default: break
        }
    }
}

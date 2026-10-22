import Foundation

/// O que o Claude Code oferece no `/` de um terminal, lido do disco.
///
/// Do disco, e não do CLI: a lista só existe dentro da TUI, e a saída
/// `stream-json` que a traz custa uma chamada à API. Lê-se o mesmo que ele lê —
/// a pasta de configuração DO NÓ (cada um escolhe a sua, ADR-054), o `.claude/`
/// do diretório dele e os plugins habilitados — a cada abertura da lista, para
/// skill instalada agora aparecer sem reiniciar nada.
enum ClaudeSlashCatalog {
    /// A lista do nó, pela configuração que ele sobe: a escolhida no nó, senão
    /// a do perfil, senão o `~/.claude`. `nil` quando o perfil não é Claude Code.
    static func commands(profile: AgentProfile, nodeConfig: String?, cwd: String) -> [SlashCommand]? {
        guard ClaudeModelCatalog.applies(to: profile) else { return nil }
        let chosen = nodeConfig ?? profile.configEnv.flatMap { profile.resolvedEnvironment[$0] }
        guard let path = chosen.map({ ($0 as NSString).expandingTildeInPath }) ?? profile.defaultConfigPath
        else { return nil }
        return commands(configDir: URL(fileURLWithPath: path), cwd: URL(fileURLWithPath: cwd))
    }

    static func commands(configDir: URL, cwd: URL?) -> [SlashCommand] {
        var out: [SlashCommand] = []
        if let cwd {
            let project = cwd.appendingPathComponent(".claude")
            out += scan(project, source: .project, prefix: nil)
        }
        out += scan(configDir, source: .user, prefix: nil)
        for (plugin, root) in enabledPlugins(configDir: configDir) {
            out += scan(root, source: .plugin(plugin), prefix: plugin)
        }
        out += builtins
        // O primeiro vence: projeto sobre o seu, o seu sobre o embutido — a
        // mesma precedência do CLI.
        var seen = Set<String>()
        return out.filter { seen.insert($0.name).inserted }
    }

    /// `commands/*.md` (subpastas incluídas) e `skills/<nome>/SKILL.md` de uma raiz.
    static func scan(_ root: URL, source: SlashCommand.Source, prefix: String?) -> [SlashCommand] {
        let fm = FileManager.default
        var found: [SlashCommand] = []
        func named(_ name: String) -> String { prefix.map { "\($0):\(name)" } ?? name }

        let commands = root.appendingPathComponent("commands")
        if let walker = fm.enumerator(at: commands, includingPropertiesForKeys: nil) {
            for case let file as URL in walker where file.pathExtension == "md" {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                let meta = ClaudeFrontmatter(text)
                guard meta.invocable else { continue }
                found.append(SlashCommand(name: named(file.deletingPathExtension().lastPathComponent),
                                          detail: meta.description ?? meta.firstLine ?? "",
                                          source: source))
            }
        }

        let skills = root.appendingPathComponent("skills")
        let folders = (try? fm.contentsOfDirectory(at: skills, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            let file = folder.appendingPathComponent("SKILL.md")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let meta = ClaudeFrontmatter(text)
            guard meta.invocable else { continue }
            found.append(SlashCommand(name: named(meta.name ?? folder.lastPathComponent),
                                      detail: meta.description ?? "", source: source))
        }
        return found.sorted { $0.name < $1.name }
    }

    /// Os plugins ligados em `settings.json`, com a pasta instalada de cada um.
    /// O nome no `/` é o do plugin sem o `@marketplace`.
    static func enabledPlugins(configDir: URL) -> [(String, URL)] {
        func json(_ name: String) -> [String: Any]? {
            (try? Data(contentsOf: configDir.appendingPathComponent(name)))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        let enabled = json("settings.json")?["enabledPlugins"] as? [String: Any] ?? [:]
        let installed = json("plugins/installed_plugins.json")?["plugins"] as? [String: Any] ?? [:]
        return enabled.keys.sorted().compactMap { key in
            guard enabled[key] as? Bool == true,
                  let entries = installed[key] as? [[String: Any]],
                  let path = entries.first?["installPath"] as? String else { return nil }
            let name = String(key.split(separator: "@").first ?? Substring(key))
            return (name, URL(fileURLWithPath: path))
        }
    }

    /// Os embutidos de uso comum. Lista nossa, porque eles moram no binário; o
    /// que faltar aqui ainda funciona digitado à mão.
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

import Foundation

/// Um comando que o CLI do agente aceita começando com `/` — embutido, seu,
/// do projeto ou de um plugin. É o que o composer do chat oferece quando você
/// digita `/`; quem sabe ler a lista de cada CLI é o submódulo dele.
struct SlashCommand: Equatable {
    enum Source: Equatable {
        case builtin
        /// Da sua configuração (`commands/` ou `skills/` da pasta do CLI).
        case user
        /// Do `.claude/` do diretório do terminal.
        case project
        case plugin(String)
    }

    /// Sem a barra: `clear`, `figma:figma-use`.
    let name: String
    let detail: String
    let source: Source

    /// Quem casa com o que foi digitado depois da barra. Começo do nome
    /// primeiro — do nome inteiro ou do que vem depois do `plugin:` —, depois
    /// quem contém. Query vazia devolve tudo, na ordem recebida.
    static func matching(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        guard !query.isEmpty else { return commands }
        let needle = query.lowercased()
        var head: [SlashCommand] = []
        var tail: [SlashCommand] = []
        for command in commands {
            let name = command.name.lowercased()
            let short = name.split(separator: ":").last.map(String.init) ?? name
            if name.hasPrefix(needle) || short.hasPrefix(needle) {
                head.append(command)
            } else if name.contains(needle) {
                tail.append(command)
            }
        }
        return head + tail
    }
}

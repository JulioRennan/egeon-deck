import Foundation

/// Um comando que o CLI do agente aceita começando com `/` — embutido, skill
/// do CLI, seu, do projeto ou de um plugin. É o que o composer do chat oferece
/// quando você digita `/`; quem sabe ler a lista de cada CLI é o submódulo dele.
struct SlashCommand: Equatable {
    enum Source: Equatable {
        case builtin
        /// Skill que vem dentro do CLI (`/simplify`, `/loop`).
        case bundled
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
    /// Outros nomes que levam ao mesmo comando (`cost` → `usage`).
    var aliases: [String] = []

    /// Quem casa com o que foi digitado depois da barra. Começo do nome
    /// primeiro — do nome inteiro, do que vem depois do `plugin:` ou de um
    /// apelido —, depois quem contém. Query vazia devolve tudo, na ordem recebida.
    static func matching(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        guard !query.isEmpty else { return commands }
        let needle = query.lowercased()
        var head: [SlashCommand] = []
        var tail: [SlashCommand] = []
        for command in commands {
            let name = command.name.lowercased()
            let short = name.split(separator: ":").last.map(String.init) ?? name
            if name.hasPrefix(needle) || short.hasPrefix(needle)
                || command.aliases.contains(where: { $0.lowercased().hasPrefix(needle) }) {
                head.append(command)
            } else if name.contains(needle) {
                tail.append(command)
            }
        }
        return head + tail
    }

    /// A busca da barra da lista: cada palavra tem de aparecer no nome, num
    /// apelido ou na descrição — sem caixa nem acento, em qualquer ordem. Quem
    /// casa tudo pelo nome vem antes de quem precisou da descrição.
    static func searching(_ commands: [SlashCommand], text: String) -> [SlashCommand] {
        func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let words = fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return commands }
        var byName: [SlashCommand] = []
        var byDetail: [SlashCommand] = []
        for command in commands {
            let name = fold(([command.name] + command.aliases).joined(separator: " "))
            let all = name + " " + fold(command.detail)
            if words.allSatisfy(name.contains) { byName.append(command) }
            else if words.allSatisfy(all.contains) { byDetail.append(command) }
        }
        return byName + byDetail
    }
}

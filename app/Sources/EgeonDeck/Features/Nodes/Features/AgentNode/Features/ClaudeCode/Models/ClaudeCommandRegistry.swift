import Foundation

/// Os comandos que o `/` do Claude Code oferece e que não estão em disco: os
/// embutidos (`/compact`, `/model`…) e as skills que vêm no binário
/// (`/simplify`, `/loop`, `/debug`…).
///
/// Mesma via do `ClaudeModelRegistry`: o JavaScript minificado do CLI declara
/// cada embutido como um objeto com `type:"local"` (ou `local-jsx`, `prompt`),
/// `name` e `description` — em qualquer ordem — e cada skill do binário como
/// `x({name:"…",menuDescription:"…"})`. Formato interno, que muda sem aviso:
/// leitura que não acha nada devolve vazio, e a lista fica com os embutidos de
/// `ClaudeSlashCatalog.builtins`.
struct ClaudeCommandRegistry: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let name: String
        let detail: String
        /// Skill que só roda digitada (`disableModelInvocation`): nunca entra
        /// na `skill_listing` do transcript, então só o binário a conhece.
        var userOnly = false
        /// `/cost` e `/stats` levam ao `/usage`.
        var aliases: [String]? = nil
    }

    /// Sobe quando a leitura muda: cache de outra versão relê o binário.
    static let currentVersion = 2
    var version: Int? = currentVersion
    var builtins: [Entry] = []
    var skills: [Entry] = []
    /// Fora do `/`: embutido com `isHidden` e skill com `userInvocable: false`
    /// — esta aparece na `skill_listing`, que é a lista do MODELO.
    var hidden: [String] = []

    private static let builtinMarks = ["local", "local-jsx", "prompt"].map { Data(#"type:"\#($0)""#.utf8) }
    private static let skillStart = Data(#"({name:""#.utf8)
    private static let window = 1500
    /// Quanto antes do `type:` o objeto pode começar.
    private static let lookBack = 800

    static func parse(binary data: Data) -> ClaudeCommandRegistry {
        var out = ClaudeCommandRegistry()
        var hidden = Set<String>()
        var seen = Set<String>()
        for mark in builtinMarks {
            var cursor = data.startIndex
            while let range = data.range(of: mark, in: cursor..<data.endIndex) {
                cursor = range.upperBound
                let before = String(decoding: data[max(data.startIndex, range.lowerBound - lookBack)..<range.lowerBound],
                                    as: UTF8.self)
                let after = String(decoding: data[range.lowerBound..<min(range.lowerBound + window, data.endIndex)],
                                   as: UTF8.self)
                guard let open = openingBrace(before),
                      let entry = builtin(String(before[open...]) + after) else { continue }
                if entry.hidden { hidden.insert(entry.name); continue }
                guard seen.insert(entry.name).inserted else { continue }
                out.builtins.append(Entry(name: entry.name, detail: entry.detail,
                                          aliases: entry.aliases.isEmpty ? nil : entry.aliases))
            }
        }
        var skillSeen = Set<String>()
        var cursor = data.startIndex
        while let range = data.range(of: skillStart, in: cursor..<data.endIndex) {
            cursor = range.upperBound
            // Janela cortada no meio de um caractere: o decodificador troca
            // só ele por `?`, o resto vale.
            let text = String(decoding: data[range.lowerBound..<min(range.lowerBound + window, data.endIndex)],
                              as: UTF8.self)
            guard let entry = skill(text) else { continue }
            if entry.hidden { hidden.insert(entry.name); continue }
            guard let detail = entry.detail, skillSeen.insert(entry.name).inserted else { continue }
            out.skills.append(Entry(name: entry.name, detail: detail, userOnly: entry.userOnly,
                                    aliases: entry.aliases.isEmpty ? nil : entry.aliases))
        }
        out.builtins.sort { $0.name < $1.name }
        out.skills.sort { $0.name < $1.name }
        out.hidden = hidden.subtracting(seen.union(skillSeen)).sorted()
        return out
    }

    private static let topName = try! NSRegularExpression(pattern: #"[{,]name:"([a-z][a-z0-9:-]*)""#)
    private static let skillHead = try! NSRegularExpression(pattern: #"^\(\{name:"([a-z][a-z0-9:-]*)","#)
    private static let aliasList = try! NSRegularExpression(pattern: #"aliases:\[([^\]]*)\]"#)

    /// O `{` que abre o objeto em que o texto termina — o último sem par.
    static func openingBrace(_ text: String) -> String.Index? {
        var depth = 0
        var index = text.endIndex
        while index > text.startIndex {
            index = text.index(before: index)
            switch text[index] {
            case "}": depth += 1
            case "{":
                if depth == 0 { return index }
                depth -= 1
            default: break
            }
        }
        return nil
    }

    /// Um embutido, a partir do `{` do objeto dele. O que vale é o próprio
    /// objeto até o código (`load`/`call`) — logo depois costuma vir um `stub`
    /// com `isHidden:!0` que não é dele.
    static func builtin(_ text: String) -> (name: String, detail: String, hidden: Bool, aliases: [String])? {
        let body = cut(object(text), at: ["load:", "call:", "async call(", "getPromptForCommand"], after: 1)
        guard let name = first(topName, body) else { return nil }
        let hidden = body.contains("isHidden:!0") || body.contains("isEnabled:()=>!1")
        return (name, literal("description", in: body) ?? "", hidden, aliases(body))
    }

    /// Uma skill do binário, a partir do `({name:"`. Sem `menuDescription` não
    /// é skill de menu — o mesmo começo é de um sem-número de objetos.
    static func skill(_ text: String) -> (name: String, detail: String?, hidden: Bool, userOnly: Bool, aliases: [String])? {
        guard let name = first(skillHead, text) else { return nil }
        let body = cut(object(String(text.dropFirst())), at: ["getPromptForCommand"], after: 1)
        let detail = literal("menuDescription", in: body)
        let hidden = body.contains("userInvocable:!1") && body.contains("description:")
        guard detail != nil || hidden else { return nil }
        return (name, detail, hidden, body.contains("disableModelInvocation:!0"), aliases(body))
    }

    private static func aliases(_ body: String) -> [String] {
        guard let list = first(aliasList, body) else { return [] }
        return list.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) }
            .filter { !$0.isEmpty }
    }

    private static func first(_ regex: NSRegularExpression, _ text: String) -> String? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Do `{` do começo até o `}` que o fecha, pulando o que está entre
    /// aspas. Sem fechamento na janela, a janela inteira.
    static func object(_ text: String) -> String {
        var depth = 0
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let c = text[index]
            if let open = quote {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == open { quote = nil }
                continue
            }
            switch c {
            case "\"", "'", "`": quote = c
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(text[...index]) }
            default: break
            }
        }
        return text
    }

    private static func cut(_ text: String, at marks: [String], after skip: Int) -> String {
        let from = text.index(text.startIndex, offsetBy: skip)
        let end = marks.compactMap { text.range(of: $0, range: from..<text.endIndex)?.lowerBound }.min()
        return String(text[..<(end ?? text.endIndex)])
    }

    /// O valor de `chave:"…"` (ou com `'`/crase), com os escapes do JS
    /// desfeitos. Nil quando o valor não é literal — um getter, uma variável.
    static func literal(_ key: String, in text: String) -> String? {
        guard let range = text.range(of: key + ":") else { return nil }
        var chars = text[range.upperBound...].makeIterator()
        guard let quote = chars.next(), "\"'`".contains(quote) else { return nil }
        var out = ""
        while let c = chars.next() {
            if c == quote { return out }
            if quote == "`", c == "$" { return nil }
            guard c == "\\" else { out.append(c); continue }
            switch chars.next() {
            case "n": out.append(" ")
            case "u":
                let hex = String([chars.next(), chars.next(), chars.next(), chars.next()].compactMap { $0 })
                if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) { out.append(Character(scalar)) }
            case let other?: out.append(other)
            case nil: return nil
            }
        }
        return nil
    }
}

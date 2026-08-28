import Foundation

// MARK: - Que linguagem é este arquivo

/// Decidida pela extensão, e só por ela (v0): ler o texto para adivinhar é o
/// que o Linguist do GitHub faz por cima, e não paga o custo aqui — o passo
/// já traz o caminho. Sem extensão conhecida é `plain`, sem cor.
enum Language: String, CaseIterable, Equatable {
    case python, html, dart, typescript, json, swift, shell, plain

    static func detect(path: String) -> Language {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .plain }
        switch name[name.index(after: dot)...].lowercased() {
        case "py", "pyi":                 return .python
        case "html", "htm", "xhtml":      return .html
        case "dart":                      return .dart
        case "ts", "tsx", "js", "jsx", "mjs", "cjs": return .typescript
        case "json", "jsonc":             return .json
        case "swift":                     return .swift
        case "sh", "bash", "zsh":         return .shell
        default:                          return .plain
        }
    }

    /// Pelo rótulo do bloco de código (```python): é a "extensão" da prosa.
    static func named(_ name: String) -> Language {
        switch name.lowercased() {
        case "python", "py":                      return .python
        case "html", "htm":                       return .html
        case "dart":                              return .dart
        case "typescript", "ts", "tsx", "javascript", "js", "jsx": return .typescript
        case "json", "jsonc":                     return .json
        case "swift":                             return .swift
        case "sh", "bash", "shell", "zsh":        return .shell
        default:                                  return .plain
        }
    }

    /// A linguagem da saída de um comando: a do primeiro arquivo com extensão
    /// conhecida citado nele (`cat config.json`, `head -20 app.py`). Continua
    /// sendo extensão, não leitura do texto (ADR-041).
    static func detect(inCommand command: String) -> Language {
        for word in command.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let path = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`;|&()"))
            let language = detect(path: path)
            if language != .plain { return language }
        }
        return .plain
    }
}

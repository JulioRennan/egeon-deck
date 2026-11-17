import Foundation

/// Projeto que nasce de dentro do app: um nome e a pasta onde ele vai morar
/// (ADR-092).
///
/// Antes só se adicionava pasta que já existia, e criar um repositório novo era
/// sair para o terminal, `mkdir`, `git init` e voltar ao formulário do
/// workspace. A pasta-mãe sugerida é a que os projetos do workspace já dividem:
/// quem tem três repositórios em `~/Documents/duck` cria o quarto ali.
enum NewProject {
    static let fallbackParent = "~/Documents"

    enum Problem: Error, Equatable {
        case emptyName
        /// Barra vira subpasta e dois-pontos o Finder mostra como barra; ponto
        /// no começo esconde a pasta — nada disso é nome de projeto.
        case invalidName
        case missingParent(String)
        /// Já há um ARQUIVO com esse nome: pasta existente é adotada, arquivo não.
        case fileInTheWay(String)
        case alreadyProject(String)

        var message: String {
            switch self {
            case .emptyName: return "Dê um nome ao projeto."
            case .invalidName: return "O nome não pode ter \"/\" nem \":\", nem começar com ponto."
            case .missingParent(let p): return "A pasta \(p) não existe."
            case .fileInTheWay(let p): return "Já existe um arquivo em \(p)."
            case .alreadyProject(let name): return "Essa pasta já é o projeto \"\(name)\" deste workspace."
            }
        }
    }

    struct Plan: Equatable {
        /// Caminho com `~`, como o `workspaces.json` guarda.
        var path: String
        /// A pasta ainda não existe e vai ser criada; senão é adotada como está.
        var create: Bool
    }

    /// A pasta-mãe mais comum entre os projetos de pasta do workspace; empate
    /// fica com a do projeto mais recente, que é onde você mexeu por último.
    static func suggestedParent(for workspace: WorkspaceConfig) -> String {
        let parents = workspace.projects.filter { !$0.isMulti }.map {
            (ProjectConfig.normalize($0.path) as NSString).deletingLastPathComponent
        }
        guard !parents.isEmpty else { return fallbackParent }
        var count: [String: Int] = [:]
        parents.forEach { count[$0, default: 0] += 1 }
        let best = count.values.max() ?? 0
        let winner = parents.last { count[$0] == best } ?? parents[parents.count - 1]
        return (winner as NSString).abbreviatingWithTildeInPath
    }

    /// `kind` diz o que há no caminho: nil (nada), `true` (pasta) ou `false`
    /// (arquivo). Injetado para o teste não depender do disco.
    static func plan(name raw: String, parent: String, in workspace: WorkspaceConfig,
                     kind: (String) -> Bool?) -> Result<Plan, Problem> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.emptyName) }
        guard !name.contains("/"), !name.contains(":"), !name.hasPrefix("."), name != ".." else {
            return .failure(.invalidName)
        }
        let base = ProjectConfig.normalize(parent)
        guard kind(base) == true else {
            return .failure(.missingParent((base as NSString).abbreviatingWithTildeInPath))
        }
        let full = (base as NSString).appendingPathComponent(name)
        let path = (full as NSString).abbreviatingWithTildeInPath
        if let existing = workspace.project(owning: full) {
            return .failure(.alreadyProject(existing.name))
        }
        let there: Bool? = kind(full)
        if there == false { return .failure(.fileInTheWay(path)) }
        return .success(Plan(path: path, create: there == nil))
    }

    static func diskKind(_ path: String) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue
    }
}

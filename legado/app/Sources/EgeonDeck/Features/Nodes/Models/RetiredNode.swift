import Foundation

extension NodeKind {
    /// Tipos de nó que saíram do app. O `editor` era o VSCode (code-server) no
    /// card, removido no ADR-076.
    static let retired: Set<String> = ["editor"]
}

/// Um item de lista gravada — nó de bancada, de template ou componente — que
/// pode ser de um tipo que saiu do app.
///
/// Sem isto, um único card de editor em `workbenches.json` derrubava a leitura
/// do arquivo inteiro, porque `NodeKind` não o conhece mais. Só o tipo
/// aposentado é pulado; qualquer outro erro continua sendo erro.
struct Retirable<T: Decodable>: Decodable {
    let value: T?

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        for name in ["type", "kind"] {
            if let raw = try? c.decode(String.self, forKey: Key(stringValue: name)),
               NodeKind.retired.contains(raw) {
                value = nil
                return
            }
        }
        value = try T(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// A lista de nós sem os de tipo aposentado.
    func decodeNodes(forKey key: Key) throws -> [NodeConfig]? {
        try decodeIfPresent([Retirable<NodeConfig>].self, forKey: key)?.compactMap(\.value)
    }
}

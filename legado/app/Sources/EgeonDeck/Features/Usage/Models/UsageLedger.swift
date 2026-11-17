import Foundation

/// O consumo de uma bancada (ADR-085), em `workbenches/<id>/usage.json`: o que
/// cada nó gastou, por tarifa, e até onde cada transcript já foi lido.
///
/// Soma incremental, e não recontagem: o transcript muda de arquivo a cada
/// `/clear` e a limpeza da bancada, e o que já foi contado não pode sumir nem
/// entrar de novo. O cursor guarda o byte e o último id lido.
struct UsageLedger: Codable, Equatable {
    struct Cursor: Codable, Equatable {
        var offset: UInt64 = 0
        var lastId: String?
    }

    var byNode: [String: UsageByPrice] = [:]
    var cursors: [String: Cursor] = [:]

    var total: UsageByPrice { byNode.values.reduce([:], +) }

    mutating func absorb(_ entries: [UsageEntry], node: String, prices: PriceTable) {
        for entry in entries { byNode[node, default: [:]].add(entry, prices: prices) }
    }

    /// Lê o que o arquivo ganhou desde a última vez. `data` é o arquivo a
    /// partir do cursor; só entra até a última quebra de linha — a linha que o
    /// CLI ainda está escrevendo fica para a próxima. `parse` é o leitor do
    /// formato do CLI (hoje, `ClaudeUsage.entries`): o registro não sabe de CLI.
    mutating func absorb(chunk data: Data, of path: String, node: String, prices: PriceTable,
                         parse: (Data, String?) -> [UsageEntry]) {
        var cursor = cursors[path] ?? Cursor()
        guard let end = data.lastIndex(of: 0x0A) else { return }
        let complete = data[data.startIndex...end]
        let entries = parse(Data(complete), cursor.lastId)
        absorb(entries, node: node, prices: prices)
        cursor.offset += UInt64(complete.count)
        if let last = entries.last { cursor.lastId = last.id }
        cursors[path] = cursor
    }

    /// Congela o que entrou sem preço, se a tabela já o tiver.
    mutating func settle(_ prices: PriceTable) {
        byNode = byNode.mapValues { $0.settled(prices) }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        byNode = try c.decodeIfPresent([String: UsageByPrice].self, forKey: .byNode) ?? [:]
        cursors = try c.decodeIfPresent([String: Cursor].self, forKey: .cursors) ?? [:]
    }
}

/// As conversas que a trilha carimbou (ADR-036): `## <data> · <nó>` e, na
/// linha de baixo, `CLI · modelo · conversa <8 primeiros>`. É o que permite
/// achar os transcripts de antes de cada `/clear` na primeira contagem.
enum TraceConversations {
    static func parse(_ text: String) -> [(node: String, prefix: String)] {
        var out: [(String, String)] = []
        var node: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                node = line.components(separatedBy: " · ").last.map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            guard let current = node, let range = line.range(of: "conversa ") else { continue }
            let prefix = line[range.upperBound...].prefix { $0.isHexDigit || $0 == "-" }
            if prefix.count >= 8 { out.append((current, String(prefix.prefix(8)))) }
            node = nil
        }
        var seen: Set<String> = []
        return out.filter { seen.insert("\($0.0)#\($0.1.lowercased())").inserted }
    }
}

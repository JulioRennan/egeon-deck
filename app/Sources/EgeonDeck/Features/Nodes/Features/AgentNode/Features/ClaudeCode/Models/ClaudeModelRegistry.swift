import Foundation

/// O catálogo de modelos lido de dentro do binário do Claude Code.
///
/// O CLI carrega no próprio JavaScript uma tabela de modelos — id, família, nome
/// de exibição, capacidades e esforço padrão — e é dela que o `/model` e o
/// `/effort` da TUI saem. Não há comando que a imprima nem API sem chave (a
/// `/v1/models` pede API key, e login de assinatura não tem), então lê-se a
/// tabela no binário: atualizar o Claude Code atualiza o catálogo junto.
///
/// É código minificado e interno: o formato pode mudar numa versão qualquer.
/// Leitura que não acha nada devolve vazio, e o nó volta para os apelidos.
enum ClaudeModelRegistry {
    private static let entryStart = Data(#"{id:"claude-"#.utf8)
    private static let entryHead = try! NSRegularExpression(
        pattern: #"^\{id:"(claude-[a-z0-9-]+)",family:"([a-z0-9]+)",display_name:"([^"]+)""#)
    private static let capabilities = try! NSRegularExpression(pattern: #"capabilities:\[([^\]]*)\]"#)
    private static let defaultEffort = try! NSRegularExpression(pattern: #"default_effort:"([a-z]+)""#)
    /// Até onde uma entrada vai: a de hoje tem ~1,3 KB.
    private static let window = 4096

    /// Níveis na ordem do slider, e a capacidade que libera cada um. Os três
    /// primeiros vêm com `effort`; `xhigh` e `max` são capacidades à parte —
    /// o Opus 4.6 tem `max` e não tem `xhigh`.
    private static let levels: [(level: String, capability: String)] = [
        ("low", "effort"), ("medium", "effort"), ("high", "effort"),
        ("xhigh", "xhigh_effort"), ("max", "max_effort")
    ]

    static func parse(binary data: Data) -> [ModelCatalog.Model] {
        var found: [ModelCatalog.Model] = []
        var seen = Set<String>()
        var cursor = data.startIndex
        while let range = data.range(of: entryStart, in: cursor..<data.endIndex) {
            let end = min(range.lowerBound + window, data.endIndex)
            cursor = range.upperBound
            guard let text = String(data: data[range.lowerBound..<end], encoding: .isoLatin1),
                  let model = parse(entry: text), seen.insert(model.id).inserted else { continue }
            found.append(model)
        }
        return found
    }

    /// Uma entrada, a partir do `{id:"claude-`. Nil quando o trecho não é da
    /// tabela de modelos — o mesmo começo aparece em outras tabelas do CLI.
    static func parse(entry text: String) -> ModelCatalog.Model? {
        let whole = NSRange(text.startIndex..., in: text)
        guard let head = entryHead.firstMatch(in: text, range: whole),
              let id = Range(head.range(at: 1), in: text),
              let family = Range(head.range(at: 2), in: text),
              let label = Range(head.range(at: 3), in: text) else { return nil }
        // Só até a próxima entrada: as capacidades da vizinha não são desta.
        var body = String(text[label.upperBound...])
        if let next = body.range(of: #"{id:"claude-"#) { body = String(body[..<next.lowerBound]) }
        let bodyRange = NSRange(body.startIndex..., in: body)

        let caps: Set<String> = capabilities.firstMatch(in: body, range: bodyRange)
            .flatMap { Range($0.range(at: 1), in: body) }
            .map { body[$0].replacingOccurrences(of: "\"", with: "").split(separator: ",") }
            .map { Set($0.map(String.init)) } ?? []
        let efforts = caps.contains("effort") ? levels.filter { caps.contains($0.capability) }.map(\.level) : []
        let fallback = defaultEffort.firstMatch(in: body, range: bodyRange)
            .flatMap { Range($0.range(at: 1), in: body) }
            .map { String(body[$0]) }

        return ModelCatalog.Model(id: String(text[id]), family: String(text[family]),
                                  label: String(text[label]), efforts: efforts,
                                  defaultEffort: efforts.isEmpty ? nil : fallback)
    }
}

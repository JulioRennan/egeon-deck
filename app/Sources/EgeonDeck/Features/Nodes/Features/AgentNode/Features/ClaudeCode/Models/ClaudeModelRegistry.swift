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
    private static let pricing = try! NSRegularExpression(pattern: #"pricing:"([A-Za-z0-9_]+)""#)
    private static let field = try! NSRegularExpression(pattern: #"([a-z0-9_]+):(-?[0-9.]+(?:e[+-]?[0-9]+)?)"#)
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

        let tier = pricing.firstMatch(in: body, range: bodyRange)
            .flatMap { Range($0.range(at: 1), in: body) }
            .map { String(body[$0]) }

        return ModelCatalog.Model(id: String(text[id]), family: String(text[family]),
                                  label: String(text[label]), efforts: efforts,
                                  defaultEffort: efforts.isEmpty ? nil : fallback, pricing: tier)
    }

    /// Os preços que o `/cost` do CLI usa: `pricing_tiers:{tier:{input:…}}`
    /// em US$ por milhão, e cada modelo apontando para a sua faixa. A faixa
    /// pode ter `long_prompt:{above_prompt_tokens:…}` — vira a tarifa `#long`.
    static func prices(binary data: Data, models: [ModelCatalog.Model]) -> [String: ModelPrice] {
        guard let start = data.range(of: Data("pricing_tiers:{".utf8)),
              let text = String(data: data[start.upperBound..<min(start.upperBound + 16_384, data.endIndex)],
                                encoding: .isoLatin1) else { return [:] }
        return prices(tiers: tiers(in: text), models: models)
    }

    static func prices(tiers: [String: [String: Double]], models: [ModelCatalog.Model]) -> [String: ModelPrice] {
        var out: [String: ModelPrice] = [:]
        for model in models {
            guard let name = model.pricing, let tier = tiers[name],
                  let price = price(tier, prefix: "", name: model.label) else { continue }
            out[model.id] = price
            if let above = tier["long.above_prompt_tokens"],
               var long = self.price(tier, prefix: "long.", name: "\(model.label) (prompt > \(Int(above) / 1000)K)") {
                long.longAbove = Int(above)
                out[model.id + "#long"] = long
            }
        }
        return out
    }

    private static func price(_ tier: [String: Double], prefix: String, name: String) -> ModelPrice? {
        guard let input = tier[prefix + "input"], let output = tier[prefix + "output"],
              let read = tier[prefix + "cache_read"] else { return nil }
        return ModelPrice(name: name, input: input, output: output, cacheRead: read,
                          cacheWrite5m: tier[prefix + "cache_write_5m"], cacheWrite1h: tier[prefix + "cache_write_1h"])
    }

    /// As faixas, do texto logo depois de `pricing_tiers:{`. Os campos de
    /// `long_prompt` vêm com o prefixo `long.`.
    static func tiers(in text: String) -> [String: [String: Double]] {
        var out: [String: [String: Double]] = [:]
        let chars = Array(text.unicodeScalars)
        var i = 0
        while i < chars.count {
            // Fim do objeto das faixas.
            if chars[i] == "}" { break }
            var name = ""
            while i < chars.count, chars[i] != ":" { name.unicodeScalars.append(chars[i]); i += 1 }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            guard i + 1 < chars.count, chars[i + 1] == "{" else { break }
            i += 2
            var depth = 1
            var body = ""
            while i < chars.count, depth > 0 {
                if chars[i] == "{" { depth += 1 }
                if chars[i] == "}" { depth -= 1 }
                if depth > 0 { body.unicodeScalars.append(chars[i]) }
                i += 1
            }
            var main = body
            var long = ""
            if let range = body.range(of: "long_prompt:{"), let close = body[range.upperBound...].firstIndex(of: "}") {
                long = String(body[range.upperBound..<close])
                main = String(body[..<range.lowerBound]) + String(body[body.index(after: close)...])
            }
            var fields = numbers(in: main)
            for (key, value) in numbers(in: long) { fields["long." + key] = value }
            if !name.isEmpty, !fields.isEmpty { out[name] = fields }
            if i < chars.count, chars[i] == "," { i += 1 }
        }
        return out
    }

    private static func numbers(in text: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for match in field.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let key = Range(match.range(at: 1), in: text), let value = Range(match.range(at: 2), in: text),
                  let number = Double(text[value]) else { continue }
            out[String(text[key])] = number
        }
        return out
    }
}

import Foundation

/// Preço de um modelo, em US$ por milhão de tokens (ADR-085).
struct ModelPrice: Codable, Equatable {
    var name: String
    var input: Double
    var output: Double
    /// Cache lido. Não é uma fração fixa da entrada: 0,1× na maioria, 0,05×
    /// no Opus 5.5, 0,025× no Fable 5.1.
    var cacheRead: Double
    /// Escrita de cache: 1,25× a entrada no de 5 minutos, 2× no de 1 hora.
    var cacheWrite5m: Double? = nil
    var cacheWrite1h: Double? = nil
    /// Só na tarifa `#long`: a partir de quantos tokens de prompt ela vale.
    var longAbove: Int? = nil

    func cost(_ usage: TokenUsage) -> Double { split(usage).total }

    /// O custo em cada tarifa — o que a barra do detalhe desenha.
    func split(_ usage: TokenUsage) -> TariffCost {
        let write5m: Double = cacheWrite5m ?? input * 1.25
        let write1h: Double = cacheWrite1h ?? input * 2
        var write: Double = Double(usage.cacheWrite5m) * write5m
        write += Double(usage.cacheWrite1h) * write1h
        return TariffCost(input: Double(usage.input) * input / 1_000_000,
                          output: Double(usage.output) * output / 1_000_000,
                          cacheWrite: write / 1_000_000,
                          cacheRead: Double(usage.cacheRead) * cacheRead / 1_000_000)
    }

    func scaled(_ factor: Double, name suffix: String) -> ModelPrice {
        ModelPrice(name: name + suffix, input: input * factor, output: output * factor,
                   cacheRead: cacheRead * factor,
                   cacheWrite5m: cacheWrite5m.map { $0 * factor },
                   cacheWrite1h: cacheWrite1h.map { $0 * factor }, longAbove: longAbove)
    }
}

/// Dólares por tarifa.
struct TariffCost: Codable, Equatable {
    var input = 0.0
    var output = 0.0
    var cacheWrite = 0.0
    var cacheRead = 0.0

    var total: Double { input + output + cacheWrite + cacheRead }

    static func + (a: TariffCost, b: TariffCost) -> TariffCost {
        TariffCost(input: a.input + b.input, output: a.output + b.output,
                   cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }
}

/// A tabela de preços (ADR-085), em camadas: a embutida, o catálogo do Claude
/// Code instalado por cima (atualiza com ele) e o `pricing.json` por cima de
/// tudo — só as exceções que você quiser forçar.
///
/// O preço é aplicado quando o gasto ENTRA, não na hora de mostrar: tabela que
/// muda vale dali para frente (`Spend`).
///
/// Uma chave por TARIFA, não por modelo: o modo rápido custa o dobro e o Haiku
/// 5.5 muda de preço com prompt acima de 100K — a requisição precisa ser
/// classificada quando é lida, porque depois só sobra a soma.
struct PriceTable: Equatable {
    enum Origin: String { case builtIn, claudeCode, file }

    var models: [String: ModelPrice]
    var origin: [String: Origin] = [:]

    /// Tabela oficial da Anthropic, API de primeira parte, em 2026-10-06. É a
    /// reserva: vale para o que o catálogo do Claude Code não trouxer.
    static let builtIn: [String: ModelPrice] = [
        "claude-fable-5-1": ModelPrice(name: "Fable 5.1", input: 10, output: 50, cacheRead: 0.25),
        "claude-mythos-5-1": ModelPrice(name: "Mythos 5.1", input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5": ModelPrice(name: "Fable 5", input: 10, output: 50, cacheRead: 1),
        "claude-mythos-5": ModelPrice(name: "Mythos 5", input: 10, output: 50, cacheRead: 1),
        "claude-opus-5-5": ModelPrice(name: "Opus 5.5", input: 4, output: 20, cacheRead: 0.2),
        "claude-opus-5": ModelPrice(name: "Opus 5", input: 5, output: 25, cacheRead: 0.5),
        "claude-opus-4-8": ModelPrice(name: "Opus 4.8", input: 5, output: 25, cacheRead: 0.5),
        "claude-opus-4-7": ModelPrice(name: "Opus 4.7", input: 5, output: 25, cacheRead: 0.5),
        "claude-opus-4-6": ModelPrice(name: "Opus 4.6", input: 5, output: 25, cacheRead: 0.5),
        "claude-sonnet-5-5": ModelPrice(name: "Sonnet 5.5", input: 2, output: 10, cacheRead: 0.2),
        "claude-sonnet-5": ModelPrice(name: "Sonnet 5", input: 2, output: 10, cacheRead: 0.2),
        "claude-sonnet-4-6": ModelPrice(name: "Sonnet 4.6", input: 3, output: 15, cacheRead: 0.3),
        "claude-haiku-5-5": ModelPrice(name: "Haiku 5.5", input: 0.1, output: 0.5, cacheRead: 0.01),
        "claude-haiku-5-5#long": ModelPrice(name: "Haiku 5.5 (prompt > 100K)", input: 0.5, output: 2.5,
                                            cacheRead: 0.05, longAbove: 100_000),
        "claude-haiku-4-5": ModelPrice(name: "Haiku 4.5", input: 1, output: 5, cacheRead: 0.1),
    ]

    /// O modo rápido custa o dobro (Opus 5.5: US$ 8 / 40).
    static let fastFactor = 2.0
    /// A partir daqui o prompt do Haiku 5.5 sai na faixa cara.
    static let longPromptThreshold = 100_000

    static var file: URL { Flavor.current.config("pricing.json") }

    /// As três camadas juntas. `catalog` é o que o Claude Code instalado traz.
    static func load(catalog: [String: ModelPrice] = [:]) -> PriceTable {
        var table = PriceTable(models: builtIn, origin: builtIn.mapValues { _ in .builtIn })
        table.overlay(catalog, as: .claudeCode)
        table.overlay(fileOverrides(), as: .file)
        return table
    }

    private mutating func overlay(_ layer: [String: ModelPrice], as source: Origin) {
        for (key, price) in layer {
            models[key] = price
            origin[key] = source
        }
    }

    private static func fileOverrides() -> [String: ModelPrice] {
        guard let data = try? Data(contentsOf: file),
              let custom = try? JSONDecoder().decode([String: ModelPrice].self, from: data) else { return [:] }
        // A versão anterior semeava o arquivo com a tabela inteira — e aí ele
        // congelaria os preços por cima de qualquer atualização. Cópia
        // intacta da embutida não é escolha sua: não vale.
        return isSeedCopy(custom) ? [:] : custom
    }

    /// A cópia que a versão anterior semeou — sem o `longAbove`, que ela não
    /// tinha.
    static func isSeedCopy(_ custom: [String: ModelPrice]) -> Bool {
        func plain(_ table: [String: ModelPrice]) -> [String: ModelPrice] {
            table.mapValues { var price = $0; price.longAbove = nil; return price }
        }
        return plain(custom) == plain(builtIn)
    }

    /// O arquivo nasce vazio — é o lugar das exceções. A cópia antiga da
    /// tabela inteira, intocada, é trocada pelo vazio.
    static func seedFileIfMissing() {
        let data = try? Data(contentsOf: file)
        if let data, !((try? JSONDecoder().decode([String: ModelPrice].self, from: data)).map(isSeedCopy) ?? false) {
            return
        }
        try? Data("{}\n".utf8).write(to: file, options: .atomic)
    }

    /// A tabela em vigor, para quem lê fora da fila principal (o leitor do
    /// transcript, o histórico do chat). Quem a troca é o `UsageStore`.
    static var current: PriceTable {
        get { currentLock.withLock { currentTable } }
        set { currentLock.withLock { currentTable = newValue } }
    }
    private static let currentLock = NSLock()
    private static var currentTable = PriceTable.load()

    func key(for entry: UsageEntry) -> String {
        let model = Self.canonical(entry.model)
        if entry.fast { return model + "#fast" }
        if let long = models[model + "#long"], entry.usage.prompt > long.longAbove ?? Self.longPromptThreshold {
            return model + "#long"
        }
        return model
    }

    /// `nil` quando o modelo não está na tabela: melhor mostrar só os tokens
    /// que inventar um preço.
    func price(for key: String) -> ModelPrice? {
        if let price = models[key] { return price }
        if key.hasSuffix("#fast"), let base = models[String(key.dropLast(5))] {
            return base.scaled(Self.fastFactor, name: " (rápido)")
        }
        return nil
    }

    /// O custo congelado, mais o pendente pelo preço de agora — quando já
    /// houver um. `unpriced`: sobrou token sem preço nenhum.
    func cost(_ usage: UsageByPrice) -> (dollars: Double, unpriced: Bool) {
        var dollars = 0.0
        var unpriced = false
        for (key, spend) in usage {
            dollars += spend.cost.total
            guard !spend.pending.isEmpty else { continue }
            if let price = price(for: key) { dollars += price.cost(spend.pending) } else { unpriced = true }
        }
        return (dollars, unpriced)
    }

    /// Sem o que não tem preço.
    func split(_ usage: UsageByPrice) -> TariffCost {
        usage.reduce(TariffCost()) { total, item in
            total + item.value.cost + (price(for: item.key)?.split(item.value.pending) ?? TariffCost())
        }
    }

    /// O modelo em que mais se gastou — o que identifica o agente no detalhe.
    func mainModel(_ usage: UsageByPrice) -> String? {
        usage.max { cost([$0.key: $0.value]).dollars < cost([$1.key: $1.value]).dollars }
            .map { name(for: $0.key) }
    }

    func name(for key: String) -> String {
        price(for: key)?.name ?? key
    }

    /// Id com data (`claude-haiku-4-5-20251001`) cai no modelo sem ela.
    static func canonical(_ model: String) -> String {
        let parts = model.split(separator: "-")
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            return parts.dropLast().joined(separator: "-")
        }
        return model
    }
}

/// Como o dinheiro e os tokens aparecem na tela.
enum UsageText {
    static func dollars(_ value: Double) -> String {
        if value > 0, value < 0.01 { return "< US$ 0,01" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "US$ " + (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }

    static func tokens(_ value: Int) -> String {
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return String(format: "%.1fK", Double(value) / 1_000).replacingOccurrences(of: ".", with: ",")
        default: return String(format: "%.2fM", Double(value) / 1_000_000).replacingOccurrences(of: ".", with: ",")
        }
    }

    /// "US$ 1,23" ou, com modelo sem preço, "US$ 1,23+".
    static func cost(_ usage: UsageByPrice, prices: PriceTable) -> String {
        let (value, unpriced) = prices.cost(usage)
        return dollars(value) + (unpriced ? "+" : "")
    }

    /// As quatro tarifas numa linha, para dica de tela.
    static func breakdown(_ usage: TokenUsage) -> String {
        "entrada \(tokens(usage.input)) · saída \(tokens(usage.output)) · "
            + "cache escrito \(tokens(usage.cacheWrite)) · cache lido \(tokens(usage.cacheRead))"
    }
}

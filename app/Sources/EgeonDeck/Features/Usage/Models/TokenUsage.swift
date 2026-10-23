import Foundation

/// Tokens gastos, nas quatro tarifas em que o preço se divide (ADR-085).
/// Escrita de cache vem em duas: a de 5 minutos custa 1,25× a entrada e a de
/// 1 hora, 2× — o Claude Code usa as duas, e somá-las juntas erraria o custo.
struct TokenUsage: Codable, Equatable {
    var input = 0
    var output = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var cacheRead = 0

    var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    var total: Int { input + output + cacheWrite + cacheRead }
    /// O tamanho do prompt da requisição — é por ele que o Haiku 5.5 muda de
    /// faixa de preço.
    var prompt: Int { input + cacheWrite + cacheRead }
    var isEmpty: Bool { total == 0 }

    static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output,
                   cacheWrite5m: a.cacheWrite5m + b.cacheWrite5m,
                   cacheWrite1h: a.cacheWrite1h + b.cacheWrite1h,
                   cacheRead: a.cacheRead + b.cacheRead)
    }

    static func += (a: inout TokenUsage, b: TokenUsage) { a = a + b }

    init(input: Int = 0, output: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
        output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
        cacheWrite5m = try c.decodeIfPresent(Int.self, forKey: .cacheWrite5m) ?? 0
        cacheWrite1h = try c.decodeIfPresent(Int.self, forKey: .cacheWrite1h) ?? 0
        cacheRead = try c.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
    }
}

/// Uma resposta do modelo, como o transcript a registra: quem respondeu, em
/// que velocidade e quanto gastou. O `id` é o da mensagem — o CLI grava uma
/// linha por bloco de conteúdo, todas com o mesmo uso, e somar cada linha
/// contaria a resposta várias vezes.
struct UsageEntry: Equatable {
    var id: String
    var model: String
    var fast = false
    var usage: TokenUsage
}

/// O que se gastou numa tarifa: os tokens e o custo CONGELADO no preço do
/// momento em que entraram (ADR-085). Preço novo vale dali para frente — o
/// passado não se recalcula. `pending` é o que entrou sem preço conhecido:
/// ganha preço (e congela) quando a tabela passar a ter o modelo.
struct Spend: Codable, Equatable {
    var tokens = TokenUsage()
    var cost = TariffCost()
    var pending = TokenUsage()

    static func + (a: Spend, b: Spend) -> Spend {
        Spend(tokens: a.tokens + b.tokens, cost: a.cost + b.cost, pending: a.pending + b.pending)
    }

    init(tokens: TokenUsage = TokenUsage(), cost: TariffCost = TariffCost(), pending: TokenUsage = TokenUsage()) {
        self.tokens = tokens
        self.cost = cost
        self.pending = pending
    }

    /// O formato de antes era só os tokens: entram como pendentes, e quem lê o
    /// arquivo congela com o preço em vigor (`settled`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.tokens) else {
            tokens = try TokenUsage(from: decoder)
            pending = tokens
            return
        }
        tokens = try c.decode(TokenUsage.self, forKey: .tokens)
        cost = try c.decodeIfPresent(TariffCost.self, forKey: .cost) ?? TariffCost()
        pending = try c.decodeIfPresent(TokenUsage.self, forKey: .pending) ?? TokenUsage()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tokens, forKey: .tokens)
        try c.encode(cost, forKey: .cost)
        if !pending.isEmpty { try c.encode(pending, forKey: .pending) }
    }

    private enum CodingKeys: String, CodingKey { case tokens, cost, pending }
}

/// Uso agrupado pela chave de preço (`PriceTable.key`).
typealias UsageByPrice = [String: Spend]

extension Dictionary where Key == String, Value == Spend {
    mutating func add(_ entry: UsageEntry, prices: PriceTable) {
        let key = prices.key(for: entry)
        var spend = self[key] ?? Spend()
        spend.tokens += entry.usage
        if let price = prices.price(for: key) {
            spend.cost = spend.cost + price.split(entry.usage)
        } else {
            spend.pending += entry.usage
        }
        self[key] = spend
    }

    /// O pendente que agora tem preço passa a ter custo congelado.
    func settled(_ prices: PriceTable) -> Self {
        var out = self
        for (key, spend) in self where !spend.pending.isEmpty {
            guard let price = prices.price(for: key) else { continue }
            out[key] = Spend(tokens: spend.tokens, cost: spend.cost + price.split(spend.pending))
        }
        return out
    }

    var totalUsage: TokenUsage { values.reduce(TokenUsage()) { $0 + $1.tokens } }

    static func + (a: Self, b: Self) -> Self { a.merging(b, uniquingKeysWith: +) }
}

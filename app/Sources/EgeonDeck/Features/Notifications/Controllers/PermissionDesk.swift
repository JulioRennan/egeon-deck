import Foundation

/// Os pedidos de permissão abertos, e a resposta que o gancho vem buscar
/// (ADR-068).
///
/// O diálogo do CLI continua na tela enquanto o gancho espera — medido —, e
/// responder lá também vale. Por isso o pedido tem três fins: resposta daqui
/// (o gancho a leva ao CLI), resposta no terminal (você teclou nele; o
/// gancho sai calado) ou turno que seguiu (`prompt`/`stop` daquele terminal).
/// Só na main.
final class PermissionDesk {
    static let shared = PermissionDesk()

    enum State: Equatable {
        case pending
        case answered(PermissionAnswer)
        /// Respondido em outro lugar, ou o pedido nunca existiu.
        case gone
    }

    private var asks: [PermissionAsk] = []
    private var answers: [String: (answer: PermissionAnswer, output: [String: Any], at: Date)] = [:]
    private var counter = 0
    /// O relógio, injetável para o teste da validade.
    var now: () -> Date = Date.init

    /// Quanto um pedido vale. O gancho desiste depois de `permissionWait`
    /// segundos — ou antes, se o socket falhar —, e um pedido mais velho que
    /// isso não tem mais quem leve a resposta: clicar nele seria aprovar nada.
    static let lifetime = TimeInterval(ClaudeHooks.permissionWait)

    init() {}

    /// Os pedidos ainda respondíveis.
    var open: [PermissionAsk] {
        expire()
        return asks
    }

    private func expire() {
        let limit = now().addingTimeInterval(-Self.lifetime)
        asks.removeAll { $0.openedAt < limit }
        answers = answers.filter { $0.value.at >= limit }
    }

    /// Abre um pedido. Vários do mesmo terminal convivem: chamadas de
    /// ferramenta em paralelo (ou subagentes) disparam um gancho cada, e cada
    /// resposta é do seu pedido.
    @discardableResult
    func open(address: String, payload: [String: Any]) -> PermissionAsk? {
        counter += 1
        let at = now()
        let id = String(format: "p%d-%.0f", counter, at.timeIntervalSince1970 * 1000)
        guard let ask = PermissionAsk(id: id, address: address, payload: payload, openedAt: at) else {
            return nil
        }
        asks.append(ask)
        Log.write("permissão[\(address)]: aberta \(id) — \(ask.tool): \(ask.summary.prefix(120))")
        return ask
    }

    func state(of id: String) -> State {
        expire()
        if let answered = answers[id] { return .answered(answered.answer) }
        return asks.contains { $0.id == id } ? .pending : .gone
    }

    /// A saída que o gancho imprime. Lida uma vez: entregue, o pedido acaba.
    func takeOutput(of id: String) -> [String: Any]? {
        answers.removeValue(forKey: id)?.output
    }

    /// Você respondeu daqui. `false` se o pedido já tinha acabado.
    @discardableResult
    func answer(_ id: String, with answer: PermissionAnswer) -> Bool {
        expire()
        guard let index = asks.firstIndex(where: { $0.id == id }) else { return false }
        let ask = asks.remove(at: index)
        answers[id] = (answer, answer.hookOutput(suggestions: ask.suggestions), now())
        Log.write("permissão[\(ask.address)]: \(answer.rawValue) pelo chat — \(id)")
        return true
    }

    /// Você respondeu as perguntas do `AskUserQuestion` daqui. `false` se o
    /// pedido acabou ou se as escolhas não fecham com as perguntas.
    @discardableResult
    func answer(_ id: String, choices: [String: [String]]) -> Bool {
        expire()
        guard let index = asks.firstIndex(where: { $0.id == id }), asks[index].accepts(choices) else {
            return false
        }
        let ask = asks.remove(at: index)
        answers[id] = (.allow, ask.answerOutput(choices), now())
        Log.write("permissão[\(ask.address)]: pergunta respondida pelo chat — \(id)")
        return true
    }

    /// O pedido deste terminal acabou fora daqui.
    func drop(address: String, why: String? = nil) {
        let before = asks.count
        asks.removeAll { $0.address == address }
        guard asks.count != before else { return }
        if let why { Log.write("permissão[\(address)]: fechada — \(why)") }
    }

    func pending(inWorkbench name: String) -> [PermissionAsk] {
        open.filter { $0.address.hasPrefix(name + "/") }
    }

    /// O endereço mudou com a bancada renomeada.
    func renamed(_ old: String, to new: String) {
        asks = asks.map { ask in
            guard ask.address == old else { return ask }
            return PermissionAsk(id: ask.id, address: new, tool: ask.tool, summary: ask.summary,
                                 detail: ask.detail, suggestions: ask.suggestions,
                                 input: ask.input, openedAt: ask.openedAt)
        }
    }
}

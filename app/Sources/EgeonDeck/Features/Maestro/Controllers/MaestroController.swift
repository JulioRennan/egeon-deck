import Foundation

/// Atende o maestro: confere que quem chama é um, lê a bancada e aplica o
/// plano (ADR-066).
///
/// Não guarda bancada nem nó, como o `EdgeController`: lê e escreve pelas
/// closures, e quem tem o `workbenches.json` continua sendo o AppDelegate. É o
/// que faz o fluxo inteiro — recusa, prévia, aplicação, trilha — rodar em
/// teste sem tela.
final class MaestroController {
    struct Wiring {
        /// A bancada pelo nome — a primeira parte do endereço.
        var bench: (String) -> WorkbenchConfig?
        /// O mundo que o planejador precisa, montado na hora para a bancada.
        var context: (_ bench: WorkbenchConfig, _ caller: String) -> MaestroContext
        var activity: (_ address: String) -> Activity?
        var profiles: () -> [String: AgentProfile]
        var catalog: (AgentProfile) -> ModelCatalog?
        /// Grava a bancada seguinte no lugar da atual, pelo id.
        var commit: (WorkbenchConfig) -> Void
        /// Monta na tela um nó que já está na bancada gravada.
        var spawn: (_ bench: String, _ node: String) -> Void
        /// Reergue um nó com o que a bancada gravada diz dele.
        var restart: (_ bench: String, _ node: String) -> Void
        /// Tira da tela um nó que já saiu da bancada gravada.
        var dispose: (_ bench: String, _ node: String) -> Void
        var redrawEdges: (_ bench: String) -> Void
        /// Leva os cards na tela aos frames que a bancada gravada diz, e
        /// enquadra (ADR-066).
        var arrange: (_ bench: String) -> Void = { _ in }
        var persist: () -> Void
        /// Linha na trilha da bancada, carimbada como quem chamou.
        var trace: (_ address: String, _ text: String) -> Void
    }

    private let wiring: Wiring

    init(_ wiring: Wiring) { self.wiring = wiring }

    static let notMaestro = "este terminal não é maestro — quem decide isso é o usuário, no "
        + "formulário do terminal (⚙ no card → \"Maestro\")"

    /// Quem chama tem de ser um nó maestro com bancada carregada.
    private func authorize(_ caller: String?) -> Result<(WorkbenchConfig, NodeConfig), Refusal> {
        guard let caller else {
            return .failure(Refusal(status: 403, message: "esta conexão não veio de um terminal"))
        }
        let parts = caller.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let bench = wiring.bench(parts[0]),
              let node = bench.nodes.first(where: { $0.id == parts[1] }) else {
            return .failure(Refusal(status: 404, message: "nó sem bancada carregada"))
        }
        guard node.isMaestro else { return .failure(Refusal(status: 403, message: Self.notMaestro)) }
        return .success((bench, node))
    }

    struct Refusal: Error {
        let status: Int
        let message: String
        var json: [String: Any] { ["ok": false, "error": message] }
    }

    // MARK: - Leitura

    func bench(caller: String?) -> (status: Int, json: [String: Any]) {
        switch authorize(caller) {
        case .failure(let refusal): return (refusal.status, refusal.json)
        case .success(let (bench, node)):
            let payload = MaestroSnapshot.bench(bench, caller: node.id) { id in
                self.wiring.activity("\(bench.name)/\(id)")
            }
            return (200, payload)
        }
    }

    func models(caller: String?) -> (status: Int, json: [String: Any]) {
        switch authorize(caller) {
        case .failure(let refusal): return (refusal.status, refusal.json)
        case .success:
            return (200, MaestroSnapshot.models(profiles: wiring.profiles(), catalog: wiring.catalog))
        }
    }

    // MARK: - Plano

    /// `dry` valida e mostra o que mudaria; sem ele, aplica. Plano com erro
    /// não muda nada, em nenhum dos dois.
    func apply(_ body: Data, caller: String?, dry: Bool) -> (status: Int, json: [String: Any]) {
        let bench: WorkbenchConfig, me: NodeConfig
        switch authorize(caller) {
        case .failure(let refusal): return (refusal.status, refusal.json)
        case .success(let found): (bench, me) = found
        }

        let plan: MaestroPlan
        switch MaestroPlan.parse(body) {
        case .failure(let error): return (400, ["ok": false, "errors": [error.message]])
        case .success(let parsed): plan = parsed
        }
        guard !plan.isEmpty else {
            return (400, ["ok": false, "errors": ["plano sem nada: use nodes, remove, edges, "
                                                   + "unlink, rules ou maxVisits"]])
        }

        let outcome = MaestroPlanner.plan(plan, on: bench, context: wiring.context(bench, me.id))
        guard outcome.errors.isEmpty else {
            return (422, ["ok": false, "errors": outcome.errors,
                          "detail": "nada foi aplicado — corrija e mande o plano inteiro de novo"])
        }

        var payload: [String: Any] = [
            "ok": true,
            "dry": dry,
            "summary": outcome.summary,
            "created": outcome.created,
            "restarted": outcome.restarted,
            "removed": outcome.removed,
        ]
        if dry {
            payload["result"] = MaestroSnapshot.bench(outcome.next, caller: me.id) { _ in nil }
            payload["detail"] = "prévia — nada mudou. `egeon apply` com o mesmo plano aplica."
            return (200, payload)
        }
        guard outcome.changed else {
            payload["detail"] = "o plano já é o que está na bancada — nada mudou"
            return (200, payload)
        }

        wiring.commit(outcome.next)
        for id in outcome.removed { wiring.dispose(bench.name, id) }
        for id in outcome.restarted { wiring.restart(bench.name, id) }
        for id in outcome.created { wiring.spawn(bench.name, id) }
        wiring.redrawEdges(bench.name)
        if outcome.relaid { wiring.arrange(bench.name) }
        wiring.persist()
        wiring.trace("\(bench.name)/\(me.id)", "maestro aplicou: \(outcome.summary)")
        Log.write("maestro[\(bench.name)/\(me.id)]: \(outcome.summary)")

        var notes: [String] = []
        if !outcome.created.isEmpty {
            notes.append("\(outcome.created.joined(separator: ", ")) sobem em alguns segundos; você já os "
                         + "alcança sem aresta, e `egeon send` enfileira até ficarem prontos")
        }
        let kept = outcome.restarted.filter { !outcome.freshConversation.contains($0) }
        if !kept.isEmpty {
            notes.append("\(kept.joined(separator: ", ")) reiniciaram com a mesma conversa")
        }
        if !outcome.freshConversation.isEmpty {
            notes.append("\(outcome.freshConversation.joined(separator: ", ")) reiniciaram com conversa "
                         + "NOVA (pasta, configuração ou CLI mudou) — o que eles sabiam ficou para trás")
        }
        if outcome.rulesChanged {
            notes.append("as regras novas da bancada valem para você no seu próximo arranque")
        }
        if !notes.isEmpty { payload["notes"] = notes }
        return (200, payload)
    }
}

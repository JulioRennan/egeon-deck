import XCTest
@testable import EgeonDeck

/// O maestro que aprova as permissões do time (ADR-080): quem recebe o aviso,
/// o que ele diz, e quem pode responder o quê.
final class MaestroPermissionsTests: XCTestCase {
    private var bench: WorkbenchConfig!
    private var open: [PermissionAsk] = []
    private var answered: [String] = []
    private var traced: [String] = []

    override func setUp() {
        var maestro = NodeConfig(type: .agent, id: "maestro")
        maestro.agent = "claude"
        maestro.maestro = true
        var revisor = NodeConfig(type: .agent, id: "revisor")
        revisor.agent = "claude"
        bench = WorkbenchConfig(name: "deck", path: "/tmp", nodes: [maestro, revisor])
        open = [
            ask("p1", from: "deck/revisor"),
            ask("p2", from: "deck/maestro"),
            ask("p3", from: "outra/revisor"),
            ask("p4", from: "deck/revisor", tool: "AskUserQuestion"),
        ]
        answered = []
        traced = []
    }

    private func ask(_ id: String, from address: String, tool: String = "Bash",
                     suggestions: [[String: Any]] = []) -> PermissionAsk {
        PermissionAsk(id: id, address: address, tool: tool, summary: "rm -rf build",
                      detail: "limpa o build", suggestions: suggestions)
    }

    private func controller() -> MaestroController {
        MaestroController(.init(
            bench: { [unowned self] name in name == bench.name ? bench : nil },
            context: { _, caller in MaestroContext(caller: caller, profiles: ["claude": .claudeCode]) },
            activity: { _ in .ready },
            profiles: { ["claude": .claudeCode] },
            catalog: { _ in nil },
            commit: { _ in }, spawn: { _, _ in }, restart: { _, _ in }, dispose: { _, _ in },
            redrawEdges: { _ in }, persist: {},
            permissions: { [unowned self] in open },
            answerPermission: { [unowned self] id, answer, by in
                guard let index = open.firstIndex(where: { $0.id == id }) else { return false }
                open.remove(at: index)
                answered.append("\(id) \(answer.rawValue) \(by)")
                return true
            },
            trace: { [unowned self] address, text in traced.append("\(address): \(text)") }))
    }

    func testApproverIsTheMaestroAndNeverTheAsker() {
        XCTAssertEqual(MaestroPermissions.approver(for: open[0], in: bench)?.id, "maestro")
        XCTAssertNil(MaestroPermissions.approver(for: open[1], in: bench), "o próprio pedido")
        XCTAssertNil(MaestroPermissions.approver(for: open[2], in: bench), "outra bancada")
        XCTAssertNil(MaestroPermissions.approver(for: open[3], in: bench), "pergunta ao usuário")

        bench.nodes[0].maestro = nil
        XCTAssertNil(MaestroPermissions.approver(for: open[0], in: bench), "deixou de ser maestro")
    }

    func testNoticeIsOneShortLineWithTheCommands() {
        let plain = MaestroPermissions.notice(for: open[0])
        XCTAssertEqual(plain, "[ED] pedido de permissão de revisor — Bash: rm -rf build (limpa o build) — "
                       + "responda: egeon allow p1 · egeon deny p1")

        let long = PermissionAsk(id: "p9", address: "deck/revisor", tool: "Bash",
                                 summary: String(repeating: "x", count: 300) + "\nsegunda linha",
                                 suggestions: [["type": "addRules"]])
        let notice = MaestroPermissions.notice(for: long)
        XCTAssertFalse(notice.contains("\n"), "várias linhas entram como colado")
        XCTAssertLessThan(notice.count, 260)
        XCTAssertTrue(notice.hasSuffix("egeon allow p9 (ou --always) · egeon deny p9"))
    }

    func testListingShowsOnlyTheTeamsToolRequests() {
        let json = controller().permissions(caller: "deck/maestro").json
        let ids = (json["open"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        XCTAssertEqual(ids, ["p1"])
    }

    func testAnswerRefusals() {
        let c = controller()
        XCTAssertEqual(c.answerPermission("p1", answer: .allow, caller: "deck/revisor").status, 403,
                       "quem não é maestro")
        XCTAssertEqual(c.answerPermission("p2", answer: .allow, caller: "deck/maestro").status, 403,
                       "o próprio pedido")
        XCTAssertEqual(c.answerPermission("p3", answer: .allow, caller: "deck/maestro").status, 403,
                       "outra bancada")
        XCTAssertEqual(c.answerPermission("p4", answer: .allow, caller: "deck/maestro").status, 403,
                       "pergunta ao usuário")
        XCTAssertEqual(c.answerPermission("p7", answer: .allow, caller: "deck/maestro").status, 404)

        bench.nodes[0].maestro = nil
        XCTAssertEqual(c.answerPermission("p1", answer: .allow, caller: "deck/maestro").status, 403,
                       "deixou de ser maestro")
        XCTAssertEqual(c.permissions(caller: "deck/maestro").status, 403)
        XCTAssertEqual(answered, [])
        XCTAssertEqual(traced, [])
    }

    func testAnswerGoesThroughAndIsTraced() {
        let c = controller()
        let reply = c.answerPermission("p1", answer: .deny, caller: "deck/maestro")
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(answered, ["p1 deny pelo maestro maestro"])
        XCTAssertEqual(traced, ["deck/maestro: maestro negou Bash de revisor: rm -rf build"])
        XCTAssertEqual(c.answerPermission("p1", answer: .allow, caller: "deck/maestro").status, 404,
                       "respondido uma vez, acabou")
    }

    func testOnlyTheUserGrantsIt() throws {
        // O plano do maestro não dá o poder a ninguém, nem a si mesmo.
        let plan = Data(#"{"nodes":[{"id":"revisor","approvesPermissions":true}]}"#.utf8)
        guard case .failure = MaestroPlan.parse(plan) else { return XCTFail("o plano aceitou") }

        // Vem com o maestro, sem caixa à parte: o componente maestro aprova.
        var template = NodeTemplateStore.capture(from: bench.nodes[0], name: "regente")
        XCTAssertEqual(NodeTemplateStore.instantiate(template, id: "m").approvesTeamPermissions, true)
        template.maestro = nil
        XCTAssertFalse(NodeTemplateStore.instantiate(template, id: "m").approvesTeamPermissions)

        // A chave antiga, de quando era caixa à parte, é só ignorada.
        let old = Data(#"{"type":"agent","id":"m","maestro":true,"approvesTeam":false}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(NodeConfig.self, from: old).approvesTeamPermissions)
    }
}

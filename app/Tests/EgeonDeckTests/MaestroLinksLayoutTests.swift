import XCTest
@testable import EgeonDeck

/// O maestro como mestre da bancada: alcança todos sem aresta desenhada, e o
/// canvas se arruma em hierarquia quando ele monta o time (ADR-066).
final class MaestroLinksLayoutTests: XCTestCase {
    private func node(_ id: String, _ type: NodeKind, maestro: Bool = false) -> NodeConfig {
        var node = NodeConfig(type: type, id: id)
        if type == .agent { node.agent = "claude" }
        node.maestro = maestro ? true : nil
        return node
    }

    func testMaestroReachesEveryoneAndAgentsReachBack() {
        let bench = WorkbenchConfig(name: "deck", path: "/tmp", nodes: [
            node("m", .agent, maestro: true), node("a", .agent), node("dev", .shell), node("ed", .editor)])
        let edges = MaestroLinks.effective(bench)
        XCTAssertTrue(edges.contains(EdgeConfig(from: "m", to: "a")))
        XCTAssertTrue(edges.contains(EdgeConfig(from: "a", to: "m")), "é por onde chega a resposta")
        XCTAssertTrue(edges.contains(EdgeConfig(from: "m", to: "dev")))
        XCTAssertFalse(edges.contains(EdgeConfig(from: "dev", to: "m")), "shell não responde")
        XCTAssertFalse(edges.contains { $0.to == "ed" }, "editor não é alvo")
        XCTAssertTrue(edges.allSatisfy { $0.maxSends == nil }, "implícita: só o teto da bancada")
        XCTAssertEqual(bench.edgeList, [], "nada se desenha")
    }

    func testDrawnEdgeWinsOverTheImplicitOne() {
        let bench = WorkbenchConfig(name: "deck", path: "/tmp",
                                    nodes: [node("m", .agent, maestro: true), node("a", .agent)],
                                    edges: [EdgeConfig(from: "m", to: "a", maxSends: 3)])
        let edges = MaestroLinks.effective(bench)
        XCTAssertEqual(edges.filter { $0 == EdgeConfig(from: "m", to: "a") }.map(\.maxSends), [3])
    }

    func testWithoutMaestroNothingIsAdded() {
        let bench = WorkbenchConfig(name: "deck", path: "/tmp", nodes: [node("a", .agent), node("b", .agent)])
        XCTAssertEqual(MaestroLinks.effective(bench), [])
    }

    func testLayoutPutsMaestroLeftTeamInGridShellsBelow() {
        let nodes = [node("m", .agent, maestro: true), node("a", .agent), node("b", .agent),
                     node("c", .agent), node("dev", .shell)]
        let frames = MaestroLayout.frames(for: nodes)
        let m = frames["m"]!, a = frames["a"]!, b = frames["b"]!, c = frames["c"]!, dev = frames["dev"]!
        XCTAssertLessThan(m.maxX, a.minX, "maestro à esquerda do time")
        XCTAssertEqual(a.minY, b.minY, "dois por linha com três agentes")
        XCTAssertGreaterThan(c.minY, a.maxY)
        XCTAssertEqual(m.maxY, c.maxY, "a coluna do maestro tem a altura do time")
        XCTAssertGreaterThan(dev.minY, m.maxY, "shell na faixa de baixo")
        XCTAssertEqual(dev.size, MaestroLayout.shell)
        let all = Array(frames.values)
        for i in all.indices { for j in all.indices where j > i {
            XCTAssertFalse(all[i].intersects(all[j]), "cards não se sobrepõem")
        } }
    }

    func testPlanWithLayoutIsNotEmpty() {
        guard case .success(let plan) = MaestroPlan.parse(Data(#"{"layout":true}"#.utf8)) else { return XCTFail() }
        XCTAssertFalse(plan.isEmpty)
    }

    /// O exemplo do manual é o que o modelo copia: tem de ser um plano que o
    /// app aceita, campo por campo.
    func testGuideExampleIsAValidPlan() throws {
        let text = MaestroGuide.text
        let start = try XCTUnwrap(text.range(of: "egeon plan <<'JSON'\n"))
        let end = try XCTUnwrap(text.range(of: "\nJSON", range: start.upperBound..<text.endIndex))
        let json = String(text[start.upperBound..<end.lowerBound])
        guard case .success(let plan) = MaestroPlan.parse(Data(json.utf8)) else {
            return XCTFail("o exemplo do manual não lê: \(MaestroPlan.parse(Data(json.utf8)))")
        }
        XCTAssertEqual(plan.nodes.map(\.id), ["back", "web", "revisor"])
    }
}


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

    /// O maestro é a âncora: a posição e o tamanho que o usuário deu a ele
    /// ficam, e o time se arruma à direita, alinhado pelo topo.
    func testMaestroKeepsItsPlaceAndTheTeamFollowsIt() {
        var maestro = node("m", .agent, maestro: true)
        maestro.setFrame(CGRect(x: 300, y: 900, width: 500, height: 600))
        let frames = MaestroLayout.frames(for: [maestro, node("a", .agent), node("b", .agent)])
        XCTAssertEqual(frames["m"], CGRect(x: 300, y: 900, width: 500, height: 600))
        XCTAssertGreaterThan(frames["a"]!.minX, 800, "time à direita do maestro")
        XCTAssertEqual(frames["a"]!.minY, 900, "alinhado pelo topo dele")
    }

    /// Seta desenhada entre agentes precisa de onde aparecer: o vão abre.
    func testLinkedAgentsGetRoomForTheArrows() {
        let nodes = [node("m", .agent, maestro: true), node("a", .agent), node("b", .agent)]
        let loose = MaestroLayout.frames(for: nodes)
        let linked = MaestroLayout.frames(for: nodes, edges: [EdgeConfig(from: "a", to: "b")])
        XCTAssertEqual(loose["b"]!.minX - loose["a"]!.maxX, MaestroLayout.gap)
        XCTAssertEqual(linked["b"]!.minX - linked["a"]!.maxX, MaestroLayout.linkedGapX,
                       "na horizontal o vão é o maior")
        // Aresta do maestro é implícita e não se desenha: não abre vão.
        let implicit = MaestroLayout.frames(for: nodes, edges: [EdgeConfig(from: "m", to: "a")])
        XCTAssertEqual(implicit["b"]!.minX - implicit["a"]!.maxX, MaestroLayout.gap)
    }

    func testPlanDoesNotMoveTheMaestro() {
        var maestro = node("m", .agent, maestro: true)
        maestro.setFrame(CGRect(x: 1200, y: 80, width: 720, height: 460))
        let bench = WorkbenchConfig(name: "deck", path: "/tmp", nodes: [maestro])
        guard case .success(let plan) = MaestroPlan.parse(Data(#"{"nodes":[{"id":"a"}],"layout":true}"#.utf8))
        else { return XCTFail() }
        var context = MaestroContext(caller: "m", profiles: ["claude": .claudeCode])
        context.directoryExists = { _ in true }
        let out = MaestroPlanner.plan(plan, on: bench, context: context)
        XCTAssertEqual(out.errors, [])
        XCTAssertEqual(out.next.nodes.first { $0.id == "m" }?.frame, maestro.frame)
    }

    /// O caso da captura: planejador ↔ testador (ida e volta), os dois →
    /// dev. Os dois ficam na mesma coluna, empilhados; o dev vai para a
    /// direita, no meio da altura deles.
    func testLinkedTeamFlowsLeftToRightAndCentersTheTarget() {
        let nodes = [node("m", .agent, maestro: true), node("planejador", .agent),
                     node("testador", .agent), node("dev", .agent)]
        let edges = [EdgeConfig(from: "planejador", to: "testador"),
                     EdgeConfig(from: "testador", to: "planejador"),
                     EdgeConfig(from: "planejador", to: "dev"),
                     EdgeConfig(from: "testador", to: "dev")]
        let f = MaestroLayout.frames(for: nodes, edges: edges)
        let p = f["planejador"]!, t = f["testador"]!, d = f["dev"]!
        XCTAssertEqual(p.minX, t.minX, "ida e volta: mesma coluna")
        XCTAssertGreaterThan(t.minY, p.maxY, "um embaixo do outro")
        XCTAssertGreaterThan(d.minX, p.maxX, "quem recebe vai para a direita")
        XCTAssertEqual(d.midY, (p.midY + t.midY) / 2, accuracy: 0.5, "no meio dos dois")
    }

    /// As setas reais da bancada de teste: um ciclo. Pela distância ao
    /// destino (o dev, que mais recebe), planejador e testador ficam juntos à
    /// esquerda e o dev no meio deles — não uma fila de três.
    func testCycleIsAnchoredOnTheTarget() {
        let nodes = [node("planejador", .agent), node("dev", .agent), node("testador", .agent)]
        let edges = [EdgeConfig(from: "planejador", to: "dev"), EdgeConfig(from: "dev", to: "testador"),
                     EdgeConfig(from: "testador", to: "dev"), EdgeConfig(from: "testador", to: "planejador")]
        let f = MaestroLayout.frames(for: nodes, edges: edges)
        let p = f["planejador"]!, t = f["testador"]!, d = f["dev"]!
        XCTAssertEqual(p.minX, t.minX, "os dois que apontam para o dev: mesma coluna")
        XCTAssertGreaterThan(d.minX, p.maxX)
        XCTAssertEqual(d.midY, (p.midY + t.midY) / 2, accuracy: 0.5)
    }

    func testOnlyTwoWayPairsStackInOneColumn() {
        let nodes = [node("a", .agent), node("b", .agent)]
        let f = MaestroLayout.frames(for: nodes, edges: [EdgeConfig(from: "a", to: "b"),
                                                         EdgeConfig(from: "b", to: "a")])
        XCTAssertEqual(f["a"]!.minX, f["b"]!.minX)
        XCTAssertGreaterThan(f["b"]!.minY, f["a"]!.maxY)
    }

    func testChainOfOneWayArrowsMakesColumns() {
        let nodes = [node("a", .agent), node("b", .agent), node("c", .agent)]
        let f = MaestroLayout.frames(for: nodes, edges: [EdgeConfig(from: "a", to: "b"),
                                                         EdgeConfig(from: "b", to: "c")])
        XCTAssertLessThan(f["a"]!.maxX, f["b"]!.minX)
        XCTAssertLessThan(f["b"]!.maxX, f["c"]!.minX)
        XCTAssertEqual(f["a"]!.midY, f["c"]!.midY, accuracy: 0.5, "pipeline em linha reta")
    }

    func testOneWayCycleDoesNotHang() {
        let nodes = [node("a", .agent), node("b", .agent), node("c", .agent)]
        let f = MaestroLayout.frames(for: nodes, edges: [EdgeConfig(from: "a", to: "b"),
                                                         EdgeConfig(from: "b", to: "c"),
                                                         EdgeConfig(from: "c", to: "a")])
        XCTAssertEqual(f.count, 3)
    }

    /// O maestro posiciona à mão: o frame do plano vence o arranjo, e o que
    /// ficar faltando sai do lugar atual.
    func testPlanFrameMovesAndResizesACard() {
        var a = node("a", .agent)
        a.setFrame(CGRect(x: 800, y: 40, width: 720, height: 460))
        let bench = WorkbenchConfig(name: "deck", path: "/tmp", nodes: [node("m", .agent, maestro: true), a])
        var context = MaestroContext(caller: "m", profiles: ["claude": .claudeCode])
        context.directoryExists = { _ in true }
        func run(_ json: String) -> MaestroOutcome {
            guard case .success(let plan) = MaestroPlan.parse(Data(json.utf8)) else {
                XCTFail(json); return MaestroOutcome(next: bench)
            }
            return MaestroPlanner.plan(plan, on: bench, context: context)
        }
        let moved = run(#"{"nodes":[{"id":"a","frame":{"y":900}}]}"#)
        XCTAssertEqual(moved.errors, [])
        XCTAssertEqual(moved.next.nodes[1].frame, CGRect(x: 800, y: 900, width: 720, height: 460))
        XCTAssertTrue(moved.relaid)
        XCTAssertEqual(moved.restarted, [], "mover não reinicia")
        XCTAssertFalse(run(#"{"nodes":[{"id":"a","frame":{"x":-5}}]}"#).errors.isEmpty)
        XCTAssertFalse(run(#"{"nodes":[{"id":"a","frame":{"w":100}}]}"#).errors.isEmpty)
        XCTAssertFalse(run(#"{"nodes":[{"id":"m","frame":{"x":0}}]}"#).errors.isEmpty, "o maestro não se move")
        guard case .failure = MaestroPlan.parse(Data(#"{"nodes":[{"id":"a","frame":{"left":3}}]}"#.utf8))
        else { return XCTFail("campo errado no frame passou") }
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


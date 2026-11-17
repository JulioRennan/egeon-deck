import XCTest
@testable import EgeonDeck

/// O controller com as três costuras em memória: config, mutação e persistência.
/// Canvas ausente de propósito — a rota `/edge` vale para bancada sem shell, e o
/// controller precisa funcionar inteiro sem tela.
final class EdgeControllerTests: XCTestCase {
    private var config: WorkbenchConfig!
    private var persisted = 0

    override func setUpWithError() throws {
        config = try JSONDecoder().decode(WorkbenchConfig.self, from: Data("""
            {"name":"ws","path":"/tmp/ws","nodes":[
              {"type":"agent","id":"a"},{"type":"agent","id":"b"},{"type":"agent","id":"c"}]}
            """.utf8))
        persisted = 0
    }

    private func makeController() -> EdgeController {
        EdgeController(
            canvas: { nil },
            config: { [unowned self] in self.config },
            change: { [unowned self] mutate in mutate(&self.config) },
            persist: { [unowned self] in self.persisted += 1 }
        )
    }

    // ADR-028: ligação nova nasce nos dois sentidos.
    func testEdgeIsBornBidirectional() {
        let controller = makeController()
        controller.add(EdgeConfig(from: "a", to: "b"))

        XCTAssertEqual(config.edgeList.count, 2)
        XCTAssertTrue(config.edgeList.contains(EdgeConfig(from: "a", to: "b")))
        XCTAssertTrue(config.edgeList.contains(EdgeConfig(from: "b", to: "a")))
        XCTAssertGreaterThan(persisted, 0)
    }

    func testDuplicateEdgeIsIgnored() {
        let controller = makeController()
        controller.add(EdgeConfig(from: "a", to: "b"))
        controller.add(EdgeConfig(from: "a", to: "b"))
        controller.add(EdgeConfig(from: "b", to: "a"))

        XCTAssertEqual(config.edgeList.count, 2)
    }

    // O X da linha leva os dois sentidos: na tela o par é uma linha só.
    func testRemoveTakesBothDirections() {
        let controller = makeController()
        controller.add(EdgeConfig(from: "a", to: "b"))
        let link = EdgeLink.collapse(config.edgeList).first!

        controller.remove(link)
        XCTAssertTrue(config.edgeList.isEmpty)
    }

    // A rota /edge sem direção: cria com o padrão da casa quando não existe,
    // e é CONSULTA quando existe — leitura não muda o que mede.
    func testApplyEmptyDirectionCreatesThenOnlyQueries() {
        let controller = makeController()

        let created = controller.apply(from: "a", to: "b", direction: "")
        XCTAssertEqual(created["direction"] as? String, "<->")

        _ = controller.apply(from: "a", to: "b", direction: "->")
        let queried = controller.apply(from: "a", to: "b", direction: "")
        XCTAssertEqual(queried["direction"] as? String, "->")
        XCTAssertEqual(config.edgeList.count, 1)
    }

    func testApplyNoneUndoesTheEdge() {
        let controller = makeController()
        _ = controller.apply(from: "a", to: "b", direction: "")

        let result = controller.apply(from: "a", to: "b", direction: "none")
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertTrue(config.edgeList.isEmpty)
    }

    func testApplyRejectsUnknownNode() {
        let controller = makeController()
        let result = controller.apply(from: "a", to: "zzz", direction: "->")

        XCTAssertEqual(result["ok"] as? Bool, false)
        XCTAssertTrue(config.edgeList.isEmpty)
    }

    // O aviso de ciclo é só para o que o teto da bancada segura: três nós ou mais.
    func testCycleIsFoundBreadthFirst() {
        let edges = [
            EdgeConfig(from: "a", to: "b"),
            EdgeConfig(from: "b", to: "c"),
            EdgeConfig(from: "c", to: "a"),
        ]
        let cycle = EdgeController.cycle(through: EdgeConfig(from: "c", to: "a"), in: edges)
        XCTAssertEqual(cycle, ["a", "b", "c", "a"])
    }
}

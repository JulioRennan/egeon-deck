import XCTest
@testable import EgeonDeck

/// A faixa sobrevive ao fechar do app: quais bancadas estavam abertas, e em que
/// ordem, vai para o `workbenches.json` ao lado de `view` e `mosaic`.
final class WorkbenchTabOrderTests: XCTestCase {
    /// Arquivo antigo não tem a chave — e tem de carregar como se estivesse
    /// fechada, sem uma linha de migração.
    func testFileWithoutTheKeyStillLoads() throws {
        let json = """
        {"name":"deck","path":"~/deck","nodes":[]}
        """
        let config = try JSONDecoder().decode(WorkbenchConfig.self, from: Data(json.utf8))
        XCTAssertNil(config.tabOrder)
        XCTAssertEqual(config.name, "deck")
    }

    func testTabOrderSurvivesARoundTrip() throws {
        var config = WorkbenchConfig(name: "deck", path: "~/deck", nodes: [])
        config.tabOrder = 2
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(WorkbenchConfig.self, from: data)
        XCTAssertEqual(back.tabOrder, 2)
        XCTAssertEqual(back.id, config.id)
    }

    /// Fechada não grava posição: o campo é o que separa "estava na faixa" de
    /// "está só no catálogo".
    func testClosedWorkbenchHasNoOrder() throws {
        let config = WorkbenchConfig(name: "parada", path: "~/x", nodes: [])
        let data = try JSONEncoder().encode(config)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("tabOrder"), "bancada fechada não escreve a chave")
    }

    /// A ordem de reabertura é a da faixa, não a da barra lateral.
    func testRestoreOrderFollowsTheSavedPositions() {
        var a = WorkbenchConfig(name: "a", path: "~/a", nodes: []); a.tabOrder = 1
        var b = WorkbenchConfig(name: "b", path: "~/b", nodes: [])
        var c = WorkbenchConfig(name: "c", path: "~/c", nodes: []); c.tabOrder = 0
        b.tabOrder = nil
        let configs = [a, b, c]
        let ordered = configs.filter { $0.tabOrder != nil }
            .sorted { ($0.tabOrder ?? 0) < ($1.tabOrder ?? 0) }
            .map(\.name)
        XCTAssertEqual(ordered, ["c", "a"], "b estava fechada e não reabre")
    }
}

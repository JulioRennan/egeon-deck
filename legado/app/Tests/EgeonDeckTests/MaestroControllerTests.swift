import XCTest
@testable import EgeonDeck

/// O controller do maestro sem tela: quem pode, o que a prévia deixa como
/// estava, e a ordem dos efeitos quando aplica (ADR-066).
final class MaestroControllerTests: XCTestCase {
    private var bench: WorkbenchConfig!
    private var events: [String] = []
    private var traced: [String] = []

    override func setUp() {
        var maestro = NodeConfig(type: .agent, id: "maestro")
        maestro.agent = "claude"
        maestro.maestro = true
        var revisor = NodeConfig(type: .agent, id: "revisor")
        revisor.agent = "claude"
        bench = WorkbenchConfig(name: "deck", path: "/tmp", nodes: [maestro, revisor])
        events = []
        traced = []
    }

    private func controller() -> MaestroController {
        MaestroController(.init(
            bench: { [unowned self] name in name == bench.name ? bench : nil },
            context: { _, caller in
                var context = MaestroContext(caller: caller, profiles: ["claude": .claudeCode])
                context.directoryExists = { _ in true }
                return context
            },
            activity: { _ in .ready },
            profiles: { ["claude": .claudeCode] },
            catalog: { _ in nil },
            commit: { [unowned self] next in bench = next; events.append("commit") },
            spawn: { [unowned self] _, id in events.append("spawn \(id)") },
            restart: { [unowned self] _, id in events.append("restart \(id)") },
            dispose: { [unowned self] _, id in events.append("dispose \(id)") },
            redrawEdges: { [unowned self] _ in events.append("edges") },
            arrange: { [unowned self] _ in events.append("arrange") },
            persist: { [unowned self] in events.append("persist") },
            trace: { [unowned self] address, text in traced.append("\(address): \(text)") }))
    }

    func testOnlyAMaestroMayAsk() {
        let c = controller()
        XCTAssertEqual(c.bench(caller: "deck/revisor").status, 403)
        XCTAssertEqual(c.bench(caller: nil).status, 403)
        XCTAssertEqual(c.models(caller: "deck/revisor").status, 403)
        XCTAssertEqual(c.apply(Data(#"{"nodes":[{"id":"x"}]}"#.utf8), caller: "deck/revisor",
                               dry: false).status, 403)
        XCTAssertEqual(c.bench(caller: "deck/maestro").status, 200)
        XCTAssertEqual(events, [], "recusa não mexe em nada")
    }

    func testBenchMarksWhoIsAsking() {
        let json = controller().bench(caller: "deck/maestro").json
        let nodes = json["nodes"] as? [[String: Any]] ?? []
        XCTAssertEqual(nodes.first { $0["id"] as? String == "maestro" }?["you"] as? Bool, true)
        XCTAssertEqual(nodes.first { $0["id"] as? String == "revisor" }?["state"] as? String, "idle")
    }

    func testDryRunChangesNothing() {
        let before = bench.nodes.map(\.id)
        let reply = controller().apply(Data(#"{"nodes":[{"id":"front"}]}"#.utf8),
                                       caller: "deck/maestro", dry: true)
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(reply.json["created"] as? [String], ["front"])
        XCTAssertEqual(bench.nodes.map(\.id), before)
        XCTAssertEqual(events, [])
        XCTAssertEqual(traced, [])
    }

    func testInvalidPlanChangesNothingAndListsErrors() {
        let reply = controller().apply(Data(#"{"nodes":[{"id":"front","cli":"cursor"}]}"#.utf8),
                                       caller: "deck/maestro", dry: false)
        XCTAssertEqual(reply.status, 422)
        XCTAssertFalse((reply.json["errors"] as? [String] ?? []).isEmpty)
        XCTAssertEqual(events, [])
    }

    func testApplyCommitsFirstThenTouchesTheScreenAndLeavesATrace() {
        let reply = controller().apply(
            Data(#"{"nodes":[{"id":"front"},{"id":"revisor","effort":"low"}]}"#.utf8),
            caller: "deck/maestro", dry: false)
        XCTAssertEqual(reply.status, 200, "\(reply.json)")
        XCTAssertEqual(events, ["commit", "restart revisor", "spawn front", "edges", "arrange", "persist"])
        XCTAssertTrue(bench.nodes.contains { $0.id == "front" })
        XCTAssertEqual(traced, ["deck/maestro: maestro aplicou: +front ~revisor · canvas rearrumado"])
    }

    func testPlanThatChangesNothingDoesNotTouchAnything() {
        let reply = controller().apply(Data(#"{"nodes":[{"id":"revisor"}]}"#.utf8),
                                       caller: "deck/maestro", dry: false)
        XCTAssertEqual(reply.status, 200)
        XCTAssertEqual(events, [])
    }
}

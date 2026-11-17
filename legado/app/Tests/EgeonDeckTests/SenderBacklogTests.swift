import XCTest
@testable import EgeonDeck

/// A fila do destino conta por remetente (ADR-077).
final class SenderBacklogTests: XCTestCase {
    func testCountsOnlyTheSender() {
        let chains = [
            ["deck/w01", "deck/maestro"],
            ["deck/w02", "deck/maestro"],
            ["deck/maestro", "deck/w01", "deck/maestro"],
            ["deck/w03", "deck/maestro"],
        ]
        XCTAssertEqual(SenderBacklog.count(from: "deck/w01", in: chains), 2)
        XCTAssertEqual(SenderBacklog.count(from: "deck/w02", in: chains), 1)
        XCTAssertEqual(SenderBacklog.count(from: "deck/w09", in: chains), 0)
    }

    /// O caso que a guarda antiga barrava: 14 agentes respondendo ao mesmo
    /// destino, um envio cada — ninguém passa de um na fila.
    func testWholeTeamCountsOneEach() {
        let team = (1...14).map { ["deck/w\($0)", "deck/maestro"] }
        XCTAssertTrue((1...14).allSatisfy { SenderBacklog.count(from: "deck/w\($0)", in: team) == 1 })
    }
}

import XCTest
@testable import EgeonDeck

/// O fim de turno decidido pelo payload do `Stop` e pela espera de vizinho
/// (ADR-067).
final class StopReportTests: XCTestCase {
    func testQueryCarriesBackgroundAndLastMessage() {
        let report = StopReport(query: ["bg": "2", "last": "feito\n[[ED:ok]]"])
        XCTAssertEqual(report.background, 2)
        XCTAssertEqual(report.lastMessage, "feito\n[[ED:ok]]")
    }

    // CLI sem os campos: nada inventado, decide o marcador.
    func testQueryWithoutFieldsIsUnknown() {
        let report = StopReport(query: ["transcript": "/tmp/x.jsonl", "last": ""])
        XCTAssertNil(report.background)
        XCTAssertNil(report.lastMessage)
    }

    func testPendingPeerBeatsAsk() {
        XCTAssertEqual(StopOutcome.decide(marker: .ask, background: 0, awaitingPeers: true), .awaiting)
        XCTAssertEqual(StopOutcome.decide(marker: .ok, background: nil, awaitingPeers: true), .awaiting)
        XCTAssertEqual(StopOutcome.decide(marker: nil, background: 3, awaitingPeers: true), .awaiting)
    }

    // O payload vence o marcador nos dois sentidos.
    func testBackgroundCountBeatsMarker() {
        XCTAssertEqual(StopOutcome.decide(marker: .ok, background: 1, awaitingPeers: false), .background)
        XCTAssertEqual(StopOutcome.decide(marker: .wait, background: 0, awaitingPeers: false), .finished)
        XCTAssertEqual(StopOutcome.decide(marker: .ask, background: 0, awaitingPeers: false), .asked)
    }

    // Servidor de dev ou `/loop` de pé a sessão inteira não podem calar a
    // pergunta: ela vence a ampulheta.
    func testAskBeatsBackground() {
        XCTAssertEqual(StopOutcome.decide(marker: .ask, background: 1, awaitingPeers: false), .asked)
    }

    func testWithoutPayloadTheMarkerDecides() {
        XCTAssertEqual(StopOutcome.decide(marker: .ask, background: nil, awaitingPeers: false), .asked)
        XCTAssertEqual(StopOutcome.decide(marker: .wait, background: nil, awaitingPeers: false), .background)
        XCTAssertEqual(StopOutcome.decide(marker: .ok, background: nil, awaitingPeers: false), .finished)
        XCTAssertEqual(StopOutcome.decide(marker: nil, background: nil, awaitingPeers: false), .finished)
    }

    func testPeerWaitKeepsOrderAndNoDuplicates() {
        var wait = PeerWait()
        wait.sent(to: "deck/back")
        wait.sent(to: "deck/front")
        wait.sent(to: "deck/back")
        XCTAssertEqual(wait.peers, ["deck/back", "deck/front"])
        XCTAssertEqual(wait.names, ["back", "front"])
    }

    func testPeerWaitResolvesOnlyWhoIsThere() {
        var wait = PeerWait()
        wait.sent(to: "deck/back")
        XCTAssertFalse(wait.resolved("deck/front"))
        XCTAssertTrue(wait.resolved("deck/back"))
        XCTAssertTrue(wait.isEmpty)
    }

    func testPeerWaitFollowsRename() {
        var wait = PeerWait()
        wait.sent(to: "deck/back")
        wait.renamed("deck/back", to: "deck2/back")
        XCTAssertEqual(wait.peers, ["deck2/back"])
    }
}

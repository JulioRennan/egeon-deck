import XCTest
@testable import EgeonDeck

/// O contrato da rota /activity: o que o gancho do CLI pode relatar.
final class HookEventTests: XCTestCase {
    func testTheKnownEvents() {
        XCTAssertEqual(HookEvent(rawValue: "start"), .start)
        XCTAssertEqual(HookEvent(rawValue: "stop"), .stop)
        XCTAssertEqual(HookEvent(rawValue: "prompt"), .prompt)
        XCTAssertEqual(HookEvent(rawValue: "ask"), .ask)
    }

    // O desconhecido morre na borda do socket, não num default silencioso.
    func testUnknownEventDoesNotParse() {
        XCTAssertNil(HookEvent(rawValue: "recap"))
        XCTAssertNil(HookEvent(rawValue: ""))
        XCTAssertNil(HookEvent(rawValue: "Stop"))
    }

    func testExpectedListsAllCases() {
        XCTAssertEqual(HookEvent.expected, "stop|prompt|ask|start")
    }
}

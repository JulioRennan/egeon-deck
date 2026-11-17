import XCTest
@testable import EgeonDeck

/// A aba "Ativas" da barra lateral (ADR-082).
final class ActiveWorkbenchesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    func testOnlyLiveOnesNewestFirstSplitAt24Hours() {
        let list = ActiveWorkbenches(live: [0, 1, 2, 3, 5],
                                     lastActive: [0: ago(30), 1: ago(0.1), 2: ago(23.9),
                                                  3: ago(72), 4: ago(0), 5: ago(5)],
                                     now: now)
        XCTAssertEqual(list.recent, [1, 5, 2])
        XCTAssertEqual(list.stale, [0, 3], "a 4 rodou agora, mas não está de pé")
    }

    func testNeverRanGoesLastAndTiesKeepListOrder() {
        let list = ActiveWorkbenches(live: [4, 2, 7, 9],
                                     lastActive: [7: ago(40), 2: ago(1), 9: ago(1)],
                                     now: now)
        XCTAssertEqual(list.recent, [2, 9])
        XCTAssertEqual(list.stale, [7, 4])
    }

    func testEmpty() {
        XCTAssertTrue(ActiveWorkbenches(live: [], lastActive: [0: now], now: now).isEmpty)
    }
}

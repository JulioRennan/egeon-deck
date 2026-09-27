import XCTest
@testable import EgeonDeck

/// O resumo por bancada que a barra lateral mostra: subir não é trabalhar.
final class ActivitySummaryTests: XCTestCase {
    func testOnlyStartingIsPreparing() {
        XCTAssertTrue(ActivitySummary(starting: 2).isPreparing)
        XCTAssertTrue(ActivitySummary(starting: 1, working: 0).isPreparing)
    }

    func testAnyOtherActivityIsNotPreparing() {
        XCTAssertFalse(ActivitySummary(starting: 1, working: 1).isPreparing)
        XCTAssertFalse(ActivitySummary(starting: 1, attention: 1).isPreparing)
        XCTAssertFalse(ActivitySummary(starting: 1, done: 1).isPreparing)
        XCTAssertFalse(ActivitySummary(starting: 1, background: 1).isPreparing)
        XCTAssertFalse(ActivitySummary().isPreparing)
    }
}

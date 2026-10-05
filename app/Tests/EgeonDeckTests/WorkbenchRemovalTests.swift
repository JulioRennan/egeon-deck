import XCTest
@testable import EgeonDeck

final class WorkbenchRemovalTests: XCTestCase {
    private struct Boom: Error {}

    private func targets(_ paths: String...) -> [WorkbenchRemoval.Target] {
        paths.map { WorkbenchRemoval.Target(path: $0, label: "repo · \($0)") }
    }

    func testAllRemovedSucceeds() {
        var called: [String] = []
        let outcome = WorkbenchRemoval.purge(targets("/a", "/b")) { called.append($0) }
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(called, ["/a", "/b"])
        XCTAssertEqual(outcome.removed.map(\.path), ["/a", "/b"])
        XCTAssertTrue(outcome.leftovers.isEmpty)
    }

    /// Sobra de pasta não segura a bancada: o registro já foi, a faxina vem depois.
    func testLeftoversCountAsRemovedAndGoToSweep() {
        let outcome = WorkbenchRemoval.purge(targets("/a")) { path in
            throw Worktree.Failure.leftovers(path: path, reason: "Directory not empty")
        }
        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(outcome.removed.map(\.path), ["/a"])
        XCTAssertEqual(outcome.leftovers, ["/a"])
    }

    /// Uma falha não para as outras: o alerta diz o que já foi e o que resistiu.
    func testFailureKeepsGoingAndIsReported() {
        let outcome = WorkbenchRemoval.purge(targets("/a", "/b", "/c")) { path in
            if path == "/b" { throw Boom() }
        }
        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.removed.map(\.path), ["/a", "/c"])
        XCTAssertEqual(outcome.failures.map(\.target.path), ["/b"])
    }

    func testNothingToRemoveSucceeds() {
        XCTAssertTrue(WorkbenchRemoval.purge([]) { _ in XCTFail() }.succeeded)
    }
}

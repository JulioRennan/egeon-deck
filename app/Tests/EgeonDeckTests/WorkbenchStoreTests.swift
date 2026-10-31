import XCTest
@testable import EgeonDeck

final class WorkbenchStoreTests: XCTestCase {
    private var root: URL!
    private var config: URL { root.appendingPathComponent("workbenches.json") }
    private var legacy: URL { root.appendingPathComponent("sessions.json") }
    private let old = #"[{"name":"velha","path":"~/velha","nodes":[]}]"#

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func write(_ text: String, to url: URL) throws { try text.write(to: url, atomically: true, encoding: .utf8) }

    private func names() -> [String] { WorkbenchStore.load(from: config, legacy: legacy).map(\.name) }

    func testLegacyFileCountsOnlyWhenTheNewOneNeverExisted() throws {
        try write(old, to: legacy)
        XCTAssertEqual(names(), ["velha"])
    }

    func testEmptyListIsAStateAndDoesNotBringOldWorkbenchesBack() throws {
        try write(old, to: legacy)
        // O formato real: é assim que sai quando a última bancada é apagada.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode([WorkbenchConfig]()).write(to: config)
        XCTAssertEqual(names(), [])
    }

    func testNewFileWinsOverLegacy() throws {
        try write(old, to: legacy)
        try write(#"[{"name":"nova","path":"~/nova","nodes":[]}]"#, to: config)
        XCTAssertEqual(names(), ["nova"])
    }

    func testBrokenNewFileDoesNotFallBackToLegacy() throws {
        try write(old, to: legacy)
        try write("{quebrado", to: config)
        XCTAssertEqual(names(), [])
    }

    func testNothingOnDiskStartsEmpty() {
        XCTAssertEqual(names(), [])
    }
}

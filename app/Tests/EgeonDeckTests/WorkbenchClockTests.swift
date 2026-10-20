import XCTest
@testable import EgeonDeck

final class WorkbenchClockTests: XCTestCase {
    func testPhasePrecedence() {
        XCTAssertNil(WorkbenchClock.phase(for: ActivitySummary()))
        XCTAssertNil(WorkbenchClock.phase(for: ActivitySummary(starting: 2, done: 1)))
        XCTAssertEqual(WorkbenchClock.phase(for: ActivitySummary(working: 1)), .running)
        XCTAssertEqual(WorkbenchClock.phase(for: ActivitySummary(background: 1)), .running)
        XCTAssertEqual(WorkbenchClock.phase(for: ActivitySummary(working: 3, attention: 1)), .waiting)
        XCTAssertEqual(WorkbenchClock.phase(for: ActivitySummary(working: 1, attention: 2, failed: 1)), .failed)
        // Tentativa agendada conta em background e em failed: é erro, não trabalho.
        XCTAssertEqual(WorkbenchClock.phase(for: ActivitySummary(background: 1, failed: 1)), .failed)
    }

    func testAddCapsLongGaps() {
        var clock = WorkbenchClock()
        clock.add(0.5, to: .running)
        clock.add(600, to: .running)
        clock.add(-3, to: .waiting)
        XCTAssertEqual(clock.running, 0.5 + WorkbenchClock.maxStep)
        XCTAssertEqual(clock.waiting, 0)
    }

    func testFormat() {
        XCTAssertEqual(WorkbenchClock.format(0), "00:00")
        XCTAssertEqual(WorkbenchClock.format(59.9), "00:59")
        XCTAssertEqual(WorkbenchClock.format(61), "01:01")
        XCTAssertEqual(WorkbenchClock.format(3599), "59:59")
        XCTAssertEqual(WorkbenchClock.format(3600 + 5 * 60 + 12), "1:05:12")
    }

    func testTickAccumulatesPersistsAndResets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clocks = WorkbenchClocks(directory: dir)
        let start = Date()
        clocks.tick(["a": .running], now: start)            // primeiro tique só marca
        clocks.tick(["a": .running, "b": .failed], now: start.addingTimeInterval(1))
        clocks.tick(["a": .waiting], now: start.addingTimeInterval(1.5))
        XCTAssertEqual(clocks.clock(for: "a").running, 1, accuracy: 0.001)
        XCTAssertEqual(clocks.clock(for: "a").waiting, 0.5, accuracy: 0.001)
        XCTAssertEqual(clocks.clock(for: "b").failed, 1, accuracy: 0.001)

        clocks.flush()
        let reloaded = WorkbenchClocks(directory: dir)
        XCTAssertEqual(reloaded.clock(for: "a"), clocks.clock(for: "a"))

        clocks.reset("a")
        XCTAssertEqual(WorkbenchClocks(directory: dir).clock(for: "a"), WorkbenchClock())
    }
}

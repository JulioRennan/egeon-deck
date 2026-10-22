import XCTest
@testable import EgeonDeck

final class WorkbenchClockTests: XCTestCase {
    func testPhasesRunTogether() {
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary()), [])
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary(starting: 2, done: 1)), [])
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary(working: 1)), [.running])
        // Aguardar vizinho é `background`: trabalho, não espera por você.
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary(background: 1)), [.running])
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary(attention: 1)), [.waiting])
        // Um perguntando não para o relógio de quem trabalha ao lado (ADR-078).
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary(working: 3, attention: 1)), [.running, .waiting])
    }

    func testFailedIsNeitherWaitingNorRunning() {
        // Desistido conta em `attention`, mas é erro, não pergunta.
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary(attention: 1, failed: 1)), [.failed])
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary(working: 1, attention: 2, failed: 1)),
                       [.failed, .waiting, .running])
        // Tentativa agendada conta em `background`, mas é erro, não trabalho.
        XCTAssertEqual(WorkbenchClock.phases(for: ActivitySummary(background: 1, failed: 1, retrying: 1)), [.failed])
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
        clocks.tick(["a": [.running]], now: start)          // primeiro tique só marca
        clocks.tick(["a": [.running], "b": [.failed]], now: start.addingTimeInterval(1))
        clocks.tick(["a": [.running, .waiting]], now: start.addingTimeInterval(1.5))
        clocks.tick(["a": []], now: start.addingTimeInterval(3))
        XCTAssertEqual(clocks.clock(for: "a").running, 1.5, accuracy: 0.001)
        XCTAssertEqual(clocks.clock(for: "a").waiting, 0.5, accuracy: 0.001)
        XCTAssertEqual(clocks.clock(for: "b").failed, 1, accuracy: 0.001)
        // O último instante com fase andando — o tique vazio não conta.
        XCTAssertEqual(clocks.clock(for: "a").lastActive, start.addingTimeInterval(1.5))
        XCTAssertEqual(clocks.clock(for: "b").lastActive, start.addingTimeInterval(1))

        clocks.flush()
        let reloaded = WorkbenchClocks(directory: dir)
        XCTAssertEqual(reloaded.clock(for: "a"), clocks.clock(for: "a"))

        clocks.reset("a")
        // Zerar começa outro período, mas não apaga quando ela rodou.
        XCTAssertEqual(WorkbenchClocks(directory: dir).clock(for: "a"),
                       WorkbenchClock(lastActive: start.addingTimeInterval(1.5)))
    }

    // Arquivo de antes do `lastActive`: a data dele é a última vez que rodou.
    func testOldFileTakesLastActiveFromModificationDate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clocks = WorkbenchClocks(directory: dir)
        let url = clocks.file(forWorkbench: "a")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(#"{"running":10,"waiting":0,"failed":0}"#.utf8).write(to: url)
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path)
        XCTAssertEqual(clocks.clock(for: "a").lastActive, when)
        XCTAssertEqual(clocks.clock(for: "a").running, 10)
    }
}

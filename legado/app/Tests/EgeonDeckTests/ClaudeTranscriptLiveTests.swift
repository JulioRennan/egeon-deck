import XCTest
@testable import EgeonDeck

/// A leitura ao vivo parte do prompt do turno em curso, em bytes: relê só o
/// turno, não a cauda inteira — e o offset é de byte, não de caractere.
final class ClaudeTranscriptLiveTests: XCTestCase {
    private let u1 = """
    {"type":"user","uuid":"u1","timestamp":"2026-08-25T17:00:00.000Z","message":{"content":"olá, ação"}}
    """
    private let a1 = """
    {"type":"assistant","timestamp":"2026-08-25T17:00:01.000Z","message":{"content":[{"type":"text","text":"Vou olhar."}]}}
    """
    private let u2 = """
    {"type":"user","uuid":"u2","timestamp":"2026-08-25T17:01:00.000Z","message":{"content":"faz"}}
    """
    private let a2 = """
    {"type":"assistant","timestamp":"2026-08-25T17:01:01.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls","description":"Lista"}}]}}
    """
    private let a3 = """
    {"type":"assistant","timestamp":"2026-08-25T17:01:02.000Z","message":{"content":[{"type":"thinking","thinking":"…"}]}}
    """

    func testScanRecordsByteOffsetOfEachPrompt() {
        let jsonl = [u1, a1, u2, a2].joined(separator: "\n") + "\n"
        let scanned = ClaudeTranscript.scan(Data(jsonl.utf8))
        XCTAssertEqual(scanned.turns.map(\.id), ["u1", "u2"])
        // "olá, ação" tem acentos: o offset conta bytes, não caracteres.
        let secondLine = (u1 + "\n" + a1 + "\n").utf8.count
        XCTAssertEqual(scanned.promptOffsets, [0, secondLine])
        XCTAssertEqual(scanned.last, .tool)
    }

    func testLiveTurnReadsFromKnownPromptOffset() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try ([u1, a1, u2, a2].joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)

        let first = try XCTUnwrap(ClaudeTranscript.liveTurn(at: url, notBefore: nil))
        XCTAssertEqual(first.turn.id, "u2")
        XCTAssertEqual(first.promptOffset, UInt64((u1 + "\n" + a1 + "\n").utf8.count))

        // Cauda minúscula: a partir do offset o prompt entra; da cauda, não.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((a3 + "\n").utf8))
        try handle.close()
        let next = try XCTUnwrap(ClaudeTranscript.liveTurn(at: url, notBefore: nil,
                                                           from: first.promptOffset, tailBytes: 64))
        XCTAssertEqual(next.turn.id, "u2")
        XCTAssertEqual(next.turn.parts.count, 1)
        XCTAssertEqual(next.last, .thinking)
        XCTAssertEqual(next.promptOffset, first.promptOffset, "o turno é o mesmo, o offset também")
        XCTAssertNil(ClaudeTranscript.liveTurn(at: url, notBefore: nil, tailBytes: 64),
                     "sem o offset, 64 bytes de cauda não trazem o prompt")
    }

    func testStaleOffsetFallsBackToTail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try ([u1, a1].joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        // Offset de uma conversa maior que já não existe: volta à cauda.
        let live = try XCTUnwrap(ClaudeTranscript.liveTurn(at: url, notBefore: nil, from: 999_999))
        XCTAssertEqual(live.turn.id, "u1")
        XCTAssertEqual(live.promptOffset, 0)
    }
}

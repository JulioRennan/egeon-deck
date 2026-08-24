import XCTest
@testable import EgeonDeck

/// O JSONL do Claude Code vira turnos: prompt seu + passos + texto final.
final class ClaudeTranscriptTests: XCTestCase {
    private let sample = """
    {"type":"attachment","timestamp":"2026-08-24T23:13:11.000Z","message":{"content":"x"}}
    {"type":"user","timestamp":"2026-08-24T23:13:27.000Z","message":{"role":"user","content":"echo egeon-chat-ok"}}
    {"type":"assistant","timestamp":"2026-08-24T23:13:31.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo egeon-chat-ok","description":"Ecoa a marca"}}]}}
    {"type":"user","timestamp":"2026-08-24T23:13:32.000Z","message":{"content":[{"type":"tool_result","content":"egeon-chat-ok"}]}}
    {"type":"assistant","timestamp":"2026-08-24T23:13:33.000Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b/app/Main.swift"}}]}}
    {"type":"assistant","timestamp":"2026-08-24T23:13:35.000Z","message":{"content":[{"type":"text","text":"`egeon-chat-ok`\\n\\n[[ED:ok]]"}]}}
    {"type":"user","timestamp":"2026-08-24T23:14:00.000Z","message":{"content":"<command-name>/clear</command-name>"}}
    {"type":"user","timestamp":"2026-08-24T23:15:00.000Z","message":{"content":[{"type":"text","text":"oi"}]}}
    """

    func testParsesPromptStepsAndReply() {
        let turns = ClaudeTranscript.parse(sample)
        XCTAssertEqual(turns.count, 2)

        let first = turns[0]
        XCTAssertEqual(first.prompt, "echo egeon-chat-ok")
        XCTAssertEqual(first.steps, [ChatStep(glyph: "$", text: "Ecoa a marca"),
                                     ChatStep(glyph: "±", text: "app/Main.swift")])
        // Marcador do protocolo é do app, não da bolha.
        XCTAssertEqual(first.replyText, "`egeon-chat-ok`")
        XCTAssertNotNil(first.replyAt)
        XCTAssertTrue(first.hasReply)

        // Comando de barra não é prompt; o "oi" em bloco de texto é.
        XCTAssertEqual(turns[1].prompt, "oi")
        XCTAssertFalse(turns[1].hasReply)
    }

    func testAssistantBeforeAnyPromptIsIgnored() {
        let orphan = """
        {"type":"assistant","timestamp":"2026-08-24T23:13:35.000Z","message":{"content":[{"type":"text","text":"solto"}]}}
        """
        XCTAssertTrue(ClaudeTranscript.parse(orphan).isEmpty)
    }
}

/// A thread cruza os agentes por tempo e tira o eco quando o transcript chega.
final class ChatThreadTests: XCTestCase {
    private func agent(_ id: String) -> ChatParticipant {
        ChatParticipant(id: id, address: "deck/\(id)", isAgent: true, role: nil, activity: .ready)
    }

    func testBuildInterleavesByTime() {
        let base = Date(timeIntervalSince1970: 1_000)
        let front = agent("front"), back = agent("back")
        var frontTurn = ChatTurn(prompt: "faz a coluna", promptAt: base)
        frontTurn.replyText = "feita"; frontTurn.replyAt = base.addingTimeInterval(30)
        let backTurn = ChatTurn(prompt: "expõe /nodes", promptAt: base.addingTimeInterval(10))

        let shell = ChatParticipant(id: "zsh", address: "deck/zsh", isAgent: false,
                                    role: nil, activity: .ready)
        // Shell não tem transcript: mesmo que a fechadura devolva algo, fica fora.
        let thread = ChatThread.build(participants: [front, back, shell]) {
            switch $0.id {
            case "front": return [frontTurn]
            case "back":  return [backTurn]
            default:      return [ChatTurn(prompt: "nunca", promptAt: base)]
            }
        }

        XCTAssertEqual(thread.count, 3)
        XCTAssertEqual(thread[0], .prompt(to: front, text: "faz a coluna", at: base))
        XCTAssertEqual(thread[1], .prompt(to: back, text: "expõe /nodes",
                                          at: base.addingTimeInterval(10)))
        XCTAssertEqual(thread[2], .reply(from: front, turn: frontTurn))
    }

    func testPendingDropsWhatTranscriptConfirmed() {
        let front = agent("front")
        let messages: [ChatMessage] = [.prompt(to: front, text: "oi", at: Date())]
        let left = ChatThread.stillPending([("oi", "front"), ("oi", "back"), ("tchau", "front")],
                                           given: messages)
        XCTAssertEqual(left.map(\.text), ["oi", "tchau"])
        XCTAssertEqual(left.map(\.target), ["back", "front"])
    }
}

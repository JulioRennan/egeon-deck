import XCTest
@testable import EgeonDeck

/// O JSONL do Claude Code vira turnos: prompt seu + passos + texto final.
final class ClaudeTranscriptTests: XCTestCase {
    private let sample = """
    {"type":"attachment","timestamp":"2026-08-24T23:13:11.000Z","message":{"content":"x"}}
    {"parentUuid":"a1","isSidechain":false,"userType":"external","cwd":"/x","sessionId":"s","version":"2.1","gitBranch":"main","type":"user","timestamp":"2026-08-24T23:13:27.000Z","message":{"role":"user","content":"echo egeon-chat-ok"}}
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
        var frontTurn = ChatTurn(id: "f1", prompt: "faz a coluna", promptAt: base)
        frontTurn.replyText = "feita"; frontTurn.replyAt = base.addingTimeInterval(30)
        let backTurn = ChatTurn(id: "b1", prompt: "expõe /nodes", promptAt: base.addingTimeInterval(10))

        let shell = ChatParticipant(id: "zsh", address: "deck/zsh", isAgent: false,
                                    role: nil, activity: .ready)
        // Shell não tem transcript: mesmo que a fechadura devolva algo, fica fora.
        let thread = ChatThread.build(participants: [front, back, shell]) {
            switch $0.id {
            case "front": return [frontTurn]
            case "back":  return [backTurn]
            default:      return [ChatTurn(id: "z", prompt: "nunca", promptAt: base)]
            }
        }

        XCTAssertEqual(thread.count, 3)
        XCTAssertEqual(thread[0], .prompt(to: front, turnId: "f1", text: "faz a coluna", at: base))
        // Prompt ao back logo depois de prompt ao front: o back ainda não falou,
        // não há o que citar.
        XCTAssertEqual(thread[1], .prompt(to: back, turnId: "b1", text: "expõe /nodes",
                                          at: base.addingTimeInterval(10)))
        // A resposta do front NÃO vem logo depois do prompt dela (o prompt ao
        // back entrou no meio): cita o prompt, estilo WhatsApp.
        guard case .reply(let from, let turn, let quote) = thread[2] else {
            return XCTFail("esperava resposta do front")
        }
        XCTAssertEqual(from, front)
        XCTAssertEqual(turn, frontTurn)
        XCTAssertEqual(quote?.authorId, nil)
        XCTAssertEqual(quote?.text, "faz a coluna")
        XCTAssertEqual(quote?.targetKey, thread[0].key)
    }

    // Consecutivo é limpo: prompt e resposta um atrás do outro, sem citação.
    func testConsecutiveReplyHasNoQuote() {
        let front = agent("front")
        let base = Date(timeIntervalSince1970: 1_000)
        var turn = ChatTurn(id: "t1", prompt: "oi", promptAt: base)
        turn.replyText = "oi"; turn.replyAt = base.addingTimeInterval(5)
        let thread = ChatThread.build(participants: [front]) { _ in [turn] }
        XCTAssertNil(thread[1].quote)
    }

    // Meu prompt intercalado cita a última fala do agente a quem falo.
    func testInterleavedPromptQuotesAgentsLastReply() {
        let front = agent("front"), back = agent("back")
        let base = Date(timeIntervalSince1970: 1_000)
        var backTurn = ChatTurn(id: "b1", prompt: "expõe", promptAt: base)
        backTurn.replyText = "no ar"; backTurn.replyAt = base.addingTimeInterval(5)
        let frontTurn = ChatTurn(id: "f1", prompt: "faz", promptAt: base.addingTimeInterval(10))
        let later = ChatTurn(id: "b2", prompt: "adiciona lastActivity", promptAt: base.addingTimeInterval(20))

        let thread = ChatThread.build(participants: [front, back]) {
            $0.id == "back" ? [backTurn, later] : [frontTurn]
        }
        // back: expõe, no ar · front: faz · back: adiciona (intercalado → cita "no ar")
        XCTAssertEqual(thread.count, 4)
        XCTAssertEqual(thread[3].quote?.authorId, "back")
        XCTAssertEqual(thread[3].quote?.text, "no ar")
        XCTAssertEqual(thread[3].quote?.targetKey, thread[1].key)
        XCTAssertNil(thread[2].quote, "front ainda não falou: nada a citar")
    }

    func testPendingDropsWhatTranscriptConfirmed() {
        let front = agent("front")
        let now = Date()
        let messages: [ChatMessage] = [.prompt(to: front, turnId: "u2", text: "oi", at: now)]
        let left = ChatThread.stillPending([
            .init(text: "oi", target: "front", sentAt: now, knownTurnIds: ["u1"]),
            .init(text: "oi", target: "back", sentAt: now, knownTurnIds: []),
            .init(text: "tchau", target: "front", sentAt: now, knownTurnIds: ["u1"]),
        ], given: messages)
        XCTAssertEqual(left.map(\.text), ["oi", "tchau"])
        XCTAssertEqual(left.map(\.target), ["back", "front"])
    }

    // Dois "oi" seguidos: o primeiro turno novo dá baixa em UM eco, não nos dois.
    func testOneNewTurnConfirmsOnePending() {
        let front = agent("front")
        let now = Date()
        let messages: [ChatMessage] = [.prompt(to: front, turnId: "u2", text: "oi", at: now)]
        let left = ChatThread.stillPending([
            .init(text: "oi", target: "front", sentAt: now, knownTurnIds: ["u1"]),
            .init(text: "oi", target: "front", sentAt: now, knownTurnIds: ["u1"]),
        ], given: messages)
        XCTAssertEqual(left.count, 1)
        // Rodada seguinte, mesma lista: o turno já usado não dá baixa de novo.
        XCTAssertEqual(ChatThread.stillPending(left, given: messages).count, 1)
        // Só o segundo turno novo fecha o segundo eco.
        let more = messages + [.prompt(to: front, turnId: "u3", text: "oi", at: now)]
        XCTAssertEqual(ChatThread.stillPending(left, given: more).count, 0)
    }

    // Um "oi" que JÁ existia na hora do envio não confirma o "oi" novo — nem que
    // tenha sido gravado há um segundo. Só id que o envio ainda não conhecia.
    func testKnownTurnDoesNotConfirmNewPending() {
        let front = agent("front")
        let now = Date()
        let messages: [ChatMessage] = [.prompt(to: front, turnId: "u1", text: "oi", at: now)]
        let left = ChatThread.stillPending(
            [.init(text: "oi", target: "front", sentAt: now, knownTurnIds: ["u1"])],
            given: messages)
        XCTAssertEqual(left.count, 1)
    }
}

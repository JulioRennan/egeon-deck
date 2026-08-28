import XCTest
@testable import EgeonDeck

/// A thread vira linhas com id estável: uma por bloco da cadeia, primeira e
/// última de cada bolha marcadas, status só no turno ao vivo.
final class ChatBlocksTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func agent(_ id: String, _ activity: Activity = .working) -> ChatParticipant {
        ChatParticipant(id: id, address: "deck/\(id)", isAgent: true, role: nil, activity: activity)
    }

    private func turn() -> ChatTurn {
        var turn = ChatTurn(id: "u1", prompt: "faz", promptAt: t0)
        turn.parts = [
            .text("Vou olhar.\n\n```swift\nlet a = 1\n```\n\nDepois disso."),
            .step(ChatStep(glyph: "$", text: "Roda", detail: "swift test")),
            .step(ChatStep(glyph: "±", text: "a.swift", diff: ["@@ -1 +1 @@", "-a", "+b"])),
            .text("Pronto."),
        ]
        turn.replyAt = t0.addingTimeInterval(9)
        return turn
    }

    func testOneRowPerBlockWithStableIds() {
        let front = agent("front")
        let messages: [ChatMessage] = [
            .prompt(to: front, turnId: "u1", text: "faz", at: t0),
            .reply(from: front, turn: turn()),
        ]
        let blocks = ChatBlocks.build(messages: messages, live: [:], typing: [])
        XCTAssertEqual(blocks.map(\.id), ["p|u1", "h|u1", "b|u1|0", "b|u1|1", "b|u1|2",
                                          "b|u1|3", "b|u1|4", "b|u1|5"])
        XCTAssertEqual(blocks.map(\.messageKey), ["p|u1"] + Array(repeating: "r|u1", count: 7))
        XCTAssertEqual(blocks.map(\.first), [true, true, false, false, false, false, false, false])
        XCTAssertEqual(blocks.map(\.last), [true, false, false, false, false, false, false, true])
        // Prosa, código, prosa, passo, diff, prosa — na ordem da cadeia.
        guard case .prose = blocks[2].kind, case .code(_, "swift", "let a = 1") = blocks[3].kind,
              case .prose = blocks[4].kind, case .step = blocks[5].kind,
              case .diff(_, "a.swift", _) = blocks[6].kind, case .prose = blocks[7].kind
        else { return XCTFail("ordem da cadeia: \(blocks.map(\.kind))") }
        XCTAssertTrue(blocks[0].alignsRight)
        XCTAssertFalse(blocks[1].alignsRight)
    }

    func testLiveTurnGetsStatusRowAndNoTime() {
        let front = agent("front")
        let messages: [ChatMessage] = [.reply(from: front, turn: turn())]
        let blocks = ChatBlocks.build(messages: messages,
                                      live: ["front": ("u1", .thinking)], typing: [])
        XCTAssertEqual(blocks.last?.id, "s|u1")
        guard case .status(_, .thinking) = blocks.last!.kind else { return XCTFail() }
        guard case .header(_, let at, _) = blocks[0].kind else { return XCTFail() }
        XCTAssertNil(at, "ao vivo é 'agora'")
        XCTAssertTrue(blocks.last!.last)
        XCTAssertFalse(blocks[blocks.count - 2].last)

        // Outro turno ao vivo do mesmo agente não pinga aqui.
        let other = ChatBlocks.build(messages: messages, live: ["front": ("u9", .working)], typing: [])
        XCTAssertNotEqual(other.last?.id, "s|u1")
    }

    func testTypingAndAgentToAgentPrompt() {
        let front = agent("front"), back = agent("back")
        let messages: [ChatMessage] = [
            .prompt(to: back, turnId: "b1", text: "oi", at: t0, from: "front"),
        ]
        let blocks = ChatBlocks.build(messages: messages, live: [:], typing: [front])
        XCTAssertEqual(blocks.map(\.id), ["p|b1", "t|front"])
        XCTAssertFalse(blocks[0].alignsRight, "mensagem de agente fica à esquerda")
        XCTAssertEqual(blocks[0].participant.id, "back")
        XCTAssertEqual(blocks[1].participant.id, "front")
    }

    // Consecutivo é limpo, intercalado é marcado: o `@` só entra quando a
    // mensagem anterior não é do mesmo participante.
    func testMentionOnlyWhenNotContinuous() {
        let front = agent("front"), back = agent("back")
        let messages: [ChatMessage] = [
            .prompt(to: front, turnId: "f1", text: "faz", at: t0),
            .reply(from: front, turn: turn()),
            .prompt(to: front, turnId: "f2", text: "continua", at: t0.addingTimeInterval(20)),
            .prompt(to: back, turnId: "b1", text: "e você?", at: t0.addingTimeInterval(30)),
            .prompt(to: front, turnId: "f3", text: "volta", at: t0.addingTimeInterval(40), from: "back"),
        ]
        let blocks = ChatBlocks.build(messages: messages, live: [:], typing: [])
        func mention(_ id: String) -> Bool? {
            guard let block = blocks.first(where: { $0.id == id }),
                  case .prompt(_, _, _, _, _, _, let mention) = block.kind else { return nil }
            return mention
        }
        XCTAssertEqual(mention("p|f1"), false, "primeira mensagem")
        XCTAssertEqual(mention("p|f2"), false, "logo depois da resposta do front")
        XCTAssertEqual(mention("p|b1"), true, "trocou de interlocutor")
        XCTAssertEqual(mention("p|f3"), true, "do back para o front, depois de uma fala ao back")
    }

    func testActivityDoesNotChangeBlocks() {
        let a = ChatBlocks.build(messages: [.reply(from: agent("x", .working), turn: turn())],
                                 live: [:], typing: [])
        let b = ChatBlocks.build(messages: [.reply(from: agent("x", .waiting), turn: turn())],
                                 live: [:], typing: [])
        XCTAssertEqual(a, b)
    }
}

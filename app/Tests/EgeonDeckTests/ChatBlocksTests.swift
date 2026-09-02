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
              case .prose = blocks[4].kind, case .step(_, _, false) = blocks[5].kind,
              case .diff(_, "a.swift", _) = blocks[6].kind, case .prose = blocks[7].kind
        else { return XCTFail("ordem da cadeia: \(blocks.map(\.kind))") }
        XCTAssertTrue(blocks[0].alignsRight)
        XCTAssertFalse(blocks[1].alignsRight)
    }

    /// Passo de comando nasce só no título e abre por id. Passo sem nada além
    /// do título é sempre inteiro, e o de edição nunca recolhe: o diff é
    /// justamente o que se quer ver.
    func testStepsCollapseUntilOpenedByIdButDiffNeverDoes() {
        let front = agent("front")
        var turn = self.turn()
        turn.parts.append(.step(ChatStep(glyph: "→", text: "só título")))
        let messages: [ChatMessage] = [.reply(from: front, turn: turn)]
        let closed = ChatBlocks.build(messages: messages, live: [:], typing: [])
        guard case .step(_, let step, false) = closed[4].kind, step.text == "Roda",
              case .diff(_, "a.swift", _) = closed[5].kind,
              case .step(_, _, true) = closed[7].kind
        else { return XCTFail("recolhidos: \(closed.map(\.kind))") }

        let open = ChatBlocks.build(messages: messages, live: [:], typing: [],
                                    expanded: ["b|u1|3"])
        guard case .step(_, _, true) = open[4].kind, case .diff(_, "a.swift", _) = open[5].kind
        else { return XCTFail("abertos: \(open.map(\.kind))") }
        XCTAssertEqual(open.map(\.id), closed.map(\.id), "abrir não muda o id")
    }

    /// Passos seguidos viram uma CAPA — "3 passos · três" — e o clique nela
    /// aprofunda: capa, títulos, tudo aberto, capa de novo. Um passo sozinho
    /// não ganha capa, e prosa, diff ou código cortam a sequência.
    func testContiguousStepsCollapseIntoOneGroup() {
        let front = agent("front")
        var turn = ChatTurn(id: "u1", prompt: "faz", promptAt: t0)
        turn.parts = [.step(ChatStep(glyph: "$", text: "um", detail: "a")),
                      .step(ChatStep(glyph: "$", text: "dois", detail: "b")),
                      .step(ChatStep(glyph: "$", text: "três", detail: "c")),
                      .text("No meio.\n\n```swift\nlet a = 1\n```"),
                      .step(ChatStep(glyph: "$", text: "quatro", detail: "d"))]
        turn.replyAt = t0.addingTimeInterval(9)
        let messages: [ChatMessage] = [.reply(from: front, turn: turn)]

        let summary = ChatBlocks.build(messages: messages, live: [:], typing: [])
        XCTAssertEqual(summary.map(\.id), ["h|u1", "g|u1|0", "b|u1|3", "b|u1|4", "b|u1|5"])
        guard case .group(_, 3, "três", .summary) = summary[1].kind
        else { return XCTFail("capa: \(summary[1].kind)") }
        guard case .step(_, let alone, false) = summary[4].kind, alone.text == "quatro"
        else { return XCTFail("passo sozinho não tem capa: \(summary[4].kind)") }

        // Um clique: a capa e os três títulos, tudo numa caixa só.
        let titles = ChatBlocks.build(messages: messages, live: [:], typing: [],
                                      groups: ["g|u1|0": .titles])
        XCTAssertEqual(titles.map(\.id),
                       ["h|u1", "g|u1|0", "b|u1|0", "b|u1|1", "b|u1|2", "b|u1|3", "b|u1|4", "b|u1|5"])
        // A capa fica na raiz; os passos dela entram um tab, cada um na sua
        // caixinha (ADR-050).
        XCTAssertEqual(titles[1...4].map(\.depth), [0, 1, 1, 1])
        XCTAssertEqual(titles.filter { $0.depth > 0 }.count, 3)
        XCTAssertTrue(summary.allSatisfy { $0.depth == 0 }, "sem capa aberta, nada é filho")
        XCTAssertTrue(titles[2...4].allSatisfy {
            if case .step(_, _, let open) = $0.kind { return !open } else { return false }
        }, "no primeiro clique os passos ainda são só título")

        // Detalhar não é um estado que sobrescreve o passo: quem abre é o
        // `expanded`, que o container preenche ao entrar em `details`.
        let details = ChatBlocks.build(messages: messages, live: [:], typing: [],
                                       expanded: ["b|u1|0", "b|u1|1", "b|u1|2"],
                                       groups: ["g|u1|0": .details])
        XCTAssertTrue(details[2...4].allSatisfy {
            if case .step(_, _, let open) = $0.kind { return open } else { return false }
        })
        XCTAssertEqual(ChatGroupLevel.summary.next(opened: false), .titles)
        XCTAssertEqual(ChatGroupLevel.titles.next(opened: false), .details)
        XCTAssertEqual(ChatGroupLevel.titles.next(opened: true), .summary,
                       "com passo aberto à mão, a capa fecha em vez de aprofundar")
        XCTAssertEqual(ChatGroupLevel.details.next(opened: true), .summary, "o ciclo volta ao começo")
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

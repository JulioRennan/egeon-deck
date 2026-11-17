import XCTest
@testable import EgeonDeck

/// As linhas são medidas sem view e fora da main: altura por largura, bolha
/// com uma largura só, e bolha que não mudou não é medida de novo.
final class ChatBlockLayoutTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let front = ChatParticipant(id: "front", address: "deck/front", isAgent: true,
                                        role: nil, activity: .ready)

    private func blocks(reply: String = "Uma linha só.", expanded: Set<String> = []) -> [ChatBlock] {
        var turn = ChatTurn(id: "u1", prompt: "faz", promptAt: t0)
        turn.parts = [.text(reply), .step(ChatStep(glyph: "$", text: "Roda", detail: "swift test",
                                                   output: "ok\nok\nok"))]
        turn.replyAt = t0.addingTimeInterval(3)
        return ChatBlocks.build(messages: [.prompt(to: front, turnId: "u1", text: "faz", at: t0),
                                           .reply(from: front, turn: turn)],
                                live: [:], typing: [], expanded: expanded)
    }

    /// Recolhido é uma linha: chevron, título e o tamanho da saída; aberto
    /// tem o comando e a saída, e a linha cresce com eles.
    func testCollapsedStepIsOneLineAndOpenOneIsTaller() {
        let closed = ChatBlockLayout.measure(blocks(), width: 800, known: [:])["r|u1"]!
        let open = ChatBlockLayout.measure(blocks(expanded: ["b|u1|1"]), width: 800, known: [:])["r|u1"]!
        XCTAssertGreaterThan(open.rows["b|u1|1"]!.height, closed.rows["b|u1|1"]!.height)
        let closedText = closed.rows["b|u1|1"]!.text!.string
        XCTAssertTrue(closedText.hasPrefix("▸ $  Roda"), closedText)
        XCTAssertTrue(closedText.hasSuffix("⎿ 3 linhas"), closedText)
        XCTAssertFalse(closedText.contains("swift test"))
        let openText = open.rows["b|u1|1"]!.text!.string
        XCTAssertTrue(openText.hasPrefix("▾ $  Roda\n"), openText)
        XCTAssertTrue(openText.contains("swift test") && openText.contains("⎿ ok"))
        // Sem nada além do título, não há o que abrir — nem chevron.
        let bare = ChatBlockLayout.render(ChatStep(glyph: "→", text: "Lê"), expanded: false).string
        XCTAssertEqual(bare, "→  Lê")
    }

    func testEveryRowGetsAHeightAndBubbleSharesWidth() {
        let rows = blocks()
        let metrics = ChatBlockLayout.measure(rows, width: 800, known: [:])
        let reply = try! XCTUnwrap(metrics["r|u1"])
        XCTAssertEqual(Set(reply.rows.keys), Set(rows.filter { $0.messageKey == "r|u1" }.map(\.id)))
        XCTAssertEqual(Set(reply.rows.values.map(\.bubbleWidth)).count, 1, "uma largura por bolha")
        for row in reply.rows.values { XCTAssertGreaterThan(row.height, 0) }
        let prompt = try! XCTUnwrap(metrics["p|u1"]?.rows["p|u1"])
        XCTAssertLessThan(prompt.bubbleWidth, 300, "prompt curto, bolha curta")
    }

    func testNarrowerThreadMakesProseTaller() {
        let long = String(repeating: "palavra ", count: 80)
        let wide = ChatBlockLayout.measure(blocks(reply: long), width: 900, known: [:])["r|u1"]!
        let narrow = ChatBlockLayout.measure(blocks(reply: long), width: 400, known: [:])["r|u1"]!
        XCTAssertGreaterThan(narrow.rows["b|u1|0"]!.height, wide.rows["b|u1|0"]!.height)
        XCTAssertLessThan(narrow.rows["b|u1|0"]!.bubbleWidth, wide.rows["b|u1|0"]!.bubbleWidth)
    }

    func testUnchangedBubbleIsReusedAndChangedOneIsNot() {
        let first = ChatBlockLayout.measure(blocks(), width: 800, known: [:])
        let again = ChatBlockLayout.measure(blocks(), width: 800, known: first)
        XCTAssertEqual(again, first)
        let grown = ChatBlockLayout.measure(blocks(reply: "Uma linha só.\n\nE outra."), width: 800, known: first)
        XCTAssertEqual(grown["p|u1"], first["p|u1"], "o prompt não mudou")
        XCTAssertNotEqual(grown["r|u1"], first["r|u1"])
        // Largura nova invalida tudo.
        let resized = ChatBlockLayout.measure(blocks(), width: 700, known: first)
        XCTAssertNotEqual(resized["p|u1"]?.width, first["p|u1"]?.width)
    }

    // Mensagem de agente para agente: quem mandou em cima, `@destinatário`
    // no texto — sem seta, como no WhatsApp.
    func testAgentPromptMentionsWithoutArrow() {
        let back = ChatParticipant(id: "back", address: "deck/back", isAgent: true, role: nil, activity: .ready)
        let text = ChatBlockLayout.prompt("vem pronto?", to: back, from: "front", mention: true).string
        XCTAssertEqual(text, "✦ front\n@back vem pronto?")
        XCTAssertEqual(ChatBlockLayout.prompt("oi", to: back, from: nil, mention: true).string, "@back oi")
        XCTAssertEqual(ChatBlockLayout.prompt("oi", to: back, from: nil, mention: false).string, "oi",
                       "mensagem contínua não marca")
    }

    func testMeasuresOffMainThread() {
        let done = expectation(description: "medido fora da main")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread)
            let metrics = ChatBlockLayout.measure(self.blocks(), width: 800, known: [:])
            XCTAssertEqual(metrics.count, 2)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}

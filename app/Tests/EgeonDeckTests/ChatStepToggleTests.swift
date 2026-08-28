import XCTest
@testable import EgeonDeck

/// Os passos de comando da bolha nascem só no título e abrem por clique: o
/// container guarda o que você abriu por id e remonta; a linha entrega o
/// clique do título ao toggle e deixa o resto da caixa com o texto. O diff
/// fica de fora disso — nasce aberto e assim fica.
@MainActor
final class ChatStepToggleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_787_678_363)
    private let front = ChatParticipant(id: "a", address: "deck/a", isAgent: true,
                                        role: nil, activity: .waiting)

    private func settle(for limit: TimeInterval = 3, until done: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(limit)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func isStep(_ block: ChatBlock, expanded: Bool) -> Bool {
        if case .step(_, _, expanded) = block.kind { return true }
        return false
    }

    func testToggleOpensStepAndDiffAndClosesAgain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ChatHistory(workbenches: root)
        var turn = ChatTurn(id: "u1", prompt: "faz", promptAt: t0)
        let steps = [ChatStep(glyph: "$", text: "Roda", detail: "swift test", output: "ok"),
                     ChatStep(glyph: "±", text: "a.swift", diff: ["@@ -1 +1 @@", "-a", "+b"])]
        turn.steps = steps
        turn.replyText = "Pronto."
        turn.parts = steps.map(ChatPart.step) + [.text("Pronto.")]
        turn.replyAt = t0.addingTimeInterval(2)
        history.append(ChatRecord(node: "a", turn: turn), workbench: "w")
        history.flush()

        let container = ChatContainer(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        container.participants = { [self.front] }
        container.historyFile = { history.current(forWorkbench: "w") }
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        container.refresh()
        settle { container.thread.blocks.contains { self.isStep($0, expanded: false) } }

        let blocks = container.thread.blocks
        let step = try XCTUnwrap(blocks.first { $0.id == "b|u1|0" })
        XCTAssertTrue(isStep(step, expanded: false))
        guard case .diff(_, "a.swift", _) = try XCTUnwrap(blocks.first { $0.id == "b|u1|1" }).kind
        else { return XCTFail("o diff nasce aberto") }

        container.toggleStep(step)
        settle { container.thread.blocks.contains { self.isStep($0, expanded: true) } }
        XCTAssertEqual(container.expandedSteps, ["b|u1|0"])
        let open = container.thread.blocks
        XCTAssertTrue(isStep(try XCTUnwrap(open.first { $0.id == "b|u1|0" }), expanded: true))
        guard case .diff(_, "a.swift", _) = try XCTUnwrap(open.first { $0.id == "b|u1|1" }).kind
        else { return XCTFail("o diff continua aberto") }

        // Pelo id é como a rota de teste alterna, sem clique.
        container.toggleStep(id: "b|u1|0")
        settle { container.thread.blocks.contains { $0.id == "b|u1|0" && self.isStep($0, expanded: false) } }
        XCTAssertEqual(container.expandedSteps, [])
        container.toggleStep(id: "não existe")
        XCTAssertEqual(container.expandedSteps, [], "id desconhecido não abre nada")
    }

    func testRowTogglesOnlyOnTheTitleStrip() throws {
        let step = ChatStep(glyph: "$", text: "Roda", detail: "swift test", output: "ok\nok")
        let closed = ChatBlock(id: "b|u1|0", messageKey: "r|u1",
                               kind: .step(from: front, step: step, expanded: false))
        let open = ChatBlock(id: "b|u1|0", messageKey: "r|u1",
                             kind: .step(from: front, step: step, expanded: true))
        let metrics = ChatBlockLayout.measure(ChatBlocks.positioned([open]), width: 600, known: [:])["r|u1"]!
        let row = ChatTextRow(frame: NSRect(x: 0, y: 0, width: 600, height: metrics.rows["b|u1|0"]!.height))
        let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
        defer { window.contentView = nil }
        window.contentView = row
        var toggles = 0
        row.onToggle = { toggles += 1 }
        row.configure(ChatBlocks.positioned([open])[0], metrics: metrics.rows["b|u1|0"]!)
        row.layoutSubtreeIfNeeded()

        let strip = try XCTUnwrap(row.toggleRect)
        XCTAssertLessThan(strip.height, 30, "a faixa é a primeira linha da caixa, não a caixa toda")
        let onTitle = NSPoint(x: strip.midX, y: strip.midY)
        let onOutput = NSPoint(x: strip.midX, y: strip.maxY + 20)
        XCTAssertTrue(row.hitTest(onTitle) === row, "o título é da linha, não do texto")
        XCTAssertFalse(row.hitTest(onOutput) === row, "a saída continua texto selecionável")

        func click(_ point: NSPoint) {
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: row.convert(point, to: nil),
                                           modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            row.mouseDown(with: event)
        }
        click(onTitle)
        XCTAssertEqual(toggles, 1)
        click(onOutput)
        XCTAssertEqual(toggles, 1, "fora da faixa não alterna")

        // O cursor tem um dono só: o texto. A linha não registra faixa de mão
        // por baixo — dois donos no mesmo ponto faziam o ponteiro tremer.
        XCTAssertEqual(row.text.toggleHeight, strip.maxY - row.text.frame.minY, accuracy: 0.01)
        XCTAssertGreaterThan(row.text.toggleHeight, 0)
        // O cursor sai todo daqui: NSTextView põe o I-beam por cursor rect, e
        // é por cursor rect que a mão tem de vir também.
        let rects = row.text.cursorRects(in: row.text.bounds)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].cursor, NSCursor.pointingHand)
        XCTAssertEqual(rects[1].cursor, NSCursor.iBeam)
        XCTAssertTrue(rects[0].rect.contains(row.text.convert(onTitle, from: row)), "mão no título")
        XCTAssertTrue(rects[1].rect.contains(row.text.convert(onOutput, from: row)), "no comando é texto")
        XCTAssertEqual(rects[0].rect.width, row.text.bounds.width)

        // E o cursor que sai de fato, pelos outros dois caminhos do AppKit.
        func cursor(at point: NSPoint, _ send: (NSEvent) -> Void) -> NSCursor {
            NSCursor.arrow.set()
            let event = NSEvent.mouseEvent(with: .mouseMoved, location: row.convert(point, to: nil),
                                           modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            send(event)
            return NSCursor.current
        }
        XCTAssertEqual(cursor(at: onTitle, row.text.cursorUpdate), NSCursor.pointingHand)
        XCTAssertEqual(cursor(at: onOutput, row.text.cursorUpdate), NSCursor.iBeam)
        XCTAssertEqual(cursor(at: onTitle, row.text.mouseMoved), NSCursor.pointingHand)
        XCTAssertEqual(cursor(at: onOutput, row.text.mouseMoved), NSCursor.iBeam)

        // Sem nada além do título, não há faixa.
        let bare = ChatBlock(id: "b|u1|1", messageKey: "r|u1",
                             kind: .step(from: front, step: ChatStep(glyph: "→", text: "Lê"), expanded: true))
        row.configure(bare, metrics: metrics.rows["b|u1|0"]!)
        row.layoutSubtreeIfNeeded()
        XCTAssertNil(row.toggleRect)
        XCTAssertEqual(row.text.toggleHeight, 0, "sem faixa, o texto não mexe no cursor")
        XCTAssertTrue(row.text.cursorRects(in: row.text.bounds).isEmpty)
        _ = closed
    }
}

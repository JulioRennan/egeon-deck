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

    /// Aberto, o passo tem anatomia de tile: cabeçalho com um fundo, miolo com
    /// outro e um fio entre os dois — é isso que separa "aqui se clica" de
    /// "aqui é texto". Medido no pixel, longe do texto.
    func testOpenStepPaintsHeaderAndBodyDifferently() throws {
        let step = ChatStep(glyph: "$", text: "Roda", detail: "swift test", output: "ok\nok\nok")
        func render(expanded: Bool) throws -> (header: NSColor, body: NSColor) {
            let blocks = ChatBlocks.positioned([ChatBlock(id: "b|u1|0", messageKey: "r|u1",
                kind: .step(from: front, step: step, expanded: expanded))])
            let metrics = try XCTUnwrap(ChatBlockLayout.measure(blocks, width: 600, known: [:])["r|u1"])
            let row = ChatTextRow(frame: NSRect(x: 0, y: 0, width: 600,
                                                height: metrics.rows["b|u1|0"]!.height))
            let window = NSWindow(contentRect: row.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            defer { window.contentView = nil }
            window.contentView = row
            row.configure(blocks[0], metrics: metrics.rows["b|u1|0"]!)
            row.layoutSubtreeIfNeeded()
            let strip = try XCTUnwrap(row.toggleRect)
            let rep = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
            row.cacheDisplay(in: row.bounds, to: rep)
            // O bitmap é o da tela: 2 pixels por ponto no retina.
            let scale = CGFloat(rep.pixelsWide) / row.bounds.width
            // Encostado na borda direita da caixa: ali não passa texto. O
            // segundo ponto é o miolo quando há um, e o fundo da bolha acima
            // da caixa quando não há.
            let x = Int((strip.maxX - 6) * scale)
            let below = expanded ? (strip.maxY + 8) : 2
            return (try XCTUnwrap(rep.colorAt(x: x, y: Int(strip.midY * scale))),
                    try XCTUnwrap(rep.colorAt(x: x, y: Int(below * scale))))
        }

        let open = try render(expanded: true)
        XCTAssertNotEqual(open.header.brightnessComponent, open.body.brightnessComponent,
                          accuracy: 0.0, "cabeçalho e miolo têm de se distinguir")
        XCTAssertGreaterThan(open.header.brightnessComponent, open.body.brightnessComponent,
                             "o cabeçalho é o claro; o miolo, o fundo")

        // Recolhido não tem miolo: a caixa inteira é cabeçalho, e o fundo da
        // bolha em volta é mais escuro que ela.
        let closed = try render(expanded: false)
        XCTAssertGreaterThan(closed.header.brightnessComponent, closed.body.brightnessComponent)
        XCTAssertEqual(closed.header.brightnessComponent, open.header.brightnessComponent,
                       accuracy: 0.05, "o cabeçalho é o mesmo, aberto ou fechado")
    }

    /// O clique na capa avança o nível no container, e voltar ao resumo
    /// esquece o que estava aberto lá dentro.
    func testClickingTheGroupCoverCyclesTheLevels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ChatHistory(workbenches: root)
        var turn = ChatTurn(id: "u1", prompt: "faz", promptAt: t0)
        let steps = [ChatStep(glyph: "$", text: "um", detail: "a", output: "1"),
                     ChatStep(glyph: "$", text: "dois", detail: "b", output: "2")]
        turn.steps = steps
        turn.parts = steps.map(ChatPart.step)
        turn.replyText = "ok"
        turn.parts.append(.text("ok"))
        turn.replyAt = t0.addingTimeInterval(2)
        history.append(ChatRecord(node: "a", turn: turn), workbench: "w")
        history.flush()

        let container = ChatContainer(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        container.participants = { [self.front] }
        container.historyFile = { history.current(forWorkbench: "w") }
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        container.refresh()
        settle { container.thread.blocks.contains { $0.id == "g|u1|0" } }

        func cover() throws -> ChatBlock {
            try XCTUnwrap(container.thread.blocks.first { $0.id == "g|u1|0" })
        }
        func level() -> ChatGroupLevel? { container.groupLevels["g|u1|0"] }
        XCTAssertEqual(container.thread.blocks.filter { $0.id.hasPrefix("b|") }.count, 1,
                       "no resumo só a prosa acompanha a capa")

        container.toggleStep(try cover())
        settle { level() == .titles && container.thread.blocks.contains { $0.id == "b|u1|0" } }
        XCTAssertEqual(level(), .titles)

        // Um passo aberto à mão dentro do grupo.
        container.toggleStep(id: "b|u1|0")
        settle { container.expandedSteps.contains("b|u1|0") }

        container.toggleStep(try cover())
        settle { container.thread.blocks.contains {
            if case .step(_, _, let open) = $0.kind { return open } else { return false } } }
        XCTAssertEqual(level(), .details)
        XCTAssertTrue(container.thread.blocks.contains {
            if case .step(_, _, let open) = $0.kind { return open } else { return false }
        })

        container.toggleStep(try cover())
        settle { !container.thread.blocks.contains { $0.id == "b|u1|0" } }
        XCTAssertEqual(level(), .summary)
        XCTAssertEqual(container.expandedSteps, [], "fechar a capa limpa o que estava aberto dentro")
        XCTAssertFalse(container.thread.blocks.contains { $0.id == "b|u1|0" })
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
        XCTAssertLessThan(strip.height, row.bounds.height * 0.6,
                          "a faixa é a primeira linha da caixa, não a caixa toda")
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

        // Recolhido, o card inteiro alterna — inclusive o rodapé, que é
        // padding: uma caixa de uma linha é um botão, sem canto morto.
        let shutBlocks = ChatBlocks.positioned([closed])
        let shutMetrics = try XCTUnwrap(ChatBlockLayout.measure(shutBlocks, width: 600, known: [:])["r|u1"])
        row.configure(shutBlocks[0], metrics: shutMetrics.rows["b|u1|0"]!)
        row.layoutSubtreeIfNeeded()
        let card = try XCTUnwrap(row.toggleRect)
        let footer = NSPoint(x: card.midX, y: card.maxY - 2)
        XCTAssertTrue(card.contains(footer), "o rodapé do card recolhido clica")
        XCTAssertTrue(row.hitTest(footer) === row)
        let before = toggles
        click(footer)
        XCTAssertEqual(toggles, before + 1)

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

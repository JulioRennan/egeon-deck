import XCTest
@testable import EgeonDeck

/// A thread é preguiçosa de ponta a ponta: só as linhas visíveis existem (e
/// são reusadas ao rolar), o texto chega renderizado da medição, e o
/// histórico entra em janelas — o fim primeiro, o resto quando você rola
/// até o começo do que há, sem a tela pular.
@MainActor
final class ChatLazyLoadTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_787_678_000)
    private let front = ChatParticipant(id: "front", address: "deck/front", isAgent: true,
                                        role: nil, activity: .ready)

    private func messages(_ count: Int) -> [ChatMessage] {
        (0..<count).flatMap { i -> [ChatMessage] in
            var turn = ChatTurn(id: "u\(i)", prompt: "pergunta \(i)", promptAt: t0.addingTimeInterval(Double(i) * 60))
            turn.parts = [.text("Resposta **\(i)** com um pouco de texto para ocupar a linha."),
                          .step(ChatStep(glyph: "$", text: "Passo \(i)", detail: "ls"))]
            turn.replyAt = turn.promptAt.addingTimeInterval(10)
            return [.prompt(to: front, turnId: turn.id, text: turn.prompt, at: turn.promptAt),
                    .reply(from: front, turn: turn)]
        }
    }

    private func host(_ view: NSView, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        view.frame = NSRect(origin: .zero, size: size)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return window
    }

    private func draw(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
    }

    func testOnlyVisibleRowsExistAndScrollingReusesThem() {
        let thread = ChatThreadController()
        let window = host(thread.scrollView, size: NSSize(width: 800, height: 600))
        defer { window.contentView = nil }
        let blocks = ChatBlocks.build(messages: messages(150), live: [:], typing: [])
        let metrics = ChatBlockLayout.measure(blocks, width: 800, known: [:])
        thread.apply(blocks, metrics: metrics)
        thread.scrollToBottom(animated: false)
        draw(thread.scrollView)

        XCTAssertEqual(thread.blocks.count, 600)
        XCTAssertGreaterThan(thread.rowsCreated, 0)
        XCTAssertLessThan(thread.rowsCreated, 60, "600 linhas, só as visíveis nascem")

        let afterFirstDraw = thread.rowsCreated
        for step in stride(from: 0.9, through: 0, by: -0.1) {
            thread.scroll(to: thread.tableView.bounds.height * step, animated: false)
            draw(thread.scrollView)
        }
        XCTAssertLessThan(thread.rowsCreated, afterFirstDraw + 40,
                          "rolar a thread inteira reusa as views em vez de criar")
    }

    func testTextComesRenderedFromMeasurement() {
        let blocks = ChatBlocks.build(messages: messages(1), live: [:], typing: [])
        let metrics = ChatBlockLayout.measure(blocks, width: 800, known: [:])
        let prose = try! XCTUnwrap(metrics["r|u0"]?.rows["b|u0|0"])
        XCTAssertEqual(prose.text?.string, "Resposta 0 com um pouco de texto para ocupar a linha.")
        XCTAssertNotNil(metrics["p|u0"]?.rows["p|u0"]?.text)
        XCTAssertNil(metrics["r|u0"]?.rows["h|u0"]?.text, "cabeçalho não tem corpo de texto")
    }

    func testRowsInsertedAboveKeepTheReaderInPlace() {
        let thread = ChatThreadController()
        let window = host(thread.scrollView, size: NSSize(width: 800, height: 600))
        defer { window.contentView = nil }
        let recent = messages(40)
        let blocks = ChatBlocks.build(messages: Array(recent.suffix(40)), live: [:], typing: [])
        thread.apply(blocks, metrics: ChatBlockLayout.measure(blocks, width: 800, known: [:]))
        // No meio da leitura: uma linha do meio no topo da viewport.
        let anchorRow = 30
        let anchorId = thread.blocks[anchorRow].id
        thread.scroll(to: thread.tableView.rect(ofRow: anchorRow).minY, animated: false)
        draw(thread.scrollView)
        let before = thread.tableView.rect(ofRow: anchorRow).minY - thread.scrollView.contentView.documentVisibleRect.minY

        // Chega histórico mais antigo em cima (a janela cresceu).
        let more = ChatBlocks.build(messages: messages(80).prefix(80).map { $0 }, live: [:], typing: [])
        thread.apply(more, metrics: ChatBlockLayout.measure(more, width: 800, known: thread.bubbleMetrics))
        draw(thread.scrollView)
        let row = thread.blocks.firstIndex { $0.id == anchorId }!
        XCTAssertGreaterThan(row, anchorRow, "entrou coisa em cima")
        let after = thread.tableView.rect(ofRow: row).minY - thread.scrollView.contentView.documentVisibleRect.minY
        XCTAssertEqual(after, before, accuracy: 1, "a mesma linha continua no mesmo lugar da tela")
    }

    func testHistoryLoadsInWindowsWhenScrolledToTop() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lazy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ChatHistory(workbenches: root)
        for i in 0..<100 {
            var turn = ChatTurn(id: "u\(i)", prompt: "pergunta \(i)", promptAt: t0.addingTimeInterval(Double(i) * 60))
            turn.replyText = "resposta \(i)"
            turn.replyAt = turn.promptAt.addingTimeInterval(5)
            history.append(ChatRecord(node: "front", turn: turn), workbench: "w")
        }
        history.flush()

        let container = ChatContainer(frame: .zero)
        container.participants = { [self.front] }
        container.historyFile = { history.current(forWorkbench: "w") }
        let window = host(container, size: NSSize(width: 1000, height: 700))
        defer { window.contentView = nil }
        func settle(until done: @escaping () -> Bool) {
            let deadline = Date().addingTimeInterval(4)
            while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        }
        container.refresh()
        settle { container.threadRebuilds >= 1 }
        XCTAssertEqual(container.loadedMessages, 60)
        let initial = container.snapshotBlockCount
        XCTAssertLessThanOrEqual(initial, 60 * 3, "60 mensagens do fim, não 200")

        container.scroll("top")
        settle { container.loadedMessages > 60 && container.threadRebuilds >= 2 }
        XCTAssertEqual(container.loadedMessages, 120)
        XCTAssertGreaterThan(container.snapshotBlockCount, initial, "o topo trouxe mais histórico")
    }
}

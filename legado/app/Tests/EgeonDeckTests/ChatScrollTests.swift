import XCTest
@testable import EgeonDeck

/// A thread desce sozinha quando você está no fim — e continua descendo. Os
/// três jeitos de isso quebrar: a tabela ainda não cresceu quando se mede o
/// fim, uma descida animada em curso parecer "subiu para ler", e você mandar
/// mensagem de um ponto um pouco acima do fim.
@MainActor
final class ChatScrollTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_787_679_000)
    private let front = ChatParticipant(id: "a", address: "deck/a", isAgent: true,
                                        role: nil, activity: .waiting)

    private func messages(_ count: Int) -> [ChatMessage] {
        (0..<count).flatMap { i -> [ChatMessage] in
            var turn = ChatTurn(id: "u\(i)", prompt: "pergunta \(i)", promptAt: t0.addingTimeInterval(Double(i) * 60))
            turn.parts = [.text("Resposta \(i) com texto suficiente para a linha ter altura de verdade.")]
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

    private func mount(_ thread: ChatThreadController, _ list: [ChatMessage]) {
        let blocks = ChatBlocks.build(messages: list, live: [:], typing: [])
        thread.apply(blocks, metrics: ChatBlockLayout.measure(blocks, width: 800, known: [:]))
    }

    /// O fim de verdade, sem a folga de 40pt do `isAtBottom`.
    private func atVeryBottom(_ thread: ChatThreadController) -> Bool {
        thread.tableView.layoutSubtreeIfNeeded()
        let visible = thread.scrollView.contentView.documentVisibleRect
        return visible.maxY >= thread.tableView.bounds.height - 1
    }

    func testNewRowIsReachedEvenBeforeTheTableRelayouts() {
        let thread = ChatThreadController()
        let window = host(thread.scrollView, size: NSSize(width: 800, height: 400))
        defer { window.contentView = nil }
        mount(thread, messages(20))
        thread.scrollToBottom(animated: false)
        XCTAssertTrue(thread.isAtBottom)

        // Mensagem nova entra e a rolagem vem logo em seguida, como no
        // applyThread — sem passe de layout entre uma coisa e outra.
        mount(thread, messages(21))
        thread.scrollToBottom(animated: false)
        XCTAssertTrue(atVeryBottom(thread), "parou no fim antigo: a linha nova não contou")
        XCTAssertTrue(thread.isAtBottom, "e daí em diante nada mais desceria sozinho")
    }

    func testThreadCountsAsAtBottomWhileTheAnimatedDropIsStillRunning() {
        let thread = ChatThreadController()
        let window = host(thread.scrollView, size: NSSize(width: 800, height: 400))
        defer { window.contentView = nil }
        mount(thread, messages(20))
        thread.scrollToTop(animated: false)
        XCTAssertFalse(thread.isAtBottom)

        thread.scrollToBottom(animated: true)
        XCTAssertTrue(thread.scrollingToBottom)
        // No meio do caminho o clip ainda está longe do fim: é aqui que a
        // montagem seguinte concluía "subiu para ler".
        XCTAssertTrue(thread.isAtBottom, "descida a caminho conta como fim")

        let deadline = Date().addingTimeInterval(3)
        while thread.scrollingToBottom, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertFalse(thread.scrollingToBottom, "a bandeira cai quando a descida acaba")
        XCTAssertTrue(atVeryBottom(thread))

        // Pegar a thread na mão no meio da descida cancela a descida.
        thread.scrollToTop(animated: false)
        thread.scrollToBottom(animated: true)
        thread.stopScrolling()
        XCTAssertFalse(thread.scrollingToBottom)
        XCTAssertFalse(thread.isAtBottom, "quem parou no meio fica onde parou")
    }

    func testSendingScrollsToBottomEvenFromAboveIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ChatHistory(workbenches: root)
        for i in 0..<12 {
            var turn = ChatTurn(id: "u\(i)", prompt: "p\(i)", promptAt: t0.addingTimeInterval(Double(i) * 60))
            turn.replyText = "Resposta \(i) com texto suficiente para ocupar a linha inteira da bolha."
            turn.replyAt = turn.promptAt.addingTimeInterval(5)
            history.append(ChatRecord(node: "a", turn: turn), workbench: "w")
        }
        history.flush()

        let container = ChatContainer(frame: NSRect(x: 0, y: 0, width: 1000, height: 500))
        let window = host(container, size: NSSize(width: 1000, height: 500))
        defer { window.contentView = nil }
        container.participants = { [self.front] }
        container.historyFile = { history.current(forWorkbench: "w") }
        var sent: [String] = []
        container.send = { text, _ in sent.append(text); return nil }
        container.refresh()
        func settle(_ limit: TimeInterval = 3, until done: @escaping () -> Bool) {
            let deadline = Date().addingTimeInterval(limit)
            while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        }
        settle { !container.thread.blocks.isEmpty }

        // Você subiu um pouco para reler e manda mensagem daí.
        container.thread.scrollToTop(animated: false)
        XCTAssertFalse(container.thread.isAtBottom)
        let rebuilds = container.threadRebuilds
        _ = container.compose("e agora?", send: true)
        settle { container.threadRebuilds > rebuilds }

        XCTAssertEqual(sent, ["e agora?"])
        XCTAssertTrue(container.thread.isAtBottom, "enviar leva ao fim, como em qualquer mensageiro")
        // O eco do que você mandou é a última bolha — o pending, `e|`.
        XCTAssertEqual(container.thread.blocks.last?.messageKey.hasPrefix("e|"), true)
    }
}

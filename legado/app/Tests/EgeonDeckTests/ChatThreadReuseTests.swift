import XCTest
@testable import EgeonDeck

/// A thread não renasce à toa: um refresh sem mudança (o tique de 1 s, o
/// vigia do transcript) não monta nem mexe na tabela. Era o que travava o
/// app no modo chat.
@MainActor
final class ChatThreadReuseTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_787_678_363)

    private func agent(_ id: String, _ activity: Activity) -> ChatParticipant {
        ChatParticipant(id: id, address: "deck/\(id)", isAgent: true, role: nil, activity: activity)
    }

    private func turn(_ id: String, reply: String) -> ChatTurn {
        var turn = ChatTurn(id: id, prompt: "oi", promptAt: t0)
        turn.replyText = reply
        turn.replyAt = t0.addingTimeInterval(2)
        return turn
    }

    func testRefreshWithoutChangeDoesNotRebuild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ChatHistory(workbenches: root)
        history.append(ChatRecord(node: "a", turn: turn("u1", reply: "olá")), workbench: "w")
        history.flush()

        let container = ChatContainer(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        var activity = Activity.waiting
        container.participants = { [self.agent("a", activity)] }
        container.historyFile = { history.current(forWorkbench: "w") }
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()

        // Histórico e montagem rodam em filas de fundo e voltam pela main.
        func settle(for limit: TimeInterval = 3, until done: @escaping () -> Bool) {
            let deadline = Date().addingTimeInterval(limit)
            while !done(), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        // Dar tempo a algo que NÃO deve acontecer: uma volta curta basta.
        func settleQuiet() { settle(for: 0.2) { false } }
        container.refresh()
        settle { container.threadRebuilds > 0 }
        XCTAssertEqual(container.threadRebuilds, 1, "prompt + resposta entram uma vez")
        let builds = container.threadBuilds

        container.refresh()
        container.refresh()
        settleQuiet()
        XCTAssertEqual(container.threadBuilds, builds, "nada mudou: nem monta")
        XCTAssertEqual(container.threadRebuilds, 1, "nada mudou, nada renasce")

        activity = .working
        container.refresh()
        settle { container.threadRebuilds > 1 }
        XCTAssertEqual(container.threadBuilds, builds + 1)
        XCTAssertEqual(container.threadRebuilds, 2, "agente passou a trabalhar: só a bolha de 'trabalhando…' entra")
        container.refresh()
        settleQuiet()
        XCTAssertEqual(container.threadBuilds, builds + 1)
        XCTAssertEqual(container.threadRebuilds, 2)
    }
}

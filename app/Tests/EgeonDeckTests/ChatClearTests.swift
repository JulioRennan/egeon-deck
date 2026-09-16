import XCTest
@testable import EgeonDeck

/// Arquivar a conversa move um arquivo — e o chat guarda coisa que não está
/// nele: o eco local de um envio que o transcript ainda não confirmou. Sem
/// avisar a thread, esse eco voltava a desenhar sozinho numa conversa vazia, e
/// era a mensagem órfã que sobrava depois de limpar a bancada (ADR-059).
@MainActor
final class ChatClearTests: XCTestCase {
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }

    private func container() -> ChatContainer {
        let container = ChatContainer(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        container.participants = {
            [ChatParticipant(id: "front", address: "deck/front", isAgent: true,
                             role: "front-end", activity: .waiting)]
        }
        container.send = { _, _ in nil }
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        settle()
        return container
    }

    func testClearingTheHistoryTakesTheUnconfirmedEchoWithIt() {
        let chat = container()
        let sent = chat.compose("olha essa melhoria aqui", send: true)
        XCTAssertEqual(sent["pending"] as? Int, 1, "o envio precisa aparecer na hora")
        settle()
        XCTAssertFalse(chat.thread.blocks.isEmpty)

        chat.clearedHistory()
        settle()
        let after = chat.snapshot()
        XCTAssertEqual(after["pending"] as? Int, 0, "o eco sobreviveu à limpeza")
        XCTAssertTrue(chat.thread.blocks.isEmpty, "sobrou bolha órfã na thread limpa")
        XCTAssertTrue((after["messages"] as? [[String: Any]])?.isEmpty ?? false)
    }

    /// O que você tinha aberto era daquela conversa: a nova nasce fechada, e a
    /// janela de rolagem volta ao começo.
    func testClearingResetsTheThreadState() {
        let chat = container()
        _ = chat.compose("um", send: true)
        settle()
        chat.clearedHistory()
        settle()
        XCTAssertTrue(chat.expandedSteps.isEmpty)
        XCTAssertTrue(chat.groupLevels.isEmpty)
        XCTAssertEqual(chat.loadedMessages, 60)
    }
}

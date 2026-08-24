import XCTest
@testable import EgeonDeck

/// A cor do agente, o turno como estrutura e a junção dos transcripts.
final class ChatThreadTests: XCTestCase {
    private var files: [URL] = []

    override func tearDown() {
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        files = []
    }

    // Derivada do id com hash próprio (FNV-1a) porque hashValue tem semente por
    // processo: a cor de "orquestrador" não pode mudar a cada arranque.
    func testAgentColorIsStable() {
        XCTAssertEqual(AgentColor.of("orquestrador"), AgentColor.of("orquestrador"))
        XCTAssertEqual(AgentColor.of("claude-2"), AgentColor.of("claude-2"))
    }

    func testAgentColorsSpreadAcrossThePalette() {
        let ids = ["claude", "claude-2", "revisor", "qa", "front", "back", "orq"]
        let distinct = Set(ids.map { AgentColor.of($0).description })
        XCTAssertGreaterThan(distinct.count, 1, "todos os ids na mesma cor")
    }

    func testWorkSummaryCountsStepsAndFiles() {
        var turn = ChatTurn(id: "t", author: "a", at: Date())
        turn.blocks = [
            .tool("leu X"),
            .edit(EditBlock(file: "m/A.swift", add: 1, del: 0, lines: [])),
            .prose("fim"),
        ]
        XCTAssertEqual(turn.workSummary, "2 passos · 1 arquivo")
    }

    // A cadeia achatada sai em ordem de tempo, e conta a si e aos de dentro.
    func testChainFlattensRepliesByTime() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        var volta = ChatTurn(id: "3", author: "a", at: base.addingTimeInterval(20))
        volta.from = "b"
        var ida = ChatTurn(id: "2", author: "b", at: base.addingTimeInterval(10))
        ida.from = "a"
        ida.replies = [volta]
        var raiz = ChatTurn(id: "1", author: "a", at: base)
        raiz.replies = [ida]

        XCTAssertEqual(raiz.chain.map(\.id), ["2", "3"])
        XCTAssertEqual(raiz.conversationCount, 3)
    }

    // Dois transcripts, uma bancada: o turno de B com envelope de A entra
    // ANINHADO no turno de A que estava aberto — ligação por remetente e tempo.
    func testThreadNestsTriggeredTurnInsideTheTrigger() {
        let thread = ChatThread()
        let a = participant(id: "claude", entries: [
            user("orquestre", at: "2026-08-23T10:00:00.000Z"),
            assistant("mandei para o vizinho", at: "2026-08-23T10:00:05.000Z"),
        ])
        let b = participant(id: "claude-2", entries: [
            user("[egeon] mensagem de deck/claude\n\nfaça a parte 2\n\n"
                 + "Quem escreveu foi outro agente, não o usuário.",
                 at: "2026-08-23T10:00:10.000Z"),
            assistant("parte 2 feita", at: "2026-08-23T10:00:15.000Z"),
        ])

        let turns = thread.turns(of: [a, b])
        XCTAssertEqual(turns.count, 1, "o turno provocado não é bloco de primeiro nível")
        XCTAssertEqual(turns[0].author, "claude")
        XCTAssertEqual(turns[0].replies.count, 1)
        XCTAssertEqual(turns[0].replies[0].author, "claude-2")
        XCTAssertEqual(turns[0].replies[0].from, "claude")
        XCTAssertEqual(turns[0].replies[0].prompt, "faça a parte 2")
    }

    // Provocador fora da cauda lida: o turno sobe para o topo em vez de sumir —
    // meia conversa é melhor que engolir metade dela.
    func testTriggeredTurnWithoutTriggerBecomesRoot() {
        let thread = ChatThread()
        let b = participant(id: "claude-2", entries: [
            user("[egeon] mensagem de deck/fantasma\n\ncorpo\n\n"
                 + "Quem escreveu foi outro agente, não o usuário.",
                 at: "2026-08-23T10:00:10.000Z"),
        ])
        let turns = thread.turns(of: [b])
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].from, "fantasma")
    }

    // MARK: apoio

    private func participant(id: String, entries: [[String: Any]]) -> ChatThread.Participant {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("egeon-thread-\(UUID().uuidString).jsonl")
        let body = entries
            .map { try! JSONSerialization.data(withJSONObject: $0) }
            .map { String(data: $0, encoding: .utf8)! }
            .joined(separator: "\n") + "\n"
        try! body.write(to: url, atomically: true, encoding: .utf8)
        files.append(url)
        return ChatThread.Participant(id: id, agent: "claude", transcript: url)
    }

    private func user(_ text: String, at: String) -> [String: Any] {
        ["type": "user", "uuid": UUID().uuidString, "timestamp": at,
         "message": ["content": text]]
    }

    private func assistant(_ text: String, at: String) -> [String: Any] {
        ["type": "assistant", "uuid": UUID().uuidString, "timestamp": at,
         "message": ["content": [["type": "text", "text": text]]]]
    }
}

import XCTest
@testable import EgeonDeck

/// O histórico do chat em disco: a corrente na raiz da bancada, as arquivadas
/// em `chat-archive/`, dedupe por turno, e "limpar" que arquiva sem apagar.
final class ChatHistoryTests: XCTestCase {
    private var root: URL!
    private var history: ChatHistory!
    private let t0 = Date(timeIntervalSince1970: 1_787_678_363.25)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("workbenches-\(UUID())")
        history = ChatHistory(workbenches: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func record(_ node: String, id: String, prompt: String = "oi",
                        reply: String = "olá", replyAfter: TimeInterval = 3.5) -> ChatRecord {
        var turn = ChatTurn(id: id, prompt: prompt, promptAt: t0, from: nil)
        turn.steps = [ChatStep(glyph: "$", text: "ls"), ChatStep(glyph: "⇄", text: "egeon send deck/b", sendTo: "deck/b")]
        turn.replyText = reply
        turn.replyAt = t0.addingTimeInterval(replyAfter)
        return ChatRecord(node: node, conversation: "3C0C394C", cli: "Claude Code",
                          model: "claude-opus-5", turn: turn)
    }

    func testCurrentLivesAtWorkbenchRoot() throws {
        XCTAssertEqual(history.current(forWorkbench: "93cbec07").path,
                       root.appendingPathComponent("93cbec07/chat.jsonl").path)
        history.append(record("a", id: "u1"), workbench: "93cbec07")
        history.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: history.current(forWorkbench: "93cbec07").path))
        XCTAssertEqual(history.archived(forWorkbench: "93cbec07"), [])
    }

    // O que sai é o que entrou: passos, envio, datas com fração de segundo.
    func testRoundTrip() throws {
        let r = record("a", id: "u1", prompt: "revisa", reply: "feito")
        history.append(r, workbench: "w")
        history.flush()
        let back = history.load(workbench: "w")
        XCTAssertEqual(back, [r])
        XCTAssertEqual(back[0].turn.steps[1].sendTo, "deck/b")
        XCTAssertEqual(back[0].turn.replyAt!.timeIntervalSince1970, t0.timeIntervalSince1970 + 3.5,
                       accuracy: 0.001)
    }

    // Dois Stop do mesmo turno, ou releitura depois do arranque: uma linha só.
    func testSameTurnIsNotWrittenTwice() throws {
        history.append(record("a", id: "u1"), workbench: "w")
        history.append(record("a", id: "u1", reply: "outra"), workbench: "w")
        history.append(record("b", id: "u1"), workbench: "w")   // outro nó, mesmo uuid: vale
        history.flush()
        XCTAssertEqual(history.load(workbench: "w").map(\.node), ["a", "b"])

        // Um processo novo não sabe do anterior: aprende do arquivo.
        let again = ChatHistory(workbenches: root)
        again.append(record("a", id: "u1"), workbench: "w")
        again.append(record("a", id: "u2"), workbench: "w")
        again.flush()
        XCTAssertEqual(again.load(workbench: "w").map(\.turn.id), ["u1", "u1", "u2"])
    }

    // O nome é o período da conversa: primeiro prompt → última resposta.
    func testArchiveIsNamedByConversationPeriod() throws {
        let late = record("b", id: "u2", replyAfter: 3_600 * 5 + 7)
        history.append(record("a", id: "u1"), workbench: "w")
        history.append(late, workbench: "w")
        history.flush()
        let archived = history.archive(workbench: "w", at: t0.addingTimeInterval(86_400))!
        let period = ChatHistory.period(of: archived)!
        XCTAssertEqual(period.start.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(period.end.timeIntervalSince1970, late.turn.replyAt!.timeIntervalSince1970, accuracy: 1)
        XCTAssertNotNil(archived.lastPathComponent.range(of: #"^chat-\d{8}-\d{6}_\d{8}-\d{6}\.jsonl$"#,
                                                          options: .regularExpression))
    }

    func testArchiveMovesCurrentAndStartsFresh() throws {
        history.append(record("a", id: "u1"), workbench: "w")
        history.flush()
        let archived = history.archive(workbench: "w", at: t0)
        XCTAssertEqual(archived?.deletingLastPathComponent().path,
                       root.appendingPathComponent("w/chat-archive").path)
        XCTAssertEqual(history.archived(forWorkbench: "w"), [archived!])
        XCTAssertEqual(history.load(workbench: "w"), [])
        XCTAssertEqual(history.load(workbench: "w", file: archived).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.current(forWorkbench: "w").path))

        // O turno já gravado na arquivada pode entrar na nova: é outra conversa.
        history.append(record("a", id: "u1"), workbench: "w")
        history.flush()
        XCTAssertEqual(history.load(workbench: "w").count, 1)
    }

    // Limpar sem conversa não deixa arquivo vazio para trás.
    func testArchiveOnEmptyIsNoop() {
        XCTAssertNil(history.archive(workbench: "w", at: t0))
        history.append(record("a", id: "u1"), workbench: "w")
        history.flush()
        XCTAssertNotNil(history.archive(workbench: "w", at: t0))
        XCTAssertNil(history.archive(workbench: "w", at: t0.addingTimeInterval(60)))
        XCTAssertEqual(history.archived(forWorkbench: "w").count, 1)
    }

    // Mesmo período duas vezes (os registros têm as mesmas datas): sufixo.
    func testSamePeriodTwiceGetsDistinctNames() throws {
        history.append(record("a", id: "u1"), workbench: "w")
        history.flush()
        let first = history.archive(workbench: "w", at: t0)
        history.append(record("a", id: "u2"), workbench: "w")
        history.flush()
        let second = history.archive(workbench: "w", at: t0)
        XCTAssertNotEqual(first, second)
        // A mais recente é a última da lista — o sufixo tem que ordenar depois.
        XCTAssertEqual(history.archived(forWorkbench: "w"), [first!, second!])
        XCTAssertEqual(ChatHistory.period(of: second!)?.start, ChatHistory.period(of: first!)?.start)
    }
}

/// O último turno inteiro lido do transcript, para o histórico.
final class TranscriptLastTurnTests: XCTestCase {
    private func user(_ s: String, id: String, at: String) -> String {
        #"{"type":"user","uuid":"\#(id)","timestamp":"\#(at)","message":{"content":"\#(s)"}}"#
    }
    private func assistant(_ s: String, at: String) -> String {
        #"{"type":"assistant","timestamp":"\#(at)","message":{"content":[{"type":"text","text":"\#(s)"}]}}"#
    }
    private func write(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testLastTurnCarriesPromptAndReply() throws {
        let url = try write([user("um", id: "u1", at: "2026-08-25T17:00:00Z"),
                             assistant("r1 [[ED:ok]]", at: "2026-08-25T17:00:05Z"),
                             user("dois", id: "u2", at: "2026-08-25T17:01:00Z"),
                             assistant("r2 [[ED:ask]]", at: "2026-08-25T17:01:05Z")])
        defer { try? FileManager.default.removeItem(at: url) }
        let turn = ClaudeTranscript.lastTurn(at: url)
        XCTAssertEqual(turn?.id, "u2")
        XCTAssertEqual(turn?.prompt, "dois")
        XCTAssertEqual(turn?.replyText, "r2")
    }

    // A cauda cortou a linha do prompt atual: o parse da cauda devolve o turno
    // ANTERIOR inteiro, e só o instante do prompt desmascara isso.
    func testTailThatLosesThePromptFallsBackToWholeFile() throws {
        let filler = String(repeating: "x", count: 300)
        let url = try write([user("um", id: "u1", at: "2026-08-25T17:00:00Z"),
                             assistant("r1", at: "2026-08-25T17:00:05Z"),
                             user("dois \(filler)", id: "u2", at: "2026-08-25T17:01:00Z"),
                             assistant("r2", at: "2026-08-25T17:01:05Z")])
        defer { try? FileManager.default.removeItem(at: url) }
        let started = ISO8601DateFormatter().date(from: "2026-08-25T17:00:50Z")
        XCTAssertEqual(ClaudeTranscript.lastTurn(at: url, notBefore: started, tailBytes: 200)?.id, "u2")
        XCTAssertEqual(ClaudeTranscript.lastTurn(at: url, tailBytes: 200)?.id, "u2")
    }

    func testEmptyOrMissing() throws {
        let url = try write([])
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ClaudeTranscript.lastTurn(at: url))
        XCTAssertNil(ClaudeTranscript.lastTurn(at: url.appendingPathExtension("nope")))
    }
}

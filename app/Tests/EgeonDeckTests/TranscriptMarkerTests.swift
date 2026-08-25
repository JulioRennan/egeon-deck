import XCTest
@testable import EgeonDeck

/// O fim de turno lido do transcript: qual marcador fechou a última resposta.
final class TranscriptMarkerTests: XCTestCase {
    private let marker = MarkerConfig()

    private func assistant(_ blocks: String) -> String {
        #"{"type":"assistant","message":{"content":[\#(blocks)]}}"#
    }
    private func text(_ s: String) -> String { #"{"type":"text","text":"\#(s)"}"# }
    private let tool = #"{"type":"tool_use","name":"Bash","input":{}}"#
    private let user = #"{"type":"user","message":{"content":"oi"}}"#

    func testOkAtEndOfLastReply() {
        let jsonl = [user, assistant(text("Feito.\\n\\n[[ED:ok]]"))].joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.lastMarker(in: jsonl, marker: marker)?.marker, .ok)
    }

    func testAskWins() {
        let jsonl = [user, assistant(text("Qual?\\n\\n[[ED:ask]]"))].joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.lastMarker(in: jsonl, marker: marker)?.marker, .ask)
    }

    // O turno anterior terminou em pergunta; o atual em ok. Só o último vale —
    // é exatamente o caso em que a tela ainda mostrava o [[ED:ask]] velho.
    func testOnlyTheLastReplyCounts() {
        let jsonl = [user, assistant(text("Posso? [[ED:ask]]")),
                     user, assistant(text("Pronto. [[ED:ok]]"))].joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.lastMarker(in: jsonl, marker: marker)?.marker, .ok)
    }

    // Texto que MENCIONA o outro marcador não muda o veredito: manda o mais baixo.
    func testMentionAboveDoesNotOverrideFinalMarker() {
        let jsonl = [user, assistant(text("Se perguntar, uso [[ED:ask]]. Aqui não.\\n[[ED:ok]]"))]
            .joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.lastMarker(in: jsonl, marker: marker)?.marker, .ok)
    }

    // Linha só com tool_use depois do texto não é fim de turno: sobe até achar texto.
    func testSkipsTrailingToolUseOnlyLines() {
        let jsonl = [user, assistant(text("Fim. [[ED:ok]]")), assistant(tool)].joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.lastMarker(in: jsonl, marker: marker)?.marker, .ok)
    }

    // A data da linha vem junto: é ela que diz se o marcador é deste turno ou
    // do passado, quando o gancho Stop chega antes da escrita.
    func testCarriesTheLineTimestamp() {
        let line = #"{"type":"assistant","timestamp":"2026-08-25T17:19:23.796Z","message":{"content":[\#(text("x [[ED:ask]]"))]}}"#
        let read = ClaudeTranscript.lastMarker(in: [user, line].joined(separator: "\n"), marker: marker)
        XCTAssertEqual(read?.marker, .ask)
        XCTAssertEqual(read?.at?.timeIntervalSince1970 ?? 0, 1787678363.796, accuracy: 0.01)
    }

    func testNoMarkerIsNil() {
        let jsonl = [user, assistant(text("esqueci o protocolo"))].joined(separator: "\n")
        XCTAssertNil(ClaudeTranscript.lastMarker(in: jsonl, marker: marker)?.marker)
        XCTAssertNil(ClaudeTranscript.lastMarker(in: "", marker: marker))
    }

    func testReadsOnlyTheTailOfTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t-\(UUID()).jsonl")
        let filler = String(repeating: "x", count: 4000)
        let jsonl = [user, assistant(text("velho [[ED:ask]] \(filler)")),
                     user, assistant(text("novo [[ED:ok]]"))].joined(separator: "\n")
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        // Cauda de 200 bytes só alcança a última linha — e é ela que decide.
        XCTAssertEqual(ClaudeTranscript.lastMarker(at: url, marker: marker, tailBytes: 200)?.marker, .ok)
    }
}

/// O nome literal do modelo, lido do transcript.
final class TranscriptModelTests: XCTestCase {
    private func assistant(model: String) -> String {
        #"{"type":"assistant","message":{"model":"\#(model)","content":[{"type":"text","text":"x"}]}}"#
    }

    func testLastAssistantModelWins() {
        let jsonl = [assistant(model: "claude-sonnet-5"), assistant(model: "claude-fable-5")]
            .joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.lastModel(in: jsonl), "claude-fable-5")
    }

    // A TUI grava respostas fabricadas com model "<synthetic>": não é modelo.
    func testSyntheticIsSkipped() {
        let jsonl = [assistant(model: "claude-fable-5"), assistant(model: "<synthetic>")]
            .joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.lastModel(in: jsonl), "claude-fable-5")
        XCTAssertNil(ClaudeTranscript.lastModel(in: assistant(model: "<synthetic>")))
        XCTAssertNil(ClaudeTranscript.lastModel(in: ""))
    }
}

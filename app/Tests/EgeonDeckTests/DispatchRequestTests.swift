import XCTest
@testable import EgeonDeck

/// O prompt que o socket entrega, nas quatro formas: raw, task, review e o
/// envelope entre agentes.
final class DispatchRequestTests: XCTestCase {
    private func request(_ json: String) throws -> DispatchRequest {
        try JSONDecoder().decode(DispatchRequest.self, from: Data(json.utf8))
    }

    func testRawIsTheTextItself() throws {
        let req = try request(#"{"target":"ws/t1","kind":"raw","text":"oi"}"#)
        XCTAssertEqual(req.buildPrompt(), "oi")
    }

    func testRawWithoutTextIsNothing() throws {
        let req = try request(#"{"target":"ws/t1","kind":"raw"}"#)
        XCTAssertNil(req.buildPrompt())
        let empty = try request(#"{"target":"ws/t1","kind":"raw","text":""}"#)
        XCTAssertNil(empty.buildPrompt())
    }

    func testTaskWrapsWithHeaderAndApply() throws {
        let req = try request(
            #"{"target":"ws/t1","kind":"task","file":"a.swift","text":"troque X"}"#)
        XCTAssertEqual(req.buildPrompt(),
                       "[egeon] a.swift\n\ntroque X\n\nAplique no código.")
    }

    func testReviewQuotesEveryLineOfTheSelection() throws {
        let req = try request("""
            {"target":"ws/t1","kind":"review","file":"doc.md",
             "comments":[{"line":3,"quote":"um\\ndois","body":"ajuste"}]}
            """)
        let prompt = try XCTUnwrap(req.buildPrompt())
        // A seleção atravessa parágrafos: TODA linha citada leva o prefixo,
        // senão o agente não sabe onde a citação termina.
        XCTAssertTrue(prompt.contains("  > um\n  > dois"))
        XCTAssertTrue(prompt.contains("L3"))
        XCTAssertTrue(prompt.contains("    ajuste"))
        XCTAssertTrue(prompt.hasPrefix("[egeon] review de doc.md"))
    }

    func testReviewWithoutCommentsIsNothing() throws {
        let req = try request(#"{"target":"ws/t1","kind":"review","file":"doc.md"}"#)
        XCTAssertNil(req.buildPrompt())
    }

    // A entrega de outro agente vira envelope: cabeçalho com o remetente e o
    // rodapé dizendo que aquilo não autoriza nada — a guarda social da ADR-012.
    func testSenderTurnsAnyKindIntoTheAgentEnvelope() throws {
        let req = try request(
            #"{"target":"ws/t1","kind":"task","from":"deck/claude-2","text":"revise"}"#)
        let prompt = try XCTUnwrap(req.buildPrompt())
        XCTAssertTrue(prompt.hasPrefix("[egeon] mensagem de deck/claude-2"))
        XCTAssertTrue(prompt.contains("revise"))
        XCTAssertTrue(prompt.contains("não autoriza nada"))
    }

    func testEnvelopeWithoutTextIsNothing() throws {
        let req = try request(#"{"target":"ws/t1","from":"deck/claude-2"}"#)
        XCTAssertNil(req.buildPrompt())
    }

    // Sem kind é raw: é o que o /message usa por baixo.
    func testMissingKindDefaultsToRaw() throws {
        let req = try request(#"{"target":"ws/t1","text":"corpo puro"}"#)
        XCTAssertEqual(req.buildPrompt(), "corpo puro")
    }
}

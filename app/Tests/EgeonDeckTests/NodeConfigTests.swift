import XCTest
@testable import EgeonDeck

final class NodeConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> NodeConfig {
        try JSONDecoder().decode(NodeConfig.self, from: Data(json.utf8))
    }

    // Arquivo gravado antes da ADR-030 traz `sessionId`/`sessionStarted`. A carga
    // absorve para os nomes novos e os antigos nunca voltam ao disco.
    func testLegacySessionIdIsAbsorbedOnLoad() throws {
        let node = try decode(
            #"{"type":"agent","id":"a","sessionId":"S123","sessionStarted":true}"#
        ).migratingLegacyNames

        XCTAssertEqual(node.conversationId, "S123")
        XCTAssertEqual(node.conversationStarted, true)
        XCTAssertNil(node.sessionId)
        XCTAssertNil(node.sessionStarted)
    }

    func testLegacyNamesNeverGoBackToDisk() throws {
        let node = try decode(
            #"{"type":"agent","id":"a","sessionId":"S123","sessionStarted":true}"#
        ).migratingLegacyNames

        let encoded = String(data: try JSONEncoder().encode(node), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("sessionId"))
        XCTAssertFalse(encoded.contains("sessionStarted"))
        XCTAssertTrue(encoded.contains("conversationId"))
    }

    // Nome novo presente ganha do antigo: a migração não pode regredir uma
    // conversa já migrada.
    func testMigrationDoesNotOverwriteNewName() throws {
        let node = try decode(
            #"{"type":"agent","id":"a","conversationId":"NOVA","sessionId":"VELHA"}"#
        ).migratingLegacyNames

        XCTAssertEqual(node.conversationId, "NOVA")
    }

    // Copiar um nó é copiar a montagem, nunca a conversa (template, duplicação em
    // worktree). Com o conversationId junto, o clone e o original disputam a mesma
    // conversa e o segundo a subir morre sem erro visível.
    func testWithoutConversationClearsConversationAndKeepsAssembly() throws {
        let node = try decode(#"""
            {"type":"agent","id":"revisor","agent":"claude","cwd":"src",
             "prompt":"revise","conversationId":"C1","conversationStarted":true,
             "transcript":"/tmp/t.jsonl"}
            """#).withoutConversation

        XCTAssertNil(node.conversationId)
        XCTAssertNil(node.conversationStarted)
        // O transcript é da conversa: mantido, o chat do clone mostraria o thread
        // do original.
        XCTAssertNil(node.transcript)

        XCTAssertEqual(node.id, "revisor")
        XCTAssertEqual(node.agent, "claude")
        XCTAssertEqual(node.cwd, "src")
        XCTAssertEqual(node.prompt, "revise")
    }
}

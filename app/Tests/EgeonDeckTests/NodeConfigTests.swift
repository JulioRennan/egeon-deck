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
        // O transcript é da conversa: mantido, o clone apontaria para a conversa
        // do original.
        XCTAssertNil(node.transcript)

        XCTAssertEqual(node.id, "revisor")
        XCTAssertEqual(node.agent, "claude")
        XCTAssertEqual(node.cwd, "src")
        XCTAssertEqual(node.prompt, "revise")
    }

    // Renomear ou marcar maestro pelo formulário remonta o nó pelo componente,
    // que não tem conversa: sem devolvê-la, o agente subia numa conversa nova.
    func testFormEditKeepsConversationWithSameCLIAndFolder() throws {
        let previous = try decode(#"""
            {"type":"agent","id":"dev","agent":"claude","cwd":"src","ultracode":true,
             "conversationId":"C1","conversationStarted":true,"transcript":"/tmp/t.jsonl"}
            """#)
        var edited = NodeConfig(type: .agent, id: "dev-novo")
        edited.agent = "claude"
        edited.cwd = "src"
        edited.maestro = true

        let kept = edited.keepingState(of: previous)
        XCTAssertEqual(kept.id, "dev-novo")
        XCTAssertEqual(kept.maestro, true)
        XCTAssertEqual(kept.conversationId, "C1")
        XCTAssertEqual(kept.conversationStarted, true)
        XCTAssertEqual(kept.transcript, "/tmp/t.jsonl")
        XCTAssertEqual(kept.ultracode, true)
    }

    // A conversa é do CLI e da pasta: em outra pasta ou outro CLI ela não abre.
    func testFormEditDropsConversationWhenFolderOrCLIChanges() throws {
        let previous = try decode(#"""
            {"type":"agent","id":"dev","agent":"claude","cwd":"src","conversationId":"C1",
             "conversationStarted":true}
            """#)
        var moved = NodeConfig(type: .agent, id: "dev")
        moved.agent = "claude"
        moved.cwd = "outra"
        XCTAssertNil(moved.keepingState(of: previous).conversationId)

        var other = NodeConfig(type: .agent, id: "dev")
        other.agent = "codex"
        other.cwd = "src"
        XCTAssertNil(other.keepingState(of: previous).conversationId)
    }

    func testFormEditKeepsWebAddress() throws {
        let previous = try decode(#"{"type":"web","id":"docs","url":"https://x.dev","profile":"p"}"#)
        let kept = NodeConfig(type: .web, id: "docs").keepingState(of: previous)
        XCTAssertEqual(kept.url, "https://x.dev")
        XCTAssertEqual(kept.profile, "p")
    }
}

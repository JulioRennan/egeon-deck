import XCTest
@testable import EgeonDeck

/// O contrato genérico de agente: as flags são DADO com placeholders, e é a
/// substituição que monta a linha de comando real.
final class AgentProfileTests: XCTestCase {
    func testClaudeCodeFactoryProfileTemplating() {
        let profile = AgentProfile.claudeCode

        XCTAssertEqual(profile.conversationArguments(profile.resume, id: "ABC"),
                       ["--resume", "ABC"])
        XCTAssertEqual(profile.conversationArguments(profile.newSession, id: "ABC"),
                       ["--session-id", "ABC"])
        XCTAssertEqual(profile.reportArguments(hookFile: "/tmp/h.json"),
                       ["--settings", "/tmp/h.json"])
        XCTAssertEqual(profile.systemPromptArguments(for: "seja revisor"),
                       ["--append-system-prompt", "seja revisor"])
        // Sabe retomar E criar com id nosso — é o que faz a conversa sobreviver
        // ao rebuild.
        XCTAssertTrue(profile.keepsConversation)
    }

    // Perfil sem a forma declarada devolve nil — aí o app fica só com o que o
    // CLI dá (papel vira mensagem, conversa não é retomável).
    func testProfileWithoutDeclarationsReturnsNil() throws {
        let bare = try JSONDecoder().decode(AgentProfile.self, from: Data(
            #"{"displayName":"X","command":["x"]}"#.utf8))
        XCTAssertNil(bare.conversationArguments(bare.resume, id: "A"))
        XCTAssertNil(bare.reportArguments(hookFile: "/f"))
        XCTAssertNil(bare.systemPromptArguments(for: "p"))
        XCTAssertFalse(bare.keepsConversation)
    }
}

/// O thread como dados — o que a rota /chat devolve para se conferir de fora.
final class ChatPayloadTests: XCTestCase {
    func testBlockPayloads() {
        XCTAssertEqual(ChatBlock.prose("oi").payload["kind"] as? String, "prose")
        XCTAssertEqual(ChatBlock.code("$ ls").payload["text"] as? String, "$ ls")

        let edit = ChatBlock.edit(EditBlock(file: "m/A.swift", add: 1, del: 2,
            lines: [DiffLine(mark: "-", text: "velho"), DiffLine(mark: "+", text: "novo")]))
        let payload = edit.payload
        XCTAssertEqual(payload["kind"] as? String, "edit")
        XCTAssertEqual(payload["add"] as? Int, 1)
        XCTAssertEqual(payload["del"] as? Int, 2)
        XCTAssertEqual(payload["diff"] as? [String], ["-velho", "+novo"])
    }

    func testTurnPayloadIsRecursiveAndOmitsEmpty() {
        var reply = ChatTurn(id: "2", author: "b", at: Date())
        reply.from = "a"
        reply.blocks = [.prose("feito")]
        var turn = ChatTurn(id: "1", author: "a", at: Date())
        turn.prompt = "faz"
        turn.replies = [reply]

        let payload = turn.payload
        XCTAssertEqual(payload["prompt"] as? String, "faz")
        XCTAssertNil(payload["work"], "turno sem caminho não leva a chave")
        XCTAssertNil(payload["inFlight"])
        let replies = payload["replies"] as? [[String: Any]]
        XCTAssertEqual(replies?.count, 1)
        XCTAssertEqual(replies?[0]["from"] as? String, "a")
    }
}

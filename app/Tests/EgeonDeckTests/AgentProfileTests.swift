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

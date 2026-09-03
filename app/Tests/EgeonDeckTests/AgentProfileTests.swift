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
        XCTAssertEqual(profile.skillArguments(directory: "/tmp/claude"),
                       ["--add-dir", "/tmp/claude"])
        // Sabe retomar E criar com id nosso — é o que faz a conversa sobreviver
        // ao rebuild.
        XCTAssertTrue(profile.keepsConversation)
        // Modelo: flag com placeholder, lista é dado.
        XCTAssertTrue(profile.offersModels)
        XCTAssertEqual(profile.modelArguments("opus"), ["--model", "opus"])
        XCTAssertEqual(profile.models, ["fable", "opus", "sonnet", "haiku", "opusplan"])
    }

    // "Padrão" é não passar flag nenhuma — nil e vazio dão o mesmo.
    func testDefaultModelMeansNoFlag() {
        let profile = AgentProfile.claudeCode
        XCTAssertNil(profile.modelArguments(nil))
        XCTAssertNil(profile.modelArguments(""))
    }

    // Perfil sem a forma declarada devolve nil — aí o app fica só com o que o
    // CLI dá (papel vira mensagem, conversa não é retomável).
    func testProfileWithoutDeclarationsReturnsNil() throws {
        let bare = try JSONDecoder().decode(AgentProfile.self, from: Data(
            #"{"displayName":"X","command":["x"]}"#.utf8))
        XCTAssertNil(bare.conversationArguments(bare.resume, id: "A"))
        XCTAssertNil(bare.reportArguments(hookFile: "/f"))
        XCTAssertNil(bare.skillArguments(directory: "/d"))
        XCTAssertNil(bare.systemPromptArguments(for: "p"))
        XCTAssertNil(bare.modelArguments("opus"))
        XCTAssertFalse(bare.offersModels)
        XCTAssertFalse(bare.keepsConversation)
    }
}

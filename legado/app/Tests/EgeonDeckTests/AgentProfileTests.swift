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
        XCTAssertNil(bare.systemPromptArguments(for: "p"))
        XCTAssertNil(bare.modelArguments("opus"))
        XCTAssertFalse(bare.offersModels)
        XCTAssertNil(bare.effortArguments("high"))
        XCTAssertFalse(bare.offersEfforts)
        XCTAssertFalse(bare.keepsConversation)
    }

    func testClaudeCodeEffortTemplating() {
        let profile = AgentProfile.claudeCode
        XCTAssertTrue(profile.offersEfforts)
        XCTAssertEqual(profile.effortArguments("xhigh"), ["--effort", "xhigh"])
        XCTAssertEqual(profile.efforts, ["low", "medium", "high", "xhigh", "max"])
        XCTAssertNil(profile.effortArguments(nil), "padrão é não passar flag")
        XCTAssertNil(profile.effortArguments(""))
    }

    /// O seletor do cabeçalho troca UM dos dois; o outro fica como estava.
    func testEffortChoiceAppliesToNodeOnly() {
        var node = NodeConfig(type: .agent, id: "rev")
        node.model = "opus"
        let withEffort = ModelChoice.effort("max").applied(to: node)
        XCTAssertEqual(withEffort.effort, "max")
        XCTAssertEqual(withEffort.model, "opus", "trocar esforço não mexe no modelo")
        let back = ModelChoice.effort(nil).applied(to: withEffort)
        XCTAssertNil(back.effort)
        XCTAssertEqual(ModelChoice.model("sonnet").applied(to: withEffort).effort, "max")
    }
}

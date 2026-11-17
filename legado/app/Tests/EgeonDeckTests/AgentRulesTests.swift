import XCTest
@testable import EgeonDeck

/// As regras que vão no fim do system prompt: as da bancada mais as do
/// terminal, com a moldura que o app põe e o texto do usuário intocado
/// (ADR-056).
final class AgentRulesTests: XCTestCase {
    func testNothingWhenThereAreNoRules() {
        XCTAssertNil(AgentRules.block(workbench: nil, node: nil))
        XCTAssertNil(AgentRules.block(workbench: "", node: "   \n  "))
    }

    /// Com um bloco só, dizer de onde ele veio não informa nada — o agente não
    /// escolhe entre os dois, segue os dois.
    func testASingleBlockCarriesNoOrigin() throws {
        let onlyNode = try XCTUnwrap(AgentRules.block(workbench: nil, node: "peça antes de commitar"))
        XCTAssertEqual(onlyNode, "\(AgentRules.header)\n\npeça antes de commitar")
        XCTAssertFalse(onlyNode.contains("Da bancada"))

        let onlyWorkbench = try XCTUnwrap(AgentRules.block(workbench: "escreva em português", node: ""))
        XCTAssertEqual(onlyWorkbench, "\(AgentRules.header)\n\nescreva em português")
    }

    func testBothBlocksAreNamedAndOrdered() throws {
        let block = try XCTUnwrap(AgentRules.block(workbench: "escreva em português",
                                                   node: "peça antes de commitar"))
        let bench = try XCTUnwrap(block.range(of: "Da bancada:"))
        let node = try XCTUnwrap(block.range(of: "Deste terminal:"))
        XCTAssertTrue(bench.lowerBound < node.lowerBound, "a da bancada vem primeiro")
        XCTAssertTrue(block.contains("escreva em português"))
        XCTAssertTrue(block.contains("peça antes de commitar"))
    }

    /// O texto é do usuário: o app enquadra, não reescreve — nem numera, nem
    /// vira bullet, nem corta.
    func testUserTextIsNotRewritten() throws {
        let written = "1. rode swift test\n2. não empurre nada sem pedir"
        let block = try XCTUnwrap(AgentRules.block(workbench: nil, node: "  \(written)  "))
        XCTAssertTrue(block.hasSuffix(written), "só o espaço em volta sai")
    }

    /// A precedência é dita, e não é zelo: diretriz geral em conflito com
    /// restrição específica costuma ser resolvida a favor da ação.
    func testHeaderStatesPrecedenceOverTheRole() {
        XCTAssertTrue(AgentRules.header.contains("valem sobre o papel"))
    }
}

/// A ordem do system prompt — marcador, catálogo, papel, regras — é o que faz a
/// regra limitar o papel em vez de ser limitada por ele.
final class SystemPromptOrderTests: XCTestCase {
    func testRulesComeAfterTheRole() throws {
        let profile = AgentProfile.claudeCode
        let text = try XCTUnwrap(profile.systemPromptText(
            role: "você é o revisor", catalog: "use `egeon`", rules: "peça antes de commitar"))

        let marker = try XCTUnwrap(text.range(of: "[[ED:ok]]"))
        let catalog = try XCTUnwrap(text.range(of: "use `egeon`"))
        let role = try XCTUnwrap(text.range(of: "você é o revisor"))
        let rules = try XCTUnwrap(text.range(of: "peça antes de commitar"))
        XCTAssertTrue(marker.lowerBound < catalog.lowerBound)
        XCTAssertTrue(catalog.lowerBound < role.lowerBound)
        XCTAssertTrue(role.lowerBound < rules.lowerBound, "regra depois do papel")
    }

    func testRulesAloneStillReachTheAgent() throws {
        let profile = AgentProfile.claudeCode
        let text = try XCTUnwrap(profile.systemPromptText(role: nil, catalog: nil,
                                                          rules: "peça antes de commitar"))
        XCTAssertTrue(text.contains("peça antes de commitar"))
    }
}

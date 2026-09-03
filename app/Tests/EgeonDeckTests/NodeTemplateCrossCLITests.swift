import XCTest
@testable import EgeonDeck

/// O componente é o PAPEL, e atravessa CLIs: nome, tipo, pasta, prompt e regras
/// valem em qualquer um. Comando, configuração e modelo não atravessam nada e
/// moram no mapa do CLI; regra pode ser substituída por CLI (ADR-057).
final class NodeTemplateCrossCLITests: XCTestCase {
    private func template() -> NodeTemplate {
        NodeTemplate(
            name: "revisor", kind: .agent, agent: "claude",
            cwd: "app", prompt: "você revisa o diff", rules: "escreva em português",
            byAgent: ["claude": .init(cmd: nil, config: "~/.claude-agro", model: "opus", rules: nil),
                      "opencode": .init(cmd: nil, config: nil, model: nil,
                                        rules: "aqui, comente em inglês")])
    }

    func testTheRoleCrossesEveryCLI() {
        let component = template()
        for cli in ["claude", "opencode", "codex", nil] {
            XCTAssertEqual(component.name, "revisor")
            XCTAssertEqual(component.prompt, "você revisa o diff")
            XCTAssertEqual(component.cwd, "app", "a pasta é da bancada, não do CLI (\(cli ?? "—"))")
        }
    }

    /// `opus` não existe no OpenCode e `~/.claude-agro` não diz nada ao Codex:
    /// nada disso pode vazar de um CLI para outro.
    func testCLISpecificValuesDoNotLeak() {
        let component = template()
        XCTAssertEqual(component.resolved(for: "claude").model, "opus")
        XCTAssertEqual(component.resolved(for: "claude").config, "~/.claude-agro")
        XCTAssertNil(component.resolved(for: "opencode").model)
        XCTAssertNil(component.resolved(for: "opencode").config)
        XCTAssertNil(component.resolved(for: "codex").model, "CLI sem mapa não herda nada")
    }

    /// Regra por CLI SUBSTITUI a geral — override, não soma.
    func testRulesOverrideRatherThanAdd() {
        let component = template()
        XCTAssertEqual(component.resolved(for: "claude").rules, "escreva em português")
        XCTAssertEqual(component.resolved(for: "opencode").rules, "aqui, comente em inglês")
        XCTAssertEqual(component.resolved(for: "codex").rules, "escreva em português")
    }

    func testInstantiateUsesTheChosenCLI() {
        var component = template()
        component.agent = "opencode"
        let node = NodeTemplateStore.instantiate(component, id: "rev")
        XCTAssertEqual(node.agent, "opencode")
        XCTAssertNil(node.model, "o modelo do Claude não sobe num OpenCode")
        XCTAssertNil(node.config)
        XCTAssertEqual(node.rules, "aqui, comente em inglês")
        XCTAssertEqual(node.prompt, "você revisa o diff")
        XCTAssertEqual(node.component, "revisor")
    }

    /// Componente escrito antes da ADR-057 tem `cmd`/`config`/`model` na raiz —
    /// eles eram do CLI o tempo todo e viram o mapa daquele CLI, sem migração
    /// de disco.
    func testLegacyRootFieldsBecomeTheAgentMap() throws {
        let json = """
            {"name":"revisor","kind":"agent","agent":"claude","model":"opus",
             "config":"~/.claude-agro","cmd":"claude --foo","prompt":"revise","rules":"em português"}
            """
        let component = try JSONDecoder().decode(NodeTemplate.self, from: Data(json.utf8))
        let claude = component.resolved(for: "claude")
        XCTAssertEqual(claude.model, "opus")
        XCTAssertEqual(claude.config, "~/.claude-agro")
        XCTAssertEqual(claude.cmd, "claude --foo")
        XCTAssertEqual(claude.rules, "em português")
        XCTAssertNil(component.resolved(for: "opencode").model, "não vaza para o outro CLI")

        // E é reescrito na forma nova, sem as chaves da raiz.
        let written = try JSONEncoder().encode(component)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertNil(object["model"])
        XCTAssertNil(object["config"])
        XCTAssertNotNil(object["byAgent"])
        let again = try JSONDecoder().decode(NodeTemplate.self, from: written)
        XCTAssertEqual(again.resolved(for: "claude").model, "opus")
    }

    /// Capturar um terminal guarda o que é dele no mapa do CLI em que ele roda.
    func testCaptureSplitsRoleFromCLI() {
        var node = NodeConfig(type: .agent, id: "rev")
        node.agent = "claude"
        node.model = "opus"
        node.config = "~/.claude-agro"
        node.prompt = "revise"
        node.rules = "em português"

        let component = NodeTemplateStore.capture(from: node, name: "revisor")
        XCTAssertEqual(component.rules, "em português", "regra do nó vira a geral")
        XCTAssertEqual(component.resolved(for: "claude").model, "opus")
        XCTAssertNil(component.resolved(for: "opencode").model)
    }
}

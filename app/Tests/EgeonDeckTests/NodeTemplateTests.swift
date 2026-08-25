import XCTest
@testable import EgeonDeck

/// O preset de nó: captura a montagem, instancia sem conversa, e o nome vira
/// id de dispatch previsível.
final class NodeTemplateTests: XCTestCase {
    func testCaptureCopiesAssemblyOnly() throws {
        let node = try JSONDecoder().decode(NodeConfig.self, from: Data("""
            {"type":"agent","id":"rev","agent":"claude","cmd":"claude --foo",
             "config":"/Users/x/.claude-trabalho","cwd":"packages/api",
             "model":"opus","prompt":"revise","conversationId":"C1","transcript":"/t.jsonl"}
            """.utf8))

        let template = NodeTemplateStore.capture(from: node, name: "Revisor")
        XCTAssertEqual(template.kind, .agent)
        XCTAssertEqual(template.agent, "claude")
        XCTAssertEqual(template.cmd, "claude --foo")
        XCTAssertEqual(template.cwd, "packages/api")
        XCTAssertEqual(template.prompt, "revise")
        XCTAssertEqual(template.model, "opus")
        // NodeTemplate nem tem campo de conversa — a montagem é tudo que existe.
    }

    func testInstantiateBuildsNodeWithoutConversation() {
        let template = NodeTemplate(name: "Revisor", kind: .agent, agent: "claude",
                                    model: "sonnet", cwd: "src", prompt: "revise")
        let node = NodeTemplateStore.instantiate(template, id: "revisor-2")

        XCTAssertEqual(node.type, .agent)
        XCTAssertEqual(node.id, "revisor-2")
        XCTAssertEqual(node.agent, "claude")
        XCTAssertEqual(node.prompt, "revise")
        XCTAssertEqual(node.model, "sonnet")
        XCTAssertNil(node.conversationId)
        // O registro de origem: só informativo, editar o preset não mexe em
        // quem já nasceu.
        XCTAssertEqual(node.component, "Revisor")
    }

    // O id sai do nome e entra no endereço de dispatch — minúsculo, sem espaço,
    // sem repetição de hífen, e nunca vazio.
    func testIdentifierIsPredictable() {
        XCTAssertEqual(NodeTemplateStore.identifier(from: "Revisor"), "revisor")
        XCTAssertEqual(NodeTemplateStore.identifier(from: "front / end"), "front-end")
        XCTAssertEqual(NodeTemplateStore.identifier(from: "  QA Ágil  "), "qa-gil")
        XCTAssertEqual(NodeTemplateStore.identifier(from: "???"), "sh")
    }
}

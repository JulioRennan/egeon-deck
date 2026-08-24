import XCTest
@testable import EgeonDeck

/// A menção por `@` no composer: onde ela está ativa e o que entra no lugar.
final class MentionParserTests: XCTestCase {
    func testMentionAtCaretWithQuery() {
        let active = MentionParser.activeMention(in: "veja com o @ba", caret: 14)
        XCTAssertEqual(active?.query, "ba")
        XCTAssertEqual(active?.range, NSRange(location: 11, length: 3))
    }

    func testBareAtOpensEmptyQuery() {
        let active = MentionParser.activeMention(in: "@", caret: 1)
        XCTAssertEqual(active?.query, "")
        XCTAssertEqual(active?.range, NSRange(location: 0, length: 1))
    }

    // Espaço fecha a menção; o `@` de trás já não conta.
    func testSpaceClosesMention() {
        XCTAssertNil(MentionParser.activeMention(in: "@back veja", caret: 10))
    }

    // `@` colado em palavra é e-mail ou código, não menção.
    func testAtInsideWordIsNotMention() {
        XCTAssertNil(MentionParser.activeMention(in: "julio@agro", caret: 10))
    }

    func testCaretBeforeAtIsNotMention() {
        XCTAssertNil(MentionParser.activeMention(in: "@back", caret: 0))
    }

    func testInsertReplacesTypedMention() {
        let result = MentionParser.insert("back", into: "veja com o @ba isso",
                                          replacing: NSRange(location: 11, length: 3))
        XCTAssertEqual(result.text, "veja com o @back  isso")
        XCTAssertEqual(result.caret, 17)
    }

    func testCandidatesFilterCaseInsensitive() {
        let names = ["front", "back", "revisor"]
        XCTAssertEqual(MentionParser.candidates(names, query: ""), names)
        XCTAssertEqual(MentionParser.candidates(names, query: "BA"), ["back"])
        XCTAssertEqual(MentionParser.candidates(names, query: "r"), ["front", "revisor"])
    }
}

/// A cor do agente é identidade: tem de ser a MESMA em todo arranque.
final class AgentPaletteTests: XCTestCase {
    func testColorIsDeterministic() {
        XCTAssertEqual(AgentPalette.color(for: "revisor"),
                       AgentPalette.color(for: "revisor"))
        XCTAssertTrue(AgentPalette.colors.contains(AgentPalette.color(for: "x")))
    }
}

/// Quem entra no grupo: agentes e shells; editor e web ficam de fora.
final class ChatParticipantTests: XCTestCase {
    private func node(_ json: String) throws -> NodeConfig {
        try JSONDecoder().decode(NodeConfig.self, from: Data(json.utf8))
    }

    func testFromNodesFiltersAndDerives() throws {
        let nodes = [
            try node(#"{"type":"agent","id":"revisor","agent":"claude","prompt":"revise\ntudo"}"#),
            try node(#"{"type":"shell","id":"zsh","cmd":"npm run dev"}"#),
            try node(#"{"type":"editor","id":"code"}"#),
            try node(#"{"type":"web","id":"docs"}"#),
        ]
        let participants = ChatParticipant.from(nodes: nodes, workbench: "deck") {
            $0 == "deck/revisor" ? .working : nil
        }

        XCTAssertEqual(participants.map(\.id), ["revisor", "zsh"])
        XCTAssertEqual(participants[0].address, "deck/revisor")
        // Só a primeira linha do papel: a lista não é lugar de prompt inteiro.
        XCTAssertEqual(participants[0].role, "revise")
        XCTAssertEqual(participants[0].activity, .working)
        XCTAssertTrue(participants[0].isAgent)
        XCTAssertEqual(participants[1].role, "npm run dev")
        // Sem alvo no Dispatcher = terminal morto.
        XCTAssertEqual(participants[1].activity, .dead)
        XCTAssertFalse(participants[1].isAgent)
    }
}

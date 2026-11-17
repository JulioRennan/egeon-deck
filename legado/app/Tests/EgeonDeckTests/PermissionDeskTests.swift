import XCTest
@testable import EgeonDeck

/// Permissão respondida pelo chat (ADR-068): o pedido sai do payload do
/// `PermissionRequest`, a resposta volta como a saída que o gancho imprime.
final class PermissionDeskTests: XCTestCase {
    private let payload: [String: Any] = [
        "tool_name": "Bash",
        "tool_input": ["command": "touch x.txt", "description": "Cria x.txt"],
        "permission_suggestions": [
            ["type": "addDirectories", "directories": ["/tmp/w"], "destination": "session"],
            ["type": "setMode", "mode": "acceptEdits", "destination": "session"],
        ],
    ]

    func testAskReadsToolSummaryAndDetail() throws {
        let ask = try XCTUnwrap(PermissionAsk(id: "p1", address: "deck/back", payload: payload))
        XCTAssertEqual(ask.tool, "Bash")
        XCTAssertEqual(ask.summary, "touch x.txt")
        XCTAssertEqual(ask.detail, "Cria x.txt")
    }

    // "Sempre" não pode virar troca de modo da sessão inteira.
    func testSetModeSuggestionIsDropped() throws {
        let ask = try XCTUnwrap(PermissionAsk(id: "p1", address: "deck/back", payload: payload))
        XCTAssertEqual(ask.suggestions.count, 1)
        XCTAssertEqual(ask.suggestions.first?["type"] as? String, "addDirectories")
        XCTAssertTrue(ask.canAlwaysAllow)
    }

    func testPayloadWithoutToolIsRefused() {
        XCTAssertNil(PermissionAsk(id: "p1", address: "deck/back", payload: ["tool_input": [:]]))
    }

    func testSummaryByTool() {
        XCTAssertEqual(PermissionAsk.summary(tool: "Edit", input: ["file_path": "/a.swift", "old_string": "x"]),
                       "/a.swift")
        XCTAssertEqual(PermissionAsk.summary(tool: "WebFetch", input: ["url": "https://x.dev"]), "https://x.dev")
        XCTAssertEqual(PermissionAsk.summary(tool: "mcp__x__y", input: ["b": 1, "a": "z"]), #"{"a":"z","b":1}"#)
        XCTAssertEqual(PermissionAsk.summary(tool: "Foo", input: [:]), "Foo")
    }

    func testHookOutputShapes() {
        let rules: [[String: Any]] = [["type": "addDirectories", "directories": ["/tmp"], "destination": "session"]]
        func decision(_ answer: PermissionAnswer, _ suggestions: [[String: Any]]) -> [String: Any] {
            let out = answer.hookOutput(suggestions: suggestions)["hookSpecificOutput"] as? [String: Any]
            XCTAssertEqual(out?["hookEventName"] as? String, "PermissionRequest")
            return out?["decision"] as? [String: Any] ?? [:]
        }
        XCTAssertEqual(decision(.allow, rules)["behavior"] as? String, "allow")
        XCTAssertNil(decision(.allow, rules)["updatedPermissions"])
        XCTAssertEqual((decision(.always, rules)["updatedPermissions"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(decision(.always, [])["updatedPermissions"])
        XCTAssertEqual(decision(.deny, rules)["behavior"] as? String, "deny")
    }

    func testAnsweredOnceThenGone() throws {
        let desk = PermissionDesk()
        let ask = try XCTUnwrap(desk.open(address: "deck/back", payload: payload))
        XCTAssertEqual(desk.state(of: ask.id), .pending)
        XCTAssertTrue(desk.answer(ask.id, with: .allow))
        XCTAssertFalse(desk.answer(ask.id, with: .deny))
        XCTAssertEqual(desk.state(of: ask.id), .answered(.allow))
        XCTAssertNotNil(desk.takeOutput(of: ask.id))
        XCTAssertEqual(desk.state(of: ask.id), .gone)
        XCTAssertTrue(desk.open.isEmpty)
    }

    // Tecla no terminal (ou turno que seguiu) fecha sem resposta: o gancho sai calado.
    func testDropMakesItGone() throws {
        let desk = PermissionDesk()
        let ask = try XCTUnwrap(desk.open(address: "deck/back", payload: payload))
        desk.drop(address: "deck/front")
        XCTAssertEqual(desk.state(of: ask.id), .pending)
        desk.drop(address: "deck/back")
        XCTAssertEqual(desk.state(of: ask.id), .gone)
    }

    // Ferramentas em paralelo: um gancho por chamada, e cada pedido é seu.
    func testAsksOfTheSameTerminalCoexist() throws {
        let desk = PermissionDesk()
        let first = try XCTUnwrap(desk.open(address: "deck/back", payload: payload))
        let other = try XCTUnwrap(desk.open(address: "deck/front", payload: payload))
        let second = try XCTUnwrap(desk.open(address: "deck/back", payload: payload))
        XCTAssertEqual(desk.open.map(\.id), [first.id, other.id, second.id])
        XCTAssertTrue(desk.answer(second.id, with: .deny))
        XCTAssertEqual(desk.state(of: first.id), .pending)
        XCTAssertEqual(desk.pending(inWorkbench: "deck").count, 2)
        XCTAssertTrue(desk.pending(inWorkbench: "dec").isEmpty)
    }

    // O gancho desiste no teto: pedido mais velho não tem quem leve a resposta,
    // e clicar nele seria aprovar nada.
    func testAsksExpireWithTheHook() throws {
        let desk = PermissionDesk()
        var clock = Date(timeIntervalSince1970: 1000)
        desk.now = { clock }
        let ask = try XCTUnwrap(desk.open(address: "deck/back", payload: payload))
        clock += PermissionDesk.lifetime - 1
        XCTAssertEqual(desk.state(of: ask.id), .pending)
        clock += 2
        XCTAssertEqual(desk.state(of: ask.id), .gone)
        XCTAssertTrue(desk.open.isEmpty)
        XCTAssertFalse(desk.answer(ask.id, with: .allow))
    }

    func testRenameFollowsTheWorkbench() throws {
        let desk = PermissionDesk()
        let ask = try XCTUnwrap(desk.open(address: "deck/back", payload: payload))
        desk.renamed("deck/back", to: "deck2/back")
        XCTAssertEqual(desk.pending(inWorkbench: "deck2").map(\.id), [ask.id])
    }
}

/// A pergunta do `AskUserQuestion` respondida pelo chat (ADR-068).
final class PermissionQuestionTests: XCTestCase {
    private let payload: [String: Any] = [
        "tool_name": "AskUserQuestion",
        "tool_input": ["questions": [
            ["question": "Qual cor?", "header": "Cor", "multiSelect": false,
             "options": [["label": "Vermelho", "description": "r"], ["label": "Azul", "description": "b"]]],
            ["question": "Quais frutas?", "header": "Frutas", "multiSelect": true,
             "options": [["label": "Maçã"], ["label": "Uva"], ["label": "Pera"]]],
        ]],
    ]

    func testQuestionsAreRead() throws {
        let ask = try XCTUnwrap(PermissionAsk(id: "p1", address: "deck/back", payload: payload))
        XCTAssertEqual(ask.summary, "Qual cor?")
        XCTAssertEqual(ask.questions.map(\.question), ["Qual cor?", "Quais frutas?"])
        XCTAssertEqual(ask.questions[0].options, ["Vermelho", "Azul"])
        XCTAssertTrue(ask.questions[1].multiSelect)
    }

    func testOtherToolsHaveNoQuestions() throws {
        let ask = try XCTUnwrap(PermissionAsk(id: "p1", address: "deck/back",
                                              payload: ["tool_name": "Bash", "tool_input": ["command": "ls"]]))
        XCTAssertTrue(ask.questions.isEmpty)
        XCTAssertFalse(ask.accepts(["x": ["y"]]))
    }

    func testChoicesMustCoverEveryQuestionWithinItsOptions() throws {
        let ask = try XCTUnwrap(PermissionAsk(id: "p1", address: "deck/back", payload: payload))
        XCTAssertTrue(ask.accepts(["Qual cor?": ["Azul"], "Quais frutas?": ["Maçã", "Uva"]]))
        XCTAssertFalse(ask.accepts(["Qual cor?": ["Azul"]]), "falta uma pergunta")
        XCTAssertFalse(ask.accepts(["Qual cor?": ["Verde"], "Quais frutas?": ["Uva"]]), "fora das opções")
        XCTAssertFalse(ask.accepts(["Qual cor?": ["Azul", "Vermelho"], "Quais frutas?": ["Uva"]]),
                       "duas escolhas numa pergunta de uma")
    }

    // A forma medida no CLI: allow com o tool_input original mais `answers`.
    func testAnswerOutputKeepsInputAndJoinsMultiSelect() throws {
        let ask = try XCTUnwrap(PermissionAsk(id: "p1", address: "deck/back", payload: payload))
        let out = ask.answerOutput(["Qual cor?": ["Azul"], "Quais frutas?": ["Maçã", "Uva"]])
        let decision = (out["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "allow")
        let updated = decision?["updatedInput"] as? [String: Any]
        XCTAssertEqual((updated?["questions"] as? [Any])?.count, 2)
        XCTAssertEqual(updated?["answers"] as? [String: String],
                       ["Qual cor?": "Azul", "Quais frutas?": "Maçã, Uva"])
    }

    func testDeskRefusesBadChoicesAndKeepsTheAskOpen() throws {
        let desk = PermissionDesk()
        let ask = try XCTUnwrap(desk.open(address: "deck/back", payload: payload))
        XCTAssertFalse(desk.answer(ask.id, choices: ["Qual cor?": ["Azul"]]))
        XCTAssertEqual(desk.state(of: ask.id), .pending)
        XCTAssertTrue(desk.answer(ask.id, choices: ["Qual cor?": ["Azul"], "Quais frutas?": ["Pera"]]))
        XCTAssertEqual(desk.state(of: ask.id), .answered(.allow))
    }

    // Só o CLI que fala por gancho ganha a linha: é por ele que a pergunta chega.
    func testQuestionToolLineOnlyForHookedProfile() throws {
        let claude = try XCTUnwrap(AgentProfile.claudeCode.systemPromptText(role: "papel"))
        XCTAssertTrue(claude.contains("AskUserQuestion"))
        var other = AgentProfile.claudeCode
        other.reportSession = nil
        XCTAssertFalse(try XCTUnwrap(other.systemPromptText(role: "papel")).contains("AskUserQuestion"))
    }
}

import XCTest
@testable import EgeonDeck

final class SlashCommandTests: XCTestCase {
    func testActiveQueryOnlyAtStartAndBeforeSpace() {
        XCTAssertEqual(SlashParser.activeQuery(in: "/", caret: 1), "")
        XCTAssertEqual(SlashParser.activeQuery(in: "/cle", caret: 4), "cle")
        XCTAssertEqual(SlashParser.activeQuery(in: "/figma:use", caret: 10), "figma:use")
        XCTAssertNil(SlashParser.activeQuery(in: "/clear agora", caret: 12))
        XCTAssertNil(SlashParser.activeQuery(in: "veja /tmp", caret: 9))
        XCTAssertNil(SlashParser.activeQuery(in: "", caret: 0))
        XCTAssertNil(SlashParser.activeQuery(in: "/x", caret: 0))
    }

    func testInsertKeepsTheRestOfTheMessage() {
        XCTAssertEqual(SlashParser.insert("clear", into: "/cl").text, "/clear ")
        XCTAssertEqual(SlashParser.insert("clear", into: "/cl").caret, 7)
        XCTAssertEqual(SlashParser.insert("review", into: "/rev 243").text, "/review 243")
    }

    func testMatchingPrefersPrefixAndPluginShortName() {
        let all = [SlashCommand(name: "compact", detail: "", source: .builtin),
                   SlashCommand(name: "figma:figma-use", detail: "", source: .plugin("figma")),
                   SlashCommand(name: "clear", detail: "", source: .builtin),
                   SlashCommand(name: "ralph-loop:cancel-ralph", detail: "", source: .plugin("ralph-loop"))]
        XCTAssertEqual(SlashCommand.matching(all, query: "").map(\.name), all.map(\.name))
        XCTAssertEqual(SlashCommand.matching(all, query: "c").map(\.name),
                       ["compact", "clear", "ralph-loop:cancel-ralph"])
        // Contém, mas não começa: vem depois de quem começa.
        let config = SlashCommand(name: "config", detail: "", source: .builtin)
        XCTAssertEqual(SlashCommand.matching([config] + all, query: "fig").map(\.name),
                       ["figma:figma-use", "config"])
        XCTAssertEqual(SlashCommand.matching(all, query: "figma-u").map(\.name), ["figma:figma-use"])
        XCTAssertEqual(SlashCommand.matching(all, query: "RALPH").map(\.name), ["ralph-loop:cancel-ralph"])
    }

    func testFrontmatterFoldedQuotedAndHidden() {
        let folded = ClaudeFrontmatter("""
        ---
        name: aws-cdk
        description: >-
          Authors and deploys
          CDK stacks.
        ---
        corpo
        """)
        XCTAssertEqual(folded.name, "aws-cdk")
        XCTAssertEqual(folded.description, "Authors and deploys CDK stacks.")
        XCTAssertTrue(folded.invocable)

        let quoted = ClaudeFrontmatter("---\ndescription: \"Start Ralph Loop\"\nuser-invocable: false\n---\n")
        XCTAssertEqual(quoted.description, "Start Ralph Loop")
        XCTAssertFalse(quoted.invocable)

        let bare = ClaudeFrontmatter("# Cria uma worktree\n\nPara: $ARGUMENTS")
        XCTAssertNil(bare.description)
        XCTAssertEqual(bare.firstLine, "Cria uma worktree")
    }

    func testCatalogReadsUserProjectAndEnabledPlugins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        let project = root.appendingPathComponent("repo")
        let plugin = root.appendingPathComponent("cache/figma")
        let off = root.appendingPathComponent("cache/off")

        func write(_ url: URL, _ text: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(config.appendingPathComponent("commands/new-worktree.md"), "Cria uma worktree")
        try write(config.appendingPathComponent("skills/egeon/SKILL.md"),
                  "---\nname: egeon\ndescription: Falar com os vizinhos\n---\n")
        try write(config.appendingPathComponent("skills/README.md"), "não é skill")
        try write(config.appendingPathComponent("skills/oculta/SKILL.md"),
                  "---\nname: oculta\nuser-invocable: false\n---\n")
        try write(project.appendingPathComponent(".claude/commands/clear.md"),
                  "---\ndescription: clear do projeto\n---\n")
        try write(plugin.appendingPathComponent("skills/figma-use/SKILL.md"),
                  "---\nname: figma-use\ndescription: Usa o Figma\n---\n")
        try write(off.appendingPathComponent("commands/nada.md"), "desligado")
        try write(config.appendingPathComponent("settings.json"),
                  #"{"enabledPlugins": {"figma@oficial": true, "off@oficial": false}}"#)
        try write(config.appendingPathComponent("plugins/installed_plugins.json"), """
        {"version": 2, "plugins": {
          "figma@oficial": [{"installPath": "\(plugin.path)"}],
          "off@oficial": [{"installPath": "\(off.path)"}]}}
        """)

        let found = ClaudeSlashCatalog.commands(configDir: config, cwd: project)
        let byName = Dictionary(found.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(byName["new-worktree"]?.detail, "Cria uma worktree")
        XCTAssertEqual(byName["egeon"]?.source, .user)
        XCTAssertEqual(byName["figma:figma-use"]?.source, .plugin("figma"))
        XCTAssertNil(byName["oculta"])
        XCTAssertNil(byName["off:nada"])
        // O do projeto vence o embutido de mesmo nome.
        XCTAssertEqual(byName["clear"]?.source, .project)
        XCTAssertEqual(found.filter { $0.name == "clear" }.count, 1)
        XCTAssertNotNil(byName["compact"])
    }
}

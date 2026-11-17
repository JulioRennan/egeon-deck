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
        let usage = SlashCommand(name: "usage", detail: "", source: .builtin, aliases: ["cost", "stats"])
        XCTAssertEqual(SlashCommand.matching(all + [usage], query: "cos").map(\.name), ["usage"])
    }

    func testSearchMatchesEveryWordInNameAliasOrDescription() {
        let all = [SlashCommand(name: "anthropic-skills:pdf", detail: "Lê e cria arquivos PDF", source: .plugin("anthropic-skills")),
                   SlashCommand(name: "debug", detail: "Turn on debug logging", source: .bundled),
                   SlashCommand(name: "export", detail: "Exporta a conversa para PDF", source: .builtin),
                   SlashCommand(name: "usage", detail: "Custo da sessão", source: .builtin, aliases: ["cost"])]
        XCTAssertEqual(SlashCommand.searching(all, text: "").map(\.name), all.map(\.name))
        // Pelo nome antes de pela descrição.
        XCTAssertEqual(SlashCommand.searching(all, text: "pdf").map(\.name), ["anthropic-skills:pdf", "export"])
        XCTAssertEqual(SlashCommand.searching(all, text: "LOGGING turn").map(\.name), ["debug"])
        XCTAssertEqual(SlashCommand.searching(all, text: "le arquivos").map(\.name), ["anthropic-skills:pdf"])
        XCTAssertEqual(SlashCommand.searching(all, text: "cost").map(\.name), ["usage"])
        XCTAssertEqual(SlashCommand.searching(all, text: "pdf debug").map(\.name), [])
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

    func testRegistryReadsBuiltinsAndBundledSkillsFromBinary() {
        let js = #"""
        x={type:"local",name:"compact",description:"Free up context",load:()=>1};
        y={type:"local-jsx",name:"plugin",aliases:["plugins"],description:'Manage plugins',load:()=>2};
        z={type:"local",name:"agents",description:"(removed)",isHidden:!0,load:()=>3};
        b={type:"local-jsx",name:"btw",description:"Side {question}",requires:{ink:!0}},E=I;var R={isHidden:!0,name:"stub"};
        w={type:"prompt",name:"init",get description(){return a},load:()=>4};
        var R={description:"Restore a previous point",name:"rewind",aliases:["checkpoint","undo"],type:"local",load:()=>5};
        var S={type:"local",name:"stub2",isEnabled:()=>!1,load:()=>6};
        Wi({name:"debug",menuDescription:"Turn on debug — logs",description:"x",disableModelInvocation:!0,async getPromptForCommand(){}});
        Wi({name:"batch",menuDescription:"Plan a large change",description:"y",async getPromptForCommand(){}});
        Wi({name:"keybindings-help",description:'Rebind keys',userInvocable:!1,async getPromptForCommand(){}});
        f({name:"nada",value:1});
        """#
        let found = ClaudeCommandRegistry.parse(binary: Data(js.utf8))
        XCTAssertEqual(found.builtins.map(\.name), ["btw", "compact", "init", "plugin", "rewind"])
        // Campos em outra ordem: o objeto é achado pelo `type:`.
        XCTAssertEqual(found.builtins.first { $0.name == "rewind" }?.detail, "Restore a previous point")
        XCTAssertEqual(found.builtins.first { $0.name == "rewind" }?.aliases, ["checkpoint", "undo"])
        XCTAssertEqual(found.builtins.first { $0.name == "btw" }?.detail, "Side {question}")
        XCTAssertEqual(found.builtins.first { $0.name == "plugin" }?.detail, "Manage plugins")
        // Getter não é literal: fica sem legenda, mas fica na lista.
        XCTAssertEqual(found.builtins.first { $0.name == "init" }?.detail, "")
        XCTAssertEqual(found.skills.map(\.name), ["batch", "debug"])
        XCTAssertEqual(found.skills.first { $0.name == "debug" }?.detail, "Turn on debug — logs")
        XCTAssertEqual(found.skills.first { $0.name == "debug" }?.userOnly, true)
        XCTAssertEqual(found.skills.first { $0.name == "batch" }?.userOnly, false)
        XCTAssertEqual(found.hidden, ["agents", "keybindings-help", "stub2"])
    }

    func testSkillListingKeepsOrderAndRestartsOnInitial() {
        func line(_ names: [String], _ content: String, initial: Bool) -> String {
            let attachment: [String: Any] = ["type": "skill_listing", "names": names,
                                             "content": content, "isInitial": initial]
            let data = try! JSONSerialization.data(withJSONObject: ["type": "attachment", "attachment": attachment])
            return String(decoding: data, as: UTF8.self)
        }
        let jsonl = [
            line(["velha"], "- velha: some", initial: true),
            #"{"type":"user","message":{"content":"fala do "skill_listing" no texto"}}"#,
            line(["simplify", "figma:figma-use"], "- simplify: Limpa o código\n- figma:figma-use: Usa o Figma",
                 initial: true),
            line(["loop"], "- loop: Repete", initial: false),
        ].joined(separator: "\n")
        let found = ClaudeSlashCatalog.skillListing(in: Data(jsonl.utf8))
        XCTAssertEqual(found.map(\.name), ["simplify", "figma:figma-use", "loop"])
        XCTAssertEqual(found.map(\.detail), ["Limpa o código", "Usa o Figma", "Repete"])
    }

    func testCatalogMergesSyncedSessionAndBinary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        let repo = root.appendingPathComponent("repo")
        let sub = repo.appendingPathComponent("app/web")

        func write(_ url: URL, _ text: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        try write(repo.appendingPathComponent(".git/HEAD"), "ref: main")
        try write(repo.appendingPathComponent(".claude/skills/raiz/SKILL.md"), "---\ndescription: Da raiz\n---\n")
        try write(sub.appendingPathComponent(".claude/commands/frontend/component.md"), "Cria um componente")
        // Acima da raiz do repositório não se procura.
        try write(root.appendingPathComponent(".claude/skills/fora/SKILL.md"), "---\nname: fora\n---\n")

        let skills = config.appendingPathComponent("skills/synced/conta")
        try write(skills.appendingPathComponent("manifest.json"), #"{"skills": [{"name": "pdf"}]}"#)
        try write(skills.appendingPathComponent("pdf/SKILL.md"), "---\nname: pdf\ndescription: PDFs\n---\n")
        try write(skills.appendingPathComponent("removida/SKILL.md"), "---\nname: removida\n---\n")
        let plugins = config.appendingPathComponent("plugins/synced/conta")
        try write(plugins.appendingPathComponent("manifest.json"),
                  #"{"plugins": [{"name": "cowork", "generation": 3}]}"#)
        try write(plugins.appendingPathComponent("cowork/skills/velha/SKILL.md"), "---\nname: velha\n---\n")
        try write(plugins.appendingPathComponent("cowork~g3/skills/nova/SKILL.md"), "---\nname: nova\n---\n")

        var binary = ClaudeCommandRegistry()
        binary.builtins = [.init(name: "compact", detail: "Free up context"), .init(name: "radio", detail: "Lo-fi")]
        binary.skills = [.init(name: "debug", detail: "Debug", userOnly: true),
                         .init(name: "design-sync", detail: "Desligada nesta sessão")]
        binary.hidden = ["keybindings-help"]
        try write(config.appendingPathComponent("skills/egeon/SKILL.md"),
                  "---\nname: egeon\nuser-invocable: false\n---\n")
        let loaded = [(name: "simplify", detail: "Limpa"), (name: "keybindings-help", detail: "Teclas"),
                      (name: "egeon", detail: "Só do modelo"),
                      (name: "anthropic-skills:pdf", detail: "Repetida")]

        let found = ClaudeSlashCatalog.commands(configDir: config, cwd: sub, loaded: loaded, binary: binary)
        let byName = Dictionary(found.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(byName["frontend:component"]?.source, .project)
        XCTAssertEqual(byName["raiz"]?.detail, "Da raiz")
        XCTAssertNil(byName["fora"])
        XCTAssertEqual(byName["anthropic-skills:pdf"]?.detail, "PDFs")
        XCTAssertNil(byName["anthropic-skills:removida"])
        XCTAssertEqual(byName["cowork:nova"]?.source, .plugin("cowork"))
        XCTAssertNil(byName["cowork:velha"])
        XCTAssertEqual(byName["simplify"]?.source, .bundled)
        XCTAssertNil(byName["keybindings-help"])
        // Oculta no disco, mesmo que a sessão a liste.
        XCTAssertNil(byName["egeon"])
        XCTAssertEqual(byName["debug"]?.source, .bundled)
        XCTAssertNil(byName["design-sync"])
        // A legenda nossa vence a do binário; o que só o binário tem entra com a dele.
        XCTAssertEqual(byName["compact"]?.detail, "Resume a conversa para liberar contexto")
        XCTAssertEqual(byName["radio"]?.detail, "Lo-fi")
        XCTAssertNil(byName["memory"])

        let entries: [[String: Any]] = [
            ["scope": "project", "projectPath": root.path, "installPath": "/velha"],
            ["scope": "user", "installPath": "/nova"],
            ["scope": "project", "projectPath": repo.path, "installPath": "/deste"]]
        XCTAssertEqual(ClaudeSlashCatalog.installPath(entries, projects: ClaudeSlashCatalog.projectRoots(from: sub)),
                       "/deste")
        XCTAssertEqual(ClaudeSlashCatalog.installPath(Array(entries.prefix(2)),
                                                      projects: ClaudeSlashCatalog.projectRoots(from: sub)), "/nova")

        // Sem a lista da sessão, as skills do binário entram todas.
        let fresh = ClaudeSlashCatalog.commands(configDir: config, cwd: sub, loaded: nil, binary: binary)
        XCTAssertTrue(fresh.contains { $0.name == "design-sync" })
    }
}

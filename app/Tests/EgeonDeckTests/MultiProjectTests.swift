import XCTest
@testable import EgeonDeck

/// Multi-projeto: um projeto feito de outros projetos de pasta do mesmo
/// workspace, com uma pasta que os junta (ADR-065).
final class MultiProjectTests: XCTestCase {
    private let web = ProjectConfig(id: "web", name: "nexus-web-app", path: "/src/agro/nexus-web-app")
    private let back = ProjectConfig(id: "back", name: "nexus-backend", path: "/src/agro/nexus-backend")

    private func link(_ id: String) -> String { "/links/\(id)" }

    func testDecodesOldProjectsAsFolders() throws {
        let json = #"{"id":"a","name":"x","path":"/x"}"#
        let project = try JSONDecoder().decode(ProjectConfig.self, from: Data(json.utf8))
        XCTAssertFalse(project.isMulti)
    }

    func testMembersRoundTrip() throws {
        let multi = ProjectConfig(id: "m", name: "Nexus", path: "/links/m", members: ["web", "back"])
        let data = try JSONEncoder().encode(multi)
        XCTAssertEqual(try JSONDecoder().decode(ProjectConfig.self, from: data).members, ["web", "back"])
    }

    func testMembersSkipMissingAndMulti() {
        let multi = ProjectConfig(id: "m", name: "N", path: "/l", members: ["web", "sumiu", "m", "back"])
        let space = WorkspaceConfig(name: "Agro", projects: [web, back, multi])
        XCTAssertEqual(space.members(of: multi).map(\.id), ["web", "back"])
    }

    func testNewMultiResolvesFoldersToProjectIDs() {
        let draft = MultiProjectDraft(name: "Nexus", folders: [web.path, back.path])
        let out = WorkspaceEdit.apply(to: [web, back], folders: [web.path, back.path], multis: [draft],
                                      linkPath: link, hasWorkbenches: { _ in false })
        let multi = out.projects.last!
        XCTAssertEqual(multi.members, ["web", "back"])
        XCTAssertEqual(multi.path, "/links/\(multi.id)")
        XCTAssertEqual(out.projects.filter { !$0.isMulti }.map(\.id), ["web", "back"])
    }

    func testMultiCanUseFolderAddedInTheSameForm() {
        let draft = MultiProjectDraft(name: "Tudo", folders: ["/src/agro/novo", web.path])
        let out = WorkspaceEdit.apply(to: [web], folders: [web.path, "/src/agro/novo"], multis: [draft],
                                      linkPath: link, hasWorkbenches: { _ in false })
        let novo = out.projects.first { $0.path == "/src/agro/novo" }!
        XCTAssertEqual(out.projects.last?.members, [novo.id, "web"])
    }

    func testEditingKeepsIDAndFolderMatchingIgnoresMultis() {
        let multi = ProjectConfig(id: "m", name: "Velho", path: "/links/m", members: ["web"])
        let draft = MultiProjectDraft(id: "m", name: "Nexus", folders: [web.path, back.path])
        let out = WorkspaceEdit.apply(to: [web, back, multi], folders: [web.path, back.path],
                                      multis: [draft], linkPath: link, hasWorkbenches: { _ in false })
        XCTAssertEqual(out.projects.map(\.id), ["web", "back", "m"])
        XCTAssertEqual(out.projects[2].name, "Nexus")
        XCTAssertEqual(out.projects[2].members, ["web", "back"])
    }

    func testRemovedMultiWithWorkbenchesStays() {
        let multi = ProjectConfig(id: "m", name: "Nexus", path: "/links/m", members: ["web"])
        let out = WorkspaceEdit.apply(to: [web, multi], folders: [web.path], multis: [],
                                      linkPath: link, hasWorkbenches: { $0 == "m" })
        XCTAssertEqual(out.projects.map(\.id), ["web", "m"])
        XCTAssertEqual(out.refused, ["Nexus"])
    }

    func testRemovedMultiWithoutWorkbenchesGoes() {
        let multi = ProjectConfig(id: "m", name: "Nexus", path: "/links/m", members: ["web"])
        let out = WorkspaceEdit.apply(to: [web, multi], folders: [web.path], multis: [],
                                      linkPath: link, hasWorkbenches: { _ in false })
        XCTAssertEqual(out.projects.map(\.id), ["web"])
    }

    func testLinkNamesDisambiguateSameFolderName() {
        let a = ProjectConfig(name: "api", path: "/a/api")
        let b = ProjectConfig(name: "api", path: "/b/api")
        XCTAssertEqual(MultiProject.linkNames(for: [a, b]).map(\.name), ["api", "api-2"])
    }

    func testWorktreeRootLivesUnderCommonParentAndProjectName() {
        let multi = ProjectConfig(name: "Nexus completo", path: "/l")
        XCTAssertEqual(MultiProject.worktreeRoot(project: multi, members: [web, back], branch: "feat/login"),
                       "/src/agro/worktrees/Nexus completo/feat-login")
    }

    func testCommonParentFallsBackToFirstWhenOnlyRootIsShared() {
        XCTAssertEqual(MultiProject.commonParent(["/Volumes/x/a", "/Users/y/b"]), "/Volumes/x")
        XCTAssertEqual(MultiProject.commonParent(["/src/a/x", "/src/b/y"]), "/src")
    }

    func testMovingTiedProjectsToAnotherWorkspaceIsRefused() {
        let multi = ProjectConfig(id: "m", name: "N", path: "/l", members: ["web"])
        let spaces = [WorkspaceConfig(id: "s1", name: "A", projects: [web, back, multi]),
                      WorkspaceConfig(id: "s2", name: "B")]
        XCTAssertNil(WorkspaceMove.project("m", toWorkspace: "s2", at: 0, in: spaces))
        XCTAssertNil(WorkspaceMove.project("web", toWorkspace: "s2", at: 0, in: spaces))
        XCTAssertNotNil(WorkspaceMove.project("back", toWorkspace: "s2", at: 0, in: spaces))
    }

    func testLinkSyncCreatesReplacesAndKeepsForeignFiles() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let dir = tmp.appendingPathComponent("m")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("NOTAS.md"))

        MultiProjectLinks.sync(dir, links: [("web", "/src/web"), ("back", "/src/back")])
        MultiProjectLinks.sync(dir, links: [("web", "/src/web2")])

        let fm = FileManager.default
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: dir.appendingPathComponent("web").path), "/src/web2")
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("back").path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("NOTAS.md").path))
    }

    func testPruneRootOnlyRemovesLinkOnlyFolders() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let fm = FileManager.default
        let links = tmp.appendingPathComponent("so-links")
        let busy = tmp.appendingPathComponent("com-pasta")
        try fm.createDirectory(at: links, withIntermediateDirectories: true)
        try fm.createDirectory(at: busy.appendingPathComponent("web"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: links.appendingPathComponent("x").path, withDestinationPath: "/tmp")

        MultiProjectLinks.pruneRoot(links)
        MultiProjectLinks.pruneRoot(busy)
        XCTAssertFalse(fm.fileExists(atPath: links.path))
        XCTAssertTrue(fm.fileExists(atPath: busy.path))
        XCTAssertEqual(MultiProjectLinks.realSubfolders(of: busy), [busy.appendingPathComponent("web").path])
    }
}

/// A branch da bancada vale para todos; a do repo, só quando você a trocou.
final class MultiProjectBranchTests: XCTestCase {
    func testEveryRepoFollowsTheWorkbenchBranchByDefault() {
        XCTAssertEqual(MultiProject.branches(for: ["web", "back"], workbench: "feat/login", overrides: [:]),
                       ["web": "feat/login", "back": "feat/login"])
    }

    func testOverrideChangesOnlyThatRepo() {
        let out = MultiProject.branches(for: ["web", "back"], workbench: "feat/login",
                                        overrides: ["back": "fix/api", "web": "  "])
        XCTAssertEqual(out, ["web": "feat/login", "back": "fix/api"])
    }

    func testRootIsNamedAfterTheWorkbenchBranchWhateverTheRepoBranches() {
        let multi = ProjectConfig(name: "Nexus", path: "/l")
        let web = ProjectConfig(name: "web", path: "/src/web")
        XCTAssertEqual(MultiProject.worktreeRoot(project: multi, members: [web], branch: "feat/login"),
                       "/src/worktrees/Nexus/feat-login")
    }
}

/// O campo de pasta do terminal sugere o que há na bancada e no workspace.
final class FolderSuggestionsTests: XCTestCase {
    func testOnlyWhatIsInsideTheWorkbenchRelative() {
        XCTAssertEqual(FolderSuggestions.list(repoChildren: ["web", "back"]), ["back", "web"])
    }

    func testRepoChildrenAreFoldersOrLinksWithGit() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp.appendingPathComponent("repo/.git"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmp.appendingPathComponent("src"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: tmp.appendingPathComponent("link").path,
                                  withDestinationPath: tmp.appendingPathComponent("repo").path)
        XCTAssertEqual(FolderSuggestions.repoChildren(of: tmp).sorted(), ["link", "repo"])
    }
}

/// "root" na lista é a raiz da bancada, gravada vazia.
final class RootOptionTests: XCTestCase {
    func testRootIsShownForEmpty() {
        XCTAssertEqual(NodeTemplateDialog.shown(cwd: nil), "root")
        XCTAssertEqual(NodeTemplateDialog.shown(cwd: ""), "root")
        XCTAssertEqual(NodeTemplateDialog.shown(cwd: "nexus-backend"), "nexus-backend")
    }

    func testFolderOptionsStartAtRootAndKeepACustomCurrent() {
        XCTAssertEqual(NodeTemplateDialog.folderOptions(current: "", suggestions: ["web", "back"]),
                       ["", "web", "back"])
        XCTAssertEqual(NodeTemplateDialog.folderOptions(current: "~/outro", suggestions: ["web"]),
                       ["", "web", "~/outro"])
        XCTAssertEqual(NodeTemplateDialog.folderOptions(current: "web", suggestions: ["web"]), ["", "web"])
    }

}

/// Shell guarda o comando dele no componente; agente não.
final class ShellCommandTests: XCTestCase {
    func testShellCommandRoundTripsAndInstantiates() throws {
        let shell = NodeTemplate(name: "dev", kind: .shell, command: "npm run dev")
        let decoded = try JSONDecoder().decode(NodeTemplate.self, from: JSONEncoder().encode(shell))
        XCTAssertEqual(decoded.command, "npm run dev")
        XCTAssertEqual(NodeTemplateStore.instantiate(decoded, id: "dev").cmd, "npm run dev")
    }

    func testCaptureKeepsShellCommand() {
        var node = NodeConfig(type: .shell, id: "dev")
        node.cmd = "npm run dev"
        XCTAssertEqual(NodeTemplateStore.capture(from: node, name: "dev").command, "npm run dev")
    }

    func testAgentLegacyRootCmdStillMigratesToByAgent() throws {
        let json = #"{"name":"a","kind":"agent","agent":"claude","cmd":"claude --x"}"#
        let decoded = try JSONDecoder().decode(NodeTemplate.self, from: Data(json.utf8))
        XCTAssertNil(decoded.command)
        XCTAssertEqual(decoded.overrides(for: "claude").cmd, "claude --x")
    }
}

/// O workspace lembra a última configuração de cada CLI.
final class LastConfigTests: XCTestCase {
    func testRememberAndForget() throws {
        var space = WorkspaceConfig(name: "Agro")
        space.remember(config: "/Users/x/.claude-agro", for: "claude")
        XCTAssertEqual(space.lastConfigs, ["claude": "/Users/x/.claude-agro"])
        let decoded = try JSONDecoder().decode(WorkspaceConfig.self, from: JSONEncoder().encode(space))
        XCTAssertEqual(decoded.lastConfigs, ["claude": "/Users/x/.claude-agro"])
        space.remember(config: nil, for: "claude")
        XCTAssertNil(space.lastConfigs, "escolher o padrão apaga a lembrança")
    }
}

/// O padrão da configuração é o caminho que o CLI usa sem a variável.
final class ConfigItemsTests: XCTestCase {
    func testDefaultIsShownByPathAndNotRepeated() {
        let home = NSHomeDirectory()
        let items = NodeTemplateDialog.configItems(
            default: home + "/.claude", discovered: [home + "/.claude", home + "/.claude-agro"], current: nil)
        XCTAssertEqual(items.map(\.title), ["~/.claude", "~/.claude-agro"])
        XCTAssertNil(items[0].value, "o padrão grava vazio")
    }

    func testMissingCurrentIsKept() {
        let items = NodeTemplateDialog.configItems(default: "/h/.claude", discovered: [], current: "/outra/.claude-x")
        XCTAssertEqual(items.map(\.value), [nil, "/outra/.claude-x"])
    }

    func testProfileDefaultComesFromTheGlob() {
        XCTAssertEqual(AgentProfile.claudeCode.configGlob, "~/.claude*")
        let profile = AgentProfile.claudeCode
        XCTAssertEqual(profile.defaultConfigPath, NSHomeDirectory() + "/.claude")
    }
}

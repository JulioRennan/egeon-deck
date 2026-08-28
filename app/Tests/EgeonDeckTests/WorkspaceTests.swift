import XCTest
@testable import EgeonDeck

/// Workspace → projeto → bancada (ADR-043): o modelo, a conciliação que dá
/// projeto a toda bancada, e a árvore que a barra lista.
final class WorkspaceTests: XCTestCase {
    private func bench(_ name: String, path: String, project: String? = nil) -> WorkbenchConfig {
        WorkbenchConfig(name: name, path: path, nodes: [], project: project)
    }

    // MARK: Modelo

    func testProjectOwnsPathIgnoringTildeAndTrailingSlash() {
        let project = ProjectConfig(name: "deck", path: "~/repos/deck")
        let home = NSHomeDirectory()
        XCTAssertTrue(project.owns(path: "\(home)/repos/deck"))
        XCTAssertTrue(project.owns(path: "\(home)/repos/deck/"))
        XCTAssertFalse(project.owns(path: "\(home)/repos/deck2"))
    }

    func testProjectForFolderNamesAfterFolderAndAbbreviates() {
        let project = ProjectConfig.forFolder("\(NSHomeDirectory())/repos/deck/")
        XCTAssertEqual(project.name, "deck")
        XCTAssertEqual(project.path, "~/repos/deck")
    }

    func testDecodeFillsIDAndProjectNameDefaults() throws {
        let json = #"[{"name":"Duck","projects":[{"path":"/repos/deck"}]}]"#
        let spaces = try JSONDecoder().decode([WorkspaceConfig].self, from: Data(json.utf8))
        XCTAssertEqual(spaces[0].id.count, 8)
        XCTAssertEqual(spaces[0].projects[0].name, "deck")
        XCTAssertEqual(spaces[0].projects[0].id.count, 8)
        XCTAssertEqual(spaces[0].initial, "D")
        XCTAssertFalse(spaces[0].isCollapsed)
    }

    func testWorkbenchProjectRoundTrips() throws {
        let original = bench("deck", path: "/repos/deck", project: "abcd1234")
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(WorkbenchConfig.self, from: data)
        XCTAssertEqual(back.project, "abcd1234")
    }

    // MARK: Conciliação

    func testReconcileCreatesDefaultWorkspaceAndOneProjectPerRepo() {
        let benches = [bench("a", path: "/repos/deck"),
                       bench("b", path: "/repos/deck"),
                       bench("c", path: "/repos/nexus")]
        let out = WorkspaceStore.reconcile(workspaces: [], workbenches: benches,
                                           mainRepo: { _ in nil })
        XCTAssertTrue(out.changed)
        XCTAssertEqual(out.workspaces.count, 1)
        XCTAssertEqual(out.workspaces[0].name, WorkspaceStore.defaultName)
        XCTAssertEqual(out.workspaces[0].projects.map(\.name), ["deck", "nexus"])
        XCTAssertEqual(out.workbenches[0].project, out.workbenches[1].project)
        XCTAssertNotEqual(out.workbenches[0].project, out.workbenches[2].project)
    }

    // A bancada em worktree é do projeto do checkout principal: saiu dele.
    func testReconcileBindsWorktreeToMainRepoProject() {
        let deck = ProjectConfig(id: "p-deck", name: "deck", path: "/repos/deck")
        let space = WorkspaceConfig(id: "w1", name: "Duck", projects: [deck])
        let benches = [bench("wt", path: "/repos/deck-worktrees/feature-x")]
        let out = WorkspaceStore.reconcile(workspaces: [space], workbenches: benches,
                                           mainRepo: { $0.contains("worktrees") ? "/repos/deck" : nil })
        XCTAssertEqual(out.workbenches[0].project, "p-deck")
        XCTAssertEqual(out.workspaces[0].projects.count, 1)
        XCTAssertTrue(out.changed)
    }

    func testReconcileKeepsExistingAssignmentAndReportsNoChange() {
        let deck = ProjectConfig(id: "p-deck", name: "deck", path: "/repos/deck")
        let space = WorkspaceConfig(id: "w1", name: "Duck", projects: [deck])
        // Bancada apontando para pasta de OUTRO projeto, mas com `project` válido:
        // pertencimento é por id, e o arquivo é editado à mão de propósito.
        let benches = [bench("a", path: "/repos/outra", project: "p-deck")]
        let out = WorkspaceStore.reconcile(workspaces: [space], workbenches: benches,
                                           mainRepo: { _ in nil })
        XCTAssertFalse(out.changed)
        XCTAssertEqual(out.workbenches[0].project, "p-deck")
    }

    func testReconcileReassignsUnknownProjectID() {
        let deck = ProjectConfig(id: "p-deck", name: "deck", path: "/repos/deck")
        let space = WorkspaceConfig(id: "w1", name: "Duck", projects: [deck])
        let benches = [bench("a", path: "/repos/deck", project: "apagado")]
        let out = WorkspaceStore.reconcile(workspaces: [space], workbenches: benches,
                                           mainRepo: { _ in nil })
        XCTAssertTrue(out.changed)
        XCTAssertEqual(out.workbenches[0].project, "p-deck")
    }

    func testReconcileCreatesMissingProjectInFirstWorkspace() {
        let first = WorkspaceConfig(id: "w1", name: "Duck", projects: [])
        let second = WorkspaceConfig(id: "w2", name: "Agro", projects: [])
        let benches = [bench("a", path: "/repos/deck")]
        let out = WorkspaceStore.reconcile(workspaces: [first, second], workbenches: benches,
                                           mainRepo: { _ in nil })
        XCTAssertEqual(out.workspaces[0].projects.map(\.name), ["deck"])
        XCTAssertTrue(out.workspaces[1].projects.isEmpty)
        XCTAssertEqual(out.workbenches[0].project, out.workspaces[0].projects[0].id)
    }

    // MARK: Árvore

    private func sample() -> WorkspaceTree {
        let deck = ProjectConfig(id: "p-deck", name: "deck", path: "/repos/deck")
        let nexus = ProjectConfig(id: "p-nexus", name: "nexus", path: "/repos/nexus")
        let duck = WorkspaceConfig(id: "w-duck", name: "Duck", projects: [deck])
        let agro = WorkspaceConfig(id: "w-agro", name: "Agro", projects: [nexus])
        let benches = [bench("deck-1", path: "/repos/deck", project: "p-deck"),
                       bench("nexus-1", path: "/repos/nexus", project: "p-nexus"),
                       bench("deck-2", path: "/repos/deck-wt", project: "p-deck"),
                       bench("perdida", path: "/repos/x", project: "nada")]
        return WorkspaceTree(workspaces: [duck, agro], workbenches: benches)
    }

    func testRowsFollowWorkspaceProjectOrderThenOrphans() {
        XCTAssertEqual(sample().rows, [
            .workspace(id: "w-duck"),
            .project(workspaceID: "w-duck", id: "p-deck"),
            .workbench(index: 0), .workbench(index: 2),
            .workspace(id: "w-agro"),
            .project(workspaceID: "w-agro", id: "p-nexus"),
            .workbench(index: 1),
            .orphans,
            .workbench(index: 3),
        ])
    }

    func testCollapsedWorkspaceHidesProjectsAndCollapsedProjectHidesWorkbenches() {
        var tree = sample()
        var spaces = tree.workspaces
        spaces[0].collapsed = true
        spaces[1].projects[0].collapsed = true
        tree = WorkspaceTree(workspaces: spaces, workbenches: tree.workbenches)
        XCTAssertEqual(tree.rows, [
            .workspace(id: "w-duck"),
            .workspace(id: "w-agro"),
            .project(workspaceID: "w-agro", id: "p-nexus"),
            .orphans,
            .workbench(index: 3),
        ])
    }

    func testMembershipAndAncestors() {
        let tree = sample()
        XCTAssertEqual(tree.indices(inWorkspace: "w-duck"), [0, 2])
        XCTAssertEqual(tree.indices(inProject: "p-nexus"), [1])
        XCTAssertEqual(tree.orphans, [3])
        XCTAssertEqual(tree.ancestors(of: 2)?.workspaceID, "w-duck")
        XCTAssertEqual(tree.ancestors(of: 2)?.projectID, "p-deck")
        XCTAssertNil(tree.ancestors(of: 3))
    }
}

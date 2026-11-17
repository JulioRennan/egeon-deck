import XCTest
@testable import EgeonDeck

/// O "Novo projeto…" do workspace: onde sugerir e o que recusar (ADR-092).
final class NewProjectTests: XCTestCase {
    private let home = NSHomeDirectory()

    private func space(_ paths: [String]) -> WorkspaceConfig {
        WorkspaceConfig(name: "duck", projects: paths.map { ProjectConfig.forFolder($0) })
    }

    func testSuggestsTheParentMostProjectsShare() {
        let ws = space(["~/Documents/duck/a", "~/Code/x", "~/Documents/duck/b"])
        XCTAssertEqual(NewProject.suggestedParent(for: ws), "~/Documents/duck")
    }

    func testTieGoesToTheNewestProject() {
        let ws = space(["~/Documents/duck/a", "~/Code/x"])
        XCTAssertEqual(NewProject.suggestedParent(for: ws), "~/Code")
    }

    /// Multi-projeto mora na pasta do app: sugerir ali seria criar repositório
    /// dentro de `~/.egeon`.
    func testIgnoresMultiProjectsAndFallsBackWhenEmpty() {
        var ws = space([])
        ws.projects.append(ProjectConfig(name: "m", path: "~/.egeon/projects/m", members: []))
        XCTAssertEqual(NewProject.suggestedParent(for: ws), NewProject.fallbackParent)
    }

    func testNewFolderIsCreatedWithTildePath() {
        let plan = NewProject.plan(name: "  api ", parent: "~/Documents/duck", in: space([]),
                                   kind: { $0 == "\(self.home)/Documents/duck" ? true : nil })
        XCTAssertEqual(try plan.get(), NewProject.Plan(path: "~/Documents/duck/api", create: true))
    }

    func testExistingFolderIsAdoptedNotRecreated() {
        let plan = NewProject.plan(name: "api", parent: "~/Documents/duck", in: space([]), kind: { _ in true })
        XCTAssertEqual(try plan.get(), NewProject.Plan(path: "~/Documents/duck/api", create: false))
    }

    func testRefusals() {
        let dirs: (String) -> Bool? = { _ in true }
        func problem(_ name: String, parent: String = "~/Documents/duck", in ws: WorkspaceConfig? = nil,
                     kind: @escaping (String) -> Bool? = { _ in true }) -> NewProject.Problem? {
            if case .failure(let p) = NewProject.plan(name: name, parent: parent, in: ws ?? space([]), kind: kind) {
                return p
            }
            return nil
        }
        XCTAssertEqual(problem("   "), .emptyName)
        XCTAssertEqual(problem("a/b"), .invalidName)
        XCTAssertEqual(problem("a:b"), .invalidName)
        XCTAssertEqual(problem(".env"), .invalidName)
        XCTAssertEqual(problem("api", kind: { _ in nil }), .missingParent("~/Documents/duck"))
        XCTAssertEqual(problem("api", kind: { $0.hasSuffix("/api") ? false : true }),
                       .fileInTheWay("~/Documents/duck/api"))
        XCTAssertEqual(problem("api", in: space(["~/Documents/duck/api"]), kind: dirs), .alreadyProject("api"))
    }
}

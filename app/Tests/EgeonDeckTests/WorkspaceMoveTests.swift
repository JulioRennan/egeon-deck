import XCTest
@testable import EgeonDeck

/// Reordenar a árvore: workspace, projeto e bancada mudam de lugar, e a lista
/// plana de bancadas — que o app endereça por índice — sai consistente, com o
/// mapa de quem foi para onde.
final class WorkspaceMoveTests: XCTestCase {
    private func project(_ id: String) -> ProjectConfig {
        ProjectConfig(id: id, name: id, path: "~/\(id)")
    }
    private func space(_ id: String, _ projects: [String]) -> WorkspaceConfig {
        WorkspaceConfig(id: id, name: id, projects: projects.map(project))
    }
    private func bench(_ name: String, _ project: String?) -> WorkbenchConfig {
        WorkbenchConfig(name: name, path: "~/x", nodes: [], project: project)
    }

    func testWorkspaceChangesPlace() {
        let spaces = [space("a", []), space("b", []), space("c", [])]
        XCTAssertEqual(WorkspaceMove.workspace("c", to: 0, in: spaces)?.map(\.id), ["c", "a", "b"])
        XCTAssertEqual(WorkspaceMove.workspace("a", to: 2, in: spaces)?.map(\.id), ["b", "c", "a"])
        // Posição além do fim encosta no fim; para o mesmo lugar, nada muda.
        XCTAssertEqual(WorkspaceMove.workspace("a", to: 99, in: spaces)?.map(\.id), ["b", "c", "a"])
        XCTAssertNil(WorkspaceMove.workspace("a", to: 0, in: spaces))
        XCTAssertNil(WorkspaceMove.workspace("nada", to: 0, in: spaces))
    }

    func testProjectMovesInsideAndBetweenWorkspaces() throws {
        let spaces = [space("a", ["p1", "p2"]), space("b", ["p3"])]

        let inside = try XCTUnwrap(WorkspaceMove.project("p2", toWorkspace: "a", at: 0, in: spaces))
        XCTAssertEqual(inside[0].projects.map(\.id), ["p2", "p1"])

        let across = try XCTUnwrap(WorkspaceMove.project("p1", toWorkspace: "b", at: 0, in: spaces))
        XCTAssertEqual(across[0].projects.map(\.id), ["p2"])
        XCTAssertEqual(across[1].projects.map(\.id), ["p1", "p3"])
        XCTAssertNil(WorkspaceMove.project("p1", toWorkspace: "nada", at: 0, in: spaces))
    }

    func testWorkbenchReordersInsideItsProject() throws {
        let list = [bench("um", "p1"), bench("dois", "p1"), bench("três", "p1")]
        let moved = try XCTUnwrap(WorkspaceMove.workbench(2, toProject: "p1", at: 0, in: list))
        XCTAssertEqual(moved.list.map(\.name), ["três", "um", "dois"])
        // Quem estava no caminho desceu um; o resto ficou.
        XCTAssertEqual(moved.map, [2: 0, 0: 1, 1: 2])
        XCTAssertNil(WorkspaceMove.workbench(0, toProject: "p1", at: 0, in: list))
    }

    func testWorkbenchChangesProjectAndLandsAmongItsNewSiblings() throws {
        let list = [bench("um", "p1"), bench("dois", "p2"), bench("três", "p2")]
        let moved = try XCTUnwrap(WorkspaceMove.workbench(0, toProject: "p2", at: 1, in: list))
        XCTAssertEqual(moved.list.map(\.name), ["dois", "um", "três"])
        XCTAssertEqual(moved.list.map(\.project), ["p2", "p2", "p2"])

        // Para o fim do projeto, e para um projeto ainda vazio.
        let last = try XCTUnwrap(WorkspaceMove.workbench(0, toProject: "p2", at: 9, in: list))
        XCTAssertEqual(last.list.map(\.name), ["dois", "três", "um"])
        let empty = try XCTUnwrap(WorkspaceMove.workbench(1, toProject: "p9", at: 0, in: list))
        XCTAssertEqual(empty.list.map(\.name), ["um", "três", "dois"])
        XCTAssertEqual(empty.list.last?.project, "p9")
    }

    /// O mapa é o que salva os terminais na tela: cada índice antigo tem de
    /// achar a sua bancada na lista nova.
    func testMapPointsEveryMovedIndexToItsNewHome() throws {
        let list = [bench("um", "p"), bench("dois", "p"), bench("três", "p"), bench("quatro", "p")]
        for (from, to) in [(0, 3), (3, 0), (1, 2), (2, 1)] {
            let moved = try XCTUnwrap(WorkspaceMove.workbench(from, toProject: "p", at: to, in: list))
            for (old, new) in moved.map {
                XCTAssertEqual(moved.list[new].name, list[old].name,
                               "\(from)→\(to): o índice \(old) devia virar \(new)")
            }
            // Quem não está no mapa não saiu do lugar.
            for index in list.indices where moved.map[index] == nil {
                XCTAssertEqual(moved.list[index].name, list[index].name)
            }
        }
    }
}

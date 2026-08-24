import XCTest
@testable import EgeonDeck

/// A bancada como modelo: endereço, arestas de saída e a resolução de cwd —
/// incluindo a armadilha do `..` (ADR-017).
final class WorkbenchConfigTests: XCTestCase {
    private func workbench(_ json: String) throws -> WorkbenchConfig {
        try JSONDecoder().decode(WorkbenchConfig.self, from: Data(json.utf8))
    }

    func testAddressIsWorkbenchSlashNode() throws {
        let ws = try workbench(#"{"name":"deck","path":"/tmp/deck","nodes":[{"type":"agent","id":"revisor"}]}"#)
        XCTAssertEqual(ws.address(of: ws.nodes[0]), "deck/revisor")
    }

    func testTargetsAreOutgoingEdgesOnly() throws {
        let ws = try workbench("""
            {"name":"deck","path":"/tmp/deck","nodes":[],
             "edges":[{"from":"a","to":"b"},{"from":"b","to":"a"},{"from":"a","to":"c"}]}
            """)
        XCTAssertEqual(ws.targets(of: "a"), ["b", "c"])
        XCTAssertEqual(ws.targets(of: "c"), [])
    }

    func testVisitLimitDefaultsToFour() throws {
        let ws = try workbench(#"{"name":"deck","path":"/t","nodes":[]}"#)
        XCTAssertEqual(ws.visitLimit, 4)
        let strict = try workbench(#"{"name":"deck","path":"/t","nodes":[],"maxVisits":1}"#)
        XCTAssertEqual(strict.visitLimit, 1)
    }

    // As três formas de cwd, cada uma com seu motivo. `..` resolve lexical
    // (standardized): previsível a partir do texto, sem depender de symlink.
    func testResolveCwdThreeForms() {
        let root = URL(fileURLWithPath: "/repos/deck")
        XCTAssertEqual(WorkbenchConfig.resolve(cwd: "packages/api", against: root),
                       "/repos/deck/packages/api")
        XCTAssertEqual(WorkbenchConfig.resolve(cwd: "/outra/casa", against: root),
                       "/outra/casa")
        XCTAssertEqual(WorkbenchConfig.resolve(cwd: "../vizinho", against: root),
                       "/repos/vizinho")
        XCTAssertEqual(WorkbenchConfig.resolve(cwd: "~", against: root),
                       NSHomeDirectory())
    }

    func testResolvedDirectoryWithoutCwdIsTheRoot() throws {
        let ws = try workbench(#"{"name":"d","path":"/repos/deck","nodes":[{"type":"shell","id":"t1"}]}"#)
        XCTAssertEqual(ws.resolvedDirectory(for: ws.nodes[0]), "/repos/deck")
    }
}

/// O template de bancada: um molde não carrega o que foi dito dentro dele.
final class WorkbenchTemplateTests: XCTestCase {
    func testCaptureStripsConversationAndReducesWebToOrigin() throws {
        let ws = try JSONDecoder().decode(WorkbenchConfig.self, from: Data("""
            {"name":"deck","path":"/tmp/deck","nodes":[
              {"type":"agent","id":"a","agent":"claude","conversationId":"C1",
               "conversationStarted":true,"transcript":"/t.jsonl","prompt":"papel"},
              {"type":"web","id":"w","url":"http://localhost:3000/farms/123?x=1"}]}
            """.utf8))

        let template = WorkbenchTemplateStore.capture(from: ws)
        XCTAssertNil(template.nodes[0].conversationId)
        XCTAssertNil(template.nodes[0].transcript)
        XCTAssertEqual(template.nodes[0].prompt, "papel")
        // Reabrir a rota exata herdaria o estado de navegação de outra bancada.
        XCTAssertEqual(template.nodes[1].url, "http://localhost:3000")
    }

    // Template salvo por versão antiga pode ter conversa dentro; instanciar
    // zera de novo para não ressuscitar a conversa alheia.
    func testInstantiateZeroesConversationAgain() throws {
        let old = try JSONDecoder().decode(WorkbenchTemplate.self, from: Data("""
            {"nodes":[{"type":"agent","id":"a","conversationId":"VELHA"}],
             "basePath":"/tmp/deck"}
            """.utf8))
        XCTAssertNil(old.instantiate()[0].conversationId)
    }
}

/// O plano de worktree por terminal: uma regra só, e é a branch que a diz.
final class NodeWorktreeTests: XCTestCase {
    private func plan(inside: Bool, repo: String? = "/repos/deck") -> NodeWorktree {
        NodeWorktree(nodeID: "t", currentPath: "/repos/deck/api",
                     repoRoot: repo, insideWorkbench: inside,
                     enabled: false, branch: "")
    }

    func testSameBranchInsideGoesAlong() {
        var p = plan(inside: true); p.branch = "feat/x"
        XCTAssertFalse(p.decided(workbenchBranch: "feat/x").enabled,
                       "mesma branch dentro da bancada vai junto pelo cwd relativo")
    }

    func testOtherBranchInsideGetsOwnWorktree() {
        var p = plan(inside: true); p.branch = "fix/api"
        XCTAssertTrue(p.decided(workbenchBranch: "feat/x").enabled)
    }

    func testNeighborRepoWithBranchGetsOwnWorktree() {
        var p = plan(inside: false); p.branch = "feat/x"
        XCTAssertTrue(p.decided(workbenchBranch: "feat/x").enabled,
                      "repo vizinho precisa de worktree própria mesmo na mesma branch")
    }

    func testEmptyBranchStays() {
        var p = plan(inside: false); p.branch = ""
        XCTAssertFalse(p.decided(workbenchBranch: "feat/x").enabled)
    }

    func testNonGitFolderNeverGetsWorktree() {
        var p = plan(inside: false, repo: nil); p.branch = "feat/x"
        XCTAssertFalse(p.decided(workbenchBranch: "feat/x").enabled)
    }
}

import XCTest
@testable import EgeonDeck

/// A worktree nova herda a confiança do repositório de onde saiu — e só o que
/// a origem já tem aceito.
final class ClaudeTrustTests: XCTestCase {
    private func root(_ projects: [String: [String: Any]]) -> [String: Any] {
        ["numStartups": 3, "projects": projects]
    }

    func testWorktreeInheritsWhatTheRepositoryAccepted() throws {
        let config = root(["/r/app": ["hasTrustDialogAccepted": true,
                                      "hasClaudeMdExternalIncludesApproved": true,
                                      "hasClaudeMdExternalIncludesWarningShown": true,
                                      "lastCost": 1.5]])
        let updated = try XCTUnwrap(ClaudeTrust.inheriting(config, target: "/r/worktrees/app/b1", from: ["/r/app"]))
        let entry = try XCTUnwrap((updated["projects"] as? [String: Any])?["/r/worktrees/app/b1"] as? [String: Any])
        XCTAssertEqual(entry["hasTrustDialogAccepted"] as? Bool, true)
        XCTAssertEqual(entry["hasClaudeMdExternalIncludesApproved"] as? Bool, true)
        // Entrada nova com o esqueleto que o CLI espera, e nada da conversa da origem.
        XCTAssertNotNil(entry["allowedTools"])
        XCTAssertNil(entry["lastCost"])
        XCTAssertEqual(updated["numStartups"] as? Int, 3)
    }

    func testNothingWhenOriginNotAcceptedOrTargetAlready() {
        let untrusted = root(["/r/app": ["hasTrustDialogAccepted": false]])
        XCTAssertNil(ClaudeTrust.inheriting(untrusted, target: "/r/wt", from: ["/r/app"]))
        let done = root(["/r/app": ["hasTrustDialogAccepted": true], "/r/wt": ["hasTrustDialogAccepted": true]])
        XCTAssertNil(ClaudeTrust.inheriting(done, target: "/r/wt", from: ["/r/app"]))
        XCTAssertNil(ClaudeTrust.inheriting(done, target: "/r/x", from: []))
    }

    // A pasta do multi-projeto junta repositórios: confia só se todos confiam.
    func testMultiFolderNeedsEveryRepository() {
        let half = root(["/r/back": ["hasTrustDialogAccepted": true], "/r/web": ["hasTrustDialogAccepted": false]])
        XCTAssertNil(ClaudeTrust.inheriting(half, target: "/r/worktrees/multi/b", from: ["/r/back", "/r/web"]))
    }

    // A chave é o realpath: `/private/tmp/...` não pode virar `/tmp/...`.
    func testPrivatePrefixIsKept() {
        let projects: [String: Any] = ["/private/tmp/x/app": ["hasTrustDialogAccepted": true]]
        XCTAssertTrue(ClaudeTrust.granted("hasTrustDialogAccepted", in: projects, path: "/private/tmp/x/app"))
        XCTAssertFalse(ClaudeTrust.granted("hasTrustDialogAccepted", in: projects, path: "/tmp/x/app"))
    }

    // Aceito num pai também vale, como o Claude lê.
    func testAcceptedParentCounts() {
        let config = root(["/r": ["hasTrustDialogAccepted": true]])
        XCTAssertTrue(ClaudeTrust.granted("hasTrustDialogAccepted",
                                          in: config["projects"] as! [String: Any], path: "/r/app/sub"))
    }

    // Repositório de verdade: worktree ligada herda do principal; pasta de
    // multi-projeto, dos repositórios de dentro; o principal não herda.
    func testSourcesFromRealGit() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("trust-\(UUID().uuidString)")
        let repo = base.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        func git(_ args: [String], in dir: URL) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", dir.path] + args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
        }
        try git(["init", "-q"], in: repo)
        try git(["-c", "user.email=a@b", "-c", "user.name=a", "commit", "-q", "--allow-empty", "-m", "x"], in: repo)
        let multi = base.appendingPathComponent("multi/b1")
        try FileManager.default.createDirectory(at: multi, withIntermediateDirectories: true)
        try git(["worktree", "add", "-q", "-b", "b1", multi.appendingPathComponent("app").path], in: repo)

        let real = { (url: URL) in ClaudeTrustSeeder.real(url.path) }
        XCTAssertNil(ClaudeTrustSeeder.sources(for: repo.path))
        let linked = try XCTUnwrap(ClaudeTrustSeeder.sources(for: multi.appendingPathComponent("app").path))
        XCTAssertEqual(linked.target, real(multi.appendingPathComponent("app")))
        XCTAssertEqual(linked.origins, [real(repo)])
        let folder = try XCTUnwrap(ClaudeTrustSeeder.sources(for: multi.path))
        XCTAssertEqual(folder.target, real(multi))
        XCTAssertEqual(folder.origins, [real(repo)])
    }
}

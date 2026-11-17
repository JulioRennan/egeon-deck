import XCTest
@testable import EgeonDeck

/// A cópia do que o git não versiona: clone por entrada inteira, e o script do
/// usuário só quando ele mexeu na lógica.
final class UnversionedCopyTests: XCTestCase {
    func testScriptWrittenByTheAppIsStockEvenWithAnotherHeader() throws {
        let written = Worktree.stockCopyScript
        XCTAssertTrue(UnversionedCopy.isStockScript(written))
        let renamed = written.replacingOccurrences(of: "# Egeon Deck —", with: "# mega-brain —")
        XCTAssertTrue(UnversionedCopy.isStockScript(renamed), "comentário não conta")
    }

    func testEditedScriptIsNotStock() throws {
        let written = Worktree.stockCopyScript
        let edited = written.replacingOccurrences(of: ".git/|.git) continue ;;",
                                                  with: ".git/|.git|node_modules/) continue ;;")
        XCTAssertFalse(UnversionedCopy.isStockScript(edited))
    }

    func testCopiesUntrackedAndIgnoredButNotTracked() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("copy-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        let worktree = root.appendingPathComponent("wt")
        try fm.createDirectory(at: repo.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try fm.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "node_modules/\n.env\n".write(to: repo.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "SECRET=1".write(to: repo.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "x".write(to: repo.appendingPathComponent("node_modules/pkg/index.js"), atomically: true, encoding: .utf8)
        try "novo".write(to: repo.appendingPathComponent("rascunho.md"), atomically: true, encoding: .utf8)
        func git(_ args: String...) throws {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            task.arguments = ["-C", repo.path] + args
            try task.run()
            task.waitUntilExit()
        }
        try git("init", "-q")
        try git("add", ".gitignore")

        let entries = UnversionedCopy.entries(in: repo.path)
        XCTAssertEqual(Set(entries), [".env", "node_modules/", "rascunho.md"])
        let outcome = UnversionedCopy.copy(entries, from: repo.path, to: worktree.path)
        XCTAssertEqual(outcome, .init(copied: 3, failed: []))
        XCTAssertEqual(try String(contentsOf: worktree.appendingPathComponent(".env"), encoding: .utf8), "SECRET=1")
        XCTAssertTrue(fm.fileExists(atPath: worktree.appendingPathComponent("node_modules/pkg/index.js").path))
        XCTAssertFalse(fm.fileExists(atPath: worktree.appendingPathComponent(".gitignore").path), "versionado não")
    }

    func testExistingDestinationIsKept() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("keep-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "origem".write(to: root.appendingPathComponent("a"), atomically: true, encoding: .utf8)
        try "seu".write(to: root.appendingPathComponent("b"), atomically: true, encoding: .utf8)
        XCTAssertTrue(UnversionedCopy.clone(root.appendingPathComponent("a").path, root.appendingPathComponent("b").path))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("b"), encoding: .utf8), "seu")
    }
}

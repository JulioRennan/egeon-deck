import XCTest
@testable import EgeonDeck

/// O ⌘-clique no terminal: o texto que o SwiftTerm acha sob o cursor vira o
/// arquivo que existe, e não uma URL sem esquema que o `NSWorkspace` recusa.
final class TerminalLinkTests: XCTestCase {
    private let disk: Set<String> = [
        "/repo/app/Sources/a.swift",
        "/repo/README.md",
        "/repo/weird:1",
        NSHomeDirectory() + "/notas.md",
    ]
    private func resolve(_ text: String, _ dirs: [String] = ["/repo/app", "/repo"]) -> String? {
        TerminalLink.resolve(text, in: dirs, exists: disk.contains)?.path
    }

    func testRelativePathResolvesAgainstTheDirectoriesInOrder() {
        XCTAssertEqual(resolve("Sources/a.swift"), "/repo/app/Sources/a.swift")
        XCTAssertEqual(resolve("./Sources/a.swift"), "/repo/app/Sources/a.swift")
        // Não está na primeira pasta, está na segunda.
        XCTAssertEqual(resolve("README.md"), "/repo/README.md")
        XCTAssertEqual(resolve("../README.md", ["/repo/app"]), "/repo/README.md")
    }

    func testLineAndColumnSuffixIsDropped() {
        XCTAssertEqual(resolve("Sources/a.swift:42"), "/repo/app/Sources/a.swift")
        XCTAssertEqual(resolve("Sources/a.swift:42:7:"), "/repo/app/Sources/a.swift")
        XCTAssertEqual(resolve("/repo/app/Sources/a.swift:3"), "/repo/app/Sources/a.swift")
    }

    func testAFileWhoseNameEndsInColonDigitsWinsOverTheSuffix() {
        XCTAssertEqual(resolve("/repo/weird:1"), "/repo/weird:1")
    }

    func testHomeIsExpanded() {
        XCTAssertEqual(resolve("~/notas.md"), NSHomeDirectory() + "/notas.md")
        XCTAssertEqual(resolve("$HOME/notas.md"), NSHomeDirectory() + "/notas.md")
    }

    func testMissingFileOpensNothing() {
        XCTAssertNil(resolve("Sources/nao-existe.swift"))
        XCTAssertNil(resolve("   "))
    }

    func testUrlsPassThroughUntouched() {
        XCTAssertEqual(TerminalLink.resolve("https://example.com/a", in: [], exists: { _ in false })?
            .absoluteString, "https://example.com/a")
        XCTAssertEqual(TerminalLink.resolve("mailto:x@y.z", in: [], exists: { _ in false })?
            .absoluteString, "mailto:x@y.z")
    }
}

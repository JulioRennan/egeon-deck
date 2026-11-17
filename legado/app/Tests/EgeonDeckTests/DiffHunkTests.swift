import XCTest
@testable import EgeonDeck

/// O diff unificado do passo vira trechos com número de linha, e cada trecho
/// vira linhas lado a lado pareadas como o GitHub faz.
final class DiffHunkTests: XCTestCase {
    func testParsesHeadersAndKinds() {
        let hunks = DiffHunk.parse(["@@ -3,2 +3,3 @@", " ctx", "-old", "+new", "+more", "… +5 linhas"])
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].oldStart, 3)
        XCTAssertEqual(hunks[0].newStart, 3)
        XCTAssertEqual(hunks[0].lines.map(\.kind), [.context, .removed, .added, .added, .note])
        XCTAssertEqual(hunks[0].lines[1].text, "old")
    }

    func testDiffWithoutHeaderHasNoNumbers() {
        let hunks = DiffHunk.parse(["-a", "+b"])
        XCTAssertEqual(hunks.count, 1)
        XCTAssertNil(hunks[0].oldStart)
        XCTAssertEqual(hunks[0].rows, [DiffHunk.Row(
            left: DiffHunk.Cell(number: nil, kind: .removed, text: "a"),
            right: DiffHunk.Cell(number: nil, kind: .added, text: "b"))])
    }

    // Contexto nos dois lados; `-` e `+` alinhados linha a linha; a sobra fica
    // sozinha; os números seguem cada versão.
    func testRowsPairRemovalsWithAdditionsLikeGitHub() {
        let hunk = DiffHunk.parse(["@@ -1,4 +1,5 @@", " {", "-  \"port\": 8391,", "-  \"debug\": false,",
                                   "+  \"port\": 8392,", "+  \"debug\": true,", "+  \"log\": \"x\",", " }"])[0]
        let rows = hunk.rows
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[0].left?.number, 1); XCTAssertEqual(rows[0].right?.number, 1)
        XCTAssertEqual(rows[1].left?.kind, .removed); XCTAssertEqual(rows[1].right?.kind, .added)
        XCTAssertEqual(rows[1].left?.number, 2); XCTAssertEqual(rows[1].right?.number, 2)
        XCTAssertEqual(rows[2].left?.number, 3); XCTAssertEqual(rows[2].right?.number, 3)
        XCTAssertNil(rows[3].left); XCTAssertEqual(rows[3].right?.text, "  \"log\": \"x\",")
        XCTAssertEqual(rows[3].right?.number, 4)
        XCTAssertEqual(rows[4].left?.number, 4); XCTAssertEqual(rows[4].right?.number, 5)
        XCTAssertEqual(rows[4].left?.kind, .context)
    }

    func testStructuredPatchKeepsHunkHeader() {
        XCTAssertEqual(DiffHunk.header(oldStart: 3, oldLines: 2, newStart: 3, newLines: 3), "@@ -3,2 +3,3 @@")
    }
}

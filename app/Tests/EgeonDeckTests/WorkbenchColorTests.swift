import XCTest
@testable import EgeonDeck

/// A cor de cada bancada (ADR-086): escolhida sozinha, sem repetir enquanto
/// houver cor livre.
final class WorkbenchColorTests: XCTestCase {
    private func bench(_ name: String, _ color: WorkbenchColor? = nil) -> WorkbenchConfig {
        WorkbenchConfig(name: name, path: "/tmp", nodes: [], color: color)
    }

    func testPicksTheLeastUsedAndTheFirstOnTies() {
        XCTAssertEqual(WorkbenchColor.pick(used: []), .blue)
        XCTAssertEqual(WorkbenchColor.pick(used: [.blue, nil]), .violet)
        let all = WorkbenchColor.allCases.map(Optional.some)
        XCTAssertEqual(WorkbenchColor.pick(used: all + [.blue, .violet]), .pink)
    }

    func testStatusColorsStayOutOfThePalette() {
        // Laranja, verde e vermelho falam de estado nos badges (ADR-024).
        for color in WorkbenchColor.allCases {
            let (r, g, b) = color.rgb
            XCTAssertFalse(r > 0.8 && g < 0.6 && b < 0.3, "\(color) lembra laranja ou vermelho")
            XCTAssertFalse(g > 0.7 && r < 0.5 && b < 0.5, "\(color) lembra verde")
        }
    }

    func testOldListGetsDistinctColorsInOrderAndKeepsWhatItHad() {
        var list = [bench("a"), bench("b", .blue), bench("c"), bench("d")]
        WorkbenchColor.assignMissing(&list)
        XCTAssertEqual(list.map(\.color), [.violet, .blue, .pink, .cyan])
    }

    func testNewBenchIsColoredAgainstTheOthers() {
        let others = [bench("a", .blue), bench("b", .violet)]
        XCTAssertEqual(bench("c").colored(among: others).color, .pink)
        XCTAssertEqual(bench("c", .sand).colored(among: others).color, .sand)
    }

    func testColorRoundTripsAndUnknownOneDoesNotBreakTheList() throws {
        let data = try JSONEncoder().encode([bench("a", .indigo)])
        XCTAssertEqual(try JSONDecoder().decode([WorkbenchConfig].self, from: data).first?.color, .indigo)

        let old = Data(#"[{"name":"a","path":"/tmp","nodes":[],"color":"orange"}]"#.utf8)
        let list = try JSONDecoder().decode([WorkbenchConfig].self, from: old)
        XCTAssertEqual(list.count, 1)
        XCTAssertNil(list[0].color)
    }
}

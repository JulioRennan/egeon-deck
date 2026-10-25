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
        let all = WorkbenchColor.automatic.map(Optional.some)
        XCTAssertEqual(WorkbenchColor.pick(used: all + [.blue, .violet]), .pink)
    }

    // Escolhida à mão vale qualquer uma; o app sozinho nunca dá laranja, verde
    // ou vermelho, que falam de estado nos badges (ADR-024).
    func testStatusColorsStayOutOfTheAutomaticChoice() {
        for color in WorkbenchColor.automatic {
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

        let old = Data(#"[{"name":"a","path":"/tmp","nodes":[],"color":"gold"}]"#.utf8)
        let list = try JSONDecoder().decode([WorkbenchConfig].self, from: old)
        XCTAssertEqual(list.count, 1)
        XCTAssertNil(list[0].color)
    }

    // A rota de controle recebe o nome do caso ou o rótulo do menu, como vier.
    func testColorIsFoundByCaseOrMenuLabel() {
        XCTAssertEqual(WorkbenchColor(named: "sand"), .sand)
        XCTAssertEqual(WorkbenchColor(named: "Areia"), .sand)
        XCTAssertEqual(WorkbenchColor(named: "MAGENTA"), .magenta)
        XCTAssertEqual(WorkbenchColor(named: "anil"), .indigo)
        XCTAssertNil(WorkbenchColor(named: "dourado"))
        XCTAssertNil(WorkbenchColor(named: ""))
    }

    func testPaletteHasTwentyFourNamedColors() {
        let labels = WorkbenchColor.allCases.map(\.label)
        XCTAssertEqual(labels.count, 24)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertTrue(Set(WorkbenchColor.automatic).isSubset(of: WorkbenchColor.allCases))
        XCTAssertEqual(WorkbenchColor(named: "verde-azulado"), .teal)
        XCTAssertEqual(WorkbenchColor(named: "pessego"), .peach)
    }

    // A paleta cresceu, mas o que já estava gravado no disco continua lendo.
    func testColorsSavedBeforeTheBigPaletteStillDecode() throws {
        for raw in ["blue", "violet", "pink", "cyan", "indigo", "sand", "magenta"] {
            XCTAssertNotNil(WorkbenchColor(rawValue: raw), raw)
        }
    }
}

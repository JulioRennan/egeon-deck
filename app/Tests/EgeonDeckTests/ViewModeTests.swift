import XCTest
@testable import EgeonDeck

/// O modo de olhar a bancada e as proporções do mosaico — o que vai para o
/// workbenches.json e tem de voltar igual.
final class ViewModeTests: XCTestCase {
    // Os rawValues são formato de arquivo e parâmetro da rota /layout: mudar
    // um quebra bancada gravada e script de fora.
    func testRawValuesAreFileFormat() {
        XCTAssertEqual(ViewMode.canvas.rawValue, "canvas")
        XCTAssertEqual(ViewMode.mosaic.rawValue, "mosaic")
    }

    // Ausente = canvas: bancada gravada antes do campo existir abre como sempre.
    func testMissingViewDefaultsToCanvas() throws {
        let ws = try JSONDecoder().decode(WorkbenchConfig.self,
            from: Data(#"{"name":"d","path":"/t","nodes":[]}"#.utf8))
        XCTAssertEqual(ws.viewMode, .canvas)
    }

    // Modo que saiu do app ("chat") segue gravado em bancada real: valor
    // desconhecido cai em canvas em vez de derrubar a carga da bancada.
    func testUnknownViewFallsBackToCanvas() throws {
        let ws = try JSONDecoder().decode(WorkbenchConfig.self,
            from: Data(#"{"name":"d","path":"/t","nodes":[],"view":"chat"}"#.utf8))
        XCTAssertEqual(ws.viewMode, .canvas)
    }

    // Fração e não ponto: o layout tem de sobreviver ao roundtrip do arquivo.
    func testMosaicLayoutRoundtrip() throws {
        let layout = MosaicLayout(columns: [0.3, 0.7],
                                  rows: [[1.0], [0.5, 0.5]],
                                  slots: [["editor"], ["t1", "claude"]])
        let data = try JSONEncoder().encode(layout)
        let back = try JSONDecoder().decode(MosaicLayout.self, from: data)
        XCTAssertEqual(back, layout)
    }
}

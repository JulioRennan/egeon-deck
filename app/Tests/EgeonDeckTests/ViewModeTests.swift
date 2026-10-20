import XCTest
@testable import EgeonDeck

/// O modo de olhar a bancada — o que vai para o workbenches.json e tem de
/// voltar igual.
final class ViewModeTests: XCTestCase {
    // Os rawValues são formato de arquivo e parâmetro da rota /layout: mudar
    // um quebra bancada gravada e script de fora.
    func testRawValuesAreFileFormat() {
        XCTAssertEqual(ViewMode.canvas.rawValue, "canvas")
        XCTAssertEqual(ViewMode.chat.rawValue, "chat")
    }

    // Ausente = canvas: bancada gravada antes do campo existir abre como sempre.
    func testMissingViewDefaultsToCanvas() throws {
        let ws = try JSONDecoder().decode(WorkbenchConfig.self,
            from: Data(#"{"name":"d","path":"/t","nodes":[]}"#.utf8))
        XCTAssertEqual(ws.viewMode, .canvas)

        let chat = try JSONDecoder().decode(WorkbenchConfig.self,
            from: Data(#"{"name":"d","path":"/t","nodes":[],"view":"chat"}"#.utf8))
        XCTAssertEqual(chat.viewMode, .chat)
    }

    // Modo que sair do app um dia segue gravado em bancada real: valor
    // desconhecido cai em canvas em vez de derrubar a carga da bancada.
    func testUnknownViewFallsBackToCanvas() throws {
        let ws = try JSONDecoder().decode(WorkbenchConfig.self,
            from: Data(#"{"name":"d","path":"/t","nodes":[],"view":"holograma"}"#.utf8))
        XCTAssertEqual(ws.viewMode, .canvas)
    }

    // O mosaico saiu do app: bancada gravada nele abre no canvas, e as
    // proporções que ficaram no arquivo não atrapalham a carga.
    func testRemovedMosaicOpensInCanvas() throws {
        let ws = try JSONDecoder().decode(WorkbenchConfig.self, from: Data(#"""
            {"name":"d","path":"/t","nodes":[],"view":"mosaic",
             "mosaic":{"columns":[0.3,0.7],"rows":[[1.0],[0.5,0.5]],"slots":[["a"],["b","c"]]}}
            """#.utf8))
        XCTAssertEqual(ws.viewMode, .canvas)
        XCTAssertEqual(ViewMode.all, [.canvas, .chat])
    }
}

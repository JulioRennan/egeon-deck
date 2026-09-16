import XCTest
@testable import EgeonDeck

/// Posição envelhece; id não. Estes testes são a rede do passo em que os
/// dicionários do app deixaram de ser chaveados por posição na lista.
final class WorkbenchLookupTests: XCTestCase {
    private func bench(_ name: String) -> WorkbenchConfig {
        WorkbenchConfig(name: name, path: "~/\(name)", nodes: [])
    }

    func testIndexAndIdAreTwoWays() {
        let configs = [bench("um"), bench("dois"), bench("três")]
        XCTAssertEqual(WorkbenchLookup.id(at: 1, in: configs), configs[1].id)
        XCTAssertEqual(WorkbenchLookup.index(ofID: configs[2].id, in: configs), 2)
        XCTAssertEqual(WorkbenchLookup.index(ofName: "um", in: configs), 0)
        XCTAssertEqual(WorkbenchLookup.id(ofName: "três", in: configs), configs[2].id)
    }

    func testOutOfRangeAndUnknownAreNilAndNotACrash() {
        let configs = [bench("um")]
        XCTAssertNil(WorkbenchLookup.id(at: -1, in: configs))
        XCTAssertNil(WorkbenchLookup.id(at: 1, in: configs))
        XCTAssertNil(WorkbenchLookup.index(ofID: "sumida", in: configs))
        XCTAssertNil(WorkbenchLookup.index(ofName: "sumida", in: configs))
        XCTAssertNil(WorkbenchLookup.id(at: 0, in: []))
    }

    /// O ponto do passo: remover a do meio desloca as outras, e quem guardou
    /// posição passa a apontar para a bancada errada — quem guardou id, não.
    func testIdSurvivesRemovalWhilePositionDoesNot() {
        var configs = [bench("um"), bench("dois"), bench("três")]
        let terceira = configs[2].id
        XCTAssertEqual(WorkbenchLookup.index(ofID: terceira, in: configs), 2)

        configs.remove(at: 0)
        XCTAssertEqual(WorkbenchLookup.index(ofID: terceira, in: configs), 1,
                       "o id acompanhou o deslocamento")
        XCTAssertNotEqual(WorkbenchLookup.id(at: 2, in: configs), terceira,
                          "a posição 2 já é outra bancada — ou nenhuma")
    }

    /// Rename não mexe no id: é o que permite uma janela sobreviver ao nome novo.
    func testRenameKeepsTheId() {
        var configs = [bench("antes")]
        let id = configs[0].id
        configs[0].name = "depois"
        XCTAssertEqual(WorkbenchLookup.index(ofID: id, in: configs), 0)
        XCTAssertNil(WorkbenchLookup.index(ofName: "antes", in: configs))
        XCTAssertEqual(WorkbenchLookup.index(ofName: "depois", in: configs), 0)
    }

    func testAddressSplitsOnTheFirstSlashOnly() {
        XCTAssertEqual(WorkbenchLookup.split(address: "deck/revisor")?.workbench, "deck")
        XCTAssertEqual(WorkbenchLookup.split(address: "deck/revisor")?.node, "revisor")
        // Nome de bancada com espaço é comum; com barra, não existe.
        XCTAssertEqual(WorkbenchLookup.split(address: "minha bancada/claude")?.workbench,
                       "minha bancada")
        XCTAssertEqual(WorkbenchLookup.split(address: "deck/a/b")?.node, "a/b")
        XCTAssertNil(WorkbenchLookup.split(address: "deck"))
        XCTAssertNil(WorkbenchLookup.split(address: "/claude"))
        XCTAssertNil(WorkbenchLookup.split(address: "deck/"))
    }
}

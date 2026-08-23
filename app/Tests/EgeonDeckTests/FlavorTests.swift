import XCTest
@testable import EgeonDeck

/// O contrato de isolamento dev/estável. Já houve bug real de o dev pisar nas
/// bancadas do estável — estes testes pregam cada caminho no chão.
final class FlavorTests: XCTestCase {
    func testConfigDirectoriesAreSeparate() {
        XCTAssertTrue(Flavor.stable.configDirectory.path.hasSuffix("/.egeon"))
        XCTAssertTrue(Flavor.dev.configDirectory.path.hasSuffix("/.egeon-dev"))
        XCTAssertNotEqual(Flavor.stable.configDirectory, Flavor.dev.configDirectory)
    }

    func testConfigBuildsInsideOwnDirectory() {
        XCTAssertEqual(
            Flavor.dev.config("workbenches.json").path,
            Flavor.dev.configDirectory.appendingPathComponent("workbenches.json").path
        )
    }

    func testLogsAreSeparate() {
        XCTAssertTrue(Flavor.stable.logPath.hasSuffix("/egeon.log"))
        XCTAssertTrue(Flavor.dev.logPath.hasSuffix("/egeon-dev.log"))
    }

    // Porta repetida faz o segundo app a subir matar o code-server do outro,
    // achando que é órfão.
    func testCodeServerPortsDiffer() {
        XCTAssertEqual(Flavor.stable.codeServerPort, 8391)
        XCTAssertEqual(Flavor.dev.codeServerPort, 8392)
    }

    // Sem bundle (swift run, swift test) assume estável.
    func testCurrentWithoutBundleIsStable() {
        XCTAssertEqual(Flavor.current, .stable)
    }
}

import XCTest
@testable import EgeonDeck

/// O VSCode saiu (ADR-076): o que foi gravado com card de editor continua
/// abrindo, sem ele.
final class RetiredNodeTests: XCTestCase {
    func testWorkbenchDropsEditorAndKeepsTheRest() throws {
        let json = #"""
        {"name":"deck","path":"/tmp","nodes":[
          {"type":"editor","id":"code"},
          {"type":"agent","id":"claude","agent":"claude"},
          {"type":"shell","id":"sh"}]}
        """#
        let bench = try JSONDecoder().decode(WorkbenchConfig.self, from: Data(json.utf8))
        XCTAssertEqual(bench.nodes.map(\.id), ["claude", "sh"])
    }

    func testOtherBadNodeIsStillAnError() {
        let json = #"{"name":"deck","path":"/tmp","nodes":[{"type":"robo","id":"x"}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(WorkbenchConfig.self, from: Data(json.utf8)))
    }

    func testWorkbenchTemplateDropsEditor() throws {
        let json = #"{"basePath":"/tmp","view":"chat","nodes":[{"type":"editor","id":"code"},{"type":"web","id":"docs"}]}"#
        let template = try JSONDecoder().decode(WorkbenchTemplate.self, from: Data(json.utf8))
        XCTAssertEqual(template.nodes.map(\.id), ["docs"])
        XCTAssertEqual(template.view, .chat)
        XCTAssertEqual(template.basePath, "/tmp")
    }

    func testNodeComponentOfEditorKindIsSkipped() throws {
        let json = #"{"vscode":{"name":"vscode","kind":"editor"},"zsh":{"name":"zsh","kind":"shell"}}"#
        let map = try JSONDecoder().decode([String: Retirable<NodeTemplate>].self, from: Data(json.utf8))
            .compactMapValues(\.value)
        XCTAssertEqual(Array(map.keys), ["zsh"])
    }
}

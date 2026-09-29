import AppKit
import XCTest
@testable import EgeonDeck

/// O seletor de esforço do cabeçalho e a faixa que o abriga.
final class EffortDialTests: XCTestCase {
    private let levels = ["low", "medium", "high", "xhigh", "max"]

    func testStartsOnTheCurrentLevel() {
        XCTAssertEqual(EffortDial(levels: levels, current: "high", tint: .purple).value, "high")
        XCTAssertNil(EffortDial(levels: levels, current: nil, tint: .purple).value, "nil é o padrão")
    }

    /// Nível escrito à mão no JSON e fora da lista continua valendo.
    func testKeepsAnUnknownCurrentLevel() {
        XCTAssertEqual(EffortDial(levels: levels, current: "ultra", tint: .purple).value, "ultra")
    }

    /// A largura é a do nome mais comprido: rolar não pode fazer o cabeçalho dançar.
    func testWidthDoesNotDependOnTheCurrentLevel() {
        let low = EffortDial(levels: levels, current: "low", tint: .purple)
        let xhigh = EffortDial(levels: levels, current: "xhigh", tint: .purple)
        XCTAssertEqual(low.preferredWidth, xhigh.preferredWidth)
        XCTAssertEqual(low.fittingSize.width, low.preferredWidth)
    }

    /// A faixa só existe quando tem o que mostrar; com ela, o corpo desce.
    func testAccessoryRowGrowsTheHeader() {
        let node = NodeView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                            title: "x", accent: .purple)
        XCTAssertEqual(node.headerExtent, NodeView.headerHeight)
        node.accessoryRow = [NSView()]
        XCTAssertEqual(node.headerExtent, NodeView.headerHeight + NodeView.accessoryRowHeight)
        node.layoutSubtreeIfNeeded()
        XCTAssertEqual(node.body.frame.minY, node.headerExtent)
    }
}

/// O título do seletor de modelo mostra quem respondeu — mas só depois do
/// arranque atual. Antes disso a resposta é do modelo que você acabou de trocar.
final class LastModelSinceTests: XCTestCase {
    private let jsonl = """
        {"type":"assistant","timestamp":"2026-09-27T01:06:45.373Z","message":{"model":"claude-haiku-4-5"}}
        """

    func testIgnoresAnswersFromBeforeTheLaunch() {
        let launch = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z")!
        XCTAssertNil(ClaudeTranscript.lastModel(in: jsonl, since: launch))
    }

    func testKeepsAnswersAfterTheLaunch() {
        let launch = ISO8601DateFormatter().date(from: "2026-09-27T01:00:00Z")!
        XCTAssertEqual(ClaudeTranscript.lastModel(in: jsonl, since: launch), "claude-haiku-4-5")
        XCTAssertEqual(ClaudeTranscript.lastModel(in: jsonl), "claude-haiku-4-5", "sem limite, como antes")
    }
}

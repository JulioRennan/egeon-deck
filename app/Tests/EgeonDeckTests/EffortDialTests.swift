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

    /// O nível ocupa só o próprio texto (sem buraco antes do vizinho), e o
    /// slider e o auto ficam ancorados à direita: com a faixa alinhada à direita,
    /// são eles que não podem sair de baixo do cursor quando o texto muda.
    func testTextTakesOnlyItsWidthAndTheControlsStayRight() {
        let low = EffortDial(levels: levels, current: "low", tint: .purple)
        let auto = EffortDial(levels: levels, current: nil, autoLevel: "medium", tint: .purple)
        XCTAssertLessThan(low.preferredWidth, auto.preferredWidth, "\"low\" < \"medium\"")
        XCTAssertEqual(low.fittingSize.width, low.preferredWidth)
        var gaps: [CGFloat] = []
        for dial in [low, auto] {
            dial.frame = NSRect(origin: .zero, size: dial.fittingSize)
            dial.layoutSubtreeIfNeeded()
            gaps.append(dial.bounds.maxX - slider(of: dial).frame.maxX)
            XCTAssertEqual(pill(of: dial)?.frame.maxX, dial.bounds.maxX)
        }
        XCTAssertEqual(gaps[0], gaps[1])
    }

    /// O erro que a pílula veio resolver: em auto a barra não pode ficar vazia
    /// enquanto o modelo roda noutro nível, nem ser confundida com um nível fixo.
    func testAutoShowsTheModelLevelDimmedAndLitPill() {
        let auto = EffortDial(levels: levels, current: nil, autoLevel: "high", tint: .purple)
        XCTAssertTrue(auto.isAuto)
        XCTAssertEqual(slider(of: auto).integerValue, 2)
        XCTAssertLessThan(slider(of: auto).alphaValue, 1)
        XCTAssertEqual(label(of: auto), "high")

        let fixed = EffortDial(levels: levels, current: "high", autoLevel: "high", tint: .purple)
        XCTAssertFalse(fixed.isAuto)
        XCTAssertEqual(slider(of: fixed).integerValue, 2)
        XCTAssertEqual(slider(of: fixed).alphaValue, 1)
        XCTAssertNotEqual(pill(of: auto)?.layer?.backgroundColor, pill(of: fixed)?.layer?.backgroundColor)
    }

    func testTogglingAutoOffKeepsTheLevelTheModelWasUsing() {
        let dial = EffortDial(levels: levels, current: nil, autoLevel: "high", tint: .purple)
        dial.toggleAuto()
        XCTAssertEqual(dial.value, "high")
        XCTAssertEqual(label(of: dial), "high…", "só vale quando assenta")
        dial.toggleAuto()
        XCTAssertNil(dial.value)
        XCTAssertEqual(label(of: dial), "high", "voltou ao que estava: nada a assentar")
    }

    /// Sem saber o nível do auto (antes do primeiro turno, ou CLI sem catálogo).
    func testTogglingAutoOffWithoutKnownLevelPicksTheMiddle() {
        let dial = EffortDial(levels: levels, current: nil, tint: .purple)
        XCTAssertEqual(label(of: dial), "")
        dial.toggleAuto()
        XCTAssertEqual(dial.value, "high", "o do meio de cinco")
    }

    func testTogglingAutoOnFromALevel() {
        let dial = EffortDial(levels: levels, current: "max", autoLevel: "medium", tint: .purple)
        dial.toggleAuto()
        XCTAssertTrue(dial.isAuto)
        XCTAssertEqual(slider(of: dial).integerValue, 1)
        XCTAssertEqual(label(of: dial), "medium…")
    }

    /// Mexer na barra em auto escolhe o nível e desliga o auto, mesmo sem sair
    /// do lugar: clicar no botão sobre o nível que já aparece é escolhê-lo.
    func testTouchingTheSliderLeavesAuto() {
        let dial = EffortDial(levels: levels, current: nil, autoLevel: "high", tint: .purple)
        let bar = slider(of: dial)
        _ = bar.target?.perform(bar.action, with: bar)
        XCTAssertFalse(dial.isAuto)
        XCTAssertEqual(dial.value, "high")
    }

    /// Modelo sem esforço: não há o que ligar.
    func testNoEffortModelHasNoAutoPill() {
        let dial = EffortDial(levels: [], current: nil, tint: .purple)
        XCTAssertNil(pill(of: dial))
        XCTAssertEqual(label(of: dial), "sem esforço")
        XCTAssertFalse(slider(of: dial).isEnabled)
    }

    private func slider(of dial: EffortDial) -> NSSlider {
        dial.subviews.compactMap { $0 as? NSSlider }.first!
    }

    private func pill(of dial: EffortDial) -> HandButton? {
        dial.subviews.compactMap { $0 as? HandButton }.first
    }

    private func label(of dial: EffortDial) -> String? {
        dial.subviews.compactMap { $0 as? NSTextField }.first?.stringValue
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

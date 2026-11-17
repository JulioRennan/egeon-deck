import AppKit
import XCTest
@testable import EgeonDeck

/// A borda da bancada que parou: só existe enquanto ligada, gira nos dois tons
/// e acompanha o tamanho de quem a carrega.
final class AttentionRingTests: XCTestCase {
    private func ringLayer(in host: NSView) -> CALayer? {
        host.layer?.sublayers?.first { $0.zPosition == 50 }
    }

    func testHiddenUntilTurnedOn() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let ring = AttentionRing(host: host, cornerRadius: 7)
        ring.layout()
        XCTAssertEqual(ringLayer(in: host)?.isHidden, true)
        ring.tone = .asking
        XCTAssertEqual(ringLayer(in: host)?.isHidden, false)
        ring.tone = nil
        XCTAssertEqual(ringLayer(in: host)?.isHidden, true)
    }

    private func spins(_ layer: CALayer?) -> Bool {
        guard let layer else { return false }
        if !(layer.animationKeys() ?? []).isEmpty { return true }
        return (layer.sublayers ?? []).contains { spins($0) }
    }

    func testBothTonesSpinAndOffStops() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let ring = AttentionRing(host: host, cornerRadius: 7)
        ring.layout()
        let moves = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ring.tone = .done
        XCTAssertEqual(ringLayer(in: host)?.isHidden, false)
        XCTAssertEqual(spins(ringLayer(in: host)), moves)
        ring.tone = .asking
        XCTAssertEqual(spins(ringLayer(in: host)), moves)
        ring.tone = nil
        XCTAssertFalse(spins(ringLayer(in: host)))
    }

    func testFollowsTheHostSize() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let ring = AttentionRing(host: host, cornerRadius: 7)
        host.frame.size = NSSize(width: 120, height: 26)
        ring.layout()
        XCTAssertEqual(ringLayer(in: host)?.frame, host.bounds)
    }

    func testOrangeBeatsGreen() {
        XCTAssertNil(AttentionRing.tone(for: ActivitySummary(working: 2)))
        XCTAssertEqual(AttentionRing.tone(for: ActivitySummary(done: 1)), .done)
        XCTAssertEqual(AttentionRing.tone(for: ActivitySummary(attention: 1, done: 3)), .asking)
    }
}

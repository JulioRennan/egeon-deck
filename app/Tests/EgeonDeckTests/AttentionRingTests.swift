import AppKit
import XCTest
@testable import EgeonDeck

/// A borda que gira na bancada que precisa de você: só existe enquanto ligada,
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
        ring.isOn = true
        XCTAssertEqual(ringLayer(in: host)?.isHidden, false)
        ring.isOn = false
        XCTAssertEqual(ringLayer(in: host)?.isHidden, true)
    }

    func testFollowsTheHostSize() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let ring = AttentionRing(host: host, cornerRadius: 7)
        host.frame.size = NSSize(width: 120, height: 26)
        ring.layout()
        XCTAssertEqual(ringLayer(in: host)?.frame, host.bounds)
    }
}

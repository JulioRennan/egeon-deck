import XCTest
@testable import EgeonDeck

/// O zoom de enquadrar: cabe com margem, nunca amplia além de 100%.
final class CanvasFitTests: XCTestCase {
    func testFitsWideContentByWidth() {
        let zoom = CanvasContainer.fitZoom(for: NSRect(x: 0, y: 0, width: 2000, height: 500),
                                           in: NSSize(width: 1120, height: 800))
        // 1120 − 2·60 = 1000 útil para 2000 de conteúdo.
        XCTAssertEqual(zoom, 0.5, accuracy: 0.001)
    }

    func testNeverZoomsInPastOneHundred() {
        let zoom = CanvasContainer.fitZoom(for: NSRect(x: 40, y: 40, width: 300, height: 200),
                                           in: NSSize(width: 1600, height: 1000))
        XCTAssertEqual(zoom, 1)
    }

    func testClampsToMinimumStep() {
        let zoom = CanvasContainer.fitZoom(for: NSRect(x: 0, y: 0, width: 50_000, height: 100),
                                           in: NSSize(width: 1000, height: 800))
        XCTAssertEqual(zoom, CanvasContainer.zoomSteps.first!)
    }

    func testDegenerateInputsFallBackToOne() {
        XCTAssertEqual(CanvasContainer.fitZoom(for: .zero, in: NSSize(width: 800, height: 600)), 1)
        XCTAssertEqual(CanvasContainer.fitZoom(for: NSRect(x: 0, y: 0, width: 100, height: 100),
                                               in: NSSize(width: 50, height: 50)), 1)
    }
}

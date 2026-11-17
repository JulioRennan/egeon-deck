import XCTest
@testable import EgeonDeck

/// O canvas é infinito para os quatro lados: à esquerda e no topo deslocando o
/// mundo (`makeSpace`), à direita e embaixo só crescendo o documento.
@MainActor
final class CanvasDocumentGrowthTests: XCTestCase {
    private func makeCanvas() -> CanvasContainer {
        let canvas = CanvasContainer(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        canvas.needsLayout = true
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    func testPanPastRightEdgeGrowsDocument() {
        let canvas = makeCanvas()
        let before = canvas.doc.frame.size
        let viewport = canvas.scroll.contentView.bounds.size
        XCTAssertEqual(viewport.width, 1000)

        canvas.extendDocument(toShow: NSPoint(x: before.width + 300, y: 0))

        XCTAssertEqual(canvas.doc.frame.width, before.width + 300 + viewport.width)
        XCTAssertEqual(canvas.doc.frame.height, before.height)
    }

    func testPanPastBottomEdgeGrowsDocument() {
        let canvas = makeCanvas()
        let before = canvas.doc.frame.size
        let viewport = canvas.scroll.contentView.bounds.size

        canvas.extendDocument(toShow: NSPoint(x: 0, y: before.height + 50))

        XCTAssertEqual(canvas.doc.frame.width, before.width)
        XCTAssertEqual(canvas.doc.frame.height, before.height + 50 + viewport.height)
    }

    func testDocumentNeverShrinks() {
        let canvas = makeCanvas()
        let before = canvas.doc.frame.size
        canvas.extendDocument(toShow: .zero)
        canvas.growDocument(toAtLeast: NSSize(width: 10, height: 10))
        XCTAssertEqual(canvas.doc.frame.size, before)
    }

    func testGrowthStopsAtCeiling() {
        let canvas = makeCanvas()
        let far = CanvasContainer.maxDocumentSize * 2
        canvas.extendDocument(toShow: NSPoint(x: far, y: far))
        XCTAssertEqual(canvas.doc.frame.width, CanvasContainer.maxDocumentSize)
        XCTAssertEqual(canvas.doc.frame.height, CanvasContainer.maxDocumentSize)
    }
}

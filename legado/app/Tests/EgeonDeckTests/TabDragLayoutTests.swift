import XCTest
@testable import EgeonDeck

/// A conta do arrasto da faixa. O que estes testes seguram é o tremor: com
/// larguras diferentes, um critério mal escolhido troca as abas duas vezes no
/// mesmo movimento.
final class TabDragLayoutTests: XCTestCase {
    /// Três abas de larguras diferentes, como na vida real (o nome manda).
    private let widths: [CGFloat] = [100, 160, 120]
    private let start: CGFloat = 10
    private let gap: CGFloat = 4

    private func center(of index: Int) -> CGFloat {
        let xs = TabDragLayout.offsets(widths: widths, start: start, gap: gap)
        return xs[index] + widths[index] / 2
    }

    func testOffsetsStackWithTheGap() {
        XCTAssertEqual(TabDragLayout.offsets(widths: widths, start: start, gap: gap),
                       [10, 114, 278])
    }

    func testStandingStillKeepsThePosition() {
        for i in widths.indices {
            XCTAssertEqual(TabDragLayout.destination(center: center(of: i), dragging: i,
                                                     widths: widths, start: start, gap: gap), i)
        }
    }

    /// Só troca depois de passar o CENTRO da vizinha — encostar não basta.
    func testTouchingTheNeighbourIsNotEnough() {
        let quase = center(of: 1) - 1
        XCTAssertEqual(TabDragLayout.destination(center: quase, dragging: 0, widths: widths,
                                                 start: start, gap: gap), 0)
        let passou = center(of: 1) + 1
        XCTAssertEqual(TabDragLayout.destination(center: passou, dragging: 0, widths: widths,
                                                 start: start, gap: gap), 1)
    }

    func testDraggingToTheEndAndToTheStart() {
        XCTAssertEqual(TabDragLayout.destination(center: 10_000, dragging: 0, widths: widths,
                                                 start: start, gap: gap), 2)
        XCTAssertEqual(TabDragLayout.destination(center: -10_000, dragging: 2, widths: widths,
                                                 start: start, gap: gap), 0)
    }

    /// Arrastar para fora da faixa não inventa índice: prende nas pontas.
    func testBeyondTheEdgesClampsInsteadOfOverflowing() {
        let alvo = TabDragLayout.destination(center: 99_999, dragging: 1, widths: widths,
                                             start: start, gap: gap)
        XCTAssertEqual(alvo, 2)
        XCTAssertTrue(widths.indices.contains(alvo))
    }

    func testMovedTakesOutAndPutsBackIn() {
        XCTAssertEqual(TabDragLayout.moved(["a", "b", "c"], from: 0, to: 2), ["b", "c", "a"])
        XCTAssertEqual(TabDragLayout.moved(["a", "b", "c"], from: 2, to: 0), ["c", "a", "b"])
        XCTAssertEqual(TabDragLayout.moved(["a", "b", "c"], from: 1, to: 1), ["a", "b", "c"])
        XCTAssertEqual(TabDragLayout.moved(["a", "b", "c"], from: 5, to: 0), ["a", "b", "c"])
        XCTAssertEqual(TabDragLayout.moved([String](), from: 0, to: 0), [])
    }

    /// Índice fora da lista não derruba nem reordena nada — é o estado em que o
    /// arrasto fica se a bancada sair da faixa no meio dele.
    func testUnknownIndexIsInert() {
        XCTAssertEqual(TabDragLayout.destination(center: 50, dragging: 9, widths: widths,
                                                 start: start, gap: gap), 9)
    }
}

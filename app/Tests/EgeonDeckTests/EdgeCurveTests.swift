import XCTest
@testable import EgeonDeck

/// Qual rota a aresta toma entre dois cards. Coordenadas do documento do
/// canvas, flipped: y cresce para baixo.
final class EdgeCurveTests: XCTestCase {
    private let size = NSSize(width: 720, height: 460)
    private func card(_ x: CGFloat, _ y: CGFloat) -> NSRect { NSRect(origin: NSPoint(x: x, y: y), size: size) }

    /// O caso da captura: um card embaixo do outro, na mesma coluna. Antes a
    /// linha saía pela direita do de cima, dava a volta por baixo do de baixo
    /// e entrava pela esquerda dele.
    func testStackedCardsConnectBottomToTop() {
        let upper = card(784, 40), lower = card(784, 524)
        for (a, b) in [(upper, lower), (lower, upper)] {
            guard case let .stacked(from, to) = EdgeCurve.route(from: a, to: b) else {
                return XCTFail("coluna virou \(EdgeCurve.route(from: a, to: b))")
            }
            XCTAssertEqual(from.y, upper.maxY, "sai da base do de cima")
            XCTAssertEqual(to.y, lower.minY, "entra no topo do de baixo")
            XCTAssertEqual(from.x, to.x, "reta, no meio da faixa comum")
        }
        XCTAssertTrue(EdgeCurve.prefersDirect(from: upper, to: lower))
        XCTAssertFalse(EdgeCurve.prefersDirect(from: lower, to: upper))
    }

    func testSlightlyShiftedColumnIsStillStacked() {
        guard case .stacked = EdgeCurve.route(from: card(100, 40), to: card(300, 600)) else {
            return XCTFail("deslocado menos que meia largura ainda é coluna")
        }
    }

    func testSideBySideStaysDirect() {
        guard case .direct = EdgeCurve.route(from: card(40, 40), to: card(784, 40)) else {
            return XCTFail()
        }
        // Na diagonal, sem faixa comum: continua lateral.
        guard case .direct = EdgeCurve.route(from: card(40, 40), to: card(784, 524)) else {
            return XCTFail()
        }
    }

    func testTargetBehindAndNotStackedStillLoops() {
        guard case .loop = EdgeCurve.route(from: card(784, 40), to: card(40, 40)) else {
            return XCTFail("destino à esquerda, mesma linha: volta por baixo")
        }
    }

    func testOverlappingCardsDoNotStack() {
        // Um sobre o outro mas se tocando: não há vão para a linha vertical.
        guard case .stacked = EdgeCurve.route(from: card(40, 40), to: card(40, 300)) else { return }
        XCTFail("cards sobrepostos não ganham rota vertical")
    }

    func testStackedEndpointsPointAlongTheColumn() {
        let route = EdgeCurve.route(from: card(784, 40), to: card(784, 524))
        let ends = EdgeCurve.endpoints(route)
        XCTAssertEqual(ends.endTangent.dy, 1, accuracy: 0.001, "a ponta entra de cima para baixo")
        XCTAssertEqual(ends.startTangent.dy, -1, accuracy: 0.001, "a ponta de volta aponta para cima")
    }

    /// Os controles da seta (direção, limite, remover) ficam NO MEIO da linha
    /// de pé, e acima do meio na deitada — onde não a cobrem.
    func testControlsCenterOnAVerticalEdge() {
        let stacked = EdgeCurve.route(from: card(784, 40), to: card(784, 664))
        let (mid, _) = EdgeCurve.midpoint(stacked)
        let top = EdgeCurve.controlsTop(route: stacked, midpoint: mid, height: 24, lift: 10)
        XCTAssertEqual(top + 12, mid.y, accuracy: 0.001, "centrados no ponto médio")
        XCTAssertEqual(mid.y, (40 + 460 + 664) / 2, accuracy: 1, "e o ponto médio é o meio do vão")

        let side = EdgeCurve.route(from: card(40, 40), to: card(1100, 40))
        let (sideMid, _) = EdgeCurve.midpoint(side)
        XCTAssertEqual(EdgeCurve.controlsTop(route: side, midpoint: sideMid, height: 24, lift: 10),
                       sideMid.y - 34, accuracy: 0.001, "deitada: acima da linha")
    }
}


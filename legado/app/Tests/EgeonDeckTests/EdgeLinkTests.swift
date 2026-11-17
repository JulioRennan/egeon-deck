import XCTest
@testable import EgeonDeck

/// A ligação como a tela vê (EdgeLink) e a aresta como as guardas leem
/// (EdgeConfig) — ADR-012 e ADR-028.
final class EdgeLinkTests: XCTestCase {
    // O par é guardado em ordem de nome para ter identidade estável; quem
    // desenha decide a origem do traçado depois.
    func testPairOrdersByName() {
        XCTAssertTrue(EdgeLink.pair("zeta", "alfa") == ("alfa", "zeta"))
        XCTAssertTrue(EdgeLink.pair("alfa", "zeta") == ("alfa", "zeta"))
    }

    func testCollapseJoinsBothDirectionsIntoOneLink() {
        let links = EdgeLink.collapse([
            EdgeConfig(from: "b", to: "a"),
            EdgeConfig(from: "a", to: "b"),
        ])
        XCTAssertEqual(links.count, 1)
        XCTAssertTrue(links[0].isBidirectional)
        XCTAssertEqual(links[0].a, "a")
        XCTAssertEqual(links[0].b, "b")
    }

    // Com os sentidos divergindo no arquivo editado à mão, vale o limite de
    // a→b — independente da ordem em que as arestas aparecem.
    func testCollapseLimitOfAToBWins() {
        let links = EdgeLink.collapse([
            EdgeConfig(from: "b", to: "a", maxSends: 9),
            EdgeConfig(from: "a", to: "b", maxSends: 3),
        ])
        XCTAssertEqual(links[0].maxSends, 3)
    }

    // O botão da linha: ida → ida e volta → volta → ida. Nunca passa por
    // "nenhum sentido" — para isso existe o X.
    func testCycledNeverReachesNoDirection() {
        let ida = EdgeLink(a: "a", b: "b", aToB: true, bToA: false, maxSends: nil)
        let idaEVolta = ida.cycled()
        XCTAssertTrue(idaEVolta.aToB && idaEVolta.bToA)

        let volta = idaEVolta.cycled()
        XCTAssertTrue(!volta.aToB && volta.bToA)

        let deNovoIda = volta.cycled()
        XCTAssertTrue(deNovoIda.aToB && !deNovoIda.bToA)
    }

    func testEdgesMaterializesOnlyActiveDirections() {
        let volta = EdgeLink(a: "a", b: "b", aToB: false, bToA: true, maxSends: 5)
        let edges = volta.edges
        XCTAssertEqual(edges, [EdgeConfig(from: "b", to: "a")])
        XCTAssertEqual(edges[0].maxSends, 5)
    }

    // Igualdade só pelo par: trocar a direção é a MESMA linha mudando de
    // estado — o realce sob o cursor sobrevive ao clique.
    func testLinkEqualityIgnoresDirection() {
        let x = EdgeLink(a: "a", b: "b", aToB: true, bToA: false, maxSends: nil)
        let y = EdgeLink(a: "a", b: "b", aToB: false, bToA: true, maxSends: 7)
        XCTAssertEqual(x, y)
    }

    // Chave ausente herda o padrão (2); null explícito desliga o limite da
    // seta. O Decodable sintetizado erraria os dois — por isso o init à mão.
    func testDecodeDistinguishesAbsentFromNull() throws {
        let absent = try JSONDecoder().decode(EdgeConfig.self,
            from: Data(#"{"from":"a","to":"b"}"#.utf8))
        XCTAssertEqual(absent.maxSends, EdgeConfig.defaultSends)

        let explicitNull = try JSONDecoder().decode(EdgeConfig.self,
            from: Data(#"{"from":"a","to":"b","maxSends":null}"#.utf8))
        XCTAssertNil(explicitNull.maxSends)
    }

    // A igualdade ignora o limite: é o que faz `contains` continuar achando a
    // aresta depois de você editar o número.
    func testEdgeEqualityIgnoresLimit() {
        XCTAssertEqual(EdgeConfig(from: "a", to: "b", maxSends: 1),
                       EdgeConfig(from: "a", to: "b", maxSends: 99))
    }
}

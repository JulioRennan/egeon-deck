import XCTest
@testable import EgeonDeck

/// A faixa montada de verdade: as abas têm de existir, caber e ficar dentro da
/// área visível — o defeito que isto pega é a faixa desenhada e vazia.
@MainActor
final class WorkbenchTabsBarTests: XCTestCase {
    private func tab(_ name: String, active: Bool = false) -> WorkbenchTab {
        WorkbenchTab(id: name, name: name, isActive: active, summary: ActivitySummary())
    }

    private func bar(_ tabs: [WorkbenchTab], width: CGFloat = 900) -> WorkbenchTabsBar {
        let bar = WorkbenchTabsBar(frame: NSRect(x: 0, y: 0, width: width,
                                                 height: WorkbenchTabsBar.height))
        bar.show(tabs)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    private func pills(_ bar: WorkbenchTabsBar) -> [WorkbenchTabView] {
        bar.subviews.compactMap { $0 as? WorkbenchTabView }
    }

    func testEveryTabGetsAVisiblePill() {
        let bar = bar([tab("deck", active: true), tab("nexus"), tab("revisor")])
        let drawn = pills(bar)
        XCTAssertEqual(drawn.count, 3, "faixa montada sem pastilha nenhuma")
        for pill in drawn {
            XCTAssertGreaterThan(pill.frame.width, 0, "\(pill.id) sem largura")
            XCTAssertGreaterThan(pill.frame.height, 0, "\(pill.id) sem altura")
            let inWindow = pill.convert(pill.bounds, to: bar)
            XCTAssertGreaterThanOrEqual(inWindow.minY, 0, "\(pill.id) acima da faixa")
            XCTAssertLessThanOrEqual(inWindow.maxY, WorkbenchTabsBar.height + 0.5,
                                     "\(pill.id) abaixo da faixa")
            XCTAssertLessThan(inWindow.minX, bar.bounds.width, "\(pill.id) fora da faixa")
        }
    }

    /// As pastilhas não se empilham no mesmo x.
    func testTabsAreLaidOutSideBySide() {
        let bar = bar([tab("um"), tab("dois"), tab("três")])
        let xs = pills(bar).map { $0.convert($0.bounds, to: bar).minX }.sorted()
        XCTAssertEqual(Set(xs).count, 3, "pastilhas empilhadas no mesmo lugar")
        XCTAssertEqual(xs, xs.sorted())
    }

    /// Nada aberto: a faixa some, para não comer altura do canvas.
    func testEmptyBarHidesItself() {
        XCTAssertTrue(bar([]).isHidden)
        XCTAssertFalse(bar([tab("a"), tab("b")]).isHidden)
    }

    /// Reordenar leva a pastilha para o outro lugar de verdade — é o mesmo
    /// caminho que o arrasto usa no fim do movimento.
    func testMovingATabRearrangesThePills() {
        let bar = bar([tab("a", active: true), tab("b"), tab("c")])
        XCTAssertEqual(pills(bar).map(\.id), ["a", "b", "c"])

        XCTAssertEqual(bar.move(id: "a", to: 2), ["a", "b", "c"].isEmpty ? [] : ["b", "c", "a"])
        bar.layoutSubtreeIfNeeded()
        let xs = pills(bar).sorted { $0.frame.minX < $1.frame.minX }.map(\.id)
        XCTAssertEqual(xs, ["b", "c", "a"], "a ordem na tela não acompanhou")
    }

    func testMovingToAnImpossiblePlaceDoesNothing() {
        let bar = bar([tab("a"), tab("b")])
        XCTAssertNil(bar.move(id: "a", to: 9))
        XCTAssertNil(bar.move(id: "sumida", to: 0))
        XCTAssertEqual(pills(bar).map(\.id), ["a", "b"])
    }

    /// Quem manda na ordem é o app: um `show` na ordem nova reordena as
    /// pastilhas que já existem, sem recriar nenhuma — recriar perde o hover e o
    /// cache do badge, e o deslize vira um piscar seco.
    func testReorderingFromTheAppKeepsTheSameViews() {
        let bar = bar([tab("a"), tab("b"), tab("c")])
        let antes = Dictionary(uniqueKeysWithValues: pills(bar).map { ($0.id, ObjectIdentifier($0)) })

        bar.show([tab("c"), tab("a"), tab("b")])
        bar.layoutSubtreeIfNeeded()

        let depois = pills(bar).sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(depois.map(\.id), ["c", "a", "b"])
        for pill in depois {
            XCTAssertEqual(ObjectIdentifier(pill), antes[pill.id], "\(pill.id) foi recriada")
        }
    }

    /// Trocar só o estado não remonta as pastilhas (a identidade delas é o id).
    func testStateChangeKeepsTheSameViews() {
        let bar = bar([tab("a", active: true), tab("b")])
        let before = pills(bar).map(ObjectIdentifier.init)
        var busy = ActivitySummary(); busy.working = 1
        bar.show([WorkbenchTab(id: "a", name: "a", isActive: true, summary: busy),
                  WorkbenchTab(id: "b", name: "b", isActive: false, summary: ActivitySummary())])
        bar.layoutSubtreeIfNeeded()
        XCTAssertEqual(pills(bar).map(ObjectIdentifier.init), before)
    }
}

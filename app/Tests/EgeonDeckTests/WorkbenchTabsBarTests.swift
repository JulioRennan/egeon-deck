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

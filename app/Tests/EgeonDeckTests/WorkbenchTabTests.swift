import XCTest
@testable import EgeonDeck

/// A faixa de abas: o que ela mostra sai de "quem está aberto" cruzado com o
/// estado dos terminais, e nada mais. Sem tela.
final class WorkbenchTabTests: XCTestCase {
    private func bench(_ name: String) -> WorkbenchConfig {
        WorkbenchConfig(name: name, path: "~/\(name)", nodes: [])
    }

    private func working(_ n: Int = 1) -> ActivitySummary {
        var s = ActivitySummary(); s.working = n; return s
    }
    private func asking() -> ActivitySummary {
        var s = ActivitySummary(); s.attention = 1; return s
    }
    private func done() -> ActivitySummary {
        var s = ActivitySummary(); s.done = 1; return s
    }

    func testTabsFollowTheOrderYouOpenedThem() {
        let configs = [bench("um"), bench("dois"), bench("três")]
        let open = [configs[2].id, configs[0].id]
        let tabs = WorkbenchTabs.build(open: open, configs: configs, active: configs[0].id,
                                       activity: [:])
        XCTAssertEqual(tabs.map(\.name), ["três", "um"], "a faixa não é a ordem da lateral")
        XCTAssertEqual(tabs.map(\.isActive), [false, true])
    }

    /// Só o que está aberto entra — é a diferença entre a faixa e o catálogo.
    func testClosedWorkbenchesAreNotTabs() {
        let configs = [bench("um"), bench("dois")]
        let tabs = WorkbenchTabs.build(open: [configs[1].id], configs: configs,
                                       active: configs[1].id, activity: [:])
        XCTAssertEqual(tabs.map(\.name), ["dois"])
    }

    /// Bancada removida enquanto a aba dela estava aberta não vira aba órfã.
    func testTabOfARemovedWorkbenchDisappears() {
        let configs = [bench("um")]
        let tabs = WorkbenchTabs.build(open: ["sumida", configs[0].id], configs: configs,
                                       active: nil, activity: [:])
        XCTAssertEqual(tabs.map(\.name), ["um"])
    }

    /// Os três avisos convivem e a ordem é fixa (ADR-024): uma bancada pode ter
    /// um agente trabalhando, um perguntando e um que já acabou.
    func testAllThreeBadgesShowTogetherInAFixedOrder() {
        let configs = [bench("deck")]
        var mixed = ActivitySummary()
        mixed.working = 1; mixed.attention = 1; mixed.done = 2
        let tabs = WorkbenchTabs.build(open: [configs[0].id], configs: configs,
                                       active: nil, activity: ["deck": mixed])
        XCTAssertEqual(tabs[0].line, "  deck ⠿ ●! ●")
        XCTAssertTrue(tabs[0].isWorking)
        XCTAssertTrue(tabs[0].wantsAttention)
        XCTAssertTrue(tabs[0].isDone)
    }

    /// Trabalho de fundo tem a ampulheta própria, não o spinner de quem
    /// trabalha (ADR-063).
    func testBackgroundShowsTheHourglassNotTheSpinner() {
        let configs = [bench("deck")]
        var summary = ActivitySummary()
        summary.background = 1
        let tabs = WorkbenchTabs.build(open: [configs[0].id], configs: configs,
                                       active: nil, activity: ["deck": summary])
        XCTAssertEqual(tabs[0].line, "  deck ⏳")
        XCTAssertFalse(tabs[0].isWorking)
    }

    /// O estado vem por NOME de bancada (é como o Dispatcher agrega), e a aba é
    /// por id: a ponte é a lista de configs, e renomear não pode apagar o badge.
    func testActivityIsMatchedByWorkbenchName() {
        let configs = [bench("nexus")]
        let tabs = WorkbenchTabs.build(open: [configs[0].id], configs: configs,
                                       active: nil, activity: ["nexus": asking()])
        XCTAssertTrue(tabs[0].wantsAttention)
        XCTAssertEqual(tabs[0].line, "  nexus ●!")
    }

    func testQuietWorkbenchHasNoBadge() {
        let configs = [bench("quieta")]
        let tabs = WorkbenchTabs.build(open: [configs[0].id], configs: configs,
                                       active: configs[0].id, activity: ["quieta": ActivitySummary()])
        XCTAssertEqual(tabs[0].line, "▸ quieta")
    }

    func testWorkingAndDoneAreDifferentBadges() {
        let configs = [bench("a"), bench("b")]
        let tabs = WorkbenchTabs.build(open: configs.map(\.id), configs: configs, active: nil,
                                       activity: ["a": working(2), "b": done()])
        XCTAssertTrue(tabs[0].isWorking)
        XCTAssertFalse(tabs[0].isDone)
        XCTAssertTrue(tabs[1].isDone)
        XCTAssertFalse(tabs[1].isWorking)
    }

    /// Fechar leva para a vizinha da direita; na última, para a da esquerda.
    func testClosingATabPicksTheNeighbour() {
        let open = ["a", "b", "c"]
        XCTAssertEqual(WorkbenchTabs.neighbour(of: "a", in: open), "b")
        XCTAssertEqual(WorkbenchTabs.neighbour(of: "b", in: open), "c")
        XCTAssertEqual(WorkbenchTabs.neighbour(of: "c", in: open), "b")
        XCTAssertNil(WorkbenchTabs.neighbour(of: "a", in: ["a"]))
        XCTAssertNil(WorkbenchTabs.neighbour(of: "x", in: open))
    }
}

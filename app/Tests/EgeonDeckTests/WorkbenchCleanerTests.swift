import XCTest
@testable import EgeonDeck

/// Limpar a bancada é uma sequência com tempo: manda o `clear`, espera os
/// agentes assentarem e só ENTÃO arquiva (ADR-059). Arquivar junto com o
/// disparo era o que deixava o fim do turno velho cair na conversa nova.
final class WorkbenchCleanerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_787_679_000)

    private func agent(_ id: String, clear: String? = "/clear") -> WorkbenchCleaner.Agent {
        .init(id: id, address: "deck/\(id)", command: clear)
    }

    func testArchivesOnlyAfterTheAgentsSettle() {
        var busy = Set(["front"])
        var archives = 0
        var finished: WorkbenchCleaner.Result?
        let cleaner = WorkbenchCleaner(
            agents: [agent("front"), agent("revisor")],
            dispatch: { _ in true },
            isBusy: { busy.contains($0.id) },
            archive: { archives += 1; return (URL(fileURLWithPath: "/tmp/chat.jsonl"), nil) },
            onFinish: { finished = $0 },
            grace: 2, timeout: 45)

        cleaner.start(now: t0)
        XCTAssertEqual(archives, 0, "arquivou no disparo — é o bug")

        // Dentro da folga ninguém conta como assentado: o texto acabou de ser
        // colado e o gancho de início de turno ainda não chegou.
        busy = []
        cleaner.tick(now: t0.addingTimeInterval(1))
        XCTAssertEqual(archives, 0, "arquivou antes de a injeção sequer chegar à TUI")

        busy = ["front"]
        cleaner.tick(now: t0.addingTimeInterval(5))
        XCTAssertEqual(archives, 0, "um agente ainda trabalhando e já arquivou")
        XCTAssertEqual(cleaner.phase, .clearing(remaining: 1))

        busy = []
        cleaner.tick(now: t0.addingTimeInterval(6))
        XCTAssertEqual(archives, 1)
        XCTAssertEqual(cleaner.phase, .done)
        XCTAssertEqual(finished?.cleared, ["front", "revisor"])
        XCTAssertEqual(finished?.timedOut, false)
        XCTAssertNotNil(finished?.chat)
    }

    func testStuckAgentDoesNotHoldTheCleanupForever() {
        var finished: WorkbenchCleaner.Result?
        var archives = 0
        let cleaner = WorkbenchCleaner(
            agents: [agent("front")],
            dispatch: { _ in true },
            isBusy: { _ in true },
            archive: { archives += 1; return (nil, nil) },
            onFinish: { finished = $0 },
            grace: 2, timeout: 30)

        cleaner.start(now: t0)
        cleaner.tick(now: t0.addingTimeInterval(29))
        XCTAssertEqual(archives, 0)
        cleaner.tick(now: t0.addingTimeInterval(31))
        XCTAssertEqual(archives, 1, "o teto existe para o loading não ficar eterno")
        XCTAssertEqual(finished?.timedOut, true)
    }

    /// CLI sem `clear` declarado é pulado — e não pode segurar a espera, senão
    /// bancada só de shell ficava com a cortina até o teto.
    func testAgentsWithoutClearAreSkippedAndDoNotDelayArchiving() {
        var archives = 0
        var finished: WorkbenchCleaner.Result?
        var phases: [WorkbenchCleaner.Phase] = []
        let cleaner = WorkbenchCleaner(
            agents: [agent("shell", clear: nil), agent("outro", clear: "")],
            dispatch: { _ in XCTFail("nada a despachar"); return false },
            isBusy: { _ in true },
            archive: { archives += 1; return (nil, URL(fileURLWithPath: "/tmp/trace.md")) },
            onPhase: { phases.append($0) },
            onFinish: { finished = $0 },
            grace: 2, timeout: 30)

        cleaner.start(now: t0)
        XCTAssertEqual(archives, 1)
        XCTAssertEqual(finished?.skipped, ["shell", "outro"])
        XCTAssertTrue(finished?.cleared.isEmpty == true)
        XCTAssertEqual(phases.last, .done)
        XCTAssertTrue(phases.contains(.archiving), "a cortina precisa dizer que está arquivando")
    }

    /// Quem parou pedindo permissão depende de VOCÊ: a fila dele não anda com a
    /// caixa na tela, e esperar era ficar com a cortina de pé até o teto — visto
    /// no DEV, 45 s por um agente que só queria um "sim".
    func testAgentAskingForPermissionIsNotWaitedFor() {
        XCTAssertFalse(WorkbenchCleaner.isBusy(activity: .asking, pending: 1))
        XCTAssertTrue(WorkbenchCleaner.isBusy(activity: .working, pending: 0))
        XCTAssertTrue(WorkbenchCleaner.isBusy(activity: .starting, pending: 0))
        XCTAssertTrue(WorkbenchCleaner.isBusy(activity: .waiting, pending: 1),
                      "o `clear` ainda na fila é trabalho por fazer")
        XCTAssertFalse(WorkbenchCleaner.isBusy(activity: .waiting, pending: 0))
        XCTAssertFalse(WorkbenchCleaner.isBusy(activity: .ready, pending: 0))
    }

    /// Agente que não está mais no Dispatcher (terminal fechado) entra em
    /// pulados pelo próprio `dispatch`, e a limpeza segue.
    func testDispatchFailureCountsAsSkipped() {
        var finished: WorkbenchCleaner.Result?
        let cleaner = WorkbenchCleaner(
            agents: [agent("front"), agent("sumido")],
            dispatch: { $0.id != "sumido" },
            isBusy: { _ in false },
            archive: { (nil, nil) },
            onFinish: { finished = $0 },
            grace: 0, timeout: 30)

        cleaner.start(now: t0)
        cleaner.tick(now: t0.addingTimeInterval(1))
        XCTAssertEqual(finished?.cleared, ["front"])
        XCTAssertEqual(finished?.skipped, ["sumido"])
    }
}

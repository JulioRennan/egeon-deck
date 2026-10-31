import XCTest
@testable import EgeonDeck

final class PromptQueueTests: XCTestCase {
    func testDestinationFallsBackToFirstLinked() {
        var queue = PromptQueue()
        XCTAssertNil(queue.destination(among: []))
        XCTAssertEqual(queue.destination(among: ["dev", "front"]), "dev")
        queue.target = "front"
        XCTAssertEqual(queue.destination(among: ["dev", "front"]), "front")
        // Aresta apagada: o escolhido some, vale o primeiro que sobrou.
        XCTAssertEqual(queue.destination(among: ["dev"]), "dev")
    }

    func testMoveStaysInsideTheList() {
        var queue = PromptQueue(items: ["a", "b", "c"].map { QueueItem(id: $0, title: $0) })
        queue.move("a", by: -1)
        XCTAssertEqual(queue.items.map(\.id), ["a", "b", "c"])
        queue.move("a", by: 1)
        XCTAssertEqual(queue.items.map(\.id), ["b", "a", "c"])
        queue.move("c", by: -5)
        XCTAssertEqual(queue.items.map(\.id), ["c", "b", "a"])
    }

    func testDragMoveCountsOnlyTheRowsThatStayed() {
        var queue = PromptQueue(items: ["a", "b", "c", "d"].map { QueueItem(id: $0, title: $0) })
        // "a" solto depois de "c": entre as que ficaram (b, c, d), posição 2.
        queue.move("a", to: 2)
        XCTAssertEqual(queue.items.map(\.id), ["b", "c", "a", "d"])
        queue.move("d", to: 0)
        XCTAssertEqual(queue.items.map(\.id), ["d", "b", "c", "a"])
        queue.move("b", to: 99)
        XCTAssertEqual(queue.items.map(\.id), ["d", "c", "a", "b"])
    }

    func testRunnerWaitsForWorkThenFinishesAndSendsNextOnlyInAuto() {
        var queue = PromptQueue(items: [QueueItem(id: "1", title: "um", status: .sent),
                                        QueueItem(id: "2", title: "dois")])
        queue.items[0].sentAt = Date()
        // Parado logo depois do envio, sem ter trabalhado: ainda não é o fim.
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: .waiting, sawWork: false), .init())
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: .working, sawWork: true), .init())
        // Pergunta não é fim de turno: mandar por cima atropelaria a resposta.
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: .asking, sawWork: true), .init())
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: .waiting, sawWork: true),
                       .init(finish: "1", send: nil))
        queue.auto = true
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: .waiting, sawWork: true),
                       .init(finish: "1", send: "2"))
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: .dead, sawWork: true), .init())
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: nil, sawWork: true), .init())
    }

    func testRunnerGivesUpOnLostDelivery() {
        var queue = PromptQueue(items: [QueueItem(id: "1", title: "um", status: .sent)])
        let sent = Date()
        queue.items[0].sentAt = sent
        let later = sent.addingTimeInterval(QueueRunner.lostAfter + 1)
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: .ready, sawWork: false, now: later),
                       .init(finish: "1", send: nil))
    }

    func testRunnerStartsAutoWhenIdleAndNothingInFlight() {
        let queue = PromptQueue(items: [QueueItem(id: "1", title: "um")], auto: true)
        XCTAssertEqual(QueueRunner.step(queue: queue, activity: .ready, sawWork: false),
                       .init(finish: nil, send: "1"))
    }

    // MARK: Controller

    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fila-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private final class World {
        var linked: [QueueController.Linked] = [.init(id: "dev", label: "dev")]
        var activity: Activity? = .ready
        var sent: [(node: String, text: String, images: [String])] = []
        /// O pedido sem o rodapé de comandos da tarefa.
        var bodies: [String] { sent.map { $0.text.components(separatedBy: "\n\n[ED]").first ?? $0.text } }
        var failure: String?
    }

    private func controller(_ world: World) -> QueueController {
        QueueController(store: QueueStore(folder: folder),
                        linked: { world.linked },
                        activity: { _ in world.activity },
                        dispatch: { node, text, images in
                            if let failure = world.failure { return failure }
                            world.sent.append((node, text, images))
                            return nil
                        })
    }

    func testAutoWalksTheQueueOneTurnAtATime() throws {
        let world = World()
        let queue = controller(world)
        queue.add(title: "primeiro")
        queue.add(title: "segundo", notes: "com detalhe")
        // A tarefa em branco é a que você está escrevendo: não é a próxima.
        let blank = queue.add(title: "  ")

        queue.setAuto(true)
        XCTAssertEqual(world.bodies, ["primeiro"])
        XCTAssertEqual(queue.queue.items.map(\.status), [.sent, .pending, .pending])

        // O agente pega o primeiro, trabalha, e só ao parar vai o segundo.
        world.activity = .working
        queue.tick()
        XCTAssertEqual(world.sent.count, 1)
        world.activity = .waiting
        queue.tick()
        XCTAssertEqual(world.bodies, ["primeiro", "segundo\n\ncom detalhe"])
        XCTAssertEqual(queue.queue.items.map(\.status), [.done, .sent, .pending])
        queue.dropIfEmpty(blank.id)

        // A fila sobrevive ao app: o disco tem o mesmo que a memória.
        let reloaded = QueueStore(folder: folder).load()
        XCTAssertEqual(reloaded.items.map(\.id), queue.queue.items.map(\.id))
        XCTAssertEqual(reloaded.items.map(\.status), [.done, .sent])
        XCTAssertEqual(reloaded.items.map(\.sentTo), ["dev", "dev"])
        XCTAssertTrue(reloaded.auto)
    }

    func testManualSendWithoutLinkOrWithFailureKeepsItemPending() {
        let world = World()
        world.linked = []
        let queue = controller(world)
        let item = queue.add(title: "pedido")
        XCTAssertNotNil(queue.send(item.id))
        XCTAssertEqual(queue.queue.items.first?.status, .pending)

        world.linked = [.init(id: "dev", label: "dev")]
        world.failure = "terminal desconhecido"
        XCTAssertEqual(queue.send(item.id), "terminal desconhecido")
        XCTAssertEqual(queue.queue.items.first?.status, .pending)

        world.failure = nil
        XCTAssertNil(queue.send(item.id))
        XCTAssertEqual(queue.queue.items.first?.sentTo, "dev")
    }

    func testSendingOverAnInFlightItemClosesIt() {
        let world = World()
        let queue = controller(world)
        let first = queue.add(title: "um")
        let second = queue.add(title: "dois")
        queue.send(first.id)
        queue.send(second.id)
        XCTAssertEqual(queue.queue.items.map(\.status), [.done, .sent])
    }

    func testImagesGoAsAbsolutePathsAndLeaveWithTheItem() throws {
        let world = World()
        let queue = controller(world)
        let name = try XCTUnwrap(queue.store.saveImage(png: Data([0x89, 0x50, 0x4E, 0x47])))
        let item = queue.add(title: "", images: [name])
        queue.send(item.id)
        XCTAssertEqual(world.sent.first?.images, [queue.store.url(of: name).path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.store.url(of: name).path))

        queue.remove(item.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.store.url(of: name).path))
    }

    func testTargetsChangingNotifiesTheView() {
        let world = World()
        let queue = controller(world)
        var changes = 0
        queue.onChange = { changes += 1 }
        queue.tick()
        XCTAssertEqual(changes, 0)
        world.linked.append(.init(id: "front", label: "front"))
        queue.tick()
        XCTAssertEqual(changes, 1)
    }

    func testEnterAfterAnOpenTaskInsertsBelowItAndBlankOnesGoAway() {
        let world = World()
        let queue = controller(world)
        let a = queue.add(title: "a")
        queue.add(title: "c")
        let b = queue.add(title: "", after: a.id)
        XCTAssertEqual(queue.queue.items.map(\.title), ["a", "", "c"])
        XCTAssertEqual(queue.queue.pendingCount, 2)
        queue.dropIfEmpty(a.id)
        XCTAssertEqual(queue.queue.items.count, 3)
        queue.dropIfEmpty(b.id)
        XCTAssertEqual(queue.queue.items.map(\.title), ["a", "c"])
    }

    func testCheckboxMarksDoneByHandAndBack() {
        let world = World()
        let queue = controller(world)
        let item = queue.add(title: "resolvi sozinho")
        queue.toggleDone(item.id)
        XCTAssertEqual(queue.queue.items.first?.status, .done)
        XCTAssertTrue(world.sent.isEmpty)
        queue.toggleDone(item.id)
        XCTAssertEqual(queue.queue.items.first?.status, .pending)
    }

    func testAttachAndDetachImages() throws {
        let world = World()
        let queue = controller(world)
        let item = queue.add(title: "com print")
        let name = try XCTUnwrap(queue.store.saveImage(png: Data([1, 2, 3])))
        queue.attach([name], to: item.id)
        XCTAssertEqual(queue.queue.items.first?.images, [name])
        queue.detach(name, from: item.id)
        XCTAssertEqual(queue.queue.items.first?.images, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.store.url(of: name).path))
    }

    // MARK: Thread

    func testFooterOnlyGoesToAgentsAndCarriesTheShortID() {
        let world = World()
        let queue = controller(world)
        let item = queue.add(title: "conserta o toast")
        queue.send(item.id)
        XCTAssertTrue(world.sent[0].text.hasSuffix(queue.footer(for: item)))
        XCTAssertTrue(world.sent[0].text.contains("egeon task done \(item.shortID)"))

        world.linked = [.init(id: "sh", label: "sh", agent: false)]
        let other = queue.add(title: "ls")
        queue.send(other.id)
        XCTAssertEqual(world.sent[1].text, "ls")
    }

    func testAgentTicksAsksAndNotesByShortID() {
        let world = World()
        let queue = controller(world)
        let item = queue.add(title: "toast atrás do header")
        XCTAssertNotNil(queue.agent("dev", "done", task: "zzzz", text: ""))
        XCTAssertNotNil(queue.agent("dev", "ask", task: item.shortID, text: "  "))

        XCTAssertNil(queue.agent("dev", "note", task: item.shortID.uppercased(), text: "achei no header.css"))
        XCTAssertNil(queue.agent("dev", "ask", task: item.shortID, text: "o header é fixo em todas?"))
        XCTAssertTrue(queue.queue.items[0].awaiting)
        XCTAssertNil(queue.agent("dev", "done", task: item.id, text: ""))
        let done = queue.queue.items[0]
        XCTAssertEqual(done.status, .done)
        XCTAssertFalse(done.awaiting)
        XCTAssertEqual(done.thread.map(\.kind), [.note, .question, .done])
        XCTAssertEqual(done.thread.map(\.author), ["dev", "dev", "dev"])
        XCTAssertEqual(queue.tasks().first?["id"] as? String, item.shortID)
    }

    func testOpenQuestionHoldsTheQueueUntilYouReply() {
        let world = World()
        let queue = controller(world)
        let first = queue.add(title: "primeira")
        queue.add(title: "segunda")
        queue.setAuto(true)
        world.activity = .working
        queue.tick()
        _ = queue.agent("dev", "ask", task: first.shortID, text: "qual navegador?")
        // O agente parou para perguntar: não é fim de tarefa, a fila espera.
        world.activity = .waiting
        queue.tick()
        queue.tick()
        XCTAssertEqual(world.sent.count, 1)
        XCTAssertEqual(queue.queue.items.map(\.status), [.sent, .pending])

        XCTAssertNil(queue.reply(first.id, text: "Safari"))
        XCTAssertEqual(world.sent.count, 2)
        XCTAssertEqual(world.sent[1].node, "dev")
        XCTAssertTrue(world.sent[1].text.contains("primeira"))
        XCTAssertTrue(world.sent[1].text.hasSuffix("Safari"))
        XCTAssertFalse(queue.queue.items[0].awaiting)

        // A resposta é trabalho novo: só depois dele a fila anda.
        world.activity = .working
        queue.tick()
        world.activity = .waiting
        queue.tick()
        XCTAssertEqual(queue.queue.items.map(\.status), [.done, .sent])
    }

    func testCommentBeforeSendingGoesWithTheTask() {
        let world = World()
        let queue = controller(world)
        let item = queue.add(title: "logo pixelado")
        queue.reply(item.id, text: "só no retina")
        XCTAssertTrue(world.sent.isEmpty)
        queue.send(item.id)
        XCTAssertEqual(world.bodies, ["logo pixelado\n\nsó no retina"])
    }

    func testOldFileWithoutThreadStillLoads() throws {
        let json = #"{"items":[{"id":"abc123","title":"t","notes":"","images":[],"status":"pending"}],"auto":false}"#
        let queue = try JSONDecoder().decode(PromptQueue.self, from: Data(json.utf8))
        XCTAssertEqual(queue.items.first?.thread, [])
        XCTAssertEqual(queue.items.first?.awaiting, false)
    }
}

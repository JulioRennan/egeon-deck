import Foundation

/// O que a fila de um nó faz: guardar, editar, mandar e, no automático, andar
/// sozinha a cada fim de turno do agente.
///
/// Dono da fila DESTE nó e do arquivo dela — o `workbenches.json` não guarda
/// item nenhum. O resto chega por closures, como no `EdgeController`: quem
/// está ligado (as arestas são da bancada), o estado do agente e o envio (do
/// `Dispatcher`). É o que deixa o teste rodar sem tela e sem terminal.
final class QueueController {
    struct Linked: Equatable {
        let id: String
        let label: String
        /// Agente lê o rodapé com os comandos da tarefa; shell o executaria.
        var agent = true
    }

    private(set) var queue: PromptQueue
    let store: QueueStore
    /// O nome do nó, que o agente vê no rodapé da tarefa.
    let name: String
    /// A fila mudou — a view redesenha.
    var onChange: (() -> Void)?

    private let linked: () -> [Linked]
    private let activity: (String) -> Activity?
    /// Manda texto e imagens (caminho absoluto) ao nó; devolve o erro, ou nil.
    private let dispatch: (_ node: String, _ text: String, _ images: [String]) -> String?
    private let now: () -> Date

    /// Viu o agente trabalhando depois do último envio — ver `QueueRunner`.
    private var sawWork = false
    /// Os ligados na última batida: aresta criada ou apagada no canvas muda o
    /// seletor sem ninguém avisar a fila.
    private var lastLinked: [Linked]?
    private var timer: Timer?

    init(store: QueueStore,
         name: String = "fila",
         linked: @escaping () -> [Linked],
         activity: @escaping (String) -> Activity?,
         dispatch: @escaping (String, String, [String]) -> String?,
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.name = name
        self.linked = linked
        self.activity = activity
        self.dispatch = dispatch
        self.now = now
        queue = store.load()
    }

    deinit { timer?.invalidate() }

    var targets: [Linked] { linked() }
    var destination: String? { queue.destination(among: linked().map(\.id)) }

    /// Por que não dá para mandar agora, ou nil.
    var blocker: String? {
        destination == nil ? "Ligue a fila a um agente: arraste o + da borda até ele." : nil
    }

    // MARK: Edição

    /// Tarefa nova no fim, ou logo depois de `after` — o Enter no título de
    /// uma tarefa aberta cria a próxima ali, como no Things. Vazia é permitida:
    /// ela nasce para você escrever, e some se ficar vazia (`dropIfEmpty`).
    @discardableResult
    func add(title: String, notes: String = "", images: [String] = [], after: String? = nil) -> QueueItem {
        let item = QueueItem(title: title, notes: notes, images: images)
        if let after, let index = queue.index(of: after) {
            queue.items.insert(item, at: index + 1)
        } else {
            queue.items.append(item)
        }
        changed()
        return item
    }

    func update(_ id: String, title: String, notes: String) {
        guard let index = queue.index(of: id),
              queue.items[index].title != title || queue.items[index].notes != notes else { return }
        queue.items[index].title = title
        queue.items[index].notes = notes
        changed()
    }

    func attach(_ images: [String], to id: String) {
        guard let index = queue.index(of: id), !images.isEmpty else { return }
        queue.items[index].images += images
        changed()
    }

    func detach(_ image: String, from id: String) {
        guard let index = queue.index(of: id) else { return }
        Log.write("fila: print \(image) tirado da tarefa \(id.prefix(8))")
        queue.items[index].images.removeAll { $0 == image }
        store.remove(images: [image])
        changed()
    }

    /// A tarefa recolhida sem nada escrito não fica na lista.
    func dropIfEmpty(_ id: String) {
        guard let index = queue.index(of: id), queue.items[index].isEmpty else { return }
        remove(id)
    }

    /// O checkbox: feito vira pendente, e o resto vira feito — à mão, sem
    /// mandar nada (o problema que você resolveu sozinho).
    func toggleDone(_ id: String) {
        guard let index = queue.index(of: id) else { return }
        if queue.items[index].status == .done { reopen(id); return }
        queue.items[index].status = .done
        queue.items[index].doneAt = now()
        changed()
    }

    func remove(_ id: String) {
        guard let index = queue.index(of: id) else { return }
        Log.write("fila: tarefa \(id.prefix(8)) apagada (\(queue.items[index].images.count) print(s))")
        store.remove(images: queue.items[index].images)
        queue.items.remove(at: index)
        changed()
    }

    func move(_ id: String, by offset: Int) {
        queue.move(id, by: offset)
        changed()
    }

    func move(_ id: String, to index: Int) {
        let before = queue.items.map(\.id)
        queue.move(id, to: index)
        guard queue.items.map(\.id) != before else { return }
        changed()
    }

    /// Volta para pendente — para mandar de novo.
    func reopen(_ id: String) {
        guard let index = queue.index(of: id) else { return }
        queue.items[index].status = .pending
        queue.items[index].sentAt = nil
        queue.items[index].sentTo = nil
        queue.items[index].doneAt = nil
        changed()
    }

    /// Tira da lista o que já foi, com as imagens.
    func clearDone() {
        let done = queue.items.filter { $0.status == .done }
        guard !done.isEmpty else { return }
        store.remove(images: done.flatMap(\.images))
        queue.items.removeAll { $0.status == .done }
        changed()
    }

    func setAuto(_ on: Bool) {
        guard queue.auto != on else { return }
        queue.auto = on
        changed()
        if on { tick() }
    }

    func setTarget(_ id: String) {
        guard queue.target != id else { return }
        queue.target = id
        changed()
    }

    // MARK: Envio

    /// Manda o item agora. Se outro ainda estava em andamento, ele é dado por
    /// encerrado: mandar por cima é decisão sua de seguir em frente, e a fila
    /// só acompanha um turno por vez.
    @discardableResult
    func send(_ id: String) -> String? {
        guard let destination else { return blocker }
        guard let index = queue.index(of: id) else { return "item sumiu" }
        let item = queue.items[index]
        guard !item.isEmpty else { return "tarefa vazia" }
        let agent = linked().first { $0.id == destination }?.agent ?? false
        // Comentário seu feito antes de mandar segue junto: é parte do pedido.
        let comments = item.thread.filter { $0.author == nil }.map(\.text)
        let body = ([item.prompt] + comments).filter { !$0.isEmpty }.joined(separator: "\n\n")
        let text = agent ? body + "\n\n" + footer(for: item) : body
        if let error = dispatch(destination, text, item.images.map { store.url(of: $0).path }) {
            Log.write("fila: envio para \(destination) falhou — \(error)")
            return error
        }
        if let current = queue.inFlight, current.id != id, let open = queue.index(of: current.id) {
            queue.items[open].status = .done
            queue.items[open].doneAt = now()
        }
        queue.items[index].status = .sent
        queue.items[index].sentTo = destination
        queue.items[index].sentAt = now()
        queue.items[index].doneAt = nil
        queue.items[index].awaiting = false
        sawWork = false
        Log.write("fila: item \(id.prefix(8)) enviado para \(destination) "
                  + "(\(item.images.count) imagem(ns), \(queue.pendingCount) pendente(s))")
        changed()
        return nil
    }

    /// O que vai embaixo da tarefa: de onde ela veio e como o agente fala de
    /// volta com ela. Sem isso ele não sabe que a tarefa existe fora do prompt.
    func footer(for item: QueueItem) -> String {
        "\(DispatchRequest.tag) tarefa \(item.shortID) da fila \(name). Ao concluir: `egeon task done \(item.shortID)`. "
            + "Para perguntar algo sobre ela: `egeon task ask \(item.shortID)` com a pergunta no stdin — "
            + "a pergunta aparece na tarefa e a resposta volta para você."
    }

    // MARK: Agente

    /// O que o agente vê com `egeon tasks`: as tarefas desta fila, curtas.
    func tasks() -> [[String: Any]] {
        queue.items.filter { !$0.isEmpty }.map { item in
            var out: [String: Any] = ["id": item.shortID, "title": item.title,
                                      "status": item.status.rawValue, "fila": name]
            if !item.notes.isEmpty { out["notes"] = item.notes }
            if item.awaiting { out["awaiting"] = true }
            if !item.thread.isEmpty {
                out["thread"] = item.thread.map { ["from": $0.author ?? "você", "kind": $0.kind.rawValue, "text": $0.text] }
            }
            return out
        }
    }

    /// O agente mexeu na tarefa: `done`, `ask` ou `note`. Devolve o erro, ou nil.
    func agent(_ author: String, _ action: String, task typed: String, text: String) -> String? {
        guard let index = queue.index(matching: typed) else {
            return "tarefa \(typed) não existe na fila \(name) (veja `egeon tasks`)"
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action {
        case "done":
            queue.items[index].status = .done
            queue.items[index].doneAt = now()
            queue.items[index].awaiting = false
            queue.items[index].thread.append(QueueMessage(author: author, kind: .done, text: text, at: now()))
            sawWork = false
        case "ask":
            guard !text.isEmpty else { return "pergunta vazia — o que você quer saber?" }
            queue.items[index].awaiting = true
            queue.items[index].thread.append(QueueMessage(author: author, kind: .question, text: text, at: now()))
        case "note":
            guard !text.isEmpty else { return "comentário vazio" }
            queue.items[index].thread.append(QueueMessage(author: author, kind: .note, text: text, at: now()))
        default:
            return "ação desconhecida \(action) — use done, ask ou note"
        }
        Log.write("fila: \(author) → \(action) na tarefa \(queue.items[index].shortID)")
        changed()
        return nil
    }

    /// Você escreveu na thread. Tarefa que já foi a um agente leva a resposta
    /// a ele — com o título, para ele saber do que se trata; a que ainda não
    /// foi só guarda o comentário, que segue junto quando ela for.
    @discardableResult
    func reply(_ id: String, text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = queue.index(of: id), !text.isEmpty else { return nil }
        let item = queue.items[index]
        if let agent = item.sentTo {
            let prompt = "Sobre a tarefa \(item.shortID) “\(item.title)” da fila \(name):\n\n\(text)"
            if let error = dispatch(agent, prompt, []) { return error }
            queue.items[index].status = .sent
            queue.items[index].doneAt = nil
            sawWork = false
        }
        queue.items[index].awaiting = false
        queue.items[index].thread.append(QueueMessage(author: nil, kind: .reply, text: text, at: now()))
        changed()
        return nil
    }

    func sendNext() -> String? {
        guard let next = queue.nextPending else { return "nada pendente" }
        return send(next.id)
    }

    /// Uma batida: fecha o item cujo turno acabou e, no automático, manda o
    /// próximo.
    func tick() {
        let current = linked()
        if lastLinked != nil, lastLinked != current { onChange?() }
        lastLinked = current
        guard let destination else { return }
        let state = activity(destination)
        if let state, QueueRunner.isBusy(state) { sawWork = true }
        let step = QueueRunner.step(queue: queue, activity: state, sawWork: sawWork, now: self.now())
        if let finished = step.finish, let index = queue.index(of: finished) {
            queue.items[index].status = .done
            queue.items[index].doneAt = now()
            sawWork = false
            Log.write("fila: item \(finished.prefix(8)) concluído por \(destination)")
            changed()
        }
        if let next = step.send { send(next) }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func changed() {
        store.save(queue)
        onChange?()
    }

    /// A fila como dados, para a rota `/queue`.
    func snapshot() -> [String: Any] {
        [
            "auto": queue.auto,
            "destination": destination ?? "",
            "targets": targets.map(\.id),
            "items": queue.items.map { item -> [String: Any] in
                ["id": item.id, "title": item.title, "notes": item.notes, "images": item.images.count,
                 "status": item.status.rawValue, "sentTo": item.sentTo ?? ""]
            },
        ]
    }
}

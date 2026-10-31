import Foundation

/// Uma mensagem na thread de uma tarefa — do agente ou sua.
struct QueueMessage: Codable, Equatable {
    enum Kind: String, Codable {
        /// O agente perguntou e espera você.
        case question
        /// O agente comentou — andamento, achado, o que fez.
        case note
        /// O agente marcou a tarefa como feita.
        case done
        /// Você, respondendo ou comentando.
        case reply
    }

    /// O nó do agente; nil é você.
    var author: String?
    var kind: Kind
    var text: String
    var at: Date
}

/// Uma tarefa da fila: um texto corrido e os prints — juntos, o prompt — e a
/// thread do que o agente e você disseram sobre ela.
struct QueueItem: Codable, Equatable {
    enum Status: String, Codable {
        /// Anotado, ainda não foi.
        case pending
        /// Entregue ao agente, e o turno dele ainda não fechou.
        case sent
        /// O agente fechou o turno em que recebeu este item.
        case done
    }

    var id: String
    /// Um texto só, como numa nota: não há título separado do corpo.
    var text: String
    /// Nomes dos arquivos na pasta da fila — relativos, para a pasta da
    /// bancada mudar de lugar sem quebrar nada.
    var images: [String]
    var status: Status
    /// O nó que recebeu, e quando.
    var sentTo: String?
    var sentAt: Date?
    var doneAt: Date?
    var thread: [QueueMessage] = []
    /// O agente perguntou e você ainda não respondeu: a fila não anda.
    var awaiting = false

    init(id: String = UUID().uuidString, text: String, images: [String] = [], status: Status = .pending) {
        self.id = id
        self.text = text
        self.images = images
        self.status = status
    }

    /// O id curto que o agente digita (`egeon task done 3f9a2c`).
    var shortID: String { String(id.lowercased().prefix(6)) }

    /// Já foi a um agente: o texto e os prints são o registro do que foi pedido, e
    /// a partir daqui a conversa segue pela thread.
    var isLocked: Bool { sentAt != nil }

    /// O que o agente recebe.
    var prompt: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A primeira linha, curta: como a resposta na thread diz de que tarefa fala.
    var headline: String {
        let line = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    /// Sem texto e sem imagem não há o que mandar.
    var isEmpty: Bool { prompt.isEmpty && images.isEmpty }
}

extension QueueItem {
    /// Como a v1.7 gravava a tarefa, antes de ela virar um texto só.
    private enum LegacyKeys: String, CodingKey { case title, notes }

    /// Thread e pergunta chegaram depois das tarefas: arquivo de antes não tem
    /// as chaves, e o `Decodable` sintetizado recusaria a tarefa inteira. Título e
    /// notas antigos viram o texto, com a linha em branco que o prompt já levava.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        if let current = try c.decodeIfPresent(String.self, forKey: .text) {
            text = current
        } else {
            let old = try decoder.container(keyedBy: LegacyKeys.self)
            text = try [old.decodeIfPresent(String.self, forKey: .title),
                        old.decodeIfPresent(String.self, forKey: .notes)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .pending
        sentTo = try c.decodeIfPresent(String.self, forKey: .sentTo)
        sentAt = try c.decodeIfPresent(Date.self, forKey: .sentAt)
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        thread = try c.decodeIfPresent([QueueMessage].self, forKey: .thread) ?? []
        awaiting = try c.decodeIfPresent(Bool.self, forKey: .awaiting) ?? false
    }
}

/// A fila de um nó: os itens na ordem de envio, o modo automático e para quem.
struct PromptQueue: Codable, Equatable {
    var items: [QueueItem] = []
    /// Manda o próximo sozinha quando o agente fecha o turno.
    var auto = false
    /// O destino escolhido entre os nós ligados por aresta. Nil, ou um que não
    /// está mais ligado, cai no primeiro ligado.
    var target: String?

    var inFlight: QueueItem? { items.first { $0.status == .sent } }
    /// A tarefa ainda em branco é a que você está escrevendo, não a próxima.
    var nextPending: QueueItem? { items.first { $0.status == .pending && !$0.isEmpty } }
    var pendingCount: Int { items.filter { $0.status == .pending && !$0.isEmpty }.count }

    func destination(among linked: [String]) -> String? {
        if let target, linked.contains(target) { return target }
        return linked.first
    }

    func index(of id: String) -> Int? { items.firstIndex { $0.id == id } }

    /// A tarefa pelo id que o agente digitou: o curto ou o inteiro, sem caixa.
    func index(matching typed: String) -> Int? {
        let key = typed.lowercased().trimmingCharacters(in: .whitespaces)
        guard key.count >= 4 else { return nil }
        let found = items.indices.filter { items[$0].id.lowercased().hasPrefix(key) }
        return found.count == 1 ? found[0] : nil
    }

    /// Leva o item para a posição `index` da lista SEM ele — a conta que o
    /// arrasto faz, contando só as linhas que ficaram no lugar.
    mutating func move(_ id: String, to index: Int) {
        guard let from = self.index(of: id) else { return }
        let item = items.remove(at: from)
        items.insert(item, at: min(max(0, index), items.count))
    }

    /// Sobe ou desce um item, sem sair da lista.
    mutating func move(_ id: String, by offset: Int) {
        guard let from = index(of: id) else { return }
        let to = min(max(0, from + offset), items.count - 1)
        guard to != from else { return }
        items.insert(items.remove(at: from), at: to)
    }
}

/// O que a fila faz a cada batida do relógio, pelo estado do agente destino.
///
/// Fechar o item é "o agente trabalhou e voltou a ficar parado" — e não "parou
/// de sair byte", que acontece no meio do turno. Por isso o `sawWork`: quem
/// chama marca que viu o agente trabalhando depois do envio, e só então o
/// silêncio conta como fim.
enum QueueRunner {
    struct Step: Equatable {
        /// Item em andamento que fechou agora.
        var finish: String?
        /// Item a mandar agora.
        var send: String?
    }

    /// Parado esperando prompt: terminou o turno, ou nem começou nenhum. A
    /// pergunta (`asking`) não entra — o agente parou por você, e mandar o
    /// próximo por cima da pergunta atropelaria a resposta.
    static func isFree(_ activity: Activity) -> Bool {
        switch activity {
        case .waiting, .ready: return true
        default: return false
        }
    }

    /// Estados em que o agente está trabalhando no que recebeu — inclusive
    /// parado por você no meio, que ainda é o mesmo turno.
    static func isBusy(_ activity: Activity) -> Bool {
        switch activity {
        case .working, .background, .awaiting, .asking, .retrying: return true
        default: return false
        }
    }

    /// Item enviado sem nunca ver o agente trabalhar, e parado há este tanto:
    /// a entrega se perdeu, e a fila não pode ficar presa nele para sempre.
    static let lostAfter: TimeInterval = 120

    static func step(queue: PromptQueue, activity: Activity?, sawWork: Bool,
                     now: Date = Date()) -> Step {
        guard let activity, isFree(activity) else { return Step() }
        var step = Step()
        if let current = queue.inFlight {
            // Pergunta aberta: o turno fechou por você, e a tarefa continua.
            if current.awaiting { return Step() }
            let lost = now.timeIntervalSince(current.sentAt ?? now) >= lostAfter
            guard sawWork || lost else { return step }
            step.finish = current.id
        }
        if queue.auto, let next = queue.nextPending { step.send = next.id }
        return step
    }
}

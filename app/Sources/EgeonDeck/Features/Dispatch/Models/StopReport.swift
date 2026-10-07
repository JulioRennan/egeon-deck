import Foundation

/// O que o gancho `Stop` conta do turno que acabou, além do instante (ADR-067).
///
/// O Claude Code passou a mandar no payload o que antes só o marcador dizia:
/// `background_tasks` e `session_crons` (há trabalho que vai acordar o agente)
/// e `last_assistant_message` (o texto final, sem esperar o transcript ser
/// gravado). Os dois são opcionais aqui porque CLI sem eles — outra versão,
/// outro programa — continua decidindo pelo marcador, como antes.
struct StopReport: Equatable {
    /// Tarefas de fundo mais crons da sessão. `nil` quando o CLI não relatou.
    var background: Int?
    /// O fim da última mensagem do agente. `nil` quando o CLI não relatou.
    var lastMessage: String?

    init(background: Int? = nil, lastMessage: String? = nil) {
        self.background = background
        self.lastMessage = lastMessage
    }

    /// Lido da query de `/activity`: `bg` e `last`.
    init(query: [String: String]) {
        self.background = query["bg"].flatMap(Int.init)
        self.lastMessage = query["last"].flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Como um turno fechou, decidido no `Stop`.
enum StopOutcome: Equatable {
    case finished
    case asked
    case background
    /// Acionou um agente vizinho que ainda não respondeu: o trabalho seguiu no
    /// card do outro, e a volta chega como prompt novo.
    case awaiting

    /// A ordem é o que importa:
    ///
    /// - **vizinho pendente vence tudo, inclusive `[[ED:ask]]`.** Medido no log:
    ///   o agente que manda `egeon send` e para fecha o turno com `ask` porque
    ///   "depende de uma resposta" — a do vizinho, não a sua —, e o card apitava
    ///   no meio de uma conversa entre agentes. Pedido de permissão não passa
    ///   por aqui: vem pelo `Notification`.
    /// - **a pergunta vence a ampulheta.** Um servidor de dev em background ou
    ///   um `/loop` agendado ficam de pé a sessão inteira; se a pergunta
    ///   perdesse para eles, nenhuma pergunta daquele agente tocaria de novo.
    /// - **o payload vence o marcador no resto.** Com `background` relatado, a
    ///   ampulheta é fato do CLI; um `[[ED:wait]]` sem nada rodando é engano do
    ///   modelo, e a falta dele com um comando de fundo de pé também.
    static func decide(marker: HookEvent.Marker?, background: Int?, awaitingPeers: Bool) -> StopOutcome {
        if awaitingPeers { return .awaiting }
        if marker == .ask { return .asked }
        if let background {
            return background > 0 ? .background : .finished
        }
        switch marker {
        case .ask?:  return .asked
        case .wait?: return .background
        default:     return .finished
        }
    }
}

/// Os agentes vizinhos que este terminal acionou e que ainda não responderam.
///
/// Sai da lista quem responde (manda de volta) e quem encerra o turno sem
/// responder: aí não há mais volta a esperar, e quem acionou não pode ficar
/// na ampulheta para sempre.
struct PeerWait: Equatable {
    private(set) var peers: [String] = []

    var isEmpty: Bool { peers.isEmpty }

    mutating func sent(to address: String) {
        if !peers.contains(address) { peers.append(address) }
    }

    /// `true` quando o endereço estava na lista.
    @discardableResult
    mutating func resolved(_ address: String) -> Bool {
        guard let index = peers.firstIndex(of: address) else { return false }
        peers.remove(at: index)
        return true
    }

    mutating func clear() { peers = [] }

    /// A bancada mudou de nome: o endereço do vizinho mudou junto.
    mutating func renamed(_ old: String, to new: String) {
        peers = peers.map { $0 == old ? new : $0 }
    }

    /// Os nomes sem a bancada — no card todos são da mesma.
    var names: [String] {
        peers.map { String($0.split(separator: "/").last ?? Substring($0)) }
    }
}

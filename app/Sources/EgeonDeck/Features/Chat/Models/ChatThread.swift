import Foundation

// MARK: - A thread da bancada

/// A citação em cima de uma bolha, no jeito do WhatsApp: de quem é, o que
/// dizia e onde está na thread (para o clique rolar até lá).
struct ChatQuote: Equatable {
    /// `nil` é você.
    let authorId: String?
    let text: String
    let at: Date
    let targetKey: String
}

/// Uma linha da thread: seu prompt para alguém, a resposta de alguém, ou um
/// prompt seu que acabou de sair e o transcript ainda não confirmou.
enum ChatMessage: Equatable {
    case prompt(to: ChatParticipant, turnId: String, text: String, at: Date, quote: ChatQuote? = nil)
    case reply(from: ChatParticipant, turn: ChatTurn, quote: ChatQuote? = nil)
    /// Eco local. Entra na linha do tempo pela hora do envio — pinado embaixo,
    /// uma resposta que chegasse antes da confirmação passaria por cima dele.
    case pending(to: ChatParticipant, text: String, at: Date, quote: ChatQuote? = nil)

    var at: Date {
        switch self {
        case .prompt(_, _, _, let at, _): return at
        case .reply(_, let turn, _):   return turn.replyAt ?? turn.promptAt
        case .pending(_, _, let at, _): return at
        }
    }

    /// Identidade estável da mensagem entre remontagens — alvo de citação.
    var key: String {
        switch self {
        case .prompt(_, let turnId, _, _, _): return "p|\(turnId)"
        case .reply(_, let turn, _):          return "r|\(turn.id)"
        case .pending(let to, _, let at, _):  return "e|\(to.id)|\(at.timeIntervalSince1970)"
        }
    }

    var participantId: String {
        switch self {
        case .prompt(let to, _, _, _, _): return to.id
        case .reply(let from, _, _):   return from.id
        case .pending(let to, _, _, _): return to.id
        }
    }

    var promptText: String? {
        if case .prompt(_, _, let text, _, _) = self { return text }
        return nil
    }

    var quote: ChatQuote? {
        switch self {
        case .prompt(_, _, _, _, let quote), .reply(_, _, let quote),
             .pending(_, _, _, let quote): return quote
        }
    }

    private func with(quote: ChatQuote?) -> ChatMessage {
        switch self {
        case .prompt(let to, let turnId, let text, let at, _):
            return .prompt(to: to, turnId: turnId, text: text, at: at, quote: quote)
        case .reply(let from, let turn, _):        return .reply(from: from, turn: turn, quote: quote)
        case .pending(let to, let text, let at, _):
            return .pending(to: to, text: text, at: at, quote: quote)
        }
    }

    // MARK: Montagem

    /// Cruza os transcripts de todos os agentes por tempo e marca as citações.
    ///
    /// A regra é a do WhatsApp: consecutivo é limpo; intercalado é citado. Uma
    /// resposta que não vem logo depois do próprio prompt cita esse prompt; um
    /// prompt seu que não vem logo depois de uma fala do mesmo agente cita a
    /// última resposta dele. Sem isto, dois papos ao mesmo tempo "juntam".
    static func thread(participants: [ChatParticipant], extra: [ChatMessage] = [],
                       turns: (ChatParticipant) -> [ChatTurn]) -> [ChatMessage] {
        let agents = participants.filter(\.isAgent)
        var perAgent: [String: [ChatTurn]] = [:]
        for agent in agents { perAgent[agent.id] = turns(agent) }

        var messages: [ChatMessage] = extra
        for (participant, turn) in fold(agents: agents, turns: perAgent) {
            let label = turn.from.map { "de \($0): \(turn.prompt)" } ?? turn.prompt
            messages.append(.prompt(to: participant, turnId: turn.id, text: label,
                                    at: turn.promptAt))
            if turn.hasReply { messages.append(.reply(from: participant, turn: turn)) }
        }
        // `sorted` não é estável: dois itens no mesmo instante trocariam de
        // lugar entre uma remontagem e outra. O índice desempata.
        let sorted = messages.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
        return quoting(sorted)
    }

    /// Sub-conversa: turno que chegou de OUTRO agente não vira bolha de topo —
    /// entra, achatado e em ordem, na bolha do agente que começou a cadeia. Se o
    /// próprio dono da bolha recebeu a volta e continuou, o que ele escreveu é o
    /// corpo da bolha, e os passos dele somam aos do turno. Quem não tem dono
    /// (mensagem sem remetente conhecido) fica no topo, para não sumir.
    static func fold(agents: [ChatParticipant],
                     turns: [String: [ChatTurn]]) -> [(ChatParticipant, ChatTurn)] {
        let byAddress = Dictionary(uniqueKeysWithValues: agents.map { ($0.address, $0) })
        var roots: [(ChatParticipant, ChatTurn)] = []
        var rootIndex: [String: Int] = [:]
        for agent in agents {
            for turn in turns[agent.id] ?? [] where turn.from == nil {
                rootIndex[turn.id] = roots.count
                roots.append((agent, turn))
            }
        }

        let received = agents.flatMap { agent in
            (turns[agent.id] ?? []).filter { $0.from != nil }.map { (agent, $0) }
        }.sorted { $0.1.promptAt < $1.1.promptAt }

        for (receiver, turn) in received {
            guard let from = turn.from,
                  let root = rootOf(receiver: receiver, turn: turn, byAddress: byAddress, turns: turns),
                  let index = rootIndex[root.1.id] else {
                rootIndex[turn.id] = roots.count
                roots.append((receiver, turn))
                continue
            }
            let isOwner = receiver.id == root.0.id
            let exchange = ChatExchange(
                fromId: byAddress[from]?.id ?? from, toId: receiver.id, text: turn.prompt,
                at: turn.promptAt, steps: turn.steps.count,
                note: isOwner ? "" : turn.replyText)
            roots[index].1.exchanges.append(exchange)
            roots[index].1.parts = placing(exchange, in: roots[index].1.chain,
                                           sentTo: isOwner ? nil : receiver.address)
            if isOwner {
                roots[index].1.parts += turn.chain
                roots[index].1.steps += turn.steps
                if !turn.replyText.isEmpty {
                    roots[index].1.replyText +=
                        (roots[index].1.replyText.isEmpty ? "" : "\n\n") + turn.replyText
                }
                if let at = turn.replyAt { roots[index].1.replyAt = at }
            }
        }
        return roots
    }

    /// A troca entra na cadeia onde aconteceu: a ida logo depois do último `⇄`
    /// para aquele destino (pulando trocas já penduradas ali); a volta (que
    /// chega ao dono) no fim, antes do que ele escreveu em seguida. Sem isso a
    /// conversa com o vizinho ficava toda depois da resposta final, fora de
    /// ordem com o que a provocou.
    static func placing(_ exchange: ChatExchange, in chain: [ChatPart],
                        sentTo address: String?) -> [ChatPart] {
        var chain = chain
        guard let address,
              let sendIndex = chain.lastIndex(where: {
                  if case .step(let step) = $0 { return step.sendTo == address } else { return false }
              }) else {
            chain.append(.exchange(exchange))
            return chain
        }
        var position = sendIndex + 1
        while position < chain.count, case .exchange = chain[position] { position += 1 }
        chain.insert(.exchange(exchange), at: position)
        return chain
    }

    /// Sobe a cadeia até o turno que VOCÊ disparou: quem mandou esta mensagem,
    /// em que turno dele estava (o último, antes dela, com `egeon send` para o
    /// destino — ou o último antes dela), e assim por diante.
    private static func rootOf(receiver: ChatParticipant, turn: ChatTurn,
                               byAddress: [String: ChatParticipant],
                               turns: [String: [ChatTurn]]) -> (ChatParticipant, ChatTurn)? {
        var current = (receiver, turn)
        for _ in 0..<8 {
            guard let from = current.1.from, let sender = byAddress[from] else { return nil }
            let before = (turns[sender.id] ?? []).filter { $0.promptAt <= current.1.promptAt }
            let owner = before.last { candidate in
                candidate.steps.contains { $0.sendTo == current.0.address }
            } ?? before.last
            guard let owner else { return nil }
            if owner.from == nil { return (sender, owner) }
            current = (sender, owner)
        }
        return nil
    }

    static func quoting(_ sorted: [ChatMessage]) -> [ChatMessage] {
        var out: [ChatMessage] = []
        for (index, message) in sorted.enumerated() {
            let previous = index > 0 ? sorted[index - 1] : nil
            switch message {
            case .reply(_, let turn, _):
                if case .prompt(_, let turnId, _, _, _)? = previous, turnId == turn.id {
                    out.append(message)
                } else {
                    out.append(message.with(quote: ChatQuote(
                        authorId: nil, text: turn.prompt, at: turn.promptAt,
                        targetKey: "p|\(turn.id)")))
                }
            case .prompt(let to, _, _, _, _), .pending(let to, _, _, _):
                if previous?.participantId == to.id || previous == nil {
                    out.append(message)
                } else if let last = sorted[..<index].last(where: {
                    if case .reply(let from, _, _) = $0 { return from.id == to.id }
                    return false
                }), case .reply(let from, let turn, _) = last {
                    out.append(message.with(quote: ChatQuote(
                        authorId: from.id, text: turn.replyText, at: last.at,
                        targetKey: last.key)))
                } else {
                    out.append(message)
                }
            }
        }
        return out
    }
}

/// Monta a thread cruzando os transcripts de todos os agentes por tempo.
enum ChatThread {
    static func build(participants: [ChatParticipant],
                      turns: (ChatParticipant) -> [ChatTurn]) -> [ChatMessage] {
        ChatMessage.thread(participants: participants, turns: turns)
    }

    /// A thread com os ecos DENTRO da linha do tempo, e os ecos que sobraram
    /// depois de o transcript confirmar o que já chegou.
    static func build(participants: [ChatParticipant], pending: [Pending],
                      turns: (ChatParticipant) -> [ChatTurn])
        -> (messages: [ChatMessage], pending: [Pending]) {
        let confirmed = ChatMessage.thread(participants: participants, turns: turns)
        let left = stillPending(pending, given: confirmed)
        let echoes = left.compactMap { item -> ChatMessage? in
            guard let to = participants.first(where: { $0.id == item.target }) else { return nil }
            return .pending(to: to, text: item.text, at: item.sentAt)
        }
        return (ChatMessage.thread(participants: participants, extra: echoes, turns: turns), left)
    }

    struct Pending: Equatable {
        let text: String
        let target: String
        let sentAt: Date
        /// Os turnos que o agente JÁ tinha quando este envio saiu — e os que
        /// foram aparecendo depois sem ser este eco.
        var knownTurnIds: Set<String>
    }

    /// O eco local de um envio só vale até o transcript mostrar o prompt: daí
    /// a mensagem de verdade entra e o eco sairia duplicado. Só confirma um
    /// turno NOVO — id que não existia na hora do envio — com o mesmo texto.
    /// Por texto e hora, o segundo "oi" era confirmado pelo primeiro.
    static func stillPending(_ pending: [Pending], given messages: [ChatMessage]) -> [Pending] {
        var remaining = pending
        // Um turno novo confirma UM eco: dois "oi" seguidos são dois turnos,
        // e o primeiro a chegar não pode dar baixa nos dois. Depois de visto,
        // o turno vira conhecido para os ecos que sobraram — esta função roda
        // a cada refresh com a lista inteira, e sem isso o mesmo turno daria
        // baixa no eco seguinte na rodada seguinte.
        for message in messages {
            guard case .prompt(let to, let turnId, _, _, _) = message else { continue }
            if let index = remaining.firstIndex(where: {
                $0.target == to.id && $0.text == message.promptText
                    && !$0.knownTurnIds.contains(turnId)
            }) {
                remaining.remove(at: index)
            }
            for i in remaining.indices { remaining[i].knownTurnIds.insert(turnId) }
        }
        return remaining
    }
}

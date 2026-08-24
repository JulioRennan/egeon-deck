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

/// Uma linha da thread: seu prompt para alguém, ou a resposta de alguém.
enum ChatMessage: Equatable {
    case prompt(to: ChatParticipant, text: String, at: Date, quote: ChatQuote? = nil)
    case reply(from: ChatParticipant, turn: ChatTurn, quote: ChatQuote? = nil)

    var at: Date {
        switch self {
        case .prompt(_, _, let at, _): return at
        case .reply(_, let turn, _):   return turn.replyAt ?? turn.promptAt
        }
    }

    /// Identidade estável da mensagem entre remontagens — alvo de citação.
    var key: String {
        switch self {
        case .prompt(let to, _, let at, _):
            return "p|\(to.id)|\(at.timeIntervalSince1970)"
        case .reply(let from, let turn, _):
            return "r|\(from.id)|\(turn.promptAt.timeIntervalSince1970)"
        }
    }

    var participantId: String {
        switch self {
        case .prompt(let to, _, _, _): return to.id
        case .reply(let from, _, _):   return from.id
        }
    }

    var quote: ChatQuote? {
        switch self {
        case .prompt(_, _, _, let quote), .reply(_, _, let quote): return quote
        }
    }

    private func with(quote: ChatQuote?) -> ChatMessage {
        switch self {
        case .prompt(let to, let text, let at, _): return .prompt(to: to, text: text, at: at, quote: quote)
        case .reply(let from, let turn, _):        return .reply(from: from, turn: turn, quote: quote)
        }
    }

    // MARK: Montagem

    /// Cruza os transcripts de todos os agentes por tempo e marca as citações.
    ///
    /// A regra é a do WhatsApp: consecutivo é limpo; intercalado é citado. Uma
    /// resposta que não vem logo depois do próprio prompt cita esse prompt; um
    /// prompt seu que não vem logo depois de uma fala do mesmo agente cita a
    /// última resposta dele. Sem isto, dois papos ao mesmo tempo "juntam".
    static func thread(participants: [ChatParticipant],
                       turns: (ChatParticipant) -> [ChatTurn]) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        for participant in participants where participant.isAgent {
            for turn in turns(participant) {
                messages.append(.prompt(to: participant, text: turn.prompt, at: turn.promptAt))
                if turn.hasReply { messages.append(.reply(from: participant, turn: turn)) }
            }
        }
        // `sorted` não é estável: dois itens no mesmo instante trocariam de
        // lugar entre uma remontagem e outra. O índice desempata.
        let sorted = messages.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
        return quoting(sorted)
    }

    static func quoting(_ sorted: [ChatMessage]) -> [ChatMessage] {
        var out: [ChatMessage] = []
        for (index, message) in sorted.enumerated() {
            let previous = index > 0 ? sorted[index - 1] : nil
            switch message {
            case .reply(let from, let turn, _):
                if case .prompt(let to, let text, _, _)? = previous,
                   to.id == from.id, text == turn.prompt {
                    out.append(message)
                } else {
                    let promptKey = "p|\(from.id)|\(turn.promptAt.timeIntervalSince1970)"
                    out.append(message.with(quote: ChatQuote(
                        authorId: nil, text: turn.prompt, at: turn.promptAt,
                        targetKey: promptKey)))
                }
            case .prompt(let to, _, _, _):
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

    struct Pending: Equatable {
        let text: String
        let target: String
        let sentAt: Date
    }

    /// O eco local de um envio só vale até o transcript mostrar o prompt: daí
    /// a mensagem de verdade entra e o eco sairia duplicado. Só conta prompt
    /// gravado DEPOIS do envio — um "oi" de ontem não confirma o "oi" de agora,
    /// e sem isso o eco sumia e a bolha de "trabalhando…" aparecia sozinha.
    static func stillPending(_ pending: [Pending], given messages: [ChatMessage]) -> [Pending] {
        pending.filter { item in
            !messages.contains {
                if case .prompt(let to, let text, let at, _) = $0 {
                    return to.id == item.target && text == item.text
                        && at >= item.sentAt.addingTimeInterval(-5)
                }
                return false
            }
        }
    }
}

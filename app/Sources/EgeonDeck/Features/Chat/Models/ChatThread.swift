import Foundation

// MARK: - A thread da bancada

/// Uma linha da thread: seu prompt para alguém, ou a resposta de alguém.
enum ChatMessage: Equatable {
    case prompt(to: ChatParticipant, text: String, at: Date)
    case reply(from: ChatParticipant, turn: ChatTurn)

    var at: Date {
        switch self {
        case .prompt(_, _, let at): return at
        case .reply(_, let turn):   return turn.replyAt ?? turn.promptAt
        }
    }
}

/// Monta a thread cruzando os transcripts de todos os agentes por tempo.
enum ChatThread {
    static func build(participants: [ChatParticipant],
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
        return messages.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    /// O eco local de um envio só vale até o transcript mostrar o prompt: daí
    /// a mensagem de verdade entra e o eco sairia duplicado.
    static func stillPending(_ pending: [(text: String, target: String)],
                             given messages: [ChatMessage]) -> [(text: String, target: String)] {
        pending.filter { item in
            !messages.contains {
                if case .prompt(let to, let text, _) = $0 {
                    return to.id == item.target && text == item.text
                }
                return false
            }
        }
    }
}

import Foundation

// MARK: - A thread como linhas

/// O que a bolha ao vivo diz que o agente está fazendo agora.
enum ChatLive: Equatable {
    case working
    case thinking
    case step(ChatStep)
    /// Permissão pedida no meio do turno: laranja, sem spinner — não há
    /// trabalho andando, há você para decidir.
    case asking

    var label: String {
        switch self {
        case .working:          return "trabalhando…"
        case .thinking:         return "pensando…"
        case .step(let step):   return "\(step.glyph) \(step.text)"
        case .asking:           return "precisa de você"
        }
    }
}

/// Uma linha da thread. A tabela desenha linha por linha e só o que está na
/// tela; a bolha é o conjunto de linhas com o mesmo `messageKey` — a primeira
/// arredonda em cima, a última embaixo (ADR-042). O `id` é estável entre
/// montagens: é por ele que a tabela sabe o que entrou, saiu ou mudou, e é o
/// alvo de rolagem de uma citação.
struct ChatBlock: Equatable {
    enum Kind: Equatable {
        /// Seu prompt (ou o de outro agente, com `from`) — bolha de uma linha.
        /// `mention` é a marca `@destinatário` no começo do texto: só quando a
        /// mensagem não é contínua — consecutivo é limpo, intercalado é
        /// marcado, como no WhatsApp.
        case prompt(to: ChatParticipant, from: String?, text: String, at: Date,
                    quote: ChatQuote?, pending: Bool, mention: Bool)
        /// Cabeçalho da resposta: nome, endereço, hora (`nil` é "agora") e a citação.
        case header(from: ChatParticipant, at: Date?, quote: ChatQuote?)
        /// Um trecho de prosa: parágrafos, títulos e listas seguidos.
        case prose(from: ChatParticipant, blocks: [MarkdownLite.Block])
        /// Bloco de código da prosa (```), na sua caixa.
        case code(from: ChatParticipant, language: String?, code: String)
        case step(from: ChatParticipant, step: ChatStep)
        case diff(from: ChatParticipant, file: String, diff: [String])
        /// A linha de status no fim da bolha ao vivo.
        case status(from: ChatParticipant, live: ChatLive)
        /// O agente trabalha e ainda não gravou nada: bolha só de status.
        case typing(from: ChatParticipant)
    }

    let id: String
    let messageKey: String
    let kind: Kind
    var first = true
    var last = true

    var participant: ChatParticipant {
        switch kind {
        case .prompt(let to, _, _, _, _, _, _): return to
        case .header(let from, _, _), .prose(let from, _), .code(let from, _, _),
             .step(let from, _), .diff(let from, _, _), .status(let from, _),
             .typing(let from):                 return from
        }
    }

    /// Bolha sua fica à direita; a de qualquer agente, à esquerda.
    var alignsRight: Bool {
        if case .prompt(_, let from, _, _, _, _, _) = kind { return from == nil }
        return false
    }
}

enum ChatBlocks {
    /// A thread inteira em linhas. `live` é o turno em curso de cada agente
    /// (id do turno e o status); `typing`, quem trabalha sem turno gravado.
    static func build(messages: [ChatMessage],
                      live: [String: (turnId: String, status: ChatLive)],
                      typing: [ChatParticipant]) -> [ChatBlock] {
        var out: [ChatBlock] = []
        for (index, message) in messages.enumerated() {
            let key = message.key
            // Contínua é a que vem logo depois de uma fala do mesmo destinatário
            // (ou é a primeira): não precisa de marca.
            let previous = index > 0 ? messages[index - 1] : nil
            let mention = previous.map { $0.participantId != message.participantId } ?? false
            switch message {
            case .prompt(let to, _, let text, let at, let quote, let from):
                out.append(ChatBlock(id: key, messageKey: key,
                                     kind: .prompt(to: still(to), from: from, text: text, at: at,
                                                   quote: quote, pending: false, mention: mention)))
            case .pending(let to, let text, let at, let quote):
                out.append(ChatBlock(id: key, messageKey: key,
                                     kind: .prompt(to: still(to), from: nil, text: text, at: at,
                                                   quote: quote, pending: true, mention: mention)))
            case .reply(let from, let turn, let quote):
                let agent = still(from)
                let status = live[from.id].flatMap { $0.turnId == turn.id ? $0.status : nil }
                var rows = [ChatBlock(id: "h|\(turn.id)", messageKey: key,
                                      kind: .header(from: agent,
                                                    at: status == nil ? (turn.replyAt ?? turn.promptAt) : nil,
                                                    quote: quote))]
                var index = 0
                func add(_ kind: Kind) {
                    rows.append(ChatBlock(id: "b|\(turn.id)|\(index)", messageKey: key, kind: kind))
                    index += 1
                }
                for part in turn.chain {
                    switch part {
                    case .text(let text):
                        for kind in split(text, from: agent) { add(kind) }
                    case .step(let step):
                        if let diff = step.diff, !diff.isEmpty {
                            add(.diff(from: agent, file: step.text, diff: diff))
                        } else {
                            add(.step(from: agent, step: step))
                        }
                    }
                }
                if let status { rows.append(ChatBlock(id: "s|\(turn.id)", messageKey: key,
                                                      kind: .status(from: agent, live: status))) }
                out += rows
            }
        }
        for agent in typing {
            out.append(ChatBlock(id: "t|\(agent.id)", messageKey: "t|\(agent.id)",
                                 kind: .typing(from: still(agent))))
        }
        return positioned(out)
    }

    typealias Kind = ChatBlock.Kind

    /// A prosa em linhas: parágrafos, títulos e listas seguidos numa linha só;
    /// cada bloco de código na sua.
    static func split(_ text: String, from agent: ChatParticipant) -> [Kind] {
        var out: [Kind] = []
        var run: [MarkdownLite.Block] = []
        for block in MarkdownLite.blocks(text) {
            if case .code(let language, let code) = block {
                if !run.isEmpty { out.append(.prose(from: agent, blocks: run)); run = [] }
                out.append(.code(from: agent, language: language, code: code))
            } else {
                run.append(block)
            }
        }
        if !run.isEmpty { out.append(.prose(from: agent, blocks: run)) }
        return out
    }

    /// Marca a primeira e a última linha de cada bolha.
    static func positioned(_ blocks: [ChatBlock]) -> [ChatBlock] {
        var out = blocks
        for i in out.indices {
            out[i].first = i == 0 || out[i - 1].messageKey != out[i].messageKey
            out[i].last = i == out.count - 1 || out[i + 1].messageKey != out[i].messageKey
        }
        return out
    }

    /// `ChatParticipant` carrega `activity`, que muda a cada turno de todo
    /// mundo e a linha não mostra: sem zerar, cada mudança de estado faria
    /// todas as linhas do agente parecerem outras.
    private static func still(_ participant: ChatParticipant) -> ChatParticipant {
        var copy = participant
        copy.activity = .ready
        return copy
    }
}

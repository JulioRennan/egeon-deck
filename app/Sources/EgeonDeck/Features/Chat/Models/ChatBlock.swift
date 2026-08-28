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

/// Quanto de uma sequência de passos está à vista. O clique na capa avança um
/// nível e volta ao começo depois do último (ADR-049).
enum ChatGroupLevel: Int, Equatable {
    /// Só a capa: "3 passos · echo três".
    case summary = 0
    /// A capa e os títulos dos passos.
    case titles = 1
    /// Tudo aberto: cada passo com comando e saída.
    case details = 2

    var next: ChatGroupLevel { ChatGroupLevel(rawValue: (rawValue + 1) % 3) ?? .summary }
    var showsSteps: Bool { self != .summary }
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
        /// Um passo na sua caixa. Recolhido é só o título (com `+a −b` e o
        /// tamanho da saída); aberto mostra comando e saída. O diff aberto é
        /// `.diff`; recolhido, é um `.step` como os outros.
        case step(from: ChatParticipant, step: ChatStep, expanded: Bool)
        /// A capa de uma sequência de passos: "3 passos · echo três". O clique
        /// aprofunda — resumo, títulos, tudo aberto (ADR-049).
        case group(from: ChatParticipant, count: Int, last: String, level: ChatGroupLevel)
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
    /// Passos contíguos dividem UMA caixa: a de cima arredonda em cima, a de
    /// baixo embaixo, e entre elas não há borda nem respiro (ADR-047). Mesmo
    /// arranjo que a bolha usa com `first`/`last`, um nível abaixo.
    var boxTop = true
    var boxBottom = true

    /// Passo e a capa do grupo dele dividem caixa; bloco de código fica na sua.
    var groupsWithNeighbours: Bool {
        switch kind {
        case .step, .group: return true
        default:            return false
        }
    }

    var participant: ChatParticipant {
        switch kind {
        case .prompt(let to, _, _, _, _, _, _): return to
        case .header(let from, _, _), .prose(let from, _), .code(let from, _, _),
             .step(let from, _, _), .group(let from, _, _, _), .diff(let from, _, _), .status(let from, _),
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
    /// (id do turno e o status); `typing`, quem trabalha sem turno gravado;
    /// `expanded`, os ids dos passos que você abriu — todo o resto fica só no
    /// título. Passo sem nada além do título é sempre inteiro, e passo com
    /// diff nunca recolhe.
    static func build(messages: [ChatMessage],
                      live: [String: (turnId: String, status: ChatLive)],
                      typing: [ChatParticipant],
                      expanded: Set<String> = [],
                      groups: [String: ChatGroupLevel] = [:]) -> [ChatBlock] {
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
                func add(_ kind: Kind, id: String? = nil) {
                    rows.append(ChatBlock(id: id ?? "b|\(turn.id)|\(index)", messageKey: key, kind: kind))
                    if id == nil { index += 1 }
                }
                /// Passos seguidos com nada entre eles: dois ou mais ganham
                /// capa, e a capa decide quanto deles aparece.
                var run: [(ChatStep, String)] = []
                func flushRun() {
                    defer { run = [] }
                    guard !run.isEmpty else { return }
                    guard run.count > 1 else {
                        let (step, id) = run[0]
                        add(.step(from: agent, step: step,
                                  expanded: !step.isExpandable || expanded.contains(id)), id: id)
                        return
                    }
                    let groupId = "g|\(run[0].1.dropFirst(2))"
                    let level = groups[groupId] ?? .summary
                    add(.group(from: agent, count: run.count, last: run[run.count - 1].0.text,
                               level: level), id: groupId)
                    guard level.showsSteps else { return }
                    for (step, id) in run {
                        add(.step(from: agent, step: step,
                                  expanded: !step.isExpandable || level == .details
                                      || expanded.contains(id)), id: id)
                    }
                }
                for part in turn.chain {
                    switch part {
                    case .text(let text):
                        flushRun()
                        for kind in split(text, from: agent) { add(kind) }
                    case .step(let step):
                        // Diff nunca recolhe: ver o que mudou no arquivo é o
                        // que sempre interessa — é o passo de comando, com o
                        // seu despejo de saída, que nasce só no título.
                        if let diff = step.diff, !diff.isEmpty {
                            flushRun()
                            add(.diff(from: agent, file: step.text, diff: diff))
                        } else {
                            run.append((step, "b|\(turn.id)|\(index)"))
                            index += 1
                        }
                    }
                }
                flushRun()
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

    /// Marca a primeira e a última linha de cada bolha — e de cada caixa de
    /// passos contíguos dentro dela.
    static func positioned(_ blocks: [ChatBlock]) -> [ChatBlock] {
        var out = blocks
        func joined(_ a: ChatBlock, _ b: ChatBlock) -> Bool {
            a.groupsWithNeighbours && b.groupsWithNeighbours && a.messageKey == b.messageKey
        }
        for i in out.indices {
            out[i].first = i == 0 || out[i - 1].messageKey != out[i].messageKey
            out[i].last = i == out.count - 1 || out[i + 1].messageKey != out[i].messageKey
            out[i].boxTop = i == 0 || !joined(out[i - 1], out[i])
            out[i].boxBottom = i == out.count - 1 || !joined(out[i], out[i + 1])
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

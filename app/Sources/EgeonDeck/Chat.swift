import AppKit

// MARK: - Cor de agente

/// Uma cor por terminal, derivada do id.
///
/// O que o thread precisa é distinguir três agentes numa linha só: quem falou se
/// lê pela cor antes de se ler o nome. O acento do card não serve — lá ele diz o
/// TIPO do nó, então dois agentes na mesma bancada têm a mesma cor.
///
/// Derivada e não configurada: campo de cor no `workbenches.json` é mais uma coisa
/// para você manter, e paleta escolhida à mão em bancada de cinco agentes acaba em
/// dois tons de azul. O hash é próprio porque `hashValue` do Swift tem semente
/// por processo — com ele a cor de `orquestrador` mudaria a cada arranque.
enum AgentColor {
    private static let palette: [NSColor] = [
        NSColor(srgbRed: 0.88, green: 0.64, blue: 0.35, alpha: 1),  // âmbar
        NSColor(srgbRed: 0.35, green: 0.76, blue: 0.84, alpha: 1),  // ciano
        NSColor(srgbRed: 0.65, green: 0.55, blue: 0.98, alpha: 1),  // violeta
        NSColor(srgbRed: 0.47, green: 0.74, blue: 0.44, alpha: 1),  // verde
        NSColor(srgbRed: 0.37, green: 0.62, blue: 0.86, alpha: 1),  // azul
        NSColor(srgbRed: 0.91, green: 0.52, blue: 0.71, alpha: 1),  // rosa
    ]

    static func of(_ id: String) -> NSColor {
        guard !id.isEmpty else { return NSColor(calibratedWhite: 0.6, alpha: 1) }
        // FNV-1a: estável entre execuções, que é a única exigência aqui.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    /// Fundo do chip com o nome do agente. Alfa baixo porque ele fica sobre o
    /// fundo da mensagem, e chip opaco viraria botão.
    static func chipBackground(_ id: String) -> NSColor {
        of(id).withAlphaComponent(0.16)
    }
}

// MARK: - Um terminal, do ponto de vista do chat

/// O retrato de um terminal que o modo Chat consome.
///
/// Retrato e não referência ao `NodeView`: em modo chat os cards estão fora da
/// hierarquia de views, e o painel precisa mostrá-los de qualquer jeito. O que ele
/// mostra é estado, não desenho — então o que atravessa é um struct de valores,
/// remontado a cada leitura.
struct ChatNode {
    let id: String
    let address: String
    /// Roda um agente de IA — tem perfil. O contrário é shell.
    let isAgent: Bool
    /// Chave em `agents.json`. É por ela que se escolhe o adapter que sabe ler a
    /// conversa deste CLI.
    let agentKey: String?
    let role: String?
    /// Linha de comando do nó, que é o que identifica um processo na lista.
    let cmd: String
    let activity: Activity
    /// Onde o CLI está gravando esta conversa. Nil em shell e em agente que ainda
    /// não recebeu prompt nenhum.
    let transcript: URL?
    /// Ids da mesma bancada que este nó pode acionar. É a lista de arestas — no
    /// chat ela é só de leitura, e desenhar aresta continua sendo no canvas.
    let reaches: [String]
}

// MARK: - O thread de uma bancada

/// Junta os transcripts dos agentes da bancada num thread só, na ordem do tempo.
///
/// Um thread por bancada e não por nó: o que se perde dirigindo vários agentes é a
/// ordem em que as coisas aconteceram, e ela só existe cruzando os transcripts.
/// O timestamp é do CLI, não do app — então a ordem é a real, mesmo com dois
/// agentes respondendo ao mesmo tempo.
final class ChatThread {
    /// Um adapter por caminho de transcript, para o offset incremental sobreviver
    /// entre leituras. Chaveado pelo caminho e não pelo id do nó: trocar de
    /// conversa dentro da TUI muda o arquivo, e o leitor antigo não serve mais.
    private var adapters: [String: ChatAdapter] = [:]
    /// O que cada nó estava fazendo na última leitura. Preenchido por `entries`.
    private var liveByNode: [String: String] = [:]

    /// Quem participa: id curto do nó, qual CLI ele roda e onde está o transcript.
    struct Participant {
        let id: String
        let agent: String?
        let transcript: URL?
    }

    /// O que este nó está fazendo agora, se o adapter dele souber dizer.
    func live(of id: String) -> String? { liveByNode[id] }

    /// Os turnos da bancada, do jeito que o thread mostra: os SEUS no topo, e os que
    /// um agente provocou aninhados dentro de quem os provocou.
    func turns(of participants: [Participant]) -> [ChatTurn] {
        var all: [ChatTurn] = []
        liveByNode = [:]
        for participant in participants {
            guard let url = participant.transcript else { continue }
            let adapter = adapters[url.path] ?? {
                let new = ChatAdapters.make(agent: participant.agent, transcript: url)
                if let new { adapters[url.path] = new }
                return new
            }()
            guard let adapter else { continue }
            all += adapter.read(author: participant.id)
            if let live = adapter.live { liveByNode[participant.id] = live }
        }
        // Empate resolvido pelo id para a ordem não dançar entre leituras: dois
        // agentes gravam no mesmo milissegundo com mais frequência do que parece.
        all.sort { first, second in
            if first.at != second.at { return first.at < second.at }
            return first.id < second.id
        }
        return nest(all)
    }

    /// Esquece transcripts que não são de ninguém mais. Sem isto, trocar de
    /// conversa num nó dez vezes deixa dez adapters com o arquivo antigo aberto.
    func forget(except participants: [Participant]) {
        let alive = Set(participants.compactMap { $0.transcript?.path })
        adapters = adapters.filter { alive.contains($0.key) }
    }

    /// Põe cada turno acionado dentro do turno que o acionou.
    ///
    /// A ligação é pelo REMETENTE e pelo tempo, não pelo texto: o envelope diz quem
    /// falou, e um agente só pode ter acionado alguém durante um turno dele que já
    /// tinha começado. Então o turno de B com `from: A` entra no último turno de A
    /// que abriu antes dele. Casar por texto seria mais frágil de graça — o mesmo
    /// pedido repetido duas vezes na mesma cadeia não se distingue.
    ///
    /// Turno acionado cujo provocador ficou FORA da cauda lida sobe para o topo em vez
    /// de desaparecer: mostrar meia conversa é melhor que engolir metade dela.
    private func nest(_ turns: [ChatTurn]) -> [ChatTurn] {
        // Índice de trás para frente: para cada turno, quem é o pai.
        var children: [String: [ChatTurn]] = [:]
        var roots: [ChatTurn] = []

        for turn in turns {
            guard let sender = turn.from else { roots.append(turn); continue }
            let parent = turns.last { $0.author == sender && $0.at <= turn.at }
            if let parent {
                children[parent.id, default: []].append(turn)
            } else {
                roots.append(turn)
            }
        }

        func attach(_ turn: ChatTurn) -> ChatTurn {
            var copy = turn
            copy.replies = (children[turn.id] ?? []).map(attach)
            return copy
        }
        return roots.map(attach)
    }
}

// MARK: - O thread como dados

extension ChatBlock {
    /// Forma de dados, para a rota `/chat`.
    var payload: [String: Any] {
        switch self {
        case .prose(let text): return ["kind": "prose", "text": text]
        case .code(let text):  return ["kind": "code", "text": text]
        case .tool(let text):  return ["kind": "tool", "text": text]
        case .edit(let edit):
            return ["kind": "edit", "file": edit.file, "add": edit.add, "del": edit.del,
                    "diff": edit.lines.map { "\($0.mark)\($0.text)" }]
        }
    }
}

extension ChatTurn {
    /// Forma de dados, para a rota `/chat`. Recursiva, porque o aninhamento é o que
    /// precisa ser conferido: turno acionado dentro de quem o acionou.
    var payload: [String: Any] {
        var out: [String: Any] = [
            "id": id,
            "author": author,
            "at": ISO8601DateFormatter().string(from: at),
            "time": timeLabel
        ]
        if !prompt.isEmpty { out["prompt"] = prompt }
        if let from { out["from"] = from }
        if inFlight { out["inFlight"] = true }
        if !work.isEmpty { out["work"] = work.map(\.payload) }
        if !answer.isEmpty { out["answer"] = answer.map(\.payload) }
        if !replies.isEmpty { out["replies"] = replies.map(\.payload) }
        return out
    }
}

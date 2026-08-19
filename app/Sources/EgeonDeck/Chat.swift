import AppKit

// MARK: - Cor de agente

/// Uma cor por terminal, derivada do id.
///
/// O que o thread precisa é distinguir três agentes numa linha só: quem falou se
/// lê pela cor antes de se ler o nome. O acento do card não serve — lá ele diz o
/// TIPO do nó, então dois agentes na mesma sessão têm a mesma cor.
///
/// Derivada e não configurada: campo de cor no `sessions.json` é mais uma coisa
/// para você manter, e paleta escolhida à mão em sessão de cinco agentes acaba em
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
    let role: String?
    /// Linha de comando do nó, que é o que identifica um processo na lista.
    let cmd: String
    let activity: Activity
    /// Onde o CLI está gravando esta conversa. Nil em shell e em agente que ainda
    /// não recebeu prompt nenhum.
    let transcript: URL?
    /// Ids da mesma sessão que este nó pode acionar. É a lista de arestas — no
    /// chat ela é só de leitura, e desenhar aresta continua sendo no canvas.
    let reaches: [String]
}

// MARK: - O thread de uma sessão

/// Junta os transcripts dos agentes da sessão num thread só, na ordem do tempo.
///
/// Um thread por sessão e não por nó: o que se perde dirigindo vários agentes é a
/// ordem em que as coisas aconteceram, e ela só existe cruzando os transcripts.
/// O timestamp é do CLI, não do app — então a ordem é a real, mesmo com dois
/// agentes respondendo ao mesmo tempo.
final class ChatThread {
    /// Um leitor por caminho de transcript, para o offset incremental sobreviver
    /// entre leituras. Chaveado pelo caminho e não pelo id do nó: trocar de
    /// conversa dentro da TUI muda o arquivo, e o leitor antigo não serve mais.
    private var readers: [String: TranscriptReader] = [:]

    /// Quem participa: id curto do nó e onde está o transcript dele.
    struct Participant {
        let id: String
        let transcript: URL?
    }

    func entries(of participants: [Participant]) -> [ChatEntry] {
        var all: [ChatEntry] = []
        for participant in participants {
            guard let url = participant.transcript else { continue }
            let reader = readers[url.path] ?? {
                let new = TranscriptReader(url: url)
                readers[url.path] = new
                return new
            }()
            all += reader.read(author: participant.id)
        }
        // Empate resolvido pelo id para a ordem não dançar entre leituras: dois
        // agentes gravam no mesmo milissegundo com mais frequência do que parece.
        all.sort { first, second in
            if first.at != second.at { return first.at < second.at }
            return first.id < second.id
        }
        return fold(all)
    }

    /// Esquece transcripts que não são de ninguém mais. Sem isto, trocar de
    /// conversa num nó dez vezes deixa dez leitores com o arquivo antigo aberto.
    func forget(except participants: [Participant]) {
        let live = Set(participants.compactMap { $0.transcript?.path })
        readers = readers.filter { live.contains($0.key) }
    }

    /// Junta o que é uma mensagem só aparecendo em vários transcripts.
    ///
    /// Mandar para `todos` entrega o MESMO texto a cada agente, e cada um grava no
    /// próprio arquivo. Sem juntar, uma frase sua aparece três vezes seguidas — e
    /// o que você quer ver é uma pergunta com três destinatários.
    ///
    /// A janela é de segundos porque as entregas são enfileiradas e drenadas por
    /// um laço de 0,25s: o mesmo prompt chega a dois terminais com diferença de
    /// tempo, e comparar timestamp exato não juntaria nada.
    private func fold(_ entries: [ChatEntry]) -> [ChatEntry] {
        var out: [ChatEntry] = []
        for entry in entries {
            guard entry.kind == .user else { out.append(entry); continue }
            if let last = out.indices.last(where: { out[$0].kind == .user }),
               out[last].text == entry.text,
               entry.at.timeIntervalSince(out[last].at) < Self.foldWindow,
               // Só junta o que está encostado: mensagem igual repetida depois de
               // uma resposta é você mandando de novo, e virou outra mensagem.
               last == out.count - 1 {
                out[last].recipients += entry.recipients
                continue
            }
            out.append(entry)
        }
        return out
    }

    /// Quanto tempo separa "a mesma mensagem para vários" de "mandei de novo".
    private static let foldWindow: TimeInterval = 20
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

extension ChatEntry {
    var payload: [String: Any] {
        var out: [String: Any] = [
            "id": id,
            "kind": String(describing: kind),
            "at": ISO8601DateFormatter().string(from: at),
            "time": timeLabel
        ]
        if let author { out["author"] = author }
        if !recipients.isEmpty { out["to"] = recipients }
        if !text.isEmpty { out["text"] = text }
        if !blocks.isEmpty { out["blocks"] = blocks.map(\.payload) }
        if alert { out["alert"] = true }
        return out
    }
}

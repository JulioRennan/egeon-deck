import AppKit

// MARK: - Quem está no grupo

/// Um participante do modo chat: agente ou shell da bancada, como estado puro.
/// Editor e web ficam de fora — não são endereçáveis e não têm conversa.
struct ChatParticipant: Equatable {
    let id: String
    /// `bancada/id` — o endereço que o Dispatcher entende.
    let address: String
    let isAgent: Bool
    /// O que aparece embaixo do nome: papel do agente ou comando do shell.
    let role: String?
    var activity: Activity
    /// Onde o CLI grava a conversa deste agente — de onde as respostas saem.
    var transcript: URL? = nil

    var color: NSColor { isAgent ? AgentPalette.color(for: id) : AgentPalette.shell }
    var glyph: String { isAgent ? "✦" : "❯" }

    static func from(nodes: [NodeConfig], workbench: String,
                     activity: (String) -> Activity?) -> [ChatParticipant] {
        nodes.compactMap { node in
            guard node.type == .agent || node.type == .shell else { return nil }
            let address = "\(workbench)/\(node.id)"
            let role = node.type == .agent
                ? node.prompt?.split(separator: "\n").first.map(String.init)
                : (node.cmd ?? "shell")
            return ChatParticipant(id: node.id, address: address,
                                   isAgent: node.type == .agent,
                                   role: role,
                                   activity: activity(address) ?? .dead,
                                   transcript: node.transcript.map(URL.init(fileURLWithPath:)))
        }
    }
}

// MARK: - Cor por agente

/// Cada agente tem uma cor própria, estável entre arranques — é ela que liga a
/// linha do participante, o chip do composer e a bolha na thread.
enum AgentPalette {
    /// Hex fixo, não `systemPurple` e afins: cor dinâmica muda com o tema do
    /// sistema e quebraria o "reconheço o agente pela cor de longe".
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.784, green: 0.529, blue: 0.980, alpha: 1), // roxo
        NSColor(srgbRed: 0.255, green: 0.765, blue: 0.949, alpha: 1), // azul
        NSColor(srgbRed: 0.941, green: 0.392, blue: 0.549, alpha: 1), // rosa
        NSColor(srgbRed: 0.404, green: 0.847, blue: 0.910, alpha: 1), // ciano
        NSColor(srgbRed: 0.843, green: 0.706, blue: 0.353, alpha: 1), // amarelo
        NSColor(srgbRed: 0.263, green: 0.820, blue: 0.486, alpha: 1), // verde
    ]

    static let shell = NSColor(srgbRed: 0.604, green: 0.655, blue: 0.733, alpha: 1)

    /// FNV-1a, e não `hashValue`: o hash do Swift muda a cada processo, e a cor
    /// do agente não pode trocar entre um arranque e outro.
    static func color(for id: String) -> NSColor {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return colors[Int(hash % UInt64(colors.count))]
    }
}

import Foundation

/// De que jeito você está olhando a bancada.
///
/// Os dois modos não são duas cópias do nó: o card é o MESMO `NodeView`, e o que
/// muda é quem lhe dá o frame. Tirar uma view de um pai e pôr em outro não toca
/// no processo — o pty segue ligado ao SwiftTerm e o WKWebView não recarrega — e
/// é isso que permite trocar de modo com cinco agentes trabalhando.
enum ViewMode: String, Codable {
    /// Bancada livre: posição, tamanho, zoom e arestas.
    case canvas
    /// A janela inteira dividida entre os nós, sem sobreposição e sem zoom.
    case mosaic
    /// A bancada como conversa: participantes, thread e composer.
    case chat

    /// Modo que sai do app continua gravado no `workbenches.json` de quem o
    /// usou. Valor desconhecido vira canvas em vez de derrubar a carga da
    /// bancada inteira.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ViewMode(rawValue: raw) ?? .canvas
    }

    /// Os modos na ordem em que aparecem na barra e nas teclas ⌥⌘1..3.
    static let all: [ViewMode] = [.canvas, .mosaic, .chat]

    var label: String {
        switch self {
        case .canvas: return "Canvas"
        case .mosaic: return "Mosaico"
        case .chat:   return "Chat"
        }
    }

    var symbols: [String] {
        switch self {
        case .canvas: return ["square.on.square.dashed", "rectangle.dashed", "square.dashed"]
        case .mosaic: return ["rectangle.split.2x1", "square.split.2x1", "sidebar.right"]
        case .chat:   return ["bubble.left.and.bubble.right", "bubble.left", "message"]
        }
    }

    var tooltip: String {
        switch self {
        case .canvas: return "Canvas — nós soltos, com zoom e ligações (⌥⌘1)"
        case .mosaic: return "Mosaico — os mesmos nós dividindo a janela (⌥⌘2)"
        case .chat:   return "Chat — a bancada como conversa, sem os cards (⌥⌘3)"
        }
    }
}

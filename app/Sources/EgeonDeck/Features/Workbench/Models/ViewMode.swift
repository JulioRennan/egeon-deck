import Foundation

/// De que jeito você está olhando a bancada.
///
/// Nos dois modos que desenham cards não são duas cópias do nó: o card é o MESMO
/// `NodeView`, e o que muda é quem lhe dá o frame. Tirar uma view de um pai e pôr
/// em outro não toca no processo — o pty segue ligado ao SwiftTerm e o WKWebView
/// não recarrega — e é isso que permite trocar de modo com cinco agentes
/// trabalhando. O chat não desenha card nenhum, mas também não os desmonta: o
/// canvas continua no lugar, coberto — nó fora da hierarquia não recebe layout, e
/// sem layout o pty nasce com zero colunas.
enum ViewMode: String, Codable {
    /// Bancada livre: posição, tamanho, zoom e arestas.
    case canvas
    /// A janela inteira dividida entre os nós, sem sobreposição e sem zoom.
    case mosaic
    /// A bancada como conversa: os transcripts dos agentes num thread só.
    case chat

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

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

    /// Modo que saiu do app continua gravado no `workbenches.json` de quem o
    /// usou — "chat" está lá em bancada real. Valor desconhecido vira canvas em
    /// vez de derrubar a carga da bancada inteira.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ViewMode(rawValue: raw) ?? .canvas
    }

    /// Os modos na ordem em que aparecem na barra e nas teclas ⌥⌘1..2.
    static let all: [ViewMode] = [.canvas, .mosaic]

    var label: String {
        switch self {
        case .canvas: return "Canvas"
        case .mosaic: return "Mosaico"
        }
    }

    var symbols: [String] {
        switch self {
        case .canvas: return ["square.on.square.dashed", "rectangle.dashed", "square.dashed"]
        case .mosaic: return ["rectangle.split.2x1", "square.split.2x1", "sidebar.right"]
        }
    }

    var tooltip: String {
        switch self {
        case .canvas: return "Canvas — nós soltos, com zoom e ligações (⌥⌘1)"
        case .mosaic: return "Mosaico — os mesmos nós dividindo a janela (⌥⌘2)"
        }
    }
}

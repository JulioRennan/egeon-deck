import AppKit

/// Ferramentas da barra. `cursor` é o modo normal — navegar, arrastar nó,
/// digitar no terminal. As outras armam o próximo clique no canvas.
enum CanvasTool: String, CaseIterable {
    case cursor
    case terminal
    case web
    /// Ligar um terminal a outro: arrastar da origem até o destino.

    var symbols: [String] {
        switch self {
        // Listas de candidatos: o nome do símbolo muda entre versões do SF
        // Symbols, e um `nil` aqui viraria botão vazio.
        case .cursor:   return ["cursorarrow", "arrow.up.left"]
        case .terminal: return ["apple.terminal", "terminal", "chevron.left.forwardslash.chevron.right"]
        case .web:      return ["globe", "network"]
        }
    }

    var tooltip: String {
        switch self {
        case .cursor:   return "Cursor — arrastar o canvas, mover nós (⌘V)"
        case .terminal: return "Terminal — clique ou arraste no canvas (⌘T)"
        case .web:      return "Web — clique ou arraste no canvas (⌘W)"
        }
    }

    /// Que tipo de nó esta ferramenta cria. Nem toda ferramenta cria nó.
    var nodeKind: NodeKind? {
        switch self {
        case .cursor: return nil
        case .terminal:      return .shell
        case .web:           return .web
        }
    }

    /// Base do id do nó novo. Entra no endereço de dispatch, então segue a
    /// convenção que já está no workbenches.json (`sh`, `web`).
    var idPrefix: String {
        switch self {
        case .cursor: return ""
        case .terminal:      return "sh"
        case .web:           return "web"
        }
    }

    /// Tamanho de quem só clica, sem arrastar.
    var defaultNodeSize: NSSize { NSSize(width: 720, height: 460) }
}

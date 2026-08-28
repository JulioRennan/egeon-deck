import AppKit

// MARK: - Cabeçalho da resposta, e a bolha de "trabalhando…"

/// Nome na cor do agente, endereço, hora (ou "agora") e a citação. Também
/// serve de bolha inteira para quem trabalha e ainda não gravou nada — nome
/// em cima, status embaixo.
final class ChatHeaderRow: ChatRowView {
    static let identifier = NSUserInterfaceItemIdentifier("chat.header")
    private let name = ChatRowView.label(ChatBlockLayout.nameFont, .white)
    private let address = ChatRowView.label(ChatBlockLayout.addressFont, NSColor(calibratedWhite: 0.45, alpha: 1))
    private let time = ChatRowView.label(ChatBlockLayout.timeFont, NSColor(calibratedWhite: 0.45, alpha: 1))
    private let status = ChatRowView.label(ChatBlockLayout.statusFont, NSColor(calibratedWhite: 0.5, alpha: 1))
    private var quoteView: ChatQuoteView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        [name, address, time, status].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply() {
        guard let block else { return }
        quoteView?.removeFromSuperview()
        quoteView = nil
        let from = block.participant
        name.stringValue = "\(from.glyph) \(from.id)"
        name.textColor = from.color
        address.stringValue = from.address
        switch block.kind {
        case .header(_, let at, let quote):
            time.stringValue = at.map(ChatBlockLayout.clock) ?? "agora"
            status.isHidden = true
            if let quote {
                // Quem perguntou: você (azul) ou outro agente (na cor dele).
                let author = quote.authorId
                let view = ChatQuoteView(quote: quote,
                                         authorLabel: author.map { "✦ \($0)" } ?? "você",
                                         color: author.map(AgentPalette.color(for:)) ?? ChatBlockLayout.youColor)
                view.onClick = { [weak self] in self?.onClick?() }
                addSubview(view)
                quoteView = view
            }
        case .typing:
            time.stringValue = "agora"
            status.isHidden = false
            tick()
        default: break
        }
    }

    func tick() {
        guard let block, case .typing = block.kind else { return }
        let text = ChatBlockLayout.status(.working, spinner: Spinner.current)
        if status.stringValue != text { status.stringValue = text }
    }

    override func layout() {
        super.layout()
        let bubble = bubbleRect
        let inset = ChatBlockLayout.textInset
        let y = ChatBlockLayout.topPad
        let slack = ChatBlockLayout.labelSlack
        let nameWidth = name.intrinsicContentSize.width + slack
        name.frame = NSRect(x: bubble.minX + inset, y: y, width: nameWidth, height: ChatBlockLayout.headerHeight)
        address.frame = NSRect(x: bubble.minX + inset + nameWidth + 8, y: y + 2,
                               width: address.intrinsicContentSize.width + slack, height: 13)
        let timeWidth = time.intrinsicContentSize.width + slack
        time.frame = NSRect(x: bubble.maxX - timeWidth - inset, y: y + 2, width: timeWidth, height: 13)
        quoteView?.frame = NSRect(x: bubble.minX + inset, y: y + ChatBlockLayout.headerHeight + 8,
                                  width: bubble.width - inset * 2, height: ChatBlockLayout.quoteHeight)
        status.frame = NSRect(x: bubble.minX + inset,
                              y: y + ChatBlockLayout.headerHeight + ChatBlockLayout.rowGap,
                              width: bubble.width - inset * 2, height: ChatBlockLayout.statusHeight)
    }
}

// MARK: - A linha de status da bolha ao vivo

/// O que o agente está fazendo agora: spinner e o último passo, "pensando…",
/// ou ● laranja quando pediu permissão.
final class ChatStatusRow: ChatRowView {
    static let identifier = NSUserInterfaceItemIdentifier("chat.status")
    private let status = ChatRowView.label(ChatBlockLayout.statusFont, NSColor(calibratedWhite: 0.5, alpha: 1))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        status.lineBreakMode = .byTruncatingMiddle
        addSubview(status)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply() { tick() }

    /// Chega 8 vezes por segundo: escrever o mesmo texto redesenha à toa.
    func tick() {
        guard let block, case .status(_, let live) = block.kind else { return }
        let text = ChatBlockLayout.status(live, spinner: Spinner.current)
        if case .asking = live {
            status.textColor = Activity.asking.color
        } else {
            status.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        }
        if status.stringValue != text { status.stringValue = text }
    }

    override func layout() {
        super.layout()
        let bubble = bubbleRect
        let inset = ChatBlockLayout.textInset
        status.frame = NSRect(x: bubble.minX + inset, y: ChatBlockLayout.rowGap,
                              width: bubble.width - inset * 2, height: ChatBlockLayout.statusHeight)
    }
}

// MARK: - O diff de uma edição

/// A sub-bolha do diff, lado a lado, sempre visível. A `DiffView` é imutável
/// de propósito; a linha troca a view ao ser reconfigurada — só as visíveis
/// existem, e é barato.
final class ChatDiffRow: ChatRowView {
    static let identifier = NSUserInterfaceItemIdentifier("chat.diff")
    private var diff: DiffView?

    override func apply() {
        guard let block, case .diff(_, let file, let lines) = block.kind else { return }
        diff?.removeFromSuperview()
        let view = DiffView(file: file, diff: lines)
        addSubview(view)
        diff = view
    }

    override func layout() {
        super.layout()
        let bubble = bubbleRect
        let inset = ChatBlockLayout.textInset
        diff?.frame = NSRect(x: bubble.minX + inset, y: ChatBlockLayout.rowGap,
                             width: bubble.width - inset * 2, height: diff?.height ?? 0)
    }
}

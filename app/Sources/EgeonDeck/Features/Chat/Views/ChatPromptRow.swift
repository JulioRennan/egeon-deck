import AppKit

// MARK: - A bolha de um prompt

/// Seu prompt à direita, ou o de outro agente à esquerda: o texto, a hora no
/// canto de baixo e a citação em cima quando as regras de reply pedem.
final class ChatPromptRow: ChatRowView {
    static let identifier = NSUserInterfaceItemIdentifier("chat.prompt")
    private let text = ChatRowView.makeTextView()
    private let time = ChatRowView.label(ChatBlockLayout.timeFont, NSColor(calibratedWhite: 0.45, alpha: 1))
    private var quoteView: ChatQuoteView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(text)
        addSubview(time)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply() {
        guard let block, case .prompt(let to, _, _, let at, let quote, _, _) = block.kind else { return }
        text.textStorage?.setAttributedString(
            metrics.text ?? ChatBlockLayout.attributed(block.kind) ?? NSAttributedString())
        time.stringValue = ChatBlockLayout.clock(at)
        quoteView?.removeFromSuperview()
        quoteView = nil
        if let quote {
            let view = ChatQuoteView(quote: quote, authorLabel: "\(to.glyph) \(to.id)", color: to.color)
            view.onClick = { [weak self] in self?.onClick?() }
            addSubview(view)
            quoteView = view
        }
    }

    override func layout() {
        super.layout()
        let bubble = bubbleRect
        let inset = ChatBlockLayout.textInset
        var y: CGFloat = 10
        if let quoteView {
            quoteView.frame = NSRect(x: bubble.minX + inset, y: y, width: bubble.width - inset * 2,
                                     height: ChatBlockLayout.quoteHeight)
            y += ChatBlockLayout.quoteHeight + 8
        }
        let textHeight = bubble.height - y - 4 - ChatBlockLayout.timeHeight - 9
        text.frame = NSRect(x: bubble.minX + inset, y: y, width: bubble.width - inset * 2,
                            height: max(0, textHeight))
        let timeWidth = time.intrinsicContentSize.width + ChatBlockLayout.labelSlack
        time.frame = NSRect(x: bubble.maxX - timeWidth - inset, y: bubble.maxY - 22,
                            width: timeWidth, height: ChatBlockLayout.timeHeight)
    }
}

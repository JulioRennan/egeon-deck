import AppKit

// MARK: - Bolha de mensagem enviada

/// Uma mensagem SUA na thread: cabeçalho "→ ✦ destino · hora" e o texto.
final class ChatBubbleView: NSView, ThreadBubble {
    private let header = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")

    static let maxWidth: CGFloat = 560
    let alignsRight = true
    var onQuoteClick: (() -> Void)?
    private var quoteView: ChatQuoteView?

    init(text: String, target: ChatParticipant, at: Date = Date(), pending: Bool = false,
         quote: ChatQuote? = nil) {
        super.init(frame: .zero)
        // Eco local ainda sem confirmação do transcript: meio apagado.
        if pending { alphaValue = 0.6 }
        if let quote {
            let view = ChatQuoteView(quote: quote, authorLabel: "\(target.glyph) \(target.id)",
                                     color: target.color)
            view.onClick = { [weak self] in self?.onQuoteClick?() }
            addSubview(view)
            quoteView = view
        }
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor(srgbRed: 0.184, green: 0.498, blue: 0.965,
                                         alpha: 0.12).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(srgbRed: 0.184, green: 0.498, blue: 0.965,
                                     alpha: 0.32).cgColor

        header.font = .monospacedSystemFont(ofSize: 11.5, weight: .bold)
        header.textColor = target.color
        header.stringValue = "→ \(target.glyph) \(target.id)"

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        time.font = .systemFont(ofSize: 10.5)
        time.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        time.stringValue = formatter.string(from: at)

        body.font = .systemFont(ofSize: 13.5)
        body.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        body.stringValue = text

        [header, time, body].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// A célula do NSTextField come uns pixels de cada lado antes de quebrar a
    /// linha; medir sem essa folga corta a última palavra.
    private static let cellSlack: CGFloat = 8

    private var quoteBlock: CGFloat { quoteView == nil ? 0 : ChatQuoteView.height + 8 }

    /// Altura para uma largura dada — quem empilha pergunta antes de posicionar.
    func height(for width: CGFloat) -> CGFloat {
        let textWidth = min(width, Self.maxWidth) - 26 - Self.cellSlack
        let textHeight = body.attributedStringValue
            .boundingRect(with: NSSize(width: textWidth, height: .infinity),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        return ceil(textHeight) + 46 + quoteBlock
    }

    func width(for available: CGFloat) -> CGFloat {
        let textWidth = ceil(body.attributedStringValue
            .boundingRect(with: NSSize(width: Self.maxWidth - 26 - Self.cellSlack,
                                       height: .infinity),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).width)
        let headerWidth = header.intrinsicContentSize.width
            + time.intrinsicContentSize.width + 40
        // Citação precisa de espaço para se ler; bolha de "oi" com citação
        // esmagada não diz nada.
        let quoteMin: CGFloat = quoteView == nil ? 0 : 300
        return min(min(available, Self.maxWidth),
                   max(textWidth + 26 + Self.cellSlack, headerWidth, quoteMin))
    }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 13, y: 10,
                              width: header.intrinsicContentSize.width, height: 15)
        let timeWidth = time.intrinsicContentSize.width
        time.frame = NSRect(x: bounds.width - timeWidth - 13, y: 11,
                            width: timeWidth, height: 13)
        quoteView?.frame = NSRect(x: 13, y: 30, width: bounds.width - 26,
                                  height: ChatQuoteView.height)
        body.frame = NSRect(x: 13, y: 30 + quoteBlock, width: bounds.width - 26,
                            height: max(0, bounds.height - 41 - quoteBlock))
    }
}

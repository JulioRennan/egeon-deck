import AppKit

// MARK: - Bolha de mensagem enviada

/// Uma mensagem SUA na thread: começa com a menção `@agente` na cor dele, como
/// no WhatsApp, e o texto segue na mesma linha; hora no canto de baixo.
final class ChatBubbleView: NSView, ThreadBubble {
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
        // Cor fixa, sua: o lado direito é só seu, e um fundo que variasse com o
        // destinatário faria a bolha parecer do agente.
        layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.24, blue: 0.46, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(srgbRed: 0.24, green: 0.44, blue: 0.75, alpha: 0.7).cgColor

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        time.font = .systemFont(ofSize: 10.5)
        time.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        time.stringValue = formatter.string(from: at)

        // A menção é o endereçamento: quem lê sabe para quem foi sem cabeçalho.
        let mention = NSMutableAttributedString(
            string: "@\(target.id) ",
            attributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                         .foregroundColor: target.color])
        mention.append(NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 13.5),
                         .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1)]))
        body.attributedStringValue = mention

        [time, body].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// Prompt com citação: clicar em qualquer parte dele leva à fala citada.
    override func mouseDown(with event: NSEvent) { onQuoteClick?() }

    /// A célula do NSTextField come uns pixels de cada lado antes de quebrar a
    /// linha; medir sem essa folga corta a última palavra.
    private static let cellSlack: CGFloat = 8

    private var quoteBlock: CGFloat { quoteView == nil ? 0 : ChatQuoteView.height + 8 }

    private func textHeight(width: CGFloat) -> CGFloat {
        ceil(body.attributedStringValue
            .boundingRect(with: NSSize(width: width - 26 - Self.cellSlack, height: .infinity),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    /// Altura para uma largura dada — quem empilha pergunta antes de posicionar.
    func height(for width: CGFloat) -> CGFloat {
        // 10 em cima, texto, 4, linha da hora (13), 9 embaixo.
        10 + quoteBlock + textHeight(width: min(width, Self.maxWidth)) + 4 + 13 + 9
    }

    func width(for available: CGFloat) -> CGFloat {
        let textWidth = ceil(body.attributedStringValue
            .boundingRect(with: NSSize(width: Self.maxWidth - 26 - Self.cellSlack,
                                       height: .infinity),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).width)
        // Citação precisa de espaço para se ler; bolha de "oi" com citação
        // esmagada não diz nada.
        let quoteMin: CGFloat = quoteView == nil ? 0 : 300
        let timeMin = time.intrinsicContentSize.width + 40
        return min(min(available, Self.maxWidth),
                   max(textWidth + 26 + Self.cellSlack, quoteMin, timeMin))
    }

    override func layout() {
        super.layout()
        quoteView?.frame = NSRect(x: 13, y: 10, width: bounds.width - 26,
                                  height: ChatQuoteView.height)
        let bodyHeight = textHeight(width: bounds.width)
        body.frame = NSRect(x: 13, y: 10 + quoteBlock, width: bounds.width - 26,
                            height: bodyHeight)
        let timeWidth = time.intrinsicContentSize.width
        time.frame = NSRect(x: bounds.width - timeWidth - 13, y: bounds.height - 22,
                            width: timeWidth, height: 13)
    }
}

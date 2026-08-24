import AppKit

// MARK: - A citação em cima da bolha

/// Mini-card com fio colorido à esquerda: quem falou, quando, e o trecho —
/// no máximo duas linhas. Clique rola até a mensagem original.
final class ChatQuoteView: NSView {
    var onClick: (() -> Void)?

    private let author = NSTextField(labelWithString: "")
    private let excerpt = NSTextField(wrappingLabelWithString: "")
    private let bar = NSView()

    static let height: CGFloat = 52

    init(quote: ChatQuote, authorLabel: String, color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.30).cgColor

        bar.wantsLayer = true
        bar.layer?.backgroundColor = color.cgColor
        bar.layer?.cornerRadius = 1.5
        addSubview(bar)

        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        author.stringValue = "\(authorLabel) · \(clock.string(from: quote.at))"
        author.font = .systemFont(ofSize: 10.5, weight: .bold)
        author.textColor = color
        addSubview(author)

        excerpt.stringValue = quote.text.replacingOccurrences(of: "\n", with: " ")
        excerpt.font = .systemFont(ofSize: 12)
        excerpt.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        excerpt.maximumNumberOfLines = 2
        excerpt.lineBreakMode = .byTruncatingTail
        excerpt.cell?.truncatesLastVisibleLine = true
        addSubview(excerpt)

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    @objc private func clicked() { onClick?() }

    override func layout() {
        super.layout()
        bar.frame = NSRect(x: 0, y: 0, width: 3, height: bounds.height)
        author.frame = NSRect(x: 10, y: 7, width: bounds.width - 20, height: 13)
        excerpt.frame = NSRect(x: 10, y: 22, width: bounds.width - 20, height: bounds.height - 28)
    }
}

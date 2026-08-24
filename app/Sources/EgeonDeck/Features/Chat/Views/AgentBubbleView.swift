import AppKit

// MARK: - Bolha de resposta do agente

/// O que o agente respondeu: cabeçalho na cor dele, a pilha de passos
/// (fechada por padrão) e o texto final. Sub-conversas e citações entram
/// depois — a forma da bolha já reserva o lugar.
final class AgentBubbleView: NSView, ThreadBubble {
    var onToggleSteps: (() -> Void)?
    var onQuoteClick: (() -> Void)?
    private var quoteView: ChatQuoteView?

    private let name = NSTextField(labelWithString: "")
    private let address = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let stepsBox = NSView()
    private let stepsHeader = NSTextField(labelWithString: "")
    private var stepRows: [NSTextField] = []
    private let body = NSTextField(wrappingLabelWithString: "")

    private let steps: [ChatStep]
    private let expanded: Bool
    private let hasBody: Bool

    static let maxWidth: CGFloat = 660
    private static let stepRowHeight: CGFloat = 18

    let alignsRight = false

    /// Azul do seu prompt — a cor do fio da citação quando o citado é você.
    static let youColor = NSColor(srgbRed: 0.184, green: 0.498, blue: 0.965, alpha: 1)

    init(from participant: ChatParticipant, turn: ChatTurn, expanded: Bool,
         quote: ChatQuote? = nil) {
        steps = turn.steps
        self.expanded = expanded
        hasBody = !turn.replyText.isEmpty
        super.init(frame: .zero)
        decorate(color: participant.color)

        name.stringValue = "\(participant.glyph) \(participant.id)"
        name.textColor = participant.color
        address.stringValue = participant.address
        time.stringValue = Self.clock.string(from: turn.replyAt ?? turn.promptAt)

        if let quote {
            let view = ChatQuoteView(quote: quote, authorLabel: "você → \(participant.id)",
                                     color: Self.youColor)
            view.onClick = { [weak self] in self?.onQuoteClick?() }
            addSubview(view)
            quoteView = view
        }

        if !steps.isEmpty {
            stepsBox.wantsLayer = true
            stepsBox.layer?.cornerRadius = 10
            stepsBox.layer?.borderWidth = 1
            stepsBox.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
            stepsBox.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.03).cgColor
            let edits = steps.filter { $0.glyph == "±" }.count
            var summary = "\(steps.count) passo\(steps.count == 1 ? "" : "s")"
            if edits > 0 { summary += " · \(edits) edição\(edits == 1 ? "" : "ões")" }
            stepsHeader.stringValue = "\(expanded ? "▾" : "▸")  \(summary)"
            stepsHeader.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
            stepsHeader.textColor = NSColor(calibratedWhite: 0.6, alpha: 1)
            stepsBox.addSubview(stepsHeader)
            let click = NSClickGestureRecognizer(target: self, action: #selector(toggle))
            stepsBox.addGestureRecognizer(click)
            if expanded {
                stepRows = steps.map { step in
                    let row = NSTextField(labelWithString: "\(step.glyph)  \(step.text)")
                    row.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                    row.textColor = NSColor(calibratedWhite: 0.7, alpha: 1)
                    row.lineBreakMode = .byTruncatingMiddle
                    stepsBox.addSubview(row)
                    return row
                }
            }
            addSubview(stepsBox)
        }

        body.font = .systemFont(ofSize: 13.5)
        body.textColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        body.stringValue = turn.replyText
        body.isHidden = !hasBody
        addSubview(body)
    }

    /// A bolha de "digitando…": o agente está trabalhando e ainda não há texto.
    init(typing participant: ChatParticipant) {
        steps = []
        expanded = false
        hasBody = true
        super.init(frame: .zero)
        decorate(color: participant.color)
        name.stringValue = "\(participant.glyph) \(participant.id)"
        name.textColor = participant.color
        address.stringValue = participant.address
        time.stringValue = "agora"
        body.font = .systemFont(ofSize: 11.5)
        body.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        body.stringValue = "\(Spinner.current) trabalhando…"
        addSubview(body)
    }

    /// Só a bolha de "trabalhando…" tem o que animar; o resto ignora o tique.
    func tick() {
        guard isTyping else { return }
        body.stringValue = "\(Spinner.current) trabalhando…"
    }
    private var isTyping: Bool { time.stringValue == "agora" }

    private func decorate(color: NSColor) {
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor(srgbRed: 0.075, green: 0.094, blue: 0.149,
                                         alpha: 0.92).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = color.withAlphaComponent(0.38).cgColor
        name.font = .systemFont(ofSize: 13, weight: .bold)
        address.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        address.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        time.font = .systemFont(ofSize: 10.5)
        time.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        [name, address, time].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    @objc private func toggle() { onToggleSteps?() }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: Medidas

    private var stepsHeight: CGFloat {
        guard !steps.isEmpty else { return 0 }
        return 26 + (expanded ? CGFloat(steps.count) * Self.stepRowHeight + 6 : 0)
    }

    private func bodyHeight(width: CGFloat) -> CGFloat {
        guard hasBody else { return 0 }
        return ceil(body.attributedStringValue
            .boundingRect(with: NSSize(width: width - 26 - 8, height: .infinity),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    private var quoteBlock: CGFloat { quoteView == nil ? 0 : ChatQuoteView.height + 8 }

    func height(for width: CGFloat) -> CGFloat {
        var total: CGFloat = 10 + 16 + quoteBlock
        if !steps.isEmpty { total += 8 + stepsHeight }
        if hasBody { total += 8 + bodyHeight(width: width) }
        return total + 12
    }

    func width(for available: CGFloat) -> CGFloat {
        let cap = min(available, Self.maxWidth)
        let textWidth = hasBody ? ceil(body.attributedStringValue
            .boundingRect(with: NSSize(width: cap - 34, height: .infinity),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).width) + 34 : 0
        let headerWidth = name.intrinsicContentSize.width + address.intrinsicContentSize.width
            + time.intrinsicContentSize.width + 50
        let stepsWidth: CGFloat = steps.isEmpty ? 0 : (expanded ? 420 : 240)
        let quoteMin: CGFloat = quoteView == nil ? 0 : 300
        return min(cap, max(textWidth, headerWidth, stepsWidth, quoteMin))
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 10
        let nameWidth = name.intrinsicContentSize.width
        name.frame = NSRect(x: 13, y: y, width: nameWidth, height: 16)
        address.frame = NSRect(x: 13 + nameWidth + 8, y: y + 2,
                               width: address.intrinsicContentSize.width, height: 13)
        let timeWidth = time.intrinsicContentSize.width
        time.frame = NSRect(x: bounds.width - timeWidth - 13, y: y + 2,
                            width: timeWidth, height: 13)
        y += 16

        if let quoteView {
            y += 8
            quoteView.frame = NSRect(x: 13, y: y, width: bounds.width - 26,
                                     height: ChatQuoteView.height)
            y += ChatQuoteView.height
        }

        if !steps.isEmpty {
            y += 8
            stepsBox.frame = NSRect(x: 13, y: y, width: bounds.width - 26, height: stepsHeight)
            stepsHeader.frame = NSRect(x: 10, y: 6, width: stepsBox.bounds.width - 20, height: 14)
            for (index, row) in stepRows.enumerated() {
                row.frame = NSRect(x: 10, y: 28 + CGFloat(index) * Self.stepRowHeight,
                                   width: stepsBox.bounds.width - 20, height: Self.stepRowHeight)
            }
            y += stepsHeight
        }

        if hasBody {
            y += 8
            body.frame = NSRect(x: 13, y: y, width: bounds.width - 26,
                                height: bodyHeight(width: bounds.width))
        }
    }
}

/// O que a thread empilha: mede a si mesma e diz de que lado fica.
protocol ThreadBubble: NSView {
    var alignsRight: Bool { get }
    func width(for available: CGFloat) -> CGFloat
    func height(for width: CGFloat) -> CGFloat
}

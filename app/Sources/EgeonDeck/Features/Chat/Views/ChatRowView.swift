import AppKit

// MARK: - Uma linha da thread

/// Base das linhas da tabela: sabe o bloco e a medida, e desenha o pedaço da
/// bolha que lhe cabe — cantos só na primeira e na última linha, e o fundo
/// estendido para fora da linha nas outras, para a bolha ler contínua
/// (ADR-042). Quem herda posiciona o conteúdo em `layout()`.
class ChatRowView: NSView {
    private(set) var block: ChatBlock?
    private(set) var metrics = ChatRowMetrics(height: 0, bubbleWidth: 0)
    /// Clique na linha: leva ao que ela cita ou responde.
    var onClick: (() -> Void)?
    /// Clique no título de um passo: abre ou recolhe.
    var onToggle: (() -> Void)?
    /// Acesa um instante depois de uma rolagem por citação.
    var flashing = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ block: ChatBlock, metrics: ChatRowMetrics) {
        self.block = block
        self.metrics = metrics
        alphaValue = { if case .prompt(_, _, _, _, _, true, _) = block.kind { return 0.6 } else { return 1 } }()
        apply()
        needsLayout = true
        needsDisplay = true
    }

    /// O conteúdo mudou: quem herda repõe textos e subviews.
    func apply() {}

    /// A bolha nesta linha, sem o vão de baixo da última.
    var bubbleRect: NSRect {
        guard let block else { return .zero }
        let x = block.alignsRight
            ? bounds.width - ChatBlockLayout.sideInset - metrics.bubbleWidth
            : ChatBlockLayout.sideInset
        let height = bounds.height - (block.last ? ChatBlockLayout.gap : 0)
        return NSRect(x: x, y: 0, width: metrics.bubbleWidth, height: height)
    }

    private static let radius: CGFloat = 14

    override func draw(_ dirtyRect: NSRect) {
        guard let block else { return }
        var rect = bubbleRect
        // Linha do meio: o retângulo sai da linha por cima e por baixo, e o
        // clipe da própria linha corta — só as bordas laterais aparecem.
        if !block.first { rect.origin.y -= Self.radius; rect.size.height += Self.radius }
        if !block.last { rect.size.height += Self.radius }
        rect = rect.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: Self.radius, yRadius: Self.radius)
        let you = block.alignsRight
        (you ? Self.youFill : Self.agentFill).setFill()
        path.fill()
        let border = flashing ? NSColor.white.withAlphaComponent(0.7)
            : you ? Self.youBorder : block.participant.color.withAlphaComponent(0.38)
        border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// Cor fixa, sua: o lado direito é só seu, e um fundo que variasse com o
    /// destinatário faria a bolha parecer do agente.
    private static let youFill = NSColor(srgbRed: 0.11, green: 0.24, blue: 0.46, alpha: 1)
    private static let youBorder = NSColor(srgbRed: 0.24, green: 0.44, blue: 0.75, alpha: 0.7)
    private static let agentFill = NSColor(srgbRed: 0.075, green: 0.094, blue: 0.149, alpha: 0.92)

    override func mouseDown(with event: NSEvent) { onClick?() }

    // MARK: Peças que as linhas dividem

    /// Um NSTextView só para mostrar, com o MESMO TextKit da medição: TextKit 1
    /// explícito, sem inset e sem folga de fragmento — a altura desenhada é a
    /// altura medida.
    static func makeTextView() -> NSTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let view = NSTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize.zero
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        return view
    }

    static func label(_ font: NSFont, _ color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = font
        field.textColor = color
        // Sem modo de truncar: com ele o `intrinsicContentSize` encolhe e o
        // rótulo sai "b…" mesmo com espaço de sobra.
        return field
    }

    /// A caixa de passo e de bloco de código dentro da bolha.
    static func makeBox() -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        box.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.03).cgColor
        return box
    }
}

// MARK: - Prosa, código e passo

/// Uma linha de texto da resposta: prosa solta, ou passo/código na sua caixa.
final class ChatTextRow: ChatRowView {
    static let identifier = NSUserInterfaceItemIdentifier("chat.text")
    private let text = ChatRowView.makeTextView()
    private let box = ChatRowView.makeBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(box)
        addSubview(text)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply() {
        guard let block else { return }
        // O texto vem medido e renderizado da fila de fundo; renderizar aqui
        // de novo era markdown e realce duas vezes por linha.
        text.textStorage?.setAttributedString(
            metrics.text ?? ChatBlockLayout.attributed(block.kind) ?? NSAttributedString())
        box.isHidden = !ChatBlockLayout.isBoxed(block.kind)
    }

    /// A faixa do título de um passo com o que abrir: a primeira linha da
    /// caixa, de borda a borda. É ela que alterna; o resto da caixa continua
    /// texto selecionável — o comando aberto é para copiar.
    var toggleRect: NSRect? {
        guard let block, case .step(_, let step, _) = block.kind, step.isExpandable else { return nil }
        let pad = ChatBlockLayout.boxPadding
        var line: CGFloat = 16
        if let manager = text.layoutManager, manager.numberOfGlyphs > 0 {
            line = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
        }
        return NSRect(x: box.frame.minX, y: box.frame.minY,
                      width: box.frame.width, height: pad * 2 + line)
    }

    /// O NSTextView engole o clique; na faixa do título a linha fica com ele.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let rect = toggleRect, rect.contains(convert(point, from: superview)) { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        if let rect = toggleRect, rect.contains(convert(event.locationInWindow, from: nil)) {
            onToggle?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func resetCursorRects() {
        if let rect = toggleRect { addCursorRect(rect, cursor: .pointingHand) }
    }

    override func layout() {
        super.layout()
        guard let block else { return }
        let bubble = bubbleRect
        let inset = ChatBlockLayout.textInset
        let height = bubble.height - ChatBlockLayout.rowGap - (block.last ? 12 : 0)
        let area = NSRect(x: bubble.minX + inset, y: ChatBlockLayout.rowGap,
                          width: bubble.width - inset * 2, height: height)
        if ChatBlockLayout.isBoxed(block.kind) {
            box.frame = area
            let pad = ChatBlockLayout.boxPadding
            text.frame = NSRect(x: area.minX + 10, y: area.minY + pad,
                                width: area.width - 20, height: area.height - pad * 2)
        } else {
            text.frame = area
        }
        window?.invalidateCursorRects(for: self)
    }
}

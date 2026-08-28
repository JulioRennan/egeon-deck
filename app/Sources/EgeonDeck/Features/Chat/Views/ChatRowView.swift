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
    static func makeTextView() -> StepTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let view = StepTextView(frame: .zero, textContainer: container)
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

}

// MARK: - Prosa, código e passo

/// Uma linha de texto da resposta: prosa solta, ou passo/código na sua caixa.
/// Passos contíguos dividem uma caixa só: cada linha desenha o seu pedaço dela
/// — cantos só nas pontas do grupo, e no meio o retângulo sai da linha para o
/// clipe cortar, deixando as laterais contínuas (ADR-047).
final class ChatTextRow: ChatRowView {
    static let identifier = NSUserInterfaceItemIdentifier("chat.text")
    let text = ChatRowView.makeTextView()

    private static let radius: CGFloat = 8
    private static let boxFill = NSColor(calibratedWhite: 1, alpha: 0.03)
    private static let boxBorder = NSColor(calibratedWhite: 1, alpha: 0.08)
    private static let titleFill = NSColor(calibratedWhite: 1, alpha: 0.05)
    private static let titleHover = NSColor(calibratedWhite: 1, alpha: 0.10)
    private static let contentFill = NSColor(calibratedWhite: 0, alpha: 0.20)

    /// Mouse em cima do cabeçalho: é o realce que diz "aqui se clica" antes
    /// de você clicar.
    private var hoveringTitle = false {
        didSet { if oldValue != hoveringTitle { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(text)
        text.onHoverToggle = { [weak self] over in self?.hoveringTitle = over }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func apply() {
        guard let block else { return }
        // O texto vem medido e renderizado da fila de fundo; renderizar aqui
        // de novo era markdown e realce duas vezes por linha.
        text.textStorage?.setAttributedString(
            metrics.text ?? ChatBlockLayout.attributed(block.kind) ?? NSAttributedString())
    }

    /// O pedaço da caixa que cabe nesta linha, sem o vão do fim da bolha.
    private var boxRect: NSRect? {
        guard let block, ChatBlockLayout.isBoxed(block.kind) else { return nil }
        let bubble = bubbleRect
        let inset = ChatBlockLayout.textInset
        let top: CGFloat = block.boxTop ? ChatBlockLayout.rowGap : 0
        let bottom = bubble.height - (block.last ? 12 : 0)
        return NSRect(x: bubble.minX + inset, y: top,
                      width: bubble.width - inset * 2, height: max(0, bottom - top))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let block, let box = boxRect else { return }
        var rect = box
        if !block.boxTop { rect.origin.y -= Self.radius; rect.size.height += Self.radius }
        if !block.boxBottom { rect.size.height += Self.radius }
        rect = rect.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: Self.radius, yRadius: Self.radius)
        Self.boxFill.setFill()
        path.fill()

        // Anatomia de tile: o cabeçalho tem fundo próprio (e clareia sob o
        // mouse) e o miolo é mais fundo — a diferença é a única pista de onde
        // o clique age e onde só há texto para ler e copiar.
        if let strip = toggleRect {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let open = expandedStep
            if open || hoveringTitle {
                (hoveringTitle ? Self.titleHover : Self.titleFill).setFill()
                strip.fill()
            }
            if open {
                Self.contentFill.setFill()
                NSRect(x: box.minX, y: strip.maxY, width: box.width,
                       height: max(0, box.maxY - strip.maxY)).fill()
                Self.boxBorder.setFill()
                NSRect(x: box.minX, y: strip.maxY - 0.5, width: box.width, height: 1).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        Self.boxBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// Passo aberto — o que tem miolo para separar do cabeçalho. A capa do
    /// grupo não tem miolo: o que ela abre são as linhas seguintes.
    private var expandedStep: Bool {
        guard let block, case .step(_, let step, let open) = block.kind else { return false }
        return open && step.isExpandable
    }

    /// A faixa do título de um passo com o que abrir: a primeira linha dele,
    /// de borda a borda da caixa. É ela que alterna; o resto continua texto
    /// selecionável — o comando aberto é para copiar.
    var toggleRect: NSRect? {
        guard let block, let box = boxRect else { return nil }
        switch block.kind {
        case .step(_, let step, _) where step.isExpandable: break
        // A capa do grupo é toda cabeçalho: uma linha, e o clique nela avança.
        case .group: break
        default: return nil
        }
        var line: CGFloat = 16
        if let manager = text.layoutManager, manager.numberOfGlyphs > 0 {
            line = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).height
        }
        // Termina no fim da PRIMEIRA linha: com o respiro de baixo somado, a
        // faixa entrava alguns pontos na linha seguinte — clique e cursor de
        // mão em cima do comando, que é texto para copiar.
        return NSRect(x: box.minX, y: box.minY, width: box.width,
                      height: (text.frame.minY - box.minY) + line)
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

    override func layout() {
        super.layout()
        guard let block else { return }
        let bubble = bubbleRect
        let inset = ChatBlockLayout.textInset
        if let box = boxRect {
            let pad = ChatBlockLayout.boxPadding
            let top = box.minY + (block.boxTop ? pad : ChatBlockLayout.stepGap)
            text.frame = NSRect(x: box.minX + 10, y: top, width: box.width - 20,
                                height: max(0, box.maxY - top - (block.boxBottom ? pad : 0)))
        } else {
            let height = bubble.height - ChatBlockLayout.rowGap - (block.last ? 12 : 0)
            text.frame = NSRect(x: bubble.minX + inset, y: ChatBlockLayout.rowGap,
                                width: bubble.width - inset * 2, height: height)
        }
        // Quanto da caixa é a faixa do título, para o texto saber onde mostrar
        // a mão. O cursor tem um dono só (`StepTextView`): com a linha
        // registrando um `cursorRect` de mão por baixo e o texto pedindo
        // I-beam por cima, o ponteiro piscava entre os dois sem sair do lugar.
        text.toggleHeight = toggleRect.map { $0.maxY - text.frame.minY } ?? 0
        // A linha é reusada e muda de lugar: os rects registrados estão no
        // ponto da janela onde ela estava antes.
        window?.invalidateCursorRects(for: text)
    }
}

// MARK: - O texto de uma linha

/// O `NSTextView` das linhas. Ele cobre a faixa do título de um passo, então é
/// ele quem manda no cursor ali: mão na faixa, I-beam no resto.
///
/// Os TRÊS caminhos, e não o que parece o certo: o AppKit resolve o ponteiro
/// por cursor rect, por `cursorUpdate` de tracking area e pelo `mouseMoved` da
/// própria `NSTextView` — qual deles chega por último depende da versão e de
/// quem mais está na hierarquia. Cobrir um só foi o que fez a mão não aparecer
/// duas vezes seguidas; nenhum deles chama `super`, senão o I-beam volta por
/// baixo.
final class StepTextView: NSTextView {
    /// Altura da faixa de título dentro deste texto; zero quando não há o que abrir.
    var toggleHeight: CGFloat = 0 {
        didSet {
            guard oldValue != toggleHeight else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    /// Avisa a linha quando o mouse entra e sai da faixa do título.
    var onHoverToggle: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverToggle?(isOnToggle(convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) { onHoverToggle?(false) }

    /// Ponto no espaço deste texto: está na faixa que abre o passo?
    func isOnToggle(_ point: NSPoint) -> Bool { toggleHeight > 0 && point.y <= toggleHeight }

    /// Onde vai cada cursor.
    func cursorRects(in bounds: NSRect) -> [(rect: NSRect, cursor: NSCursor)] {
        guard toggleHeight > 0 else { return [] }
        let strip = NSRect(x: 0, y: 0, width: bounds.width, height: min(toggleHeight, bounds.height))
        let rest = NSRect(x: 0, y: strip.maxY, width: bounds.width,
                          height: max(0, bounds.height - strip.height))
        return rest.height > 0 ? [(strip, .pointingHand), (rest, .iBeam)] : [(strip, .pointingHand)]
    }

    private func set(at point: NSPoint) {
        (isOnToggle(point) ? NSCursor.pointingHand : NSCursor.iBeam).set()
    }

    override func resetCursorRects() {
        let rects = cursorRects(in: bounds)
        guard !rects.isEmpty else { return super.resetCursorRects() }
        for (rect, cursor) in rects { addCursorRect(rect, cursor: cursor) }
    }

    override func cursorUpdate(with event: NSEvent) {
        guard toggleHeight > 0 else { return super.cursorUpdate(with: event) }
        set(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHoverToggle?(isOnToggle(point))
        guard toggleHeight > 0 else { return super.mouseMoved(with: event) }
        set(at: point)
    }

    /// A linha da tabela é reusada: quando ela entra na janela (ou muda de
    /// tamanho), os rects registrados são de outra medida.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Sem isto o `mouseMoved` não chega — e ele é um dos três caminhos.
        window?.acceptsMouseMovedEvents = true
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { window?.invalidateCursorRects(for: self) }
    }
}

import AppKit

/// O cronômetro da bancada numa pastilha (ADR-074): na barra de ações do
/// canvas e na coluna do chat, ao lado do custo — tempo e dinheiro se leem
/// juntos. O clique oferece zerar.
final class ClockChip: NSView {
    var onReset: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var signature = ""
    private var hovering = false { didSet { restyle() } }
    private var shown: WorkbenchClock?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        label.lineBreakMode = .byClipping
        addSubview(label)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var preferredWidth: CGFloat { ceil(label.intrinsicContentSize.width) + 20 }

    /// Chega 8 vezes por segundo; devolve se a largura mudou, para quem a
    /// posiciona refazer o layout.
    @discardableResult
    func show(_ clock: WorkbenchClock, phases: Set<WorkbenchClock.Phase>) -> Bool {
        let next = WorkbenchClockText.signature(clock, phases: phases)
        guard next != signature else { return false }
        signature = next
        shown = clock
        let before = preferredWidth
        label.attributedStringValue = WorkbenchClockText.attributed(clock, phases: phases, size: 11)
        toolTip = WorkbenchClockText.tooltip(clock) + "\nclique para zerar"
        needsLayout = true
        return preferredWidth != before
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 10, y: (bounds.height - 15) / 2, width: bounds.width - 16, height: 15)
    }

    private func restyle() {
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: hovering ? 0.12 : 0.06).cgColor
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard shown != nil else { return }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Zerar cronômetro", action: #selector(reset), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 4), in: self)
    }

    @objc private func reset() { onReset?() }

    override func resetCursorRects() { HandCursor.fill(self) }
}

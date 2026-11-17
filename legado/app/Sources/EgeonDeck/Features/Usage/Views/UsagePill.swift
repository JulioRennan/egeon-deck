import AppKit

/// O custo da bancada numa pastilha (ADR-085): na barra de ações do canvas e
/// no topo do chat. O clique abre o detalhe.
final class UsagePill: NSView {
    var onClick: ((NSView) -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "US$ —")
    private var hovering = false { didSet { restyle() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        icon.image = NSImage(systemSymbolName: "dollarsign.circle", accessibilityDescription: "custo")
        icon.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        icon.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.6)
        label.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = NSColor(calibratedWhite: 1, alpha: 0.85)
        label.lineBreakMode = .byClipping
        addSubview(icon)
        addSubview(label)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        toolTip = "Consumo da bancada — clique para o detalhe"
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var preferredWidth: CGFloat { ceil(label.intrinsicContentSize.width) + 16 + 6 + 16 }

    /// Devolve se a largura mudou — quem a posiciona refaz o layout.
    @discardableResult
    func show(_ text: String, tooltip: String?) -> Bool {
        let before = preferredWidth
        label.stringValue = text
        toolTip = (tooltip.map { $0 + "\n\n" } ?? "") + "Clique para o detalhe por agente e modelo."
        needsLayout = true
        return preferredWidth != before
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 7, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.frame = NSRect(x: 26, y: (bounds.height - 15) / 2, width: bounds.width - 30, height: 15)
    }

    private func restyle() {
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: hovering ? 0.12 : 0.06).cgColor
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?(self) }
    override func resetCursorRects() { HandCursor.fill(self) }
}

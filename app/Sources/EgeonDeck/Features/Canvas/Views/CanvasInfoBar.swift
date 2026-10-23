import AppKit

/// A barra informativa do canvas, sob a de ações: o cronômetro e o custo da
/// bancada (ADR-085). Sem fundo próprio — quem dá o vidro é o `GlassPanel`.
final class CanvasInfoBar: NSView {
    let clock = ClockChip()
    let usage = UsagePill()
    /// O texto muda de largura ("09:59" → "10:00", "US$ 9,99" → "US$ 10,00"):
    /// a barra é centrada pelo canvas, que refaz a conta.
    var onWidthChange: (() -> Void)?

    private static let padding: CGFloat = 4
    private static let gap: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(clock)
        addSubview(usage)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        NSSize(width: Self.padding * 2 + clock.preferredWidth + Self.gap + usage.preferredWidth, height: 34)
    }

    override func layout() {
        super.layout()
        let y = (bounds.height - 26) / 2
        clock.frame = NSRect(x: Self.padding, y: y, width: clock.preferredWidth, height: 26)
        usage.frame = NSRect(x: clock.frame.maxX + Self.gap, y: y, width: usage.preferredWidth, height: 26)
    }

    func showClock(_ value: WorkbenchClock, phases: Set<WorkbenchClock.Phase>) {
        guard clock.show(value, phases: phases) else { return }
        needsLayout = true
        onWidthChange?()
    }

    func showUsage(_ text: String, tooltip: String?) {
        guard usage.show(text, tooltip: tooltip) else { return }
        needsLayout = true
        onWidthChange?()
    }
}

import AppKit

/// O contexto em uso no cabeçalho do card: uma pizza que enche com a porcentagem
/// ao lado, as duas indo do verde ao vermelho conforme a janela enche.
final class ContextIndicator: NSView {
    private static let pieSize: CGFloat = 12
    private static let gap: CGFloat = 4
    private static let height: CGFloat = 14
    private static let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    private static let idle = NSColor(calibratedWhite: 0.62, alpha: 1)

    private let label = NSTextField(labelWithString: "—")

    /// Nil é "não se sabe": anel vazio e travessão.
    var gauge: ContextGauge? {
        didSet {
            guard gauge != oldValue else { return }
            label.stringValue = gauge?.text ?? "—"
            label.textColor = color
            toolTip = gauge.map { "\($0.detail). O CLI pode compactar a conversa antes de encher" }
                ?? "Sem resposta do modelo ainda nesta conversa"
            needsLayout = true
            needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = Self.font
        label.lineBreakMode = .byClipping
        label.textColor = Self.idle
        addSubview(label)
        toolTip = "Sem resposta do modelo ainda nesta conversa"
    }

    required init?(coder: NSCoder) { fatalError() }

    var text: String { label.stringValue }

    private var color: NSColor {
        guard let gauge else { return Self.idle }
        return NSColor(calibratedHue: gauge.hue / 360, saturation: 0.72, brightness: 0.95, alpha: 1)
    }

    override var fittingSize: NSSize {
        let text = ceil((label.stringValue as NSString).size(withAttributes: [.font: Self.font]).width) + 2
        return NSSize(width: Self.pieSize + Self.gap + text, height: Self.height)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: Self.pieSize + Self.gap, y: (bounds.height - 13) / 2,
                             width: max(0, bounds.width - Self.pieSize - Self.gap), height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSRect(x: 0.5, y: (bounds.height - Self.pieSize) / 2 + 0.5,
                            width: Self.pieSize - 1, height: Self.pieSize - 1)
        let ring = NSBezierPath(ovalIn: circle)
        NSColor(calibratedWhite: 1, alpha: 0.1).setFill()
        ring.fill()
        guard let gauge, gauge.used > 0 else {
            NSColor(calibratedWhite: 1, alpha: 0.28).setStroke()
            ring.stroke()
            return
        }
        color.setFill()
        color.withAlphaComponent(0.55).setStroke()
        ring.stroke()
        if gauge.fraction >= 1 {
            ring.fill()
            return
        }
        let center = NSPoint(x: circle.midX, y: circle.midY)
        let wedge = NSBezierPath()
        wedge.move(to: center)
        wedge.appendArc(withCenter: center, radius: circle.width / 2, startAngle: 90,
                        endAngle: 90 - 360 * gauge.fraction, clockwise: true)
        wedge.close()
        wedge.fill()
    }
}

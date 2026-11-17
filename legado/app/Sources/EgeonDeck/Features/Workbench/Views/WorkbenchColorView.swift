import AppKit

extension WorkbenchColor {
    var nsColor: NSColor {
        NSColor(calibratedRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    /// A bolinha do item de menu.
    var dot: NSImage {
        let side: CGFloat = 12
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            self.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }
}

/// A grade da paleta num popover — a mesma na bolinha do título e no menu de
/// contexto da bancada na barra lateral (ADR-086). Grade, e não menu: com 24
/// cores, uma lista de nomes obriga a ler, e a cor é para escolher de olho.
final class WorkbenchColorPalette: NSViewController, NSPopoverDelegate {
    private static let columns = 6
    private static let side: CGFloat = 26
    private static let gap: CGFloat = 10
    private static let inset: CGFloat = 14

    private let current: WorkbenchColor?
    private let onPick: (WorkbenchColor) -> Void
    private let caption = NSTextField(labelWithString: "")
    /// O popover só vive enquanto alguém o segura; quem segura é a paleta, até
    /// ele fechar.
    private var popover: NSPopover?

    private init(current: WorkbenchColor?, onPick: @escaping (WorkbenchColor) -> Void) {
        self.current = current
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func show(current: WorkbenchColor?, relativeTo rect: NSRect, of view: NSView,
                     edge: NSRectEdge, onPick: @escaping (WorkbenchColor) -> Void) {
        let palette = WorkbenchColorPalette(current: current, onPick: onPick)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = palette
        popover.delegate = palette
        palette.popover = popover
        popover.show(relativeTo: rect, of: view, preferredEdge: edge)
    }

    func popoverDidClose(_ notification: Notification) { popover = nil }

    override func loadView() {
        let all = WorkbenchColor.allCases
        let rows = (all.count + Self.columns - 1) / Self.columns
        let gridWidth = CGFloat(Self.columns) * Self.side + CGFloat(Self.columns - 1) * Self.gap
        let gridHeight = CGFloat(rows) * Self.side + CGFloat(rows - 1) * Self.gap
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: gridWidth + Self.inset * 2,
                                             height: Self.inset + 18 + gridHeight + 10 + 16 + Self.inset))

        let title = NSTextField(labelWithString: "Cor da bancada")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: Self.inset, y: Self.inset - 2, width: gridWidth, height: 16)
        root.addSubview(title)

        let top = Self.inset + 18
        for (index, color) in all.enumerated() {
            let swatch = PaletteSwatch(color: color, isCurrent: color == current)
            let column = index % Self.columns, row = index / Self.columns
            swatch.frame = NSRect(x: Self.inset + CGFloat(column) * (Self.side + Self.gap),
                                  y: top + CGFloat(row) * (Self.side + Self.gap),
                                  width: Self.side, height: Self.side)
            swatch.onHover = { [weak self] hovering in
                self?.caption.stringValue = hovering ? color.label : (self?.current?.label ?? "")
            }
            swatch.onClick = { [weak self] in
                self?.onPick(color)
                self?.popover?.close()
            }
            root.addSubview(swatch)
        }

        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .labelColor
        caption.stringValue = current?.label ?? ""
        caption.frame = NSRect(x: Self.inset, y: top + gridHeight + 10, width: gridWidth, height: 16)
        root.addSubview(caption)
        view = root
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Uma bolinha da grade. A atual leva um aro claro por fora; passar o mouse
/// cresce o aro, para o alvo ser óbvio num quadro de 24 pontos iguais.
private final class PaletteSwatch: HandView {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    private let fill = CALayer()
    private let ring = CALayer()
    private let isCurrent: Bool

    init(color: WorkbenchColor, isCurrent: Bool) {
        self.isCurrent = isCurrent
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = color.label
        fill.backgroundColor = color.nsColor.cgColor
        ring.borderColor = NSColor.labelColor.withAlphaComponent(0.9).cgColor
        ring.borderWidth = isCurrent ? 2 : 0
        layer?.addSublayer(ring)
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        ring.frame = bounds
        ring.cornerRadius = bounds.width / 2
        let inner = bounds.insetBy(dx: 4, dy: 4)
        fill.frame = inner
        fill.cornerRadius = inner.width / 2
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        ring.borderWidth = 2
        ring.borderColor = NSColor.labelColor.withAlphaComponent(isCurrent ? 0.9 : 0.45).cgColor
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        ring.borderWidth = isCurrent ? 2 : 0
        ring.borderColor = NSColor.labelColor.withAlphaComponent(0.9).cgColor
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

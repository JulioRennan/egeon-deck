import AppKit

/// As duas abas no topo da barra lateral: Todas e Ativas (ADR-082). Uma
/// cápsula com dois segmentos, no lugar do antigo título "WORKSPACES".
final class SidebarTabs: NSView {
    static let height: CGFloat = 32

    var onSelect: ((Sidebar.Tab) -> Void)?
    var selected: Sidebar.Tab = .all { didSet { restyle() } }
    /// Quantas estão de pé, ao lado de "Ativas" — sem precisar trocar de aba.
    var activeCount = 0 {
        didSet {
            guard activeCount != oldValue else { return }
            restyle()
        }
    }
    var allCount = 0 {
        didSet {
            guard allCount != oldValue else { return }
            restyle()
        }
    }

    private let all = Segment(.all)
    private let active = Segment(.active)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.22).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
        for segment in [all, active] {
            segment.onClick = { [weak self] in self?.onSelect?($0) }
            addSubview(segment)
        }
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let inset: CGFloat = 3
        let half = ((bounds.width - inset * 2) / 2).rounded()
        all.frame = NSRect(x: inset, y: inset, width: half, height: bounds.height - inset * 2)
        active.frame = NSRect(x: inset + half, y: inset, width: bounds.width - inset * 2 - half,
                              height: bounds.height - inset * 2)
    }

    private func restyle() {
        all.show("Todas", count: allCount, live: false, selected: selected == .all)
        active.show("Ativas", count: activeCount, live: true, selected: selected == .active)
    }

    private final class Segment: NSView {
        let tab: Sidebar.Tab
        var onClick: ((Sidebar.Tab) -> Void)?
        private let title = NSTextField(labelWithString: "")
        /// A contagem numa pastilha própria, e não no texto: centrar título e
        /// número juntos deixava o título fora do centro do segmento.
        private let pill = NSTextField(labelWithString: "")
        private let pillBack = NSView()

        init(_ tab: Sidebar.Tab) {
            self.tab = tab
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 7
            pillBack.wantsLayer = true
            pillBack.layer?.cornerRadius = 7
            addSubview(title)
            addSubview(pillBack)
            addSubview(pill)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }

        func show(_ text: String, count: Int, live: Bool, selected: Bool) {
            layer?.backgroundColor = selected
                ? NSColor(calibratedWhite: 1, alpha: 0.13).cgColor : NSColor.clear.cgColor
            layer?.shadowOpacity = selected ? 0.25 : 0
            layer?.shadowRadius = 2
            layer?.shadowOffset = NSSize(width: 0, height: -1)
            title.attributedStringValue = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: selected ? .semibold : .medium),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: selected ? 0.95 : 0.5),
            ])
            let tint: NSColor = live ? .systemGreen : NSColor(calibratedWhite: 1, alpha: 1)
            pill.attributedStringValue = NSAttributedString(string: "\(count)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: tint.withAlphaComponent(selected ? 0.95 : 0.55),
            ])
            pillBack.layer?.backgroundColor = tint.withAlphaComponent(selected ? 0.18 : 0.08).cgColor
            pill.isHidden = count == 0
            pillBack.isHidden = count == 0
            needsLayout = true
        }

        override func layout() {
            super.layout()
            let titleWidth = ceil(title.attributedStringValue.size().width) + 4
            let pillWidth = pill.isHidden ? 0 : max(18, ceil(pill.attributedStringValue.size().width) + 10)
            let gap: CGFloat = pill.isHidden ? 0 : 6
            var x = ((bounds.width - titleWidth - gap - pillWidth) / 2).rounded()
            title.frame = NSRect(x: x, y: (bounds.height - 16) / 2, width: titleWidth, height: 16)
            x += titleWidth + gap
            pillBack.frame = NSRect(x: x, y: (bounds.height - 14) / 2, width: pillWidth, height: 14)
            pill.frame = NSRect(x: x, y: pillBack.frame.minY + 0.5, width: pillWidth, height: 13)
            pill.alignment = .center
        }

        override func mouseDown(with event: NSEvent) { onClick?(tab) }
        override func resetCursorRects() { HandCursor.fill(self) }
    }
}

/// O rótulo de cada metade da aba Ativas: "ÚLTIMAS 24 HORAS · 3".
final class SidebarSectionLabel: NSTextField {
    static let height: CGFloat = 22

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ title: String, count: Int) {
        let text = NSMutableAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.42),
        ])
        text.append(NSAttributedString(string: "  \(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.3),
        ]))
        attributedStringValue = text
    }
}

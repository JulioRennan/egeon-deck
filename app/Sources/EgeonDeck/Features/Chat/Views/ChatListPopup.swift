import AppKit

// MARK: - Popup de escolha

/// A lista flutuante que o composer abre — o alternador de destinatário e a
/// menção por `@` são a MESMA view com conteúdos diferentes: linhas com glifo
/// colorido, nome e legenda, navegáveis por seta e Enter.
final class ChatListPopup: NSView {
    struct Item {
        let name: String
        let detail: String
        let color: NSColor
        let glyph: String
    }

    var onChoose: ((Int) -> Void)?

    private(set) var items: [Item] = []
    private var selected = 0
    private var rowViews: [NSView] = []
    private let header = NSTextField(labelWithString: "")

    static let rowHeight: CGFloat = 34

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.078, green: 0.098, blue: 0.149,
                                         alpha: 0.97).cgColor
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
        shadow = NSShadow()
        shadow?.shadowBlurRadius = 24
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.5)

        header.font = .systemFont(ofSize: 9.5, weight: .bold)
        header.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        addSubview(header)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func show(_ items: [Item], title: String) {
        self.items = items
        selected = 0
        header.stringValue = title
        rebuild()
    }

    var desiredHeight: CGFloat { 30 + CGFloat(items.count) * Self.rowHeight + 6 }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
        rebuild()
    }

    func chooseSelected() { if !items.isEmpty { onChoose?(selected) } }

    private func rebuild() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = items.enumerated().map { index, item in
            let row = HandView()
            row.wantsLayer = true
            row.layer?.cornerRadius = 9
            if index == selected {
                row.layer?.backgroundColor =
                    NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
            }

            let glyph = NSTextField(labelWithString: item.glyph)
            glyph.font = .systemFont(ofSize: 13)
            glyph.textColor = item.color
            glyph.frame = NSRect(x: 9, y: 9, width: 16, height: 16)
            row.addSubview(glyph)

            let name = NSTextField(labelWithString: item.name)
            name.font = .systemFont(ofSize: 12.5, weight: .semibold)
            name.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
            name.frame = NSRect(x: 30, y: 9, width: 110, height: 16)
            row.addSubview(name)

            let detail = NSTextField(labelWithString: item.detail)
            detail.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            detail.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
            detail.frame = NSRect(x: 142, y: 11, width: 140, height: 13)
            detail.lineBreakMode = .byTruncatingTail
            row.addSubview(detail)

            let click = NSClickGestureRecognizer(target: self,
                                                 action: #selector(rowClicked(_:)))
            row.addGestureRecognizer(click)
            row.identifier = NSUserInterfaceItemIdentifier("\(index)")
            addSubview(row)
            return row
        }
        needsLayout = true
    }

    @objc private func rowClicked(_ gesture: NSClickGestureRecognizer) {
        guard let raw = gesture.view?.identifier?.rawValue,
              let index = Int(raw) else { return }
        onChoose?(index)
    }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 12, y: 9, width: bounds.width - 24, height: 12)
        for (index, row) in rowViews.enumerated() {
            row.frame = NSRect(x: 6, y: 28 + CGFloat(index) * Self.rowHeight,
                               width: bounds.width - 12, height: Self.rowHeight - 2)
        }
    }
}

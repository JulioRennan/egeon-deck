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
    /// O texto da barra de busca mudou.
    var onSearch: ((String) -> Void)?
    /// Setas, Enter, Tab e Esc digitados na barra — o dono decide, como faz
    /// com as do composer.
    var onSearchCommand: ((Selector) -> Bool)?

    private(set) var items: [Item] = []
    private var selected = 0
    /// Lista maior que a janela rola: só as linhas à vista viram view, e
    /// `top` é a primeira delas. A seleção arrasta a janela junto.
    private var visibleRows = Int.max
    private var top = 0
    private var rowViews: [NSView] = []
    private let header = NSTextField(labelWithString: "")
    private let scroller = NSView()
    /// Só na lista de comandos: a de agentes e a de menção são curtas.
    private let search = NSSearchField()
    private var searchable = false
    private static let searchHeight: CGFloat = 32

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

        scroller.wantsLayer = true
        scroller.layer?.cornerRadius = 1.5
        scroller.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.22).cgColor
        addSubview(scroller)

        search.appearance = NSAppearance(named: .darkAqua)
        search.placeholderString = "Buscar por nome ou descrição  ⌘F"
        search.font = .systemFont(ofSize: 12)
        search.focusRingType = .none
        search.sendsSearchStringImmediately = true
        search.delegate = self
        search.isHidden = true
        addSubview(search)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// A coluna do nome cabe o maior nome, até um teto: `figma:figma-use`
    /// não cabe nos 110pt de um nome de agente.
    private var nameWidth: CGFloat = 110

    /// `searchable` põe a barra de busca em cima; o texto dela fica enquanto
    /// a lista não fecha — quem limpa é `clearSearch`.
    func show(_ items: [Item], title: String, visibleRows: Int = .max, searchable: Bool = false) {
        self.items = items
        self.visibleRows = max(1, visibleRows)
        self.searchable = searchable
        search.isHidden = !searchable
        selected = 0
        top = 0
        header.stringValue = title
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let widest = items.map { ($0.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        nameWidth = min(max(110, ceil(widest) + 4), 240)
        rebuild()
    }

    private var shownCount: Int { min(items.count, visibleRows) }

    private var rowsTop: CGFloat { 28 + (searchable ? Self.searchHeight : 0) }

    var desiredHeight: CGFloat { rowsTop + 2 + CGFloat(shownCount) * Self.rowHeight + 6 }

    var searchText: String { search.stringValue }

    var searchHasFocus: Bool {
        guard let editor = window?.firstResponder as? NSText else { return false }
        return editor.delegate === search
    }

    func focusSearch() { window?.makeFirstResponder(search) }

    func clearSearch() { search.stringValue = "" }

    func setSearch(_ text: String) {
        search.stringValue = text
        onSearch?(text)
    }

    func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
        if selected < top { top = selected }
        if selected >= top + shownCount { top = selected - shownCount + 1 }
        rebuild()
    }

    override func scrollWheel(with event: NSEvent) {
        guard items.count > shownCount else { return super.scrollWheel(with: event) }
        wheel += event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? Self.rowHeight : 1)
        let steps = Int(wheel)
        guard steps != 0 else { return }
        wheel -= CGFloat(steps)
        let newTop = min(max(0, top - steps), items.count - shownCount)
        guard newTop != top else { return }
        top = newTop
        selected = min(max(selected, top), top + shownCount - 1)
        rebuild()
    }

    private var wheel: CGFloat = 0

    func chooseSelected() { if !items.isEmpty { onChoose?(selected) } }

    private func rebuild() {
        rowViews.forEach { $0.removeFromSuperview() }
        let end = min(items.count, top + shownCount)
        rowViews = (top..<end).map { index in
            let item = items[index]
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
            name.frame = NSRect(x: 30, y: 9, width: nameWidth, height: 16)
            name.lineBreakMode = .byTruncatingTail
            row.addSubview(name)

            let detail = NSTextField(labelWithString: item.detail)
            detail.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            detail.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
            detail.frame = NSRect(x: 32 + nameWidth, y: 11,
                                  width: max(60, bounds.width - 12 - 42 - nameWidth), height: 13)
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

    private var builtWidth: CGFloat = 0

    override func layout() {
        super.layout()
        if bounds.width != builtWidth { builtWidth = bounds.width; rebuild() }
        header.frame = NSRect(x: 12, y: 9, width: bounds.width - 24, height: 12)
        search.frame = NSRect(x: 10, y: 27, width: bounds.width - 20, height: 24)
        for (index, row) in rowViews.enumerated() {
            row.frame = NSRect(x: 6, y: rowsTop + CGFloat(index) * Self.rowHeight,
                               width: bounds.width - 12, height: Self.rowHeight - 2)
        }
        scroller.isHidden = items.count <= shownCount
        if !scroller.isHidden {
            let track = CGFloat(shownCount) * Self.rowHeight - 4
            let height = max(18, track * CGFloat(shownCount) / CGFloat(items.count))
            let y = rowsTop + 2 + (track - height) * CGFloat(top) / CGFloat(items.count - shownCount)
            scroller.frame = NSRect(x: bounds.width - 5, y: y, width: 3, height: height)
        }
    }
}

extension ChatListPopup: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) { onSearch?(search.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        onSearchCommand?(selector) ?? false
    }
}

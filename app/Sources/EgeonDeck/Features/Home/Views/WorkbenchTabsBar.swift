import AppKit

// MARK: - A faixa de bancadas abertas

/// Uma aba. Pastilha com o nome, os badges de atividade e o x de fechar.
///
/// O x só aparece na aba em que o mouse está ou na que está na tela: uma fileira
/// de x's compete com os badges, que são o que se lê de relance aqui.
final class WorkbenchTabView: NSView {
    let id: String
    var onClick: ((String) -> Void)?
    var onClose: ((String) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let close = NSTextField(labelWithString: "✕")
    private var hovering = false { didSet { restyle() } }
    private var trackingArea: NSTrackingArea?

    private var isActive = false
    private var wantsAttention = false
    /// Última combinação desenhada. O spinner troca oito vezes por segundo e o
    /// resto quase nunca: sem isto seria uma `NSAttributedString` nova por
    /// quadro, por aba.
    private var lastBadge = ""
    private var badgeWidth: CGFloat = 0

    init(tab: WorkbenchTab) {
        self.id = tab.id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7

        label.stringValue = tab.name
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        badge.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        addSubview(badge)

        close.font = .systemFont(ofSize: 9, weight: .bold)
        close.textColor = NSColor(calibratedWhite: 1, alpha: 0.45)
        close.isHidden = true
        addSubview(close)

        show(tab)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    static let height: CGFloat = 26

    /// Largura pedida: nome + badges + x, com teto — trinta bancadas abertas não
    /// podem espremer a faixa a ponto de nenhum nome se ler.
    ///
    /// O espaço do x entra SEMPRE, mesmo quando ele está escondido: senão o nome
    /// encolhe e reticencia no instante em que o mouse passa por cima, e a aba
    /// dança enquanto você percorre a faixa.
    var fittingWidth: CGFloat {
        min(max(label.intrinsicContentSize.width + badgeWidth + 48, 110), 240)
    }

    func show(_ tab: WorkbenchTab) {
        if label.stringValue != tab.name { label.stringValue = tab.name }

        let signature = "\(tab.summary.starting)/\(tab.summary.working)/"
            + "\(tab.summary.attention)/\(tab.summary.done)/"
            + (tab.isWorking ? String(Spinner.current) : "")
        if signature != lastBadge {
            lastBadge = signature
            badge.attributedStringValue = Self.badgeText(tab)
            let width = badge.attributedStringValue.length == 0
                ? 0 : ceil(badge.attributedStringValue.size().width) + 6
            if width != badgeWidth { badgeWidth = width; needsLayout = true }
        }

        if isActive != tab.isActive || wantsAttention != tab.wantsAttention {
            isActive = tab.isActive
            wantsAttention = tab.wantsAttention
            restyle()
            needsLayout = true
        }
    }

    /// Mesmos glifos, mesmas cores e mesma ordem fixa da barra lateral: quem
    /// aprendeu a ler lá não aprende de novo aqui (ADR-024).
    private static func badgeText(_ tab: WorkbenchTab) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func add(_ glyph: String, _ count: Int, _ color: NSColor) {
            guard count > 0 else { return }
            if out.length > 0 { out.append(NSAttributedString(string: " ")) }
            out.append(NSAttributedString(string: count > 1 ? "\(glyph)\(count)" : glyph,
                                          attributes: [.foregroundColor: color]))
        }
        add(String(Spinner.current), tab.summary.starting,
            NSColor(calibratedWhite: 1, alpha: 0.3))
        add(String(Spinner.current), tab.summary.working,
            NSColor(calibratedWhite: 1, alpha: 0.6))
        add("●", tab.summary.attention, .systemOrange)
        add("●", tab.summary.done, .systemGreen)
        return out
    }

    private func restyle() {
        let background: CGFloat = isActive ? 0.16 : (hovering ? 0.10 : 0)
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: background * 0.6).cgColor
        label.textColor = NSColor(calibratedWhite: 1, alpha: isActive ? 0.95 : 0.55)
        // O aro laranja é o mesmo da pastilha da lateral: a bancada que pede
        // alguma coisa se reconhece sem ler o nome.
        layer?.borderWidth = wantsAttention ? 1 : 0
        layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.8).cgColor
        close.isHidden = !(isActive || hovering)
    }

    override func layout() {
        super.layout()
        let right = bounds.width - 8
        close.frame = NSRect(x: right - 10, y: (bounds.height - 12) / 2, width: 10, height: 12)
        let badgeX = right - 14 - badgeWidth
        badge.frame = NSRect(x: badgeX, y: (bounds.height - 13) / 2, width: badgeWidth, height: 13)
        label.frame = NSRect(x: 10, y: (bounds.height - 15) / 2,
                             width: max(0, badgeX - 14), height: 15)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !close.isHidden, close.frame.insetBy(dx: -6, dy: -6).contains(point) {
            onClose?(id)
        } else {
            onClick?(id)
        }
    }

    override func resetCursorRects() {
        HandCursor.fill(self)
    }
}

/// A faixa: as bancadas ABERTAS, na ordem em que você as abriu.
///
/// A barra lateral é o catálogo — tudo que existe. A faixa é a pergunta do dia
/// a dia: o que está aberto, e qual delas quer alguma coisa de mim. Por isso ela
/// mostra o mesmo estado da lateral, e não um resumo diferente.
final class WorkbenchTabsBar: NSView {
    static let height: CGFloat = 34

    var onPick: ((String) -> Void)?
    var onClose: ((String) -> Void)?

    private var views: [WorkbenchTabView] = []
    /// Ids na ordem desenhada. Remontar só quando ISTO muda; o resto é `show`.
    private var mounted: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Quanto a faixa recua à esquerda: a barra lateral flutua sobre o conteúdo,
    /// e uma aba por baixo do vidro é uma aba que não se clica.
    var leftInset: CGFloat = 0 {
        didSet { if leftInset != oldValue { needsLayout = true } }
    }

    func show(_ tabs: [WorkbenchTab]) {
        let ids = tabs.map(\.id)
        if ids != mounted {
            mounted = ids
            views.forEach { $0.removeFromSuperview() }
            views = tabs.map { tab in
                let view = WorkbenchTabView(tab: tab)
                view.onClick = { [weak self] in self?.onPick?($0) }
                view.onClose = { [weak self] in self?.onClose?($0) }
                addSubview(view)
                return view
            }
            needsLayout = true
        } else {
            for (view, tab) in zip(views, tabs) { view.show(tab) }
        }
        isHidden = tabs.isEmpty
    }

    override func layout() {
        super.layout()
        guard !views.isEmpty else { return }
        // Cabe o que cabe: com muitas bancadas abertas as pastilhas encolhem até
        // o mínimo legível, todas juntas, em vez de a última sumir do lado de
        // fora — quem tem oito bancadas abertas precisa das oito à vista.
        let available = max(0, bounds.width - leftInset - 8)
        let wanted = views.reduce(0) { $0 + $1.fittingWidth } + CGFloat(views.count - 1) * 4
        let scale = wanted > available && wanted > 0 ? available / wanted : 1
        var x = leftInset + 4
        let y = (bounds.height - WorkbenchTabView.height) / 2
        for view in views {
            let width = max(52, (view.fittingWidth * scale).rounded())
            view.frame = NSRect(x: x, y: y, width: width, height: WorkbenchTabView.height)
            x += width + 4
        }
    }

    /// Onde cada pastilha ficou, para conferir de fora — aba desenhada por baixo
    /// da barra lateral é aba que ninguém clica, e isso não se vê num print.
    var placement: [[String: Any]] {
        views.map { view in
            let inWindow = view.convert(view.bounds, to: nil)
            return ["id": view.id, "x": Int(view.frame.minX), "w": Int(view.frame.width),
                    "windowX": Int(inWindow.minX), "windowY": Int(inWindow.minY),
                    "hidden": view.isHidden]
        }
    }

    /// Fio embaixo, como na barra de cima: a faixa encosta no conteúdo.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 1, alpha: 0.07).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}

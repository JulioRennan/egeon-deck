import AppKit

/// O detalhe do consumo de uma bancada (ADR-085), num popover: o total e para
/// onde ele foi, cada agente e cada modelo com a sua barra, e a tabela de
/// preços recolhida embaixo.
final class UsagePanel: NSViewController {
    private let heading: String
    private let ledger: UsageLedger
    private let prices: PriceTable

    init(title: String, ledger: UsageLedger, prices: PriceTable) {
        self.heading = title
        self.ledger = ledger
        self.prices = prices
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Abre ancorado em `view`, com a aparência escura do resto do app.
    static func show(title: String, ledger: UsageLedger, prices: PriceTable, from view: NSView,
                     pricesOpen: Bool = false) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        let panel = UsagePanel(title: title, ledger: ledger, prices: prices)
        panel.pricesOpen = pricesOpen
        popover.contentViewController = panel
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    fileprivate var pricesOpen = false

    /// Teto do popover: bancada com muitos agentes, ou a tabela de preços
    /// aberta, passava da tela. Daí para cima, rola.
    private static var maxHeight: CGFloat {
        min(560, (NSScreen.main?.visibleFrame.height ?? 900) * 0.75)
    }

    override func loadView() {
        let panel = UsagePanelView(heading: heading, ledger: ledger, prices: prices)
        panel.showsPrices = pricesOpen
        let scroll = NSScrollView()
        scroll.documentView = panel
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = UsagePanelView.background
        panel.onResize = { [weak self] size in
            self?.preferredContentSize = NSSize(width: size.width, height: min(size.height, Self.maxHeight))
        }
        view = scroll
        panel.rebuild()
    }
}

/// As cores das quatro tarifas, as mesmas na barra e na legenda.
private enum Tariff: CaseIterable {
    case output, input, cacheWrite, cacheRead

    var title: String {
        switch self {
        case .input: return "Entrada"
        case .output: return "Saída"
        case .cacheWrite: return "Cache escrito"
        case .cacheRead: return "Cache lido"
        }
    }

    var color: NSColor {
        switch self {
        case .input: return NSColor(srgbRed: 0.40, green: 0.62, blue: 1.00, alpha: 1)
        case .output: return NSColor(srgbRed: 0.78, green: 0.53, blue: 0.98, alpha: 1)
        case .cacheWrite: return NSColor(srgbRed: 0.96, green: 0.66, blue: 0.30, alpha: 1)
        case .cacheRead: return NSColor(srgbRed: 0.33, green: 0.82, blue: 0.74, alpha: 1)
        }
    }

    func dollars(_ cost: TariffCost) -> Double {
        switch self {
        case .input: return cost.input
        case .output: return cost.output
        case .cacheWrite: return cost.cacheWrite
        case .cacheRead: return cost.cacheRead
        }
    }

    func tokens(_ usage: TokenUsage) -> Int {
        switch self {
        case .input: return usage.input
        case .output: return usage.output
        case .cacheWrite: return usage.cacheWrite
        case .cacheRead: return usage.cacheRead
        }
    }
}

private final class UsagePanelView: NSView {
    static let background = NSColor(calibratedWhite: 0.115, alpha: 1)
    var onResize: ((NSSize) -> Void)?

    private let heading: String
    private let ledger: UsageLedger
    private let prices: PriceTable
    var showsPrices = false

    private static let width: CGFloat = 400
    private static let pad: CGFloat = 20

    init(heading: String, ledger: UsageLedger, prices: PriceTable) {
        self.heading = heading
        self.ledger = ledger
        self.prices = prices
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        wantsLayer = true
        // Fundo cheio: o vidro do popover deixava o canvas aparecer por trás
        // dos números.
        layer?.backgroundColor = Self.background.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        let pad = Self.pad
        let inner = Self.width - pad * 2
        var y: CGFloat = 18

        let total = ledger.total
        let tokens = total.totalUsage
        let split = prices.split(total)

        place(label(heading.uppercased(), size: 10, weight: .bold, alpha: 0.42, kern: 0.8), x: pad, y: &y, width: inner, gap: 6)
        let amount = label(UsageText.cost(total, prices: prices), size: 30, weight: .semibold, alpha: 0.96, mono: true)
        let count = label("\(UsageText.tokens(tokens.total)) tokens", size: 11, weight: .medium, alpha: 0.45, mono: true)
        count.alignment = .right
        amount.frame = NSRect(x: pad, y: y, width: inner, height: 36)
        count.frame = NSRect(x: pad, y: y + 16, width: inner, height: 15)
        addSubview(amount)
        addSubview(count)
        y += 46

        let bar = StackedBar(parts: Tariff.allCases.map { ($0.color, $0.dollars(split)) })
        bar.frame = NSRect(x: pad, y: y, width: inner, height: 8)
        addSubview(bar)
        y += 18

        // A legenda em duas colunas: valor e tokens de cada tarifa.
        let column = (inner - 16) / 2
        for (index, tariff) in Tariff.allCases.enumerated() {
            let item = LegendItem(color: tariff.color, title: tariff.title,
                                  amount: UsageText.dollars(tariff.dollars(split)),
                                  detail: "\(UsageText.tokens(tariff.tokens(tokens))) tokens")
            item.frame = NSRect(x: pad + CGFloat(index % 2) * (column + 16), y: y + CGFloat(index / 2) * 40,
                                width: column, height: 34)
            addSubview(item)
        }
        y += 84

        let agents = ledger.byNode.map { (node: $0.key, usage: $0.value, cost: prices.cost($0.value).dollars) }
            .sorted { $0.cost > $1.cost }
        if !agents.isEmpty {
            y += 8
            section("Agentes", count: agents.count, y: &y)
            let top = max(agents.first?.cost ?? 0, 0.0001)
            for agent in agents {
                let usage = agent.usage.totalUsage
                let row = BarRow(color: AgentPalette.color(for: agent.node), name: agent.node,
                                 tag: prices.mainModel(agent.usage), amount: UsageText.cost(agent.usage, prices: prices),
                                 fraction: agent.cost / top, detail: Self.detail(usage))
                row.frame = NSRect(x: pad, y: y, width: inner, height: BarRow.height)
                addSubview(row)
                y += BarRow.height + 6
            }
        }

        var byModel: UsageByPrice = [:]
        for (key, usage) in total { byModel[key, default: TokenUsage()] += usage }
        let models = byModel.map { (key: $0.key, usage: $0.value, cost: prices.cost([$0.key: $0.value]).dollars) }
            .sorted { $0.cost > $1.cost }
        if !models.isEmpty {
            y += 8
            section("Modelos", count: models.count, y: &y)
            let top = max(models.first?.cost ?? 0, 0.0001)
            for model in models {
                let row = BarRow(color: Self.familyColor(model.key), name: prices.name(for: model.key), tag: nil,
                                 amount: UsageText.cost([model.key: model.usage], prices: prices),
                                 fraction: model.cost / top, detail: Self.detail(model.usage))
                row.frame = NSRect(x: pad, y: y, width: inner, height: BarRow.height)
                addSubview(row)
                y += BarRow.height + 6
            }
        }

        y += 8
        let divider = NSView(frame: NSRect(x: pad, y: y, width: inner, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        addSubview(divider)
        y += 12

        let toggle = DisclosureRow(title: "Tabela de preços", detail: "US$ por milhão de tokens", open: showsPrices)
        toggle.onClick = { [weak self] in
            guard let self else { return }
            self.showsPrices.toggle()
            self.rebuild()
        }
        toggle.frame = NSRect(x: pad - 6, y: y, width: inner + 12, height: 24)
        addSubview(toggle)
        y += 30

        if showsPrices {
            let card = priceCard(used: Set(byModel.keys), width: inner)
            card.frame.origin = NSPoint(x: pad, y: y)
            addSubview(card)
            y += card.frame.height + 10
        }

        let foot = label("Modo rápido custa 2× · editável em "
                         + PriceTable.file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                         size: 10, alpha: 0.32)
        place(foot, x: pad, y: &y, width: inner, gap: 0)
        y += 16

        let size = NSSize(width: Self.width, height: y)
        setFrameSize(size)
        onResize?(size)
    }

    private static func detail(_ usage: TokenUsage) -> String {
        "saída \(UsageText.tokens(usage.output)) · cache lido \(UsageText.tokens(usage.cacheRead))"
            + " · escrito \(UsageText.tokens(usage.cacheWrite)) · entrada \(UsageText.tokens(usage.input))"
    }

    /// Família pela cor: quem olha a lista reconhece Opus, Sonnet e Haiku sem
    /// ler o nome.
    private static func familyColor(_ key: String) -> NSColor {
        if key.contains("opus") { return NSColor(srgbRed: 0.78, green: 0.53, blue: 0.98, alpha: 1) }
        if key.contains("sonnet") { return NSColor(srgbRed: 0.40, green: 0.62, blue: 1.00, alpha: 1) }
        if key.contains("haiku") { return NSColor(srgbRed: 0.33, green: 0.82, blue: 0.55, alpha: 1) }
        if key.contains("fable") || key.contains("mythos") {
            return NSColor(srgbRed: 0.96, green: 0.74, blue: 0.30, alpha: 1)
        }
        return NSColor(calibratedWhite: 0.7, alpha: 1)
    }

    private func section(_ title: String, count: Int, y: inout CGFloat) {
        let text = NSMutableAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.42), .kern: 0.8,
        ])
        text.append(NSAttributedString(string: "  \(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.25),
        ]))
        let field = NSTextField(labelWithAttributedString: text)
        field.frame = NSRect(x: Self.pad, y: y, width: Self.width - Self.pad * 2, height: 14)
        addSubview(field)
        y += 22
    }

    private func priceCard(used: Set<String>, width: CGFloat) -> NSView {
        let rows = prices.models
            .filter { !$0.key.hasSuffix("#long") || used.contains($0.key) }
            .sorted { (used.contains($0.key) ? 0 : 1, -$0.value.input, $0.value.name)
                    < (used.contains($1.key) ? 0 : 1, -$1.value.input, $1.value.name) }
        func money(_ value: Double) -> String {
            (value >= 1 ? String(format: "%.2f", value) : String(format: "%.3f", value))
                .replacingOccurrences(of: ".", with: ",")
        }
        var cells: [[NSView]] = [["", "Entrada", "Saída", "5 min", "1 h", "Lido"].map {
            label($0, size: 9.5, weight: .bold, alpha: 0.38)
        }]
        for (key, price) in rows {
            let lit = used.contains(key)
            let alpha: CGFloat = lit ? 0.92 : 0.42
            let values = [price.input, price.output, price.cacheWrite5m ?? price.input * 1.25,
                          price.cacheWrite1h ?? price.input * 2, price.cacheRead]
            cells.append([label((lit ? "● " : "") + price.name, size: 11, weight: lit ? .semibold : .regular, alpha: alpha)]
                         + values.map { label(money($0), size: 11, alpha: alpha, mono: true) })
        }
        let grid = NSGridView(views: cells)
        grid.columnSpacing = 12
        grid.rowSpacing = 6
        for column in 1..<6 { grid.column(at: column).xPlacement = .trailing }
        let size = grid.fittingSize
        let card = NSView(frame: NSRect(x: 0, y: 0, width: width, height: size.height + 24))
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.04).cgColor
        grid.frame = NSRect(x: 12, y: 12, width: width - 24, height: size.height)
        card.addSubview(grid)
        return card
    }

    private func place(_ view: NSTextField, x: CGFloat, y: inout CGFloat, width: CGFloat, gap: CGFloat) {
        let height = ceil(view.intrinsicContentSize.height)
        view.frame = NSRect(x: x, y: y, width: width, height: height)
        addSubview(view)
        y += height + gap
    }
}

private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, alpha: CGFloat,
                   mono: Bool = false, kern: CGFloat = 0) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    field.textColor = NSColor(calibratedWhite: 1, alpha: alpha)
    field.lineBreakMode = .byTruncatingTail
    if kern != 0 {
        field.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: field.font!, .foregroundColor: field.textColor!, .kern: kern,
        ])
    }
    return field
}

/// A largura do texto em si. O `intrinsicContentSize` de rótulo com
/// truncamento volta curto, e o nome saía "cle…".
private func textWidth(_ field: NSTextField) -> CGFloat {
    let text = field.attributedStringValue.length > 0 ? field.attributedStringValue
        : NSAttributedString(string: field.stringValue, attributes: [.font: field.font as Any])
    return ceil(text.size().width) + 6
}

/// A barra do total, um segmento por tarifa, proporcional ao dinheiro.
private final class StackedBar: NSView {
    private let parts: [(NSColor, Double)]

    init(parts: [(NSColor, Double)]) {
        self.parts = parts
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let total = parts.reduce(0) { $0 + $1.1 }
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(calibratedWhite: 1, alpha: 0.06).setFill()
        track.fill()
        guard total > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        var x: CGFloat = 0
        for (color, value) in parts where value > 0 {
            let width = bounds.width * CGFloat(value / total)
            color.setFill()
            // Um fio escuro entre os segmentos: cores vizinhas se fundiam.
            NSRect(x: x, y: 0, width: max(0, width - 1.5), height: bounds.height).fill()
            x += width
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class LegendItem: NSView {
    private var valueField: NSTextField?

    init(color: NSColor, title: String, amount: String, detail: String) {
        super.init(frame: .zero)
        let dot = NSView(frame: NSRect(x: 0, y: 4, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = color.cgColor
        addSubview(dot)
        let name = label(title, size: 11, weight: .medium, alpha: 0.7)
        name.frame = NSRect(x: 14, y: 0, width: 110, height: 15)
        addSubview(name)
        let value = label(amount, size: 11.5, weight: .semibold, alpha: 0.92, mono: true)
        value.alignment = .right
        addSubview(value)
        valueField = value
        let tokens = label(detail, size: 10, alpha: 0.4, mono: true)
        tokens.frame = NSRect(x: 14, y: 17, width: 150, height: 13)
        addSubview(tokens)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        valueField?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 16)
    }
}

/// Uma linha com barra: nome, etiqueta, valor, a barra proporcional ao maior
/// da lista e os tokens embaixo.
private final class BarRow: NSView {
    static let height: CGFloat = 50

    private var valueField: NSTextField?
    private var trackView: NSView?
    private var fillView: NSView?
    private var detailField: NSTextField?
    private var fraction = 0.0

    init(color: NSColor, name: String, tag: String?, amount: String, fraction: Double, detail: String) {
        super.init(frame: .zero)
        let dot = NSView(frame: NSRect(x: 0, y: 5, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = color.cgColor
        addSubview(dot)

        let title = label(name, size: 12.5, weight: .semibold, alpha: 0.92)
        let titleWidth = min(textWidth(title), 200)
        title.frame = NSRect(x: 16, y: 0, width: titleWidth, height: 17)
        addSubview(title)

        if let tag {
            let chip = label(tag, size: 9.5, weight: .semibold, alpha: 0.55)
            let width = textWidth(chip) + 10
            chip.alignment = .center
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 5
            chip.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
            chip.frame = NSRect(x: 16 + titleWidth + 6, y: 2, width: width, height: 14)
            addSubview(chip)
        }

        let value = label(amount, size: 12.5, weight: .semibold, alpha: 0.95, mono: true)
        value.alignment = .right
        addSubview(value)
        valueField = value

        let track = NSView()
        track.wantsLayer = true
        track.layer?.cornerRadius = 2
        track.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
        addSubview(track)
        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 2
        fill.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        addSubview(fill)
        trackView = track
        fillView = fill
        self.fraction = max(0, min(1, fraction))

        let tokens = label(detail, size: 10, alpha: 0.4, mono: true)
        addSubview(tokens)
        detailField = tokens
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        valueField?.frame = NSRect(x: bounds.width - 110, y: 0, width: 110, height: 17)
        trackView?.frame = NSRect(x: 16, y: 23, width: bounds.width - 16, height: 4)
        // Um mínimo visível: valor pequeno ainda tem de mostrar que existe.
        let fill = max(4, (bounds.width - 16) * CGFloat(fraction))
        fillView?.frame = NSRect(x: 16, y: 23, width: fill, height: 4)
        detailField?.frame = NSRect(x: 16, y: 32, width: bounds.width - 16, height: 13)
    }
}

/// "▸ Tabela de preços": o clique abre e fecha.
private final class DisclosureRow: NSView {
    var onClick: (() -> Void)?
    private var hovering = false {
        didSet { layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: hovering ? 0.06 : 0).cgColor }
    }

    init(title: String, detail: String, open: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        let chevron = NSImageView(image: NSImage(systemSymbolName: open ? "chevron.down" : "chevron.right",
                                                 accessibilityDescription: nil) ?? NSImage())
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        chevron.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.5)
        chevron.frame = NSRect(x: 6, y: 5, width: 12, height: 14)
        addSubview(chevron)
        let name = label(title, size: 11.5, weight: .semibold, alpha: 0.8)
        let width = textWidth(name)
        name.frame = NSRect(x: 22, y: 4, width: width, height: 16)
        addSubview(name)
        let note = label(detail, size: 10.5, alpha: 0.35)
        note.frame = NSRect(x: 22 + width + 8, y: 5, width: 200, height: 14)
        addSubview(note)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { HandCursor.fill(self) }
}

import AppKit

/// O painel da direita: quem está na sessão e o que está rodando.
///
/// Existe porque o chat esconde os cards, e com eles some a única coisa que o
/// canvas dava de graça: dá para ver de relance que `dev-backend` está trabalhando
/// e que o `vitest` caiu. Aqui isso volta como lista, e a lista cabe em 300pt —
/// no canvas os mesmos cinco cards não caberiam sem zoom.
final class ChatSidePanel: NSView {
    /// Clicar num agente aponta o composer para ele. É o atalho que substitui
    /// "clicar no card e digitar".
    var onPickAgent: ((String) -> Void)?
    /// Clicar num processo abre a saída dele.
    var onOpenProcess: ((String) -> Void)?
    var onToggleCollapse: (() -> Void)?

    private(set) var isCollapsed = false

    static let width: CGFloat = 300
    static let collapsedWidth: CGFloat = 30

    private let title = ChatStyle.label("NA SESSÃO", font: ChatStyle.sectionTitle,
                                        color: ChatStyle.dim)
    private let toggle = NSButton()
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var rows: [NSView] = []
    private var drawn = ""
    /// Qual agente o composer está mirando, para a pastilha PARA.
    var aimed: String = "" { didSet { if aimed != oldValue { drawn = ""; needsLayout = true } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = ChatStyle.panelBackground.cgColor

        addSubview(title)
        toggle.title = "»"
        toggle.isBordered = false
        toggle.font = ChatStyle.mono
        toggle.contentTintColor = ChatStyle.dim
        toggle.target = self
        toggle.action = #selector(toggleClicked)
        addSubview(toggle)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    @objc private func toggleClicked() { onToggleCollapse?() }

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        toggle.title = collapsed ? "«" : "»"
        title.isHidden = collapsed
        scroll.isHidden = collapsed
        needsLayout = true
    }

    // MARK: Conteúdo

    func show(_ nodes: [ChatNode]) {
        let signature = nodes.map { "\($0.id):\($0.activity):\($0.reaches.joined(separator: "+"))" }
            .joined(separator: "|") + "|" + aimed
        guard signature != drawn else { return }
        drawn = signature

        rows.forEach { $0.removeFromSuperview() }
        rows = []

        let agents = nodes.filter(\.isAgent)
        let shells = nodes.filter { !$0.isAgent }

        if !agents.isEmpty {
            rows.append(header("AGENTES"))
            for node in agents {
                let row = AgentRow(node: node, aimed: node.id == aimed)
                row.onClick = { [weak self] in self?.onPickAgent?(node.id) }
                rows.append(row)
            }
        }
        if !shells.isEmpty {
            rows.append(header("PROCESSOS"))
            for node in shells {
                let row = ProcessRow(node: node)
                row.onClick = { [weak self] in self?.onOpenProcess?(node.id) }
                rows.append(row)
            }
        }
        rows.forEach { document.addSubview($0) }
        needsLayout = true
    }

    private func header(_ text: String) -> NSView {
        let view = FlippedView()
        let label = ChatStyle.label(text, font: ChatStyle.meta, color: ChatStyle.faint)
        view.addSubview(label)
        label.frame = NSRect(x: 16, y: 12, width: label.measured, height: 13)
        return view
    }

    override func layout() {
        super.layout()
        if isCollapsed {
            toggle.frame = NSRect(x: 5, y: 12, width: 20, height: 20)
            return
        }
        title.frame = NSRect(x: 16, y: 15, width: bounds.width - 50, height: 14)
        toggle.frame = NSRect(x: bounds.width - 26, y: 12, width: 20, height: 20)
        scroll.frame = NSRect(x: 0, y: 38, width: bounds.width,
                              height: max(0, bounds.height - 38))

        // A largura é a do conteúdo do scroll, não a do painel: o scroller vertical
        // come ~15pt, e medindo pelo painel a pastilha PARA fica embaixo dele.
        let inner = scroll.contentView.bounds.width
        var y: CGFloat = 0
        for row in rows {
            let height: CGFloat
            switch row {
            case let row as AgentRow:   height = row.height(for: inner)
            case let row as ProcessRow: height = row.height(for: inner)
            default:                    height = 30
            }
            row.frame = NSRect(x: 0, y: y, width: inner, height: height)
            y += height
        }
        document.frame = NSRect(x: 0, y: 0, width: inner,
                                height: max(y + 16, scroll.contentView.bounds.height))
    }

    /// Fio na esquerda: o painel é encostado no thread, como a barra de cima.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ChatStyle.rule.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }
}

// MARK: - Linhas do painel

/// Um agente: bolinha na cor dele, o estado em palavras, e quem ele alcança.
final class AgentRow: NSView {
    var onClick: (() -> Void)?

    private let dot = NSView()
    private let name: NSTextField
    private let state: NSTextField
    private let badge: NSTextField?
    private let reachLabel: NSTextField?
    private var chips: [AgentChip] = []
    private let accent: NSColor

    init(node: ChatNode, aimed: Bool) {
        accent = AgentColor.of(node.id)
        name = ChatStyle.label(node.id, font: ChatStyle.name, color: ChatStyle.text)
        state = ChatStyle.label(AgentRow.label(for: node),
                                font: ChatStyle.meta, color: AgentRow.color(for: node))
        badge = aimed ? ChatStyle.label("PARA", font: ChatStyle.meta, color: accent) : nil
        reachLabel = node.reaches.isEmpty
            ? nil : ChatStyle.label("alcança", font: ChatStyle.meta, color: ChatStyle.faint)
        super.init(frame: .zero)

        dot.wantsLayer = true
        dot.layer?.backgroundColor = accent.cgColor
        dot.layer?.cornerRadius = 4
        // Idle desenhado apagado: a lista tem cinco bolinhas e a cor sozinha não
        // separa "de pé sem fazer nada" de "trabalhando".
        dot.alphaValue = node.activity == .ready || node.activity == .dead ? 0.35 : 1
        addSubview(dot)
        addSubview(name)
        addSubview(state)
        if let badge {
            badge.alignment = .right
            addSubview(badge)
        }
        if let reachLabel { addSubview(reachLabel) }
        for id in node.reaches {
            let chip = AgentChip(id)
            chips.append(chip)
            addSubview(chip)
        }

        if aimed {
            wantsLayer = true
            layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.05).cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private static func label(for node: ChatNode) -> String {
        switch node.activity {
        case .asking:   return "precisa de você"
        case .working:  return "trabalhando"
        case .starting: return "subindo"
        case .waiting:  return "terminou"
        case .dead:     return "encerrado"
        case .ready:    return node.role ?? "de pé"
        }
    }

    private static func color(for node: ChatNode) -> NSColor {
        switch node.activity {
        case .asking:  return .systemOrange
        case .waiting: return .systemGreen
        case .dead:    return .systemRed
        default:       return ChatStyle.dim
        }
    }

    func height(for width: CGFloat) -> CGFloat { chips.isEmpty ? 44 : 64 }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func layout() {
        super.layout()
        dot.frame = NSRect(x: 16, y: 11, width: 8, height: 8)
        name.frame = NSRect(x: 30, y: 7, width: name.measured, height: 15)
        if let badge {
            let width = badge.measured
            badge.frame = NSRect(x: bounds.width - width - 14, y: 8, width: width, height: 13)
        }
        state.frame = NSRect(x: 30, y: 24, width: bounds.width - 44, height: 13)

        guard let reachLabel else { return }
        let reachWidth = reachLabel.measured
        reachLabel.frame = NSRect(x: 30, y: 43, width: reachWidth, height: 13)
        var x: CGFloat = 30 + reachWidth + 6
        for chip in chips {
            let size = chip.fittingSize
            // Cabe o que couber: o que passar da largura fica de fora, e a lista de
            // acesso completa está na aresta do canvas.
            guard x + size.width < bounds.width - 12 else { break }
            chip.frame = NSRect(x: x, y: 42, width: size.width, height: size.height)
            x += size.width + 4
        }
    }

    /// Barra na cor do agente na borda esquerda quando ele é o destinatário. É o
    /// mesmo vocabulário do card selecionado na barra lateral.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard badge != nil else { return }
        accent.setFill()
        NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
    }
}

/// Um terminal comum: o comando dele e se está de pé.
final class ProcessRow: NSView {
    var onClick: (() -> Void)?

    private let name: NSTextField
    private let cmd: NSTextField
    private let state: NSTextField

    init(node: ChatNode) {
        name = ChatStyle.label(node.id, font: ChatStyle.mono,
                               color: NSColor(calibratedWhite: 0.85, alpha: 1))
        cmd = ChatStyle.label(node.cmd, font: ChatStyle.meta, color: ChatStyle.faint)
        let dead = node.activity == .dead
        state = ChatStyle.label(dead ? "encerrado" : "de pé", font: ChatStyle.meta,
                                color: dead ? .systemRed : ChatStyle.dim)
        super.init(frame: .zero)
        state.alignment = .right
        addSubview(name)
        addSubview(cmd)
        addSubview(state)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func height(for width: CGFloat) -> CGFloat { 38 }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func layout() {
        super.layout()
        let stateWidth = state.measured
        name.frame = NSRect(x: 16, y: 5, width: bounds.width - stateWidth - 36, height: 14)
        state.frame = NSRect(x: bounds.width - stateWidth - 14, y: 6,
                             width: stateWidth, height: 13)
        cmd.frame = NSRect(x: 16, y: 21, width: bounds.width - 30, height: 13)
    }
}

// MARK: - A saída de um processo

/// Gaveta que entra pela direita com o que o terminal está mostrando.
///
/// Lê pelo `peek` do Dispatcher — a mesma leitura de tela que o socket expõe. Aqui
/// a tela serve: num terminal comum não há TUI redesenhando, o que está lá é a
/// saída do processo e nada mais.
final class ProcessDrawer: NSView {
    var onClose: (() -> Void)?

    private let head = ChatStyle.label("", font: ChatStyle.name, color: ChatStyle.text)
    private let subtitle = ChatStyle.label("", font: ChatStyle.meta, color: ChatStyle.dim)
    private let closeButton = NSButton()
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var lines: [NSTextField] = []

    static let width: CGFloat = 520

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.065, alpha: 1).cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = 24
        layer?.shadowOffset = NSSize(width: -8, height: 0)

        addSubview(head)
        addSubview(subtitle)
        closeButton.title = "✕"
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 13)
        closeButton.contentTintColor = ChatStyle.dim
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        addSubview(closeButton)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    @objc private func closeClicked() { onClose?() }

    func show(id: String, cmd: String, lines text: [String]) {
        head.stringValue = id
        subtitle.stringValue = cmd
        let signature = text.joined(separator: "\n")
        guard signature != drawn else { return }
        drawn = signature

        lines.forEach { $0.removeFromSuperview() }
        lines = text.map { line in
            // Vermelho no que parece falha. É heurística e está aqui de propósito:
            // a alternativa é o olho varrer 200 linhas cinzas iguais.
            let bad = line.contains("✗") || line.lowercased().contains("error")
                || line.contains("exit code") || line.lowercased().contains("failed")
            let field = ChatStyle.label(line, font: ChatStyle.mono,
                                        color: bad ? .systemRed : ChatStyle.dim)
            document.addSubview(field)
            return field
        }
        needsLayout = true
    }

    private var drawn = ""

    override func layout() {
        super.layout()
        head.frame = NSRect(x: 16, y: 14, width: 200, height: 15)
        subtitle.frame = NSRect(x: 16, y: 32, width: bounds.width - 60, height: 13)
        closeButton.frame = NSRect(x: bounds.width - 30, y: 12, width: 22, height: 22)
        scroll.frame = NSRect(x: 0, y: 54, width: bounds.width, height: max(0, bounds.height - 54))

        var y: CGFloat = 8
        for line in lines {
            line.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: 15)
            y += 15
        }
        document.frame = NSRect(x: 0, y: 0, width: bounds.width,
                                height: max(y + 8, scroll.contentView.bounds.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ChatStyle.rule.setFill()
        NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
        ChatStyle.hairline.setFill()
        NSRect(x: 0, y: 53, width: bounds.width, height: 1).fill()
    }
}

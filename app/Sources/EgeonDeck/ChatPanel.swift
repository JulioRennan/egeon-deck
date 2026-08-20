import AppKit

/// O painel da direita: quem está na bancada e o que está rodando.
///
/// Existe porque o chat esconde os cards, e com eles some a única coisa que o
/// canvas dava de graça: dá para ver de relance que `dev-backend` está trabalhando
/// e que o `vitest` caiu. Aqui isso volta como lista, e a lista cabe em 300pt —
/// no canvas os mesmos cinco cards não caberiam sem zoom.
///
/// Não pinta fundo nem fio: quem monta o painel o embrulha num `GlassPanel`, e é
/// dele que vêm a superfície, o raio e a borda. Fundo próprio aqui deixaria o vidro
/// invisível — ele reamostra o que está ATRÁS do `contentView`.
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

    private let title = ChatStyle.label("NA BANCADA", font: ChatStyle.sectionTitle,
                                        color: ChatStyle.dim)
    /// O MESMO botão da barra de bancadas, com os mesmos símbolos — espelhados,
    /// porque este painel mora do outro lado: recolher aqui empurra para a direita.
    /// Dois glifos diferentes para o mesmo gesto obrigariam a reaprender a barra.
    private let toggle = ToolbarButton(symbols: ["sidebar.trailing", "chevron.right"],
                                       tooltip: "Recolher o painel", size: 22)
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var rows: [NSView] = []
    private var drawn = ""
    /// Qual agente o composer está mirando, para a pastilha PARA.
    var aimed: String = "" { didSet { if aimed != oldValue { drawn = ""; needsLayout = true } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(title)
        toggle.onClick = { [weak self] in self?.onToggleCollapse?() }
        addSubview(toggle)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        toggle.setSymbols(collapsed ? ["sidebar.leading", "chevron.left"]
                                    : ["sidebar.trailing", "chevron.right"],
                          tooltip: collapsed ? "Abrir o painel" : "Recolher o painel")
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
            // Centrado no trilho, como o da barra de bancadas faz quando recolhida.
            toggle.frame = NSRect(x: ((bounds.width - 22) / 2).rounded(), y: 10,
                                  width: 22, height: 22)
            return
        }
        title.frame = NSRect(x: 16, y: 15, width: bounds.width - 50, height: 14)
        toggle.frame = NSRect(x: bounds.width - 32, y: 10, width: 22, height: 22)
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

}

// MARK: - Linhas do painel

/// Um agente: bolinha na cor dele, o estado em palavras, e quem ele alcança.
final class AgentRow: NSView {
    var onClick: (() -> Void)?

    private let dot = NSView()
    private let name: NSTextField
    private let state: NSTextField
    /// Este é o destinatário da caixa de escrever.
    ///
    /// Dito só pela barra na cor dele e pelo realce da linha, sem pastilha escrita: o
    /// `para:` da caixa já anuncia o destinatário em texto, e repetir a palavra aqui
    /// gastava a largura da linha para dizer duas vezes a mesma coisa.
    private let aimed: Bool
    private let reachLabel: NSTextField?
    private var chips: [AgentChip] = []
    private let accent: NSColor

    init(node: ChatNode, aimed: Bool) {
        accent = AgentColor.of(node.id)
        name = ChatStyle.label(node.id, font: ChatStyle.name, color: ChatStyle.text)
        state = ChatStyle.label(AgentRow.label(for: node),
                                font: ChatStyle.meta, color: AgentRow.color(for: node))
        self.aimed = aimed
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
        guard aimed else { return }
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
    private let closeButton = ToolbarButton(symbols: ["xmark"],
                                            tooltip: "Fechar · Esc", size: 22)
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var lines: [NSTextField] = []

    static let width: CGFloat = 520

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(head)
        addSubview(subtitle)
        closeButton.onClick = { [weak self] in self?.onClose?() }
        addSubview(closeButton)

        // A saída ganha caixa escura própria: log em fonte fixa sobre vidro fica
        // ilegível — o texto compete com o que passa por baixo.
        well.wantsLayer = true
        well.layer?.backgroundColor = ChatStyle.boxBackground.cgColor
        well.layer?.cornerRadius = 6
        addSubview(well)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        well.addSubview(scroll)
    }

    private let well = NSView()

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

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
        closeButton.frame = NSRect(x: bounds.width - 32, y: 11, width: 22, height: 22)
        well.frame = NSRect(x: 10, y: 62, width: max(0, bounds.width - 20),
                            height: max(0, bounds.height - 72))
        scroll.frame = well.bounds

        var y: CGFloat = 8
        for line in lines {
            line.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: 15)
            y += 15
        }
        document.frame = NSRect(x: 0, y: 0, width: bounds.width,
                                height: max(y + 8, scroll.contentView.bounds.height))
    }

    /// O fio embaixo do cabeçalho fica: é divisor DE DENTRO da gaveta, e o vidro só
    /// desenha a borda de fora.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ChatStyle.hairline.setFill()
        NSRect(x: 0, y: 53, width: bounds.width, height: 1).fill()
    }
}

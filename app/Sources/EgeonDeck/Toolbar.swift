import AppKit

/// Ferramentas da barra. `cursor` é o modo normal — navegar, arrastar nó,
/// digitar no terminal. As outras armam o próximo clique no canvas.
enum CanvasTool: String, CaseIterable {
    case cursor
    case terminal
    case editor
    case web
    /// Ligar um terminal a outro: arrastar da origem até o destino.

    var symbols: [String] {
        switch self {
        // Listas de candidatos: o nome do símbolo muda entre versões do SF
        // Symbols, e um `nil` aqui viraria botão vazio.
        case .cursor:   return ["cursorarrow", "arrow.up.left"]
        case .terminal: return ["apple.terminal", "terminal", "chevron.left.forwardslash.chevron.right"]
        case .editor:   return ["curlybraces", "chevron.left.forwardslash.chevron.right", "doc.text"]
        case .web:      return ["globe", "network"]
        }
    }

    var tooltip: String {
        switch self {
        case .cursor:   return "Cursor — arrastar o canvas, mover nós (⌘V)"
        case .terminal: return "Terminal — clique ou arraste no canvas (⌘T)"
        case .editor:   return "VSCode — clique ou arraste no canvas (⌘E)"
        case .web:      return "Web — clique ou arraste no canvas (⌘W)"
        }
    }

    /// Que tipo de nó esta ferramenta cria. Nem toda ferramenta cria nó.
    var nodeKind: NodeKind? {
        switch self {
        case .cursor: return nil
        case .terminal:      return .shell
        case .editor:        return .editor
        case .web:           return .web
        }
    }

    /// Base do id do nó novo. Entra no endereço de dispatch, então segue a
    /// convenção que já está no sessions.json (`sh`, `code`, `web`).
    var idPrefix: String {
        switch self {
        case .cursor: return ""
        case .terminal:      return "sh"
        case .editor:        return "code"
        case .web:           return "web"
        }
    }

    /// Tamanho de quem só clica, sem arrastar. Um workbench inteiro em 720×460
    /// nasce inutilizável — a activity bar come metade.
    var defaultNodeSize: NSSize {
        switch self {
        case .editor: return NSSize(width: 1180, height: 780)
        default:      return NSSize(width: 720, height: 460)
        }
    }
}

/// Ícone clicável da barra. É uma view crua em vez de NSButton porque o estado
/// selecionado precisa de um fundo próprio, e domar o desenho do NSButton para
/// isso dá mais trabalho do que desenhar.
final class ToolbarButton: NSView {
    var onClick: (() -> Void)?
    /// Segurar o botão. Usado para oferecer variantes sem cobrar um clique extra
    /// de quem só quer o comportamento padrão.
    var onLongPress: (() -> Void)?

    var isSelected = false { didSet { restyle() } }

    private let icon = NSImageView()
    private var hovering = false { didSet { restyle() } }
    private var trackingArea: NSTrackingArea?

    init(symbols: [String], tooltip: String, size: CGFloat = 32) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = size < 24 ? 5 : 8

        icon.image = Self.symbol(symbols)
        icon.imageScaling = .scaleProportionallyUpOrDown
        // Proporcional ao botão: com valores fixos, um botão de 18pt sairia com
        // um ícone de 4pt.
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .medium)
        addSubview(icon)

        toolTip = tooltip
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        icon.frame = bounds.insetBy(dx: bounds.width * 0.22, dy: bounds.height * 0.22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard onLongPress != nil else { onClick?(); return }

        // Soltou dentro de 0.35s é clique; passou disso é pressão. Decidido aqui
        // e não no `mouseUp`, que pode nunca chegar — o menu abre e captura o
        // evento antes.
        let releasedInTime = window?.nextEvent(matching: [.leftMouseUp],
                                               until: Date().addingTimeInterval(0.35),
                                               inMode: .eventTracking,
                                               dequeue: true) != nil
        if releasedInTime { onClick?() } else { onLongPress?() }
    }

    /// Botão direito também abre as variantes: é o gesto que a maioria tenta antes
    /// de descobrir a pressão longa.
    override func rightMouseDown(with event: NSEvent) {
        guard onLongPress != nil else { super.rightMouseDown(with: event); return }
        onLongPress?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func restyle() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            icon.contentTintColor = .controlAccentColor
        } else {
            layer?.backgroundColor = hovering
                ? NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
                : NSColor.clear.cgColor
            icon.contentTintColor = NSColor(calibratedWhite: 1, alpha: hovering ? 0.95 : 0.72)
        }
    }

    /// Troca o ícone. Serve a botão que é um interruptor e diz na cara qual é o
    /// próximo estado — recolher ou abrir.
    func setSymbols(_ names: [String], tooltip: String) {
        icon.image = Self.symbol(names)
        self.toolTip = tooltip
    }

    /// Primeiro nome que existe nesta versão do SF Symbols. Usado também pela
    /// barra superior, que tem os mesmos candidatos a resolver.
    static func symbol(_ names: [String]) -> NSImage? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                return image
            }
        }
        return nil
    }
}

/// Barra flutuante no rodapé do canvas: ferramentas à esquerda, zoom à direita.
final class CanvasToolbar: NSView {
    var onSelect: ((CanvasTool) -> Void)?
    /// `+1` aproxima, `-1` afasta.
    var onZoom: ((Int) -> Void)?
    var onResetZoom: (() -> Void)?
    /// Salvar o canvas atual como template NOVO. É ação imediata, não
    /// ferramenta: não arma o próximo clique e não fica selecionada.
    var onSaveTemplate: (() -> Void)?
    /// Regravar o template de que esta sessão nasceu. Só aparece quando existe
    /// um — ver `showsUpdateTemplate`.
    var onUpdateTemplate: (() -> Void)?
    /// Abrir uma sessão nova numa worktree desta.
    var onNewWorktree: (() -> Void)?
    /// Escolher com que componente o próximo terminal nasce. Nil = shell padrão.
    var onPickComponent: ((String?) -> Void)?
    /// Abrir o formulário para montar um terminal do zero.
    var onConfigureTerminal: (() -> Void)?
    /// Nomes dos componentes salvos, para montar o menu na hora de abrir.
    var componentNames: (() -> [String])?

    private static let height: CGFloat = 44
    private static let padding: CGFloat = 8
    private static let gap: CGFloat = 2

    private var buttons: [CanvasTool: ToolbarButton] = [:]
    private let zoomOut: ToolbarButton
    private let zoomIn: ToolbarButton
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let separator = NSView()
    private let templateSeparator = NSView()
    private let saveTemplate: ToolbarButton
    private let updateTemplate: ToolbarButton
    private let newWorktree: ToolbarButton

    override init(frame frameRect: NSRect) {
        zoomOut = ToolbarButton(symbols: ["minus"], tooltip: "Afastar (⌘−)", size: 28)
        zoomIn = ToolbarButton(symbols: ["plus"], tooltip: "Aproximar (⌘+)", size: 28)
        saveTemplate = ToolbarButton(
            symbols: ["square.and.arrow.down.on.square", "square.and.arrow.down", "bookmark"],
            tooltip: "Salvar este canvas como um template novo")
        updateTemplate = ToolbarButton(
            symbols: ["arrow.trianglehead.2.clockwise.rotate.90", "arrow.clockwise", "gobackward"],
            tooltip: "Atualizar o template de origem com este canvas")
        newWorktree = ToolbarButton(
            symbols: ["arrow.triangle.branch", "arrow.branch", "square.on.square"],
            tooltip: "Nova sessão numa worktree desta — nada aqui é reiniciado")
        super.init(frame: frameRect)

        // Sem fundo, borda nem sombra próprios: quem dá tudo isso é o
        // `GlassPanel` que a envolve no canvas.
        wantsLayer = true

        for tool in CanvasTool.allCases {
            let button = ToolbarButton(symbols: tool.symbols, tooltip: tool.tooltip)
            if tool == .terminal {
                // Clique curto continua criando shell na hora. O menu só aparece
                // ao segurar, para escolher componente não custar o caso simples.
                button.onClick = { [weak self] in self?.onSelect?(tool) }
                button.onLongPress = { [weak self] in self?.showComponentMenu(from: button) }
            } else {
                button.onClick = { [weak self] in self?.onSelect?(tool) }
            }
            addSubview(button)
            buttons[tool] = button
        }

        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.18).cgColor
        addSubview(separator)

        zoomOut.onClick = { [weak self] in self?.onZoom?(-1) }
        zoomIn.onClick = { [weak self] in self?.onZoom?(1) }
        addSubview(zoomOut)
        addSubview(zoomIn)

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoomLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.72)
        zoomLabel.alignment = .center
        zoomLabel.toolTip = "Clique para voltar a 100% (⌘0)"
        addSubview(zoomLabel)

        templateSeparator.wantsLayer = true
        templateSeparator.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.18).cgColor
        addSubview(templateSeparator)

        saveTemplate.onClick = { [weak self] in self?.onSaveTemplate?() }
        addSubview(saveTemplate)

        updateTemplate.onClick = { [weak self] in self?.onUpdateTemplate?() }
        // Escondido até a sessão dizer de qual template nasceu: um botão de
        // "atualizar" sem alvo não tem o que fazer, e explicar isso num alerta
        // depois do clique é pior do que não mostrar.
        updateTemplate.isHidden = true
        addSubview(updateTemplate)

        newWorktree.onClick = { [weak self] in self?.onNewWorktree?() }
        addSubview(newWorktree)
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init() { self.init(frame: .zero) }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        let tools = CGFloat(CanvasTool.allCases.count)
        let width = Self.padding * 2
            + tools * 32 + (tools - 1) * Self.gap   // ferramentas
            + 17                                     // separador + folgas
            + 28 + 44 + 28                           // zoom: −, rótulo, +
            + 17 + 32 + Self.gap + 32 + Self.gap + 32 // separador + ações da sessão
        return NSSize(width: width, height: Self.height)
    }

    override func layout() {
        super.layout()
        var x = Self.padding
        let y = (bounds.height - 32) / 2

        for tool in CanvasTool.allCases {
            buttons[tool]?.frame = NSRect(x: x, y: y, width: 32, height: 32)
            x += 32 + Self.gap
        }

        x += 8
        separator.frame = NSRect(x: x, y: 12, width: 1, height: bounds.height - 24)
        x += 9

        let zoomY = (bounds.height - 28) / 2
        zoomOut.frame = NSRect(x: x, y: zoomY, width: 28, height: 28)
        x += 28
        zoomLabel.frame = NSRect(x: x, y: (bounds.height - 14) / 2, width: 44, height: 14)
        x += 44
        zoomIn.frame = NSRect(x: x, y: zoomY, width: 28, height: 28)
        x += 28

        x += 8
        templateSeparator.frame = NSRect(x: x, y: 12, width: 1, height: bounds.height - 24)
        x += 9
        saveTemplate.frame = NSRect(x: x, y: y, width: 32, height: 32)
        x += 32 + Self.gap
        // O botão escondido não reserva espaço: a barra encolhe quando a sessão
        // não veio de template.
        if !updateTemplate.isHidden {
            updateTemplate.frame = NSRect(x: x, y: y, width: 32, height: 32)
            x += 32 + Self.gap
        }
        newWorktree.frame = NSRect(x: x, y: y, width: 32, height: 32)
    }

    override func mouseDown(with event: NSEvent) {
        // Clicar no número volta para 100%; clicar no vazio da barra não deve
        // vazar para o overlay de criação atrás.
        if zoomLabel.frame.contains(convert(event.locationInWindow, from: nil)) {
            onResetZoom?()
        }
    }

    private func showComponentMenu(from button: ToolbarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Shell simples", action: #selector(pickShell), keyEquivalent: "")

        let names = componentNames?() ?? []
        if !names.isEmpty {
            menu.addItem(.separator())
            for name in names {
                let item = menu.addItem(withTitle: name, action: #selector(pickSaved(_:)),
                                        keyEquivalent: "")
                item.representedObject = name
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Configurar novo terminal…",
                     action: #selector(configureNew), keyEquivalent: "")
        menu.items.forEach { if $0.action != nil { $0.target = self } }

        menu.popUp(positioning: nil,
                   at: NSPoint(x: button.frame.minX, y: button.frame.maxY + 6),
                   in: self)
    }

    @objc private func pickShell() { onPickComponent?(nil) }
    @objc private func pickSaved(_ item: NSMenuItem) {
        onPickComponent?(item.representedObject as? String)
    }
    @objc private func configureNew() { onConfigureTerminal?() }

    /// De qual template esta sessão nasceu, ou nil. Governa o botão de atualizar.
    func showsUpdateTemplate(_ template: String?) {
        updateTemplate.isHidden = template == nil
        if let template {
            updateTemplate.toolTip = "Atualizar o template \"\(template)\" com este canvas"
        }
        needsLayout = true
    }

    func select(_ tool: CanvasTool) {
        for (key, button) in buttons { button.isSelected = (key == tool) }
    }

    func showZoom(_ magnification: CGFloat) {
        zoomLabel.stringValue = "\(Int((magnification * 100).rounded()))%"
    }
}

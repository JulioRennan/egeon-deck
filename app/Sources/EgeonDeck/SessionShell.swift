import AppKit

/// Botão da barra superior: ícone e nome do modo.
///
/// Com texto, e não só ícone como na barra do canvas: são dois estados
/// mutuamente exclusivos e é o rótulo que diz em qual você está sem passar o
/// mouse por cima.
final class ModeButton: NSView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { restyle() } }

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hovering = false { didSet { restyle() } }
    private var trackingArea: NSTrackingArea?

    init(mode: ViewMode) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        icon.image = ToolbarButton.symbol(mode.symbols)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        addSubview(icon)

        label.stringValue = mode.label
        label.font = .systemFont(ofSize: 11, weight: .medium)
        addSubview(label)

        toolTip = mode.tooltip
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        NSSize(width: 14 + 16 + 5 + label.intrinsicContentSize.width, height: 24)
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 7, y: (bounds.height - 14) / 2, width: 16, height: 14)
        label.frame = NSRect(x: 28, y: (bounds.height - 14) / 2,
                             width: max(0, bounds.width - 33), height: 14)
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
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    private func restyle() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            icon.contentTintColor = .controlAccentColor
            label.textColor = .controlAccentColor
        } else {
            layer?.backgroundColor = hovering
                ? NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
                : NSColor.clear.cgColor
            let alpha: CGFloat = hovering ? 0.9 : 0.55
            icon.contentTintColor = NSColor(calibratedWhite: 1, alpha: alpha)
            label.textColor = NSColor(calibratedWhite: 1, alpha: alpha)
        }
    }
}

/// Barra superior: de que jeito você está olhando a sessão.
///
/// Separada da barra do canvas — que é flutuante, mora no rodapé e trata do que
/// você está FAZENDO: ferramenta armada, zoom, template. Esta trata de onde os
/// nós aparecem, e por isso é a única que continua na tela nos dois modos.
final class ViewToolbar: NSView {
    static let height: CGFloat = 34

    var onSelect: ((ViewMode) -> Void)?

    private var buttons: [ViewMode: ModeButton] = [:]
    private let hint = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor

        for mode in [ViewMode.canvas, .mosaic] {
            let button = ModeButton(mode: mode)
            button.onClick = { [weak self] in self?.onSelect?(mode) }
            addSubview(button)
            buttons[mode] = button
        }

        hint.font = .systemFont(ofSize: 10)
        hint.textColor = NSColor(calibratedWhite: 1, alpha: 0.35)
        addSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init() { self.init(frame: .zero) }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var x: CGFloat = 8
        for mode in [ViewMode.canvas, .mosaic] {
            guard let button = buttons[mode] else { continue }
            let width = button.fittingSize.width
            button.frame = NSRect(x: x, y: (bounds.height - 24) / 2, width: width, height: 24)
            x += width + 4
        }
        hint.frame = NSRect(x: x + 10, y: (bounds.height - 13) / 2,
                            width: max(0, bounds.width - x - 20), height: 13)
    }

    /// Fio embaixo em vez de sombra: a barra é fixa e encostada no conteúdo, e
    /// sombra aqui pousaria em cima do primeiro card.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 1, alpha: 0.09).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    func select(_ mode: ViewMode) {
        for (key, button) in buttons { button.isSelected = (key == mode) }
        hint.stringValue = mode == .mosaic
            ? "as posições do canvas ficam guardadas"
            : ""
    }
}

// MARK: - A sessão na tela

/// Uma sessão: a barra de visualização em cima e, embaixo, o canvas ou o mosaico
/// — com os MESMOS nós.
///
/// É o dono dos nós, e é por isso que existe. Antes quem os guardava era o
/// canvas, na forma de `doc.subviews`; com dois containers disputando o mesmo
/// card, a lista tem de viver acima dos dois — senão entrar no mosaico faz a
/// sessão parecer vazia para todo mundo que contava nós pelo canvas: spinner do
/// cabeçalho, geometria do socket, persistência.
final class SessionShell: NSView {
    let canvas = CanvasContainer(frame: .zero)

    private let bar = ViewToolbar()
    private let banner = NSTextField(labelWithString: "")
    private var mosaic: MosaicContainer?

    private(set) var nodes: [NodeView] = []
    private(set) var mode: ViewMode

    /// Você trocou de modo — hora de gravar no sessions.json.
    var onModeChanged: ((ViewMode) -> Void)?
    /// Divisor do mosaico arrastado.
    var onMosaicLayoutChanged: ((MosaicLayout) -> Void)?
    /// Repassados pelo container que estiver na tela, para quem escuta não ter de
    /// saber qual é.
    var onRequestClose: ((NodeView) -> Void)?
    var onRequestEditNode: ((NodeView) -> Void)?
    var onRequestNodeWorktree: ((NodeView) -> Void)?

    /// Onde cada nó estava no canvas, por id.
    ///
    /// O mosaico sobrescreve o frame do card no primeiro layout, então sem este
    /// retrato voltar para o canvas empilharia todos no mesmo canto — e o
    /// `sessions.json`, que é gravado a partir do que está na tela, levaria a
    /// pilha junto.
    private var canvasFrames: [String: NSRect] = [:]

    /// Troca dois cards de painel no mosaico, por id. Nada acontece no canvas —
    /// lá a posição é livre e não há painel para trocar.
    @discardableResult
    func swapInMosaic(_ primeiro: String, _ segundo: String) -> Bool {
        mosaic?.swap(primeiro, segundo) ?? false
    }

    /// Proporções salvas do mosaico. Repassadas na hora de montá-lo.
    var mosaicLayout: MosaicLayout? {
        didSet { mosaic?.layoutRatios = mosaicLayout }
    }

    init(frame frameRect: NSRect, mode: ViewMode) {
        self.mode = mode
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor

        bar.onSelect = { [weak self] mode in self?.show(mode) }
        bar.select(mode)
        addSubview(bar)

        banner.font = .systemFont(ofSize: 12, weight: .medium)
        banner.textColor = .black
        banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor.systemOrange.cgColor
        banner.layer?.cornerRadius = 6
        banner.alignment = .center
        banner.isHidden = true
        addSubview(banner)

        // O canvas conhece avisos que só ele sabe dar (componente armado, ciclo
        // de arestas), mas em modo mosaico ele está fora da hierarquia e o aviso
        // não apareceria. O banner mora aqui, e ele pede.
        canvas.onBanner = { [weak self] text in self?.showBanner(text) }
        canvas.onRequestClose = { [weak self] node in self?.onRequestClose?(node) }
        canvas.onRequestEditNode = { [weak self] node in self?.onRequestEditNode?(node) }
        canvas.onRequestNodeWorktree = { [weak self] node in self?.onRequestNodeWorktree?(node) }
        // Com o mosaico ativo o documento do canvas está vazio, e sem isto todo
        // nó novo nasceria no mesmo canto de lá.
        canvas.placedNodes = { [weak self] in self?.nodes ?? [] }

        place()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Nós

    func attach(_ node: NodeView) {
        nodes.append(node)
        // O frame com que o nó chega é sempre o do canvas: vem do `sessions.json`
        // ou do retângulo que você acabou de desenhar.
        if !node.nodeID.isEmpty { canvasFrames[node.nodeID] = node.frame }

        switch mode {
        case .canvas: canvas.add(node)
        // A coluna inteira muda de tamanho com um nó a mais, então não há como
        // encaixar sem remontar.
        case .mosaic: mosaic?.arrange(nodes)
        }
    }

    /// Tira o nó da sessão depois de alguém já ter confirmado. Encerra o que não
    /// morre sozinho — pty, carga de webview, registro no dispatcher.
    func detach(_ node: NodeView) {
        nodes.removeAll { $0 === node }
        canvasFrames[node.nodeID] = nil
        node.prepareForRemoval()
        node.removeFromSuperview()
        if mode == .mosaic { mosaic?.arrange(nodes) }
    }

    /// Onde este nó fica no canvas, mesmo que agora esteja num painel do mosaico.
    /// Quem grava geometria no `sessions.json` pergunta aqui.
    func canvasFrame(of nodeID: String) -> NSRect? {
        if mode == .canvas, let node = nodes.first(where: { $0.nodeID == nodeID }) {
            return node.frame
        }
        return canvasFrames[nodeID]
    }

    /// O container que está na tela.
    ///
    /// Quem mede geometria pergunta a ele, e não ao canvas: em mosaico o canvas
    /// está fora da hierarquia de janela, e converter coordenada nele devolve
    /// número plausível e errado.
    var visibleContent: NSView { mode == .canvas ? canvas : (mosaic ?? canvas) }

    var terminals: [TerminalNode] { nodes.compactMap { $0 as? TerminalNode } }

    func refreshBadges() { terminals.forEach { $0.refreshBadge() } }

    // MARK: Modo

    func show(_ mode: ViewMode) {
        guard mode != self.mode else { return }
        if self.mode == .canvas { rememberCanvasFrames() }
        self.mode = mode
        bar.select(mode)
        place()
        onModeChanged?(mode)
        Log.write("visualização: modo \(mode.rawValue)")
    }

    /// O que está na tela é a verdade sobre posição — você acabou de arrastar.
    private func rememberCanvasFrames() {
        for node in nodes where !node.nodeID.isEmpty {
            canvasFrames[node.nodeID] = node.frame
        }
    }

    private func place() {
        // Reparentar não mexe no processo: o pty continua ligado ao SwiftTerm e o
        // WKWebView não recarrega. É o que permite trocar de modo com agentes
        // trabalhando.
        nodes.forEach { $0.removeFromSuperview() }

        switch mode {
        case .canvas:
            mosaic?.removeFromSuperview()
            addSubview(canvas, positioned: .below, relativeTo: banner)
            for node in nodes {
                if let frame = canvasFrames[node.nodeID] { node.frame = frame }
                canvas.add(node)
            }

        case .mosaic:
            canvas.removeFromSuperview()
            let container = mosaic ?? makeMosaic()
            addSubview(container, positioned: .below, relativeTo: banner)
            container.layoutRatios = mosaicLayout
            container.arrange(nodes)
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func makeMosaic() -> MosaicContainer {
        let container = MosaicContainer(frame: contentFrame)
        container.onRequestClose = { [weak self] node in self?.onRequestClose?(node) }
        container.onRequestEditNode = { [weak self] node in self?.onRequestEditNode?(node) }
        container.onRequestNodeWorktree = { [weak self] node in
            self?.onRequestNodeWorktree?(node)
        }
        container.onLayoutChanged = { [weak self] layout in
            self?.onMosaicLayoutChanged?(layout)
        }
        mosaic = container
        return container
    }

    // MARK: Layout

    private var contentFrame: NSRect {
        NSRect(x: 0, y: ViewToolbar.height, width: bounds.width,
               height: max(0, bounds.height - ViewToolbar.height))
    }

    override func layout() {
        super.layout()
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: ViewToolbar.height)
        let content = contentFrame
        canvas.frame = content
        mosaic?.frame = content
        banner.frame = NSRect(x: bounds.midX - 380, y: ViewToolbar.height + 12,
                              width: 760, height: 30)
    }

    func showBanner(_ text: String?) {
        guard let text else { banner.isHidden = true; return }
        banner.stringValue = text
        banner.isHidden = false
    }
}

import AppKit

// MARK: - A bancada na tela

/// Uma bancada: a barra de visualização em cima e, embaixo, o canvas ou o
/// mosaico — os dois com os MESMOS nós.
///
/// É o dono dos nós, e é por isso que existe. Antes quem os guardava era o
/// canvas, na forma de `doc.subviews`; com dois containers disputando o mesmo
/// card, a lista tem de viver acima dos dois — senão entrar no mosaico faz a
/// bancada parecer vazia para todo mundo que contava nós pelo canvas: spinner do
/// cabeçalho, geometria do socket, persistência.
final class WorkbenchShell: NSView {
    let canvas = CanvasContainer(frame: .zero)

    private let bar = ViewToolbar()
    private let banner = NSTextField(labelWithString: "")
    /// O vidro do banner. Entra na hierarquia no lugar do rótulo, e é ele que os
    /// containers usam como referência de z-order.
    private lazy var bannerPanel = GlassPanel(content: banner, radius: 8, tint: .systemOrange)
    private var mosaic: MosaicContainer?
    /// O modo chat. Criado junto com a bancada e não sob demanda como o mosaico:
    /// não guarda geometria de card, então nasce barato, e main.swift precisa
    /// dele para ligar as fontes de dados uma vez só.
    let chat = ChatContainer()

    private(set) var nodes: [NodeView] = []
    private(set) var mode: ViewMode

    /// Você trocou de modo — hora de gravar no workbenches.json.
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
    /// `workbenches.json`, que é gravado a partir do que está na tela, levaria a
    /// pilha junto.
    private var canvasFrames: [String: NSRect] = [:]

    /// Que bancada a barra de cima anuncia.
    func setWorkbench(name: String, path: String) { bar.setWorkbench(name: name, path: path) }

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

        banner.font = .systemFont(ofSize: 12, weight: .semibold)
        banner.textColor = .black
        banner.alignment = .center
        bannerPanel.isHidden = true
        addSubview(bannerPanel)

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

        // O chat pega um terminal emprestado do canvas coberto e devolve depois.
        chat.terminalView = { [weak self] id in self?.nodes.first { $0.nodeID == id } }
        chat.releaseTerminal = { [weak self] view in
            guard let self, let node = view as? NodeView, self.nodes.contains(where: { $0 === node })
            else { return }
            if let frame = self.canvasFrames[node.nodeID] { node.frame = frame }
            self.canvas.add(node)
        }

        place()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Nós

    func attach(_ node: NodeView) {
        nodes.append(node)
        // O frame com que o nó chega é sempre o do canvas: vem do `workbenches.json`
        // ou do retângulo que você acabou de desenhar.
        if !node.nodeID.isEmpty { canvasFrames[node.nodeID] = node.frame }

        switch mode {
        case .canvas: canvas.add(node)
        // A coluna inteira muda de tamanho com um nó a mais, então não há como
        // encaixar sem remontar.
        case .mosaic: mosaic?.arrange(nodes)
        // Em chat o card entra no canvas coberto, como em `place`: ele precisa
        // do passe de layout para o pty nascer com colunas.
        case .chat:
            canvas.add(node)
            chat.refresh()
        }
    }

    /// Tira o nó da bancada depois de alguém já ter confirmado. Encerra o que não
    /// morre sozinho — pty, carga de webview, registro no dispatcher.
    func detach(_ node: NodeView) {
        nodes.removeAll { $0 === node }
        canvasFrames[node.nodeID] = nil
        node.prepareForRemoval()
        node.removeFromSuperview()
        if mode == .mosaic { mosaic?.arrange(nodes) }
        if mode == .chat { chat.refresh() }
    }

    /// Onde este nó fica no canvas, mesmo que agora esteja num painel do mosaico.
    /// Quem grava geometria no `workbenches.json` pergunta aqui.
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
    var visibleContent: NSView {
        switch mode {
        case .canvas: return canvas
        case .mosaic: return mosaic ?? canvas
        case .chat:   return chat
        }
    }

    /// O foco está dentro de um EDITOR.
    ///
    /// Mora aqui, e não no canvas, porque em mosaico o canvas está fora da
    /// hierarquia e `window` é nulo lá — a resposta sairia sempre falsa.
    var focusIsInsideEditor: Bool {
        var view = window?.firstResponder as? NSView
        while let current = view {
            if current is EditorNode { return true }
            view = current.superview
        }
        return false
    }

    var terminals: [TerminalNode] { nodes.compactMap { $0 as? TerminalNode } }

    func refreshBadges() {
        terminals.forEach { $0.refreshBadge() }
        guard mode == .chat else { return }
        chat.tick()
        // Em chat o canvas está montado por baixo, coberto — e um terminal de
        // lá pega o teclado ao ser reparentado. Você digitaria no terminal
        // escondido achando que digita na caixa. O teclado volta para o chat.
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: canvas) {
            chat.focusComposer()
        }
    }

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
        chat.leaveTerminal()
        nodes.forEach { $0.removeFromSuperview() }

        switch mode {
        case .canvas:
            mosaic?.removeFromSuperview()
            chat.removeFromSuperview()
            addSubview(canvas, positioned: .below, relativeTo: bannerPanel)
            for node in nodes {
                if let frame = canvasFrames[node.nodeID] { node.frame = frame }
                canvas.add(node)
            }

        case .mosaic:
            canvas.removeFromSuperview()
            chat.removeFromSuperview()
            let container = mosaic ?? makeMosaic()
            addSubview(container, positioned: .below, relativeTo: bannerPanel)
            container.layoutRatios = mosaicLayout
            container.arrange(nodes)

        case .chat:
            // O canvas CONTINUA montado, com os nós nele, e o chat entra opaco
            // por cima. Não é preguiça: um `NodeView` fora da hierarquia nunca
            // recebe passe de layout, e sem layout o SwiftTerm não tem colunas
            // para informar ao pty. Medido — bancada que ABRE em chat sobe os
            // terminais com tamanho zero, a TUI não tem onde desenhar, e a tela
            // fica vazia para sempre: `SIGWINCH` depois não faz o shell
            // reimprimir o prompt.
            mosaic?.removeFromSuperview()
            addSubview(canvas, positioned: .below, relativeTo: bannerPanel)
            for node in nodes {
                if let frame = canvasFrames[node.nodeID] { node.frame = frame }
                canvas.add(node)
            }
            addSubview(chat, positioned: .below, relativeTo: bannerPanel)
            chat.refresh()
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
        // Quem decide o recuo do título é a POSIÇÃO, e não o modo: se a bancada
        // começa na borda esquerda da janela — o que acontece no canvas, onde o
        // grid corre por baixo da barra flutuante —, os botões da janela ficam em
        // cima do título. Perguntar a geometria evita combinar por convenção com o
        // `RootView`, que é quem escolhe onde a bancada começa.
        bar.titleInset = convert(NSPoint.zero, to: nil).x < 40 ? 82 : 16
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: ViewToolbar.height)
        let content = contentFrame
        canvas.frame = content
        mosaic?.frame = content
        chat.frame = content
        bannerPanel.frame = NSRect(x: bounds.midX - 380, y: ViewToolbar.height + 12,
                                   width: 760, height: 30)
    }

    func showBanner(_ text: String?) {
        guard let text else { bannerPanel.isHidden = true; return }
        banner.stringValue = text
        bannerPanel.isHidden = false
    }
}

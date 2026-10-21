import AppKit

// MARK: - A bancada na tela

/// Uma bancada: a barra de visualização em cima e, embaixo, o canvas ou o chat
/// — os dois com os MESMOS nós.
///
/// É o dono dos nós, e é por isso que existe: o chat pega um terminal do canvas
/// emprestado, e a lista tem de viver acima dos dois — senão o card emprestado
/// some para todo mundo que contava nós pelo canvas: spinner do cabeçalho,
/// geometria do socket, persistência.
final class WorkbenchShell: NSView {
    let canvas = CanvasContainer(frame: .zero)

    private let bar = ViewToolbar()
    /// As bancadas abertas. Vive no shell e não na raiz porque é aqui que a
    /// barra de cima já mora, e as duas juntas são a moldura da bancada.
    let tabs = WorkbenchTabsBar(frame: .zero)
    private let banner = NSTextField(labelWithString: "")
    /// O vidro do banner. Entra na hierarquia no lugar do rótulo, e é ele que os
    /// containers usam como referência de z-order.
    private lazy var bannerPanel = GlassPanel(content: banner, radius: 8, tint: .systemOrange)
    /// A cortina de "um instante" — limpeza da bancada em curso (ADR-059).
    private let busy = BusyOverlay(frame: .zero)
    /// A trava de quando o macOS não deixa ler a pasta da bancada.
    let accessLock = AccessOverlay(frame: .zero)
    /// O modo chat. Criado junto com a bancada: não guarda geometria de card,
    /// então nasce barato, e main.swift precisa dele para ligar as fontes de
    /// dados uma vez só.
    let chat = ChatContainer()

    private(set) var nodes: [NodeView] = []
    private(set) var mode: ViewMode

    /// Você trocou de modo — hora de gravar no workbenches.json.
    var onModeChanged: ((ViewMode) -> Void)?
    /// Repassados pelo container que estiver na tela, para quem escuta não ter de
    /// saber qual é.
    var onRequestClose: ((NodeView) -> Void)?
    var onRequestEditNode: ((NodeView) -> Void)?
    var onRequestNodeWorktree: ((NodeView) -> Void)?
    var onRequestNodeModel: ((NodeView, ModelChoice) -> Void)?

    /// Onde cada nó estava no canvas, por id.
    ///
    /// O terminal que o chat pega emprestado perde o frame do canvas; sem este
    /// retrato ele voltaria para o canto — e o `workbenches.json`, que é gravado
    /// a partir do que está na tela, levaria o canto junto.
    private var canvasFrames: [String: NSRect] = [:]

    /// Que bancada a barra de cima anuncia.
    func setWorkbench(name: String, path: String) { bar.setWorkbench(name: name, path: path) }
    func showClock(_ clock: WorkbenchClock, phases: Set<WorkbenchClock.Phase>) { bar.setClock(clock, phases: phases) }
    var onResetClock: (() -> Void)? {
        get { bar.onResetClock }
        set { bar.onResetClock = newValue }
    }

    /// Quanto o CONTEÚDO cede à esquerda para a barra lateral — a barra de cima
    /// não cede nunca. Ela é a faixa da titlebar da janela: encurtá-la no
    /// chat deixava o trecho sobre a barra lateral sem ninguém para tratar
    /// arrasto e duplo clique, e o título perdia o recuo dos botões da janela.
    var contentInset: CGFloat = 0 {
        didSet { if contentInset != oldValue { needsLayout = true } }
    }

    /// Quanto a FAIXA recua — sempre a largura da barra lateral, mesmo no
    /// canvas, onde o conteúdo corre por baixo do vidro. Aba coberta pela barra
    /// é aba que não se clica.
    var tabsInset: CGFloat = 0 {
        didSet { if tabsInset != oldValue { tabs.leftInset = tabsInset } }
    }

    init(frame frameRect: NSRect, mode: ViewMode) {
        self.mode = mode
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor

        bar.onSelect = { [weak self] mode in self?.show(mode) }
        bar.select(mode)
        addSubview(bar)

        tabs.isHidden = true
        addSubview(tabs)

        banner.font = .systemFont(ofSize: 12, weight: .semibold)
        banner.textColor = .black
        banner.alignment = .center
        bannerPanel.isHidden = true
        addSubview(bannerPanel)

        busy.isHidden = true
        addSubview(busy)
        accessLock.isHidden = true
        addSubview(accessLock)

        // O canvas conhece avisos que só ele sabe dar (componente armado, ciclo
        // de arestas), mas em modo chat ele está coberto e o aviso não
        // apareceria. O banner mora aqui, e ele pede.
        canvas.onBanner = { [weak self] text in self?.showBanner(text) }
        canvas.onRequestClose = { [weak self] node in self?.onRequestClose?(node) }
        canvas.onRequestEditNode = { [weak self] node in self?.onRequestEditNode?(node) }
        canvas.onRequestNodeWorktree = { [weak self] node in self?.onRequestNodeWorktree?(node) }
        canvas.onRequestNodeModel = { [weak self] node, model in
            self?.onRequestNodeModel?(node, model)
        }
        // O card emprestado ao chat não está no documento do canvas, e sem isto
        // o nó novo nasceria em cima do lugar dele.
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
        if mode == .chat { chat.refresh() }
    }

    /// Leva os cards a novos lugares no canvas, de uma vez, e enquadra — o
    /// arranjo que o maestro dá à bancada (ADR-066).
    func arrange(_ frames: [String: NSRect]) {
        for (id, frame) in frames where canvasFrames[id] != nil || nodes.contains(where: { $0.nodeID == id }) {
            canvasFrames[id] = frame
        }
        canvas.arrange(frames)
    }

    /// Onde este nó fica no canvas, mesmo que agora esteja emprestado ao chat.
    /// Quem grava geometria no `workbenches.json` pergunta aqui.
    func canvasFrame(of nodeID: String) -> NSRect? {
        if mode == .canvas, let node = nodes.first(where: { $0.nodeID == nodeID }) {
            return node.frame
        }
        return canvasFrames[nodeID]
    }

    /// O container que está na tela.
    ///
    /// Quem mede geometria pergunta a ele, e não ao canvas: em chat o canvas
    /// está coberto, e converter coordenada nele devolve número plausível e
    /// errado.
    var visibleContent: NSView {
        switch mode {
        case .canvas: return canvas
        case .chat:   return chat
        }
    }

    /// O foco está numa caixa de texto do app — o composer do chat, um campo de
    /// formulário. Ali ⌘← e ⌘→ são "início" e "fim da linha", e um item de menu
    /// com esse atalho é consultado ANTES do responder chain: habilitado, ele
    /// roubaria a tecla de quem está escrevendo.
    var focusIsInTextInput: Bool {
        guard let responder = window?.firstResponder else { return false }
        if let text = responder as? NSTextView { return text.isEditable }
        return responder is NSTextField
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
            chat.removeFromSuperview()
            addSubview(canvas, positioned: .below, relativeTo: bannerPanel)
            for node in nodes {
                if let frame = canvasFrames[node.nodeID] { node.frame = frame }
                canvas.add(node)
            }

        case .chat:
            // O canvas CONTINUA montado, com os nós nele, e o chat entra opaco
            // por cima. Não é preguiça: um `NodeView` fora da hierarquia nunca
            // recebe passe de layout, e sem layout o SwiftTerm não tem colunas
            // para informar ao pty. Medido — bancada que ABRE em chat sobe os
            // terminais com tamanho zero, a TUI não tem onde desenhar, e a tela
            // fica vazia para sempre: `SIGWINCH` depois não faz o shell
            // reimprimir o prompt.
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

    // MARK: Layout

    /// Onde o conteúdo da bancada começa: abaixo da barra de cima e, quando há
    /// mais de uma bancada aberta, abaixo da faixa de abas também.
    var topInset: CGFloat { ViewToolbar.height + (tabs.isHidden ? 0 : WorkbenchTabsBar.height) }

    var contentFrame: NSRect {
        NSRect(x: contentInset, y: topInset,
               width: max(0, bounds.width - contentInset),
               height: max(0, bounds.height - topInset))
    }

    var barFrame: NSRect { bar.frame }

    override func layout() {
        super.layout()
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: ViewToolbar.height)
        tabs.frame = NSRect(x: 0, y: ViewToolbar.height, width: bounds.width,
                            height: WorkbenchTabsBar.height)
        let content = contentFrame
        canvas.frame = content
        chat.frame = content
        bannerPanel.frame = NSRect(x: bounds.midX - 380, y: topInset + 12,
                                   width: 760, height: 30)
        busy.frame = content
        accessLock.frame = content
    }

    /// Trava a bancada com o aviso de acesso; `nil` destrava. Acima de tudo,
    /// cortina de limpeza inclusive.
    func lockAccess(_ text: String?, asking: Bool = false) {
        guard let text else { accessLock.isHidden = true; return }
        addSubview(accessLock, positioned: .above, relativeTo: nil)
        accessLock.show(text, asking: asking)
        needsLayout = true
    }

    var isAccessLocked: Bool { !accessLock.isHidden }

    /// A cortina, com o que está acontecendo; `nil` a recolhe. Fica ACIMA de
    /// tudo, banner incluído: enquanto ela está de pé nada da bancada aceita
    /// clique.
    func showBusy(_ text: String?) {
        guard let text else { busy.hide(); return }
        addSubview(busy, positioned: .above, relativeTo: bannerPanel)
        busy.show(text)
        needsLayout = true
    }

    /// As abas da janela. Esconder quando só há uma bancada aberta: uma aba
    /// sozinha não diz nada que a barra de cima já não diga, e come 34pt.
    func showTabs(_ list: [WorkbenchTab]) {
        let hadTabs = !tabs.isHidden
        tabs.show(list.count > 1 ? list : [])
        if hadTabs != !tabs.isHidden { needsLayout = true; layoutSubtreeIfNeeded() }
    }

    /// A faixa está na tela? Para conferir de fora.
    var tabsAreVisible: Bool { !tabs.isHidden }

    func showBanner(_ text: String?) {
        guard let text else { bannerPanel.isHidden = true; return }
        banner.stringValue = text
        bannerPanel.isHidden = false
    }
}

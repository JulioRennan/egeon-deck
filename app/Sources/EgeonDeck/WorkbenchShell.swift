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
        layer?.cornerRadius = 7

        icon.image = ToolbarButton.symbol(mode.symbols)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        addSubview(icon)

        label.stringValue = mode.label
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        addSubview(label)

        toolTip = mode.tooltip
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    static let height: CGFloat = 28

    override var fittingSize: NSSize {
        NSSize(width: 22 + 16 + 6 + label.intrinsicContentSize.width, height: Self.height)
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 11, y: (bounds.height - 15) / 2, width: 16, height: 15)
        label.frame = NSRect(x: 33, y: (bounds.height - 15) / 2,
                             width: max(0, bounds.width - 39), height: 15)
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

    /// Selecionado é preenchimento CHEIO, e não texto colorido: dentro da pílula os
    /// dois botões dividem o mesmo fundo, e só a cor da letra deixava "em qual eu
    /// estou" a cargo de comparar dois tons de cinza.
    private func restyle() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
            icon.contentTintColor = .white
            label.textColor = .white
        } else {
            layer?.backgroundColor = hovering
                ? NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
                : NSColor.clear.cgColor
            let alpha: CGFloat = hovering ? 0.95 : 0.6
            icon.contentTintColor = NSColor(calibratedWhite: 1, alpha: alpha)
            label.textColor = NSColor(calibratedWhite: 1, alpha: alpha)
        }
    }
}

/// Barra superior: de que jeito você está olhando a bancada.
///
/// Separada da barra do canvas — que é flutuante, mora no rodapé e trata do que
/// você está FAZENDO: ferramenta armada, zoom, template. Esta trata de onde os
/// nós aparecem, e por isso é a única que continua na tela em todos os modos.
final class ViewToolbar: NSView {
    static let height: CGFloat = 46

    var onSelect: ((ViewMode) -> Void)?

    /// Onde o título começa. Cresce quando a barra encosta na borda esquerda da
    /// janela: com `fullSizeContentView`, os botões dela ficam ali em cima.
    var titleInset: CGFloat = 16 {
        didSet { if titleInset != oldValue { needsLayout = true } }
    }

    private var buttons: [ViewMode: ModeButton] = [:]
    /// Fundo da dupla de modos. Um trilho atrás dos dois, como abas: sem ele os
    /// botões flutuam no meio da barra e não se leem como um par de estados
    /// mutuamente exclusivos.
    private let pill = NSView()
    private let hint = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 1).cgColor

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 9
        pill.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
        addSubview(pill)

        for mode in ViewMode.all {
            let button = ModeButton(mode: mode)
            button.onClick = { [weak self] in self?.onSelect?(mode) }
            pill.addSubview(button)
            buttons[mode] = button
        }

        // Qual bancada está na tela. Repetido da barra lateral de propósito: lá é
        // uma lista e o que diz a ativa é um realce; aqui é afirmação.
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)

        subtitle.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        subtitle.textColor = NSColor(calibratedWhite: 1, alpha: 0.4)
        subtitle.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitle)

        hint.font = .systemFont(ofSize: 10)
        hint.textColor = NSColor(calibratedWhite: 1, alpha: 0.35)
        hint.alignment = .right
        hint.lineBreakMode = .byTruncatingTail
        addSubview(hint)
    }

    /// Que bancada a barra está anunciando.
    func setWorkbench(name: String, path: String) {
        title.stringValue = name
        subtitle.stringValue = path
        needsLayout = true
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init() { self.init(frame: .zero) }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let margem: CGFloat = 16
        let padding: CGFloat = 3

        // A pílula primeiro: ela manda no centro, e os dois lados se acomodam ao
        // que sobrar. Centrada na JANELA e não no espaço livre — se dependesse do
        // texto da esquerda, ela andaria a cada troca de bancada.
        var largura = padding
        for mode in ViewMode.all {
            largura += (buttons[mode]?.fittingSize.width ?? 0) + padding
        }
        let altura = ModeButton.height + padding * 2
        pill.frame = NSRect(x: ((bounds.width - largura) / 2).rounded(),
                            y: ((bounds.height - altura) / 2).rounded(),
                            width: largura, height: altura)

        var x = padding
        for mode in ViewMode.all {
            guard let button = buttons[mode] else { continue }
            let width = button.fittingSize.width
            button.frame = NSRect(x: x, y: padding, width: width, height: ModeButton.height)
            x += width + padding
        }

        let esquerda = max(0, pill.frame.minX - titleInset - margem)
        title.frame = NSRect(x: titleInset, y: 8, width: esquerda, height: 16)
        subtitle.frame = NSRect(x: titleInset, y: 25, width: esquerda, height: 13)

        let direita = max(0, bounds.width - pill.frame.maxX - margem * 2)
        hint.frame = NSRect(x: pill.frame.maxX + margem, y: (bounds.height - 13) / 2,
                            width: direita, height: 13)

        // O caminho é truncado no meio e a dica é a única forma de ler inteiro.
        // Vive numa região da barra porque o campo saiu do hit test.
        removeAllToolTips()
        if !subtitle.stringValue.isEmpty {
            addToolTip(subtitle.frame, owner: subtitle.stringValue as NSString, userData: nil)
        }
    }

    // MARK: A barra faz o que a titlebar faria

    /// A janela é `fullSizeContentView`, então esta view cobre a faixa da barra de
    /// título e come os cliques que iriam para ela. Quem trata o arrasto e o duplo
    /// clique ali é a titlebar; sem isto, a faixa do topo do app é a única do
    /// sistema onde arrastar não move e duplo clique não maximiza.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else {
            // `performDrag` roda o laço de arrasto do próprio AppKit — com snap às
            // bordas e a outros monitores, que um `setFrameOrigin` à mão não tem.
            window?.performDrag(with: event)
            return
        }
        // A ação é escolha do usuário em Ajustes › Área de Trabalho e Dock, e o
        // padrão de fábrica (chave ausente) é maximizar.
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window?.performMiniaturize(nil)
        case "None":     break
        default:         window?.performZoom(nil)
        }
    }

    /// Rótulo é texto, não botão: sobre o nome e o caminho da bancada o clique tem
    /// de continuar sendo clique na barra. `NSTextField` é `NSControl` e responde
    /// ao hit test mesmo sem ser editável nem selecionável.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let alvo = super.hitTest(point)
        if alvo === title || alvo === subtitle || alvo === hint { return self }
        return alvo
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
        switch mode {
        case .mosaic: hint.stringValue = "as posições do canvas ficam guardadas"
        case .chat:   hint.stringValue = "os terminais continuam rodando"
        case .canvas: hint.stringValue = ""
        }
    }
}

// MARK: - A bancada na tela

/// Uma bancada: a barra de visualização em cima e, embaixo, o canvas, o mosaico ou
/// o chat — os dois primeiros com os MESMOS nós.
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
    /// O modo chat. Criado junto com a bancada e não sob demanda como o mosaico: ele
    /// não guarda geometria de card nenhum, então nasce barato, e main.swift precisa
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
        // Em chat o card entra no canvas coberto, como em `place`: ele precisa do
        // passe de layout para o pty nascer com colunas. Na tela o que muda é a
        // lista da direita, na leitura seguinte.
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
            // O canvas CONTINUA montado, com os nós nele, e o chat entra opaco por
            // cima. Não é preguiça: um `NodeView` fora da hierarquia nunca recebe
            // passe de layout, e sem layout o SwiftTerm não tem colunas para
            // informar ao pty. Medido — bancada que ABRE em chat sobe os terminais
            // com tamanho zero, a TUI não tem onde desenhar, e a tela fica vazia
            // para sempre: `SIGWINCH` depois não faz o shell reimprimir o prompt.
            //
            // Coberto por uma view opaca de frame cheio, o canvas não aparece e não
            // recebe clique — o hit test para no chat, que é o irmão de cima.
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

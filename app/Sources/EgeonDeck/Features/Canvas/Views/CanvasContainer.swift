import AppKit

// MARK: - Documento do canvas (grid infinito)

final class CanvasDocument: NSView {
    override var isFlipped: Bool { true }

    /// Recebe o foco no clique de fundo, o que devolve a barra de espaço ao
    /// canvas: enquanto o foco está num terminal, espaço é caractere digitado.
    override var acceptsFirstResponder: Bool { true }

    // Sem cursor rect aqui, e a patinha do pan vive no `mouseMoved` do
    // CanvasContainer.
    //
    // Um cursor rect cobrindo o documento inteiro valia por baixo de TODO nó, e
    // quem perdia era o WKWebView do editor: ele troca o cursor por conta
    // própria, com `NSCursor.set`, e não tem cursor rect para disputar. O
    // resultado era a patinha grudada sobre o code-server, cobrindo o I-beam do
    // editor de código. O terminal escapava por acidente — o SwiftTerm declara
    // o cursor rect dele, e cursor rect de subview ganha do pai.

    // O pan vive no CanvasContainer, num monitor de eventos: aqui só chegariam
    // cliques que nenhum nó consumiu, e é justamente sobre os nós que o pan
    // precisa funcionar.

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).setFill()
        dirtyRect.fill()

        let step: CGFloat = 40
        NSColor(calibratedWhite: 1, alpha: 0.045).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1

        var x = (dirtyRect.minX / step).rounded(.down) * step
        while x < dirtyRect.maxX {
            path.move(to: NSPoint(x: x, y: dirtyRect.minY))
            path.line(to: NSPoint(x: x, y: dirtyRect.maxY))
            x += step
        }
        var y = (dirtyRect.minY / step).rounded(.down) * step
        while y < dirtyRect.maxY {
            path.move(to: NSPoint(x: dirtyRect.minX, y: y))
            path.line(to: NSPoint(x: dirtyRect.maxX, y: y))
            y += step
        }
        path.stroke()
    }
}

// MARK: - Container: scroll view com pan + zoom nativos

final class CanvasContainer: NSView {
    static let zoomSteps: [CGFloat] = [0.25, 0.4, 0.5, 0.67, 0.8, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]
    static let minDocumentSize = NSSize(width: 6000, height: 4000)
    /// Folga além do nó mais distante, para sempre haver canvas à frente.
    static let documentMargin: CGFloat = 1200
    /// Teto do documento. A origem deslizante cresce o documento a cada vez que
    /// alguém encosta na borda esquerda; sem teto, um pan longo cresceria sem fim.
    static let maxDocumentSize: CGFloat = 120_000

    let scroll = NSScrollView()
    let doc = CanvasDocument(frame: NSRect(x: 0, y: 0, width: 6000, height: 4000))
    let edgeLayer = EdgeLayerView()
    /// Zoom com que as arestas foram desenhadas por último. Ver `viewMoved`.
    private var edgeZoom: CGFloat = 1

    let toolbar = CanvasToolbar()
    /// O vidro que carrega a barra. É ele que entra na hierarquia e é dele que
    /// sai o frame — a barra em si é só o conteúdo.
    private lazy var toolbarPanel = GlassPanel(content: toolbar, radius: 14)

    /// De qual template esta bancada nasceu. Repassado à barra, que decide se
    /// mostra o botão de atualizar.
    var originTemplate: String? {
        didSet { toolbar.showsUpdateTemplate(originTemplate) }
    }
    private let overlay = ToolOverlay()

    /// Onde soltar um nó novo: retângulo já em coordenadas do documento.
    var onPlace: ((CanvasTool, NSRect) -> Void)?
    /// Nó movido, redimensionado ou criado — hora de gravar o workbenches.json.
    var onLayoutChanged: (() -> Void)?
    /// Clique no X de um nó. Confirmar é responsabilidade de quem escuta.
    var onRequestClose: ((NodeView) -> Void)?
    /// Botão de salvar template na barra.
    var onSaveTemplate: (() -> Void)?
    /// Botão de atualizar o template de origem, quando existe um.
    var onUpdateTemplate: (() -> Void)?
    /// Botão de nova worktree na barra.
    var onNewWorktree: (() -> Void)?
    /// Configurar um nó existente (lápis no cabeçalho).
    var onRequestEditNode: ((NodeView) -> Void)?
    /// Levar um nó para uma worktree própria (menu do cabeçalho).
    var onRequestNodeWorktree: ((NodeView) -> Void)?
    var onRequestNodeModel: ((NodeView, String?) -> Void)?
    /// Formulário para montar um terminal do zero.
    var onConfigureTerminal: (() -> Void)?
    /// Componentes salvos, para o menu da ferramenta de terminal.
    var nodeTemplateNames: (() -> [String])?
    /// Gesto de criar: dirigido, de quem você arrastou para quem recebeu. Quantos
    /// sentidos isso vira é política de quem grava, não do gesto.
    var onCreateEdge: ((EdgeConfig) -> Void)?
    /// Remover e editar chegam por LIGAÇÃO, que é o que existe na tela.
    var onRemoveEdge: ((EdgeLink) -> Void)?
    /// Clique na pastilha de limite da ligação.
    var onEditEdgeLimit: ((EdgeLink) -> Void)?
    /// Clique no botão de direção: ida → ida e volta → volta.
    var onCycleEdgeDirection: ((EdgeLink) -> Void)?
    /// Aviso a mostrar. O banner mora acima do canvas, e não aqui, porque em modo
    /// mosaico este container está fora da hierarquia — o aviso não apareceria.
    var onBanner: ((String?) -> Void)?
    /// Todos os nós da bancada, inclusive os que estão no mosaico agora.
    ///
    /// `spawnRect` precisa deles: com o mosaico ativo, `doc.subviews` está vazio e
    /// todo nó novo nasceria exatamente no mesmo canto.
    var placedNodes: (() -> [NodeView])?

    /// Ligações da bancada. Só terminal liga: editor e web não têm quem receba
    /// prompt.
    var edges: [EdgeConfig] {
        get { edgeLayer.edges }
        set { edgeLayer.edges = newValue }
    }

    /// Componente com que o próximo terminal nasce. Nil = shell padrão.
    ///
    /// Fica no canvas, e não no AppDelegate, porque é estado de gesto: você
    /// escolhe "revisor" e o próximo clique cria um revisor.
    private(set) var pendingComponent: String?

    var tool: CanvasTool = .cursor {
        didSet {
            guard tool != oldValue else { return }
            toolbar.select(tool)
            overlay.isHidden = (tool == .cursor)
            overlay.defaultSize = tool.defaultNodeSize
            // Alvo de remoção só faz sentido no cursor: com a ferramenta armada
            // o clique é de criação.
            if tool != .cursor { edgeLayer.setHovered(nil) }
            window?.invalidateCursorRects(for: overlay)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // NSScrollView já entrega pan (trackpad) e zoom (pinça) nativos. Nítido
        // ele não entrega: a magnificação é escala no layer, e quem acompanha o
        // zoom no `contentsScale` de cada card é `refreshContentsScale`.
        // Atrás dos nós, como no n8n: a curva passa por baixo dos cards e some
        // sob eles em vez de riscar o terminal.
        edgeLayer.frame = doc.bounds
        edgeLayer.frameForNode = { [weak self] id in
            self?.nodes.first { $0.nodeID == id }?.frame
        }
        edgeLayer.onRemove = { [weak self] link in self?.onRemoveEdge?(link) }
        edgeLayer.onEditLimit = { [weak self] link in self?.onEditEdgeLimit?(link) }
        edgeLayer.onCycleDirection = { [weak self] link in self?.onCycleEdgeDirection?(link) }
        doc.addSubview(edgeLayer)

        scroll.documentView = doc
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.allowsMagnification = true
        scroll.minMagnification = Self.zoomSteps.first!
        scroll.maxMagnification = Self.zoomSteps.last!
        scroll.magnification = 1.0
        scroll.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        scroll.drawsBackground = true
        addSubview(scroll)

        // Ordem importa: o overlay tapa o scroll para capturar o clique de
        // criação (senão o terminal engoliria), e a barra vem por cima dele
        // para continuar clicável.
        overlay.isHidden = true
        overlay.doc = doc
        overlay.onPlace = { [weak self] rect in
            guard let self, self.tool != .cursor else { return }
            self.onPlace?(self.tool, rect)
            // Igual ao Figma: colocou, volta pro cursor. O componente escolhido
            // vale para um nó só — deixá-lo armado faria o clique seguinte criar
            // um revisor sem você ter pedido.
            self.tool = .cursor
            self.pendingComponent = nil
        }
        addSubview(overlay)

        toolbar.onSelect = { [weak self] tool in self?.tool = tool }
        toolbar.onSaveTemplate = { [weak self] in self?.onSaveTemplate?() }
        toolbar.onNewWorktree = { [weak self] in self?.onNewWorktree?() }
        toolbar.nodeTemplateNames = { [weak self] in self?.nodeTemplateNames?() ?? [] }
        toolbar.onConfigureTerminal = { [weak self] in self?.onConfigureTerminal?() }
        toolbar.onUpdateTemplate = { [weak self] in self?.onUpdateTemplate?() }
        toolbar.onPickComponent = { [weak self] name in
            guard let self else { return }
            // Escolher um componente arma a ferramenta de terminal: o próximo
            // clique no canvas é que decide onde ele nasce.
            self.pendingComponent = name
            self.tool = .terminal
            self.showBanner(name.map { "Próximo terminal: \($0)" }
                            ?? "Próximo terminal: shell")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.showBanner(nil)
            }
        }
        toolbar.onZoom = { [weak self] direction in self?.stepZoom(direction) }
        toolbar.onResetZoom = { [weak self] in self?.zoom(to: 1) }
        toolbar.onFitAll = { [weak self] in self?.fitAll() }
        addSubview(toolbarPanel)

        NotificationCenter.default.addObserver(
            self, selector: #selector(viewMoved),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        scroll.contentView.postsBoundsChangedNotifications = true

        toolbar.select(.cursor)
        toolbar.showZoom(1)
        installEventMonitor()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    // MARK: - Navegação que precisa passar por cima dos nós
    //
    // SwiftTerm e WKWebView consomem mouse e scroll inteiros, então um clique
    // sobre um nó nunca chega ao canvas — daí "pan funciona em algumas áreas e
    // em outras não". Um monitor local vê o evento ANTES da entrega à view, e
    // devolver nil o consome.

    private var eventMonitor: Any?
    private var panAnchor: (mouse: NSPoint, origin: NSPoint)?

    private func installEventMonitor() {
        // `mouseMoved` só é gerado se a janela pedir. É o que alimenta o realce
        // da aresta sob o cursor — sem tracking area própria, que a camada de
        // arestas não teria como ter: ela é transparente ao hit test.
        window?.acceptsMouseMovedEvents = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .scrollWheel, .mouseMoved,
            .leftMouseDown, .leftMouseDragged, .leftMouseUp,
            .otherMouseDown, .otherMouseDragged, .otherMouseUp
        ]) { [weak self] event in
            self?.intercept(event) ?? event
        }
    }

    /// Um monitor local vale para o app todo, e existe um canvas por bancada.
    /// `superview != nil` garante que só o canvas na tela reaja.
    private var isLive: Bool { superview != nil && window != nil }

    private func intercept(_ event: NSEvent) -> NSEvent? {
        guard isLive, event.window === window else { return event }

        switch event.type {
        case .mouseMoved:
            updateCursor(event)
            guard tool == .cursor, isOverCanvas(event) else {
                edgeLayer.setHovered(nil)
                return event
            }
            let inDoc = doc.convert(event.locationInWindow, from: nil)
            edgeLayer.setHovered(edgeLayer.link(near: inDoc))
            return event

        case .scrollWheel:
            guard isOverCanvas(event) else { return event }
            // ⌘+scroll: zoom ancorado no cursor, como no Figma.
            if event.modifierFlags.contains(.command) {
                zoomAtCursor(event)
                return nil
            }
            extendDocument(forWheel: event)
            return event

        case .leftMouseDown:
            guard isOverCanvas(event) else { return event }
            // ⌥ pana de qualquer lugar, inclusive por cima de um nó.
            //
            // Aqui não entra pan por barra de espaço: espaço exige guardar
            // "está pressionado", e um keyUp perdido (troca de janela, foco
            // mudando) deixa a flag grudada — daí todo arrasto virava pan, até
            // no cabeçalho do nó. Modificador é lido do próprio evento e não
            // tem como grudar.
            let forced = event.modifierFlags.contains(.option)
            guard forced || hitsBackground(event) else { return event }
            if !forced { window?.makeFirstResponder(doc) }
            beginPan(event)
            return nil

        case .otherMouseDown:
            // Botão do meio: o gesto de pan que não colide com nada.
            guard isOverCanvas(event) else { return event }
            beginPan(event)
            return nil

        case .leftMouseDragged, .otherMouseDragged:
            guard panAnchor != nil else { return event }
            continuePan(event)
            return nil

        case .leftMouseUp, .otherMouseUp:
            guard panAnchor != nil else { return event }
            endPan()
            return nil

        default:
            return event
        }
    }

    private func isOverCanvas(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        // A barra fica por cima do canvas e tem os cliques dela.
        return bounds.contains(point) && !toolbarPanel.frame.contains(point)
    }

    /// O teclado está sendo digitado dentro de um nó (terminal, editor, campo de
    /// URL) e não no canvas. Quem monta o menu usa isto para ceder os atalhos:
    /// ⌘1…⌘4 e ⌘=/⌘− já têm dono dentro do workbench.
    var focusIsInsideNode: Bool {
        var view = window?.firstResponder as? NSView
        while let current = view {
            if current is NodeView { return true }
            view = current.superview
        }
        return false
    }

    /// Clique caiu no grid, e não em cima de um nó.
    ///
    /// Subir a cadeia de superviews em vez de comparar o alvo com uma lista:
    /// o cabeçalho de um nó pode devolver o rótulo, o botão de fechar, a alça ou
    /// o próprio nó, e tratar qualquer um deles como fundo rouba o arrasto que
    /// deveria mover o nó.
    private func hitsBackground(_ event: NSEvent) -> Bool {
        guard let hit = window?.contentView?.hitTest(event.locationInWindow) else { return false }

        var view: NSView? = hit
        while let current = view {
            if current is NodeView { return false }
            // Com uma ferramenta armada o overlay está na frente, e o clique é
            // de criação de nó, não de pan.
            if current === overlay { return false }
            if current === toolbarPanel { return false }
            view = current.superview
        }
        return hit === doc || hit === scroll || hit === scroll.contentView
    }

    // MARK: - Cursor

    /// A patinha vive no cabeçalho do nó, e em nenhum outro lugar.
    ///
    /// Por `NSCursor.set` e não por cursor rect: um rect no documento valia por
    /// baixo de todo nó, e quem perdia era o WKWebView do editor — ele troca o
    /// cursor sozinho, com `set`, e não tem rect para disputar. Era assim que a
    /// patinha grudava sobre o code-server, cobrindo o I-beam do editor.
    ///
    /// O corpo do nó fica de fora de propósito: quem manda ali é o terminal ou o
    /// WKWebView, cada um sabendo o cursor que quer.
    private func updateCursor(_ event: NSEvent) {
        guard tool == .cursor else { return }
        // `hitsBackground` e não `isOverCanvas`: o segundo só diz que o ponto
        // caiu na área do canvas, e isso inclui o que está EM CIMA dos nós.
        if hitsBackground(event) {
            NSCursor.arrow.set()
            return
        }
        guard let hit = window?.contentView?.hitTest(event.locationInWindow),
              // Botões do cabeçalho têm cursor próprio; sobrescrever aqui faria o
              // ponteiro piscar entre a patinha e a seta em cima deles.
              !(hit is ToolbarButton)
        else { return }

        var view: NSView? = hit
        while let current = view {
            if let node = current as? NodeView {
                if node.isInHeader(windowPoint: event.locationInWindow) {
                    NSCursor.openHand.set()
                }
                return
            }
            view = current.superview
        }
    }

    // MARK: - Pan

    private func beginPan(_ event: NSEvent) {
        panAnchor = (event.locationInWindow, scroll.contentView.bounds.origin)
        NSCursor.closedHand.push()
    }

    private func continuePan(_ event: NSEvent) {
        guard var anchor = panAnchor else { return }
        let now = event.locationInWindow
        let magnification = scroll.magnification
        var target = NSPoint(
            x: anchor.origin.x - (now.x - anchor.mouse.x) / magnification,
            y: anchor.origin.y + (now.y - anchor.mouse.y) / magnification)

        // Navegar além da borda esquerda/topo abre espaço igual ao arrasto de nó,
        // senão o canvas seria infinito para mover nó e finito para olhar.
        if target.x < 0 || target.y < 0 {
            let shift = CGSize(width: max(0, -target.x), height: max(0, -target.y))
            let widthBefore = doc.frame.width
            let heightBefore = doc.frame.height
            makeSpace(shift)

            // O teto do documento pode ter recusado: só compensa a âncora pelo
            // que de fato foi aberto, senão a vista descola do cursor.
            let openedX = doc.frame.width - widthBefore
            let openedY = doc.frame.height - heightBefore
            anchor.origin.x += openedX
            anchor.origin.y += openedY
            panAnchor = anchor
            target.x += openedX
            target.y += openedY
        }

        // Além da borda direita/de baixo também, senão o canvas seria infinito
        // para um lado só. Aqui basta o documento crescer.
        extendDocument(toShow: target)

        scroll.contentView.scroll(to: clampedOrigin(target))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Prende a origem dentro do documento.
    ///
    /// `NSClipView` faria isso ao rolar normalmente, mas `scroll(to:)` chamado à
    /// mão aceita valores fora e a vista escapa do documento — foi assim que a
    /// origem chegou a x=-319 e o canvas passou a "escorregar" para a esquerda,
    /// levando nós para onde nenhum gesto alcança.
    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let viewport = scroll.contentView.bounds.size
        return NSPoint(
            x: min(max(0, origin.x), max(0, doc.frame.width - viewport.width)),
            y: min(max(0, origin.y), max(0, doc.frame.height - viewport.height)))
    }

    private func endPan() {
        panAnchor = nil
        NSCursor.pop()
    }

    // MARK: - Zoom no cursor

    private func zoomAtCursor(_ event: NSEvent) {
        // Roda entrega passos grandes e discretos; trackpad, valores contínuos.
        // Sem normalizar, um clique de roda dá um salto de zoom absurdo.
        var delta = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { delta *= 6 }
        if event.isDirectionInvertedFromDevice { delta = -delta }
        guard delta != 0 else { return }

        // Parte do valor cru enquanto a magnificação for dele — é assim que a
        // roda atravessa a detente. Se o zoom mudou por fora (pinça, ⌘0, botão),
        // o cru está velho e quem manda é a magnificação.
        let base = abs(detente(rawMagnification) - scroll.magnification) < 0.0001
            ? rawMagnification : scroll.magnification

        // Exponencial: o passo é proporcional ao zoom atual, então a sensação é
        // a mesma em 0.3x e em 2x. Sinal negativo para casar com o Figma —
        // deslizar para cima aproxima.
        applyZoom(base * pow(1.0025, -delta), keeping: event.locationInWindow)
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        overlay.frame = bounds

        let size = toolbar.fittingSize
        toolbarPanel.frame = NSRect(x: (bounds.width - size.width) / 2,
                                    y: bounds.minY + 24,
                                    width: size.width, height: size.height)
    }

    func showBanner(_ text: String?) { onBanner?(text) }

    /// Pan e zoom passam os dois por aqui: o bounds do clip view muda nos dois
    /// casos, inclusive na pinça do trackpad.
    @objc private func viewMoved() {
        toolbar.showZoom(scroll.magnification)
        refreshContentsScale()
        // Ponta e controles da aresta são medidos em pontos de TELA, então mudar o
        // zoom muda o que eles valem no documento. Só no zoom: isto também roda a
        // cada pixel de pan, e ali nada mudou de tamanho.
        if abs(edgeZoom - scroll.magnification) > 0.0001 {
            edgeZoom = scroll.magnification
            edgeLayer.needsDisplay = true
        }
    }

    // MARK: - Nitidez

    /// Teto da rasterização. Numa tela Retina, 3x de zoom pediria escala 6, e o
    /// backing store cresce com o quadrado dela.
    private static let maxContentsScale: CGFloat = 3

    /// Em quantos pixels de verdade cada ponto do card aparece: a escala da tela
    /// vezes o zoom do canvas.
    ///
    /// Piso em 1 porque abaixo disso o glifo é rasterizado menor que o pixel e o
    /// ganho vira ruído — em zoom out ninguém lê o terminal mesmo.
    private var contentsScaleForNodes: CGFloat {
        let backing = window?.backingScaleFactor ?? 2
        return min(max(backing * scroll.magnification, 1), Self.maxContentsScale)
    }

    /// Manda cada nó se redesenhar na resolução em que está aparecendo.
    ///
    /// Chamado a cada quadro de pan e de zoom: a guarda é o que segura o custo,
    /// já que pan não muda escala nenhuma.
    private func refreshContentsScale() {
        let scale = contentsScaleForNodes
        guard abs(scale - appliedContentsScale) > 0.001 else { return }
        appliedContentsScale = scale
        nodes.forEach { $0.applyContentsScale(scale) }
    }

    private var appliedContentsScale: CGFloat = 0

    /// Trocar de tela muda o fator de escala sem mexer no zoom — arrastar a
    /// janela do monitor 1x para o Retina precisa redesenhar tudo.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshContentsScale()
    }

    // MARK: - Zoom

    /// Zoom pedido antes da detente. O gesto continua a partir daqui: partindo
    /// do valor já grudado, cada evento cairia de novo dentro da janela de
    /// captura e a roda ficaria presa no passo.
    private var rawMagnification: CGFloat = 1

    /// Gruda no passo mais próximo dentro de 3%.
    ///
    /// O zoom da roda é exponencial e nunca cai em 1.0 exato — 112%, 78%, 141%.
    /// Fora dos passos redondos o canvas some do lugar onde os números são
    /// legíveis, e 100% é o único ponto em que ninguém reamostra nada.
    private func detente(_ value: CGFloat) -> CGFloat {
        guard let step = Self.zoomSteps.min(by: { abs($0 - value) < abs($1 - value) })
        else { return value }
        return abs(step - value) <= step * 0.03 ? step : value
    }

    /// Zoom que deixa um ponto da tela parado no lugar.
    ///
    /// `setMagnification(_:centeredAt:)` seria o caminho óbvio, mas ele espera o
    /// ponto no sistema do content view e na prática desloca o conteúdo para o
    /// centro — era isso que fazia todo zoom "saltar para o meio da janela".
    /// Medir o ponto antes e depois da troca de escala, e corrigir o offset pela
    /// diferença, é o que de fato ancora.
    private func applyZoom(_ value: CGFloat, keeping windowPoint: NSPoint) {
        let clamped = min(max(value, scroll.minMagnification), scroll.maxMagnification)
        // Antes da guarda: preso na detente, a magnificação não muda e sair dela
        // depende justamente de o valor cru continuar andando.
        rawMagnification = clamped

        let target = detente(clamped)
        guard abs(target - scroll.magnification) > 0.0001 else { return }

        // Crescer antes: em zoom out o viewport passa a cobrir mais unidades do
        // que o documento tem, e o scroll seria clampeado — o que sozinho já
        // desloca a vista.
        growDocumentIfNeeded(forMagnification: target)

        let magBefore = scroll.magnification
        let originBefore = scroll.contentView.bounds.origin
        let before = doc.convert(windowPoint, from: nil)
        scroll.magnification = target
        let after = doc.convert(windowPoint, from: nil)

        var origin = scroll.contentView.bounds.origin
        origin.x += before.x - after.x
        origin.y += before.y - after.y
        origin = clampedOrigin(origin)
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)

        Log.write(String(format:
            "canvas: zoom %.3f→%.3f | âncora janela (%.0f,%.0f) | doc antes (%.0f,%.0f) "
            + "depois (%.0f,%.0f) | origem %.0f,%.0f → alvo %.0f,%.0f → final %.0f,%.0f",
            Double(magBefore), Double(scroll.magnification),
            windowPoint.x, windowPoint.y,
            before.x, before.y, after.x, after.y,
            originBefore.x, originBefore.y,
            origin.x, origin.y,
            scroll.contentView.bounds.origin.x, scroll.contentView.bounds.origin.y))

        toolbar.showZoom(scroll.magnification)
    }

    /// Centro do viewport em coordenadas de janela. É a âncora dos botões e dos
    /// atalhos: o que está no meio da tela continua no meio.
    private var viewportCenterInWindow: NSPoint {
        convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
    }

    func zoom(to value: CGFloat) {
        applyZoom(value, keeping: viewportCenterInWindow)
    }

    /// Zoom que faz um retângulo caber num viewport com margem. Nunca passa de
    /// 100%: dois cards pequenos não devem virar terminais gigantes — enquadrar
    /// é achar, não ampliar.
    static func fitZoom(for content: NSRect, in viewport: NSSize,
                        margin: CGFloat = 60) -> CGFloat {
        let usable = NSSize(width: viewport.width - 2 * margin,
                            height: viewport.height - 2 * margin)
        guard content.width > 0, content.height > 0, usable.width > 0, usable.height > 0
        else { return 1 }
        let scale = min(usable.width / content.width, usable.height / content.height, 1)
        return min(max(scale, zoomSteps.first!), zoomSteps.last!)
    }

    /// O que cobre o canvas por cima e não é canvas: a barra lateral flutuante à
    /// esquerda (largura lida na hora — recolhida ou aberta) e a barra de
    /// ferramentas embaixo. Enquadrar usa só o que sobra.
    var visibleInsets: (() -> NSEdgeInsets)?

    /// Em coordenadas do container, que NÃO é flipped: a barra de ferramentas
    /// fica em y pequeno, embaixo. `y` da área é a borda de baixo.
    private var visibleArea: NSRect {
        var insets = visibleInsets?() ?? NSEdgeInsets()
        insets.bottom = max(insets.bottom, toolbarPanel.frame.maxY + 12)
        return NSRect(x: insets.left, y: insets.bottom,
                      width: max(0, bounds.width - insets.left - insets.right),
                      height: max(0, bounds.height - insets.top - insets.bottom))
    }

    private var nodesUnion: NSRect? {
        let frames = nodes.map(\.frame)
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Enquadra todos os nós na área visível: zoom para caberem, centrados. É
    /// onde a bancada abre — em (0,0) você caía num canto vazio e tinha de
    /// procurar os cards — e o botão da barra quando você se perde no canvas.
    func fitAll() {
        guard let union = nodesUnion, bounds.width > 0, bounds.height > 0 else { return }
        let area = visibleArea
        guard area.width > 0, area.height > 0 else { return }
        let target = Self.fitZoom(for: union, in: area.size)

        growDocumentIfNeeded(forMagnification: target)
        rawMagnification = target
        scroll.magnification = target

        // A união de novo: crescer o documento DESLOCA os nós, e centrar na
        // união antiga errava por exatamente esse deslocamento.
        guard let moved = nodesUnion else { return }
        // O documento é flipped (y cresce para baixo) e o container não: o
        // centro da área, medido do topo, é o que se converte para o documento.
        let centerFromTop = bounds.height - area.midY
        let origin = NSPoint(x: moved.midX - area.midX / target,
                             y: moved.midY - centerFromTop / target)
        scroll.contentView.scroll(to: clampedOrigin(origin))
        scroll.reflectScrolledClipView(scroll.contentView)
        toolbar.showZoom(scroll.magnification)
        Log.write(String(format: "canvas: enquadrei %d nós em zoom %.2f, área útil %.0f×%.0f (lateral %.0f)",
                         nodes.count, Double(target), area.width, area.height, area.minX))
    }

    func stepZoom(_ direction: Int) {
        let current = scroll.magnification
        let next: CGFloat?
        if direction > 0 {
            next = Self.zoomSteps.first { $0 > current + 0.001 }
        } else {
            next = Self.zoomSteps.last { $0 < current - 0.001 }
        }
        zoom(to: next ?? current)
    }

    // MARK: - Nós

    /// A camada de arestas cobre o documento inteiro e fica no fundo. Chamado
    /// sempre que o documento cresce — em `makeSpace` e no zoom out.
    private func syncEdgeLayer() {
        if edgeLayer.frame != doc.bounds { edgeLayer.frame = doc.bounds }
        if doc.subviews.first !== edgeLayer {
            doc.addSubview(edgeLayer, positioned: .below, relativeTo: nil)
        }
        edgeLayer.needsDisplay = true
    }

    func add(_ node: NodeView) {
        doc.addSubview(node)
        // O nó pode estar voltando do mosaico, onde perdeu a alça e a porta.
        node.isFreeform = true
        // Sem forçar o layout, o terminal nasce com frame zero e só descobre o
        // tamanho real na primeira interação — até lá o pty roda numa tela de
        // dimensão degenerada e o buffer sai vazio.
        node.layoutSubtreeIfNeeded()
        // Nó novo nasce na escala do zoom atual: quem só reage à troca de zoom
        // deixaria este desenhado na escala da tela até você mexer na roda.
        node.applyContentsScale(contentsScaleForNodes)
        node.onFrameChanged = { [weak self] _ in
            self?.growDocumentIfNeeded()
            self?.onLayoutChanged?()
        }
        node.onFrameChanging = { [weak self] in self?.edgeLayer.needsDisplay = true }
        node.onPortDrag = { [weak self] node, point in
            guard let self else { return }
            self.edgeLayer.pending = (node.nodeID, self.doc.convert(point, from: nil))
        }
        node.onPortRelease = { [weak self] node, point in
            guard let self else { return }
            self.edgeLayer.pending = nil
            let inDoc = self.doc.convert(point, from: nil)
            guard let target = self.terminals.first(where: { $0.frame.contains(inDoc) }),
                  target.nodeID != node.nodeID,
                  // Já ligado é já ligado em qualquer sentido: o par é uma linha
                  // só, e arrastar de novo por cima dela não cria nada.
                  !self.edges.contains(EdgeConfig(from: node.nodeID, to: target.nodeID)),
                  !self.edges.contains(EdgeConfig(from: target.nodeID, to: node.nodeID))
            else { return }
            self.onCreateEdge?(EdgeConfig(from: node.nodeID, to: target.nodeID))
        }
        node.onRequestClose = { [weak self] node in self?.onRequestClose?(node) }
        node.onRequestSpace = { [weak self] shift in self?.makeSpace(shift) }
        node.onRequestEdit = { [weak self] node in self?.onRequestEditNode?(node) }
        node.onRequestWorktree = { [weak self] node in self?.onRequestNodeWorktree?(node) }
        (node as? TerminalNode)?.onRequestModel = { [weak self] node, model in
            self?.onRequestNodeModel?(node, model)
        }
        growDocumentIfNeeded()
    }

    /// Abre espaço à esquerda e no topo deslocando o mundo inteiro.
    ///
    /// O documento tem canto em (0,0) e o scroll não vai a negativo, então
    /// "infinito à esquerda" não vem de permitir coordenada negativa — vem de
    /// mover todos os nós e a vista pelo mesmo tanto. Na tela nada se move, e
    /// quem estava na borda ganha para onde ir.
    ///
    /// Compensar o scroll no MESMO ciclo é o que evita o salto: sem isso, todo
    /// nó pularia para a direita na hora em que o espaço fosse aberto.
    func makeSpace(_ shift: CGSize) {
        let dx = max(0, shift.width.rounded())
        let dy = max(0, shift.height.rounded())
        guard dx > 0 || dy > 0 else { return }

        // Teto para o documento não crescer sem fim em pans longos: chegando
        // aqui, volta a valer o limite duro da borda.
        guard doc.frame.width + dx <= Self.maxDocumentSize,
              doc.frame.height + dy <= Self.maxDocumentSize else {
            Log.write("canvas: documento no teto de \(Int(Self.maxDocumentSize))pt, "
                      + "não abro mais espaço", key: "canvas.docmax")
            return
        }

        doc.setFrameSize(NSSize(width: doc.frame.width + dx, height: doc.frame.height + dy))
        syncEdgeLayer()

        for node in nodes {
            node.setFrameOrigin(NSPoint(x: node.frame.minX + dx, y: node.frame.minY + dy))
        }

        let origin = scroll.contentView.bounds.origin
        scroll.contentView.scroll(to: NSPoint(x: origin.x + dx, y: origin.y + dy))
        scroll.reflectScrolledClipView(scroll.contentView)
        doc.needsDisplay = true

        // As coordenadas de todos mudaram; o arquivo precisa acompanhar.
        onLayoutChanged?()
    }

    /// Abre espaço à direita e embaixo: o documento cresce até um viewport com
    /// origem em `origin` caber inteiro. É o par de `makeSpace`, e mais barato —
    /// o canto (0,0) fica onde está, então nó nenhum se desloca.
    func extendDocument(toShow origin: NSPoint) {
        let viewport = scroll.contentView.bounds.size
        growDocument(toAtLeast: NSSize(width: origin.x + viewport.width,
                                       height: origin.y + viewport.height))
    }

    /// A roda do trackpad vai para o NSScrollView, que para na borda do
    /// documento — crescer ANTES de entregar o evento faz a borda recuar junto.
    /// Delta negativo é a vista andando para a direita/baixo, já com a inversão
    /// "natural" aplicada pelo sistema.
    private func extendDocument(forWheel event: NSEvent) {
        let origin = scroll.contentView.bounds.origin
        let scale = max(scroll.magnification, 0.01)
        // Em blocos: crescer a cada pixel redesenharia as arestas a cada evento.
        let chunk: CGFloat = 512
        var target = origin
        if event.scrollingDeltaX < 0 { target.x += chunk - event.scrollingDeltaX / scale }
        if event.scrollingDeltaY < 0 { target.y += chunk - event.scrollingDeltaY / scale }
        guard target != origin else { return }
        extendDocument(toShow: target)
    }

    /// Cresce o documento até `size`; nunca encolhe. No teto o canvas volta a
    /// ter borda dura — diferente de `makeSpace`, que precisa recusar inteiro
    /// para não deslocar os nós pela metade.
    func growDocument(toAtLeast size: NSSize) {
        let width = min(max(size.width.rounded(.up), doc.frame.width), Self.maxDocumentSize)
        let height = min(max(size.height.rounded(.up), doc.frame.height), Self.maxDocumentSize)
        guard width > doc.frame.width || height > doc.frame.height else { return }
        doc.setFrameSize(NSSize(width: width, height: height))
        doc.needsDisplay = true
        syncEdgeLayer()
    }

    /// O documento era fixo em 6000×4000, e isso trava o pan de dois jeitos: um
    /// nó arrastado para perto da borda não tem para onde continuar, e em zoom
    /// out o viewport passa a mostrar mais unidades do que o documento tem —
    /// aí o scroll simplesmente não anda.
    func growDocumentIfNeeded(forMagnification magnification: CGFloat? = nil) {
        var size = Self.minDocumentSize

        for node in nodes {
            size.width = max(size.width, node.frame.maxX + Self.documentMargin)
            size.height = max(size.height, node.frame.maxY + Self.documentMargin)
        }

        // Quanto do documento o viewport cobre na escala em questão. Recebe a
        // magnificação de destino quando o chamador está no meio de um zoom.
        let scale = magnification ?? scroll.magnification
        guard scale > 0 else { return }
        let viewport = NSSize(width: bounds.width / scale, height: bounds.height / scale)
        size.width = max(size.width, viewport.width * 1.5)
        size.height = max(size.height, viewport.height * 1.5)
        growDocument(toAtLeast: size)
    }

    /// Tira o nó da tela depois de alguém já ter confirmado.
    func remove(_ node: NodeView) {
        node.prepareForRemoval()
        node.removeFromSuperview()
    }

    var nodes: [NodeView] { doc.subviews.compactMap { $0 as? NodeView } }

    var terminals: [TerminalNode] { doc.subviews.compactMap { $0 as? TerminalNode } }

    func refreshBadges() { terminals.forEach { $0.refreshBadge() } }

    /// Ponto livre perto do canto superior esquerdo do que está visível — para
    /// quando um nó nasce sem alguém ter desenhado onde.
    func spawnRect(size: NSSize) -> NSRect {
        let visible = scroll.contentView.bounds
        let taken = placedNodes?() ?? nodes
        var origin = NSPoint(x: visible.minX + 40, y: visible.minY + 40)
        // Empilha em diagonal enquanto o lugar estiver ocupado, senão nós novos
        // nascem exatamente em cima uns dos outros.
        while taken.contains(where: { abs($0.frame.minX - origin.x) < 8 && abs($0.frame.minY - origin.y) < 8 }) {
            origin.x += 32
            origin.y += 32
        }
        return NSRect(origin: origin, size: size)
    }
}

// MARK: - Overlay de criação

/// Capa transparente ligada enquanto a ferramenta não é o cursor. Existe porque
/// terminal e WKWebView consomem o mouse inteiro: sem ela, clicar "dentro" de um
/// nó para criar outro simplesmente digitaria no terminal.
final class ToolOverlay: NSView {
    weak var doc: NSView?
    var onPlace: ((NSRect) -> Void)?

    /// Tamanho de quem só clica, sem arrastar. Trocado pela ferramenta ativa.
    var defaultSize = NSSize(width: 720, height: 460)
    private static let dragThreshold: CGFloat = 24

    private var start: NSPoint?
    private var current: NSPoint?

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil; current = nil; needsDisplay = true }
        guard let start, let current, let doc else { return }

        let a = doc.convert(start, from: self)
        let b = doc.convert(current, from: self)
        let dragged = NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
                             width: abs(b.x - a.x), height: abs(b.y - a.y))

        let rect = (dragged.width < Self.dragThreshold || dragged.height < Self.dragThreshold)
            ? NSRect(origin: a, size: defaultSize)
            : dragged
        onPlace?(NSRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
                        width: max(NodeView.minSize.width, rect.width.rounded()),
                        height: max(NodeView.minSize.height, rect.height.rounded())))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let start, let current else { return }
        let rect = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        guard rect.width > 2, rect.height > 2 else { return }

        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

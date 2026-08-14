import AppKit
import SwiftTerm

// MARK: - Nó base

/// Alça de resize no canto inferior direito.
///
/// Vive como subview do nó, acima do corpo, porque o SwiftTerm e o WKWebView
/// engolem o mouse inteiro — um `mouseDown` do próprio `NodeView` nunca
/// chegaria em cima deles.
final class NodeResizeGrip: NSView {
    var onDrag: ((CGSize) -> Void)?
    var onEnd: (() -> Void)?

    private var last: NSPoint?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 1, alpha: 0.25).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        for offset in stride(from: 4, through: 12, by: 4) {
            path.move(to: NSPoint(x: bounds.maxX - CGFloat(offset), y: bounds.maxY - 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.maxY - CGFloat(offset)))
        }
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) { last = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let previous = last else { return }
        let now = event.locationInWindow
        // O nó vive num documento magnificado: 10px de mouse viram 20 unidades
        // de documento a 0.5x. Sem dividir, a alça foge do cursor.
        let magnification = enclosingScrollView?.magnification ?? 1
        onDrag?(CGSize(width: (now.x - previous.x) / magnification,
                       // Janela tem y crescendo pra cima; o documento é flipped.
                       height: (previous.y - now.y) / magnification))
        last = now
    }

    override func mouseUp(with event: NSEvent) {
        last = nil
        onEnd?()
    }
}

/// Todo nó do canvas é um card: cabeçalho (área de arrasto) + corpo.
class NodeView: NSView {
    static let headerHeight: CGFloat = 26
    static let minSize = NSSize(width: 280, height: 180)
    static let gripSize: CGFloat = 16

    /// `id` dentro da sessão. Vazio nos nós que não vivem no
    /// sessions.json (placeholder, portal) — a persistência os ignora.
    let nodeID: String

    /// Cor do tipo do nó. Guardada porque o alerta troca a borda e precisa
    /// saber para o que voltar.
    let accent: NSColor

    let titleLabel = NSTextField(labelWithString: "")
    let body = NSView()
    private let grip = NodeResizeGrip()
    private let closeButton = ToolbarButton(symbols: ["xmark"], tooltip: "Remover nó", size: 18)
    private let editButton = ToolbarButton(symbols: ["slider.horizontal.3", "pencil"],
                                           tooltip: "Configurar este nó", size: 18)

    /// Disparado ao soltar um arrasto ou um resize. É o gancho de persistência:
    /// só no fim do gesto, para não reescrever o JSON a cada pixel.
    var onFrameChanged: ((NodeView) -> Void)?

    /// Disparado a cada pixel do gesto. Só para quem desenha em cima da posição
    /// do nó — as arestas ficariam presas no lugar antigo até você soltar.
    var onFrameChanging: (() -> Void)?

    /// Pedido de remoção. Quem escuta confirma com o usuário e só então remove —
    /// o nó não se apaga sozinho.
    var onRequestClose: ((NodeView) -> Void)?

    /// "Preciso de espaço à esquerda/topo." O canvas responde deslocando o mundo
    /// inteiro, o que deixa este nó livre para continuar andando.
    var onRequestSpace: ((CGSize) -> Void)?

    /// Pedido de configuração: nome, comando, agente, pasta, papel.
    var onRequestEdit: ((NodeView) -> Void)?

    /// Arrasto saindo do `+` deste nó, em coordenadas de janela. Quem converte
    /// para o documento e resolve o destino é o canvas.
    var onPortDrag: ((NodeView, NSPoint) -> Void)?
    var onPortRelease: ((NodeView, NSPoint) -> Void)?

    private var dragOffset: CGPoint?

    init(frame: NSRect, title: String, accent: NSColor, nodeID: String = "") {
        self.nodeID = nodeID
        self.accent = accent
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1).cgColor
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
        layer?.masksToBounds = true

        titleLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = accent
        titleLabel.stringValue = title
        addSubview(titleLabel)
        addSubview(body)
        addSubview(grip)
        addSubview(editButton)
        addSubview(closeButton)

        grip.onDrag = { [weak self] delta in self?.resize(by: delta) }
        grip.onEnd = { [weak self] in
            guard let self else { return }
            self.onFrameChanged?(self)
        }
        closeButton.onClick = { [weak self] in
            guard let self else { return }
            self.onRequestClose?(self)
        }
        editButton.onClick = { [weak self] in
            guard let self else { return }
            self.onRequestEdit?(self)
        }
        // Só nós que têm o que configurar. O editor não tem comando nem papel; o
        // que ele abre vem da pasta da sessão.
        editButton.isHidden = !supportsEditing
    }

    /// Nó com configuração editável (comando, agente, pasta, papel).
    var supportsEditing: Bool { false }

    private var isAlerting = false

    /// Acende o card enquanto alguém espera você.
    ///
    /// A borda, e não só o texto: com zoom out o cabeçalho fica ilegível muito
    /// antes de o card sumir, e é aí que você mais precisa achar quem parou.
    func setAlert(_ on: Bool) {
        guard on != isAlerting else { return }
        isAlerting = on
        layer?.borderWidth = on ? 2 : 1
        layer?.borderColor = on
            ? NSColor.systemOrange.withAlphaComponent(0.95).cgColor
            : accent.withAlphaComponent(0.55).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// O ponto está no cabeçalho deste nó? Em coordenadas de janela.
    ///
    /// Quem pergunta é o canvas, para pôr a patinha só onde se arrasta. Mora
    /// aqui, e não lá, porque é este quem sabe onde o cabeçalho acaba — e vale
    /// para todo tipo de nó, que nenhuma subclasse mexe no cabeçalho.
    func isInHeader(windowPoint: NSPoint) -> Bool {
        let local = convert(windowPoint, from: nil)
        return bounds.contains(local) && local.y >= 0 && local.y <= Self.headerHeight
    }

    override func layout() {
        super.layout()
        let closeSize: CGFloat = 18
        let controls = closeSize + (editButton.isHidden ? 0 : closeSize + 2)
        titleLabel.frame = NSRect(x: 10, y: 6,
                                  width: max(0, bounds.width - 20 - controls - 6), height: 15)
        closeButton.frame = NSRect(x: bounds.width - closeSize - 5,
                                   y: (Self.headerHeight - closeSize) / 2,
                                   width: closeSize, height: closeSize)
        editButton.frame = NSRect(x: bounds.width - closeSize * 2 - 7,
                                  y: (Self.headerHeight - closeSize) / 2,
                                  width: closeSize, height: closeSize)
        body.frame = NSRect(x: 1, y: Self.headerHeight,
                            width: bounds.width - 2,
                            height: max(0, bounds.height - Self.headerHeight - 1))
        grip.frame = NSRect(x: bounds.width - Self.gripSize,
                            y: bounds.height - Self.gripSize,
                            width: Self.gripSize, height: Self.gripSize)
    }

    // MARK: - Remoção

    /// O que o usuário perde ao remover este nó. Cada tipo responde por si —
    /// terminal mata processo, editor não, e o diálogo precisa dizer qual é qual.
    var removalWarning: String {
        "O nó sai do canvas e do sessions.json."
    }

    /// Chamado antes de sair da hierarquia. Solta o que não morre sozinho:
    /// processo de pty, carga de webview, registro em índice global.
    func prepareForRemoval() {}

    /// A sessão foi renomeada. O endereço de dispatch começa com o nome dela,
    /// então quem está registrado em algum índice precisa se re-registrar — sem
    /// derrubar o processo que já está rodando.
    func sessionRenamed(to session: String) {}

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight).fill()
    }

    /// Documento flipped: crescer em altura empurra a borda de baixo, a origem
    /// fica onde está.
    private func resize(by delta: CGSize) {
        setFrameSize(NSSize(
            width: max(Self.minSize.width, (frame.width + delta.width).rounded()),
            height: max(Self.minSize.height, (frame.height + delta.height).rounded())))
        needsLayout = true
        layoutSubtreeIfNeeded()
        onFrameChanging?()
    }

    // Arrastar pelo cabeçalho move o nó no espaço do canvas.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.y <= Self.headerHeight else { return super.mouseDown(with: event) }
        let inDoc = superview!.convert(event.locationInWindow, from: nil)
        dragOffset = CGPoint(x: inDoc.x - frame.minX, y: inDoc.y - frame.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let off = dragOffset, let doc = superview else { return }
        let inDoc = doc.convert(event.locationInWindow, from: nil)
        let desired = NSPoint(x: (inDoc.x - off.x).rounded(), y: (inDoc.y - off.y).rounded())

        // O documento do NSScrollView começa em (0,0), então em vez de barrar o
        // nó na borda o canvas desloca o mundo e abre espaço. `dragOffset` não
        // precisa de correção: o deslocamento entra igualmente no nó e na
        // conversão do cursor, então a diferença entre os dois não muda.
        guard desired.x < 0 || desired.y < 0 else {
            setFrameOrigin(desired)
            onFrameChanging?()
            return
        }

        onRequestSpace?(CGSize(width: max(0, -desired.x), height: max(0, -desired.y)))

        let shifted = doc.convert(event.locationInWindow, from: nil)
        setFrameOrigin(NSPoint(x: max(0, (shifted.x - off.x).rounded()),
                               y: max(0, (shifted.y - off.y).rounded())))
        onFrameChanging?()
    }

    override func mouseUp(with event: NSEvent) {
        guard dragOffset != nil else { return }
        dragOffset = nil
        onFrameChanged?(self)
    }
}

// MARK: - Nó de terminal (processo real, dentro da nossa janela)

/// Terminal com um gancho na saída. `dataReceived` é `open` no SwiftTerm e roda
/// na main queue, então dá para medir silêncio sem corrida com a injeção.
final class MBTerminalView: LocalProcessTerminalView {
    var onOutput: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
    }
}

final class TerminalNode: NodeView {
    let term = MBTerminalView(frame: .zero)
    private(set) var address: String
    private var baseTitle: String
    /// `✦` para terminal com IA, `▸` para shell. Guardado em vez de relido do
    /// rótulo: o rótulo agora carrega estado, e ler o símbolo de volta dele
    /// quebraria assim que o sufixo mudasse.
    private let symbol: String
    private let port = NodePortButton()

    /// `profile == nil` → terminal comum. Com perfil, é um "terminal com IA":
    /// mesma mecânica de pty, o que muda é saber injetar prompt e medir ociosidade.
    init(frame: NSRect, address: String, title: String, cwd: String,
         command: String, profile: AgentProfile?, config: String? = nil,
         prompt: String? = nil) {
        self.address = address
        // O cabeçalho carrega o endereço de dispatch e o que está rodando. Como o
        // id do nó vem do nome do componente, `deck/revisor · Claude Code` já
        // diz o nome, o alvo e o agente numa linha.
        self.baseTitle = title + (profile.map { " · \($0.displayName)" } ?? "")
        self.symbol = profile == nil ? "▸" : "✦"
        super.init(frame: frame,
                   title: "\(self.symbol) \(self.baseTitle)",
                   accent: profile == nil ? .systemTeal : .systemPurple,
                   nodeID: String(address.split(separator: "/").last ?? ""))
        body.addSubview(term)

        // Depois do corpo, para ficar na frente do SwiftTerm — ele consome o
        // mouse inteiro, e uma subview atrás dele nunca receberia o arrasto.
        addSubview(port)
        port.onDrag = { [weak self] point in
            guard let self else { return }
            self.onPortDrag?(self, point)
        }
        port.onRelease = { [weak self] point in
            guard let self else { return }
            self.onPortRelease?(self, point)
        }

        var environment = AppEnvironment.forChildProcess()
        environment["TERM"] = "xterm-256color"
        // O ambiente do perfil por cima do nosso, e a configuração escolhida no
        // nó por cima dele. É aqui que se decide com qual conjunto de plugins,
        // MCP e settings o CLI sobe — herdar o do app não serve: lançado pelo
        // Finder, ele não herdou o shell de ninguém.
        if let profile {
            environment.merge(profile.resolvedEnvironment) { _, novo in novo }
            if let config, let variable = profile.configEnv {
                environment[variable] = config
                Log.write("terminal[\(address)]: \(variable)=\(config)")
            }
        }
        // O gancho do CLI roda num processo filho e precisa saber de qual terminal
        // está falando. O endereço de dispatch é o identificador que o app usa em
        // todo lugar, então é ele que vai.
        //
        // Só em nó com agente: shell não tem conversa para rastrear, e a variável
        // ali seria lixo no ambiente de tudo que você rodar à mão.
        if profile != nil { environment[AgentHooks.targetVariable] = address }

        let env: [String] = environment.map { "\($0.key)=\($0.value)" }

        let line = "cd \(shellQuote(cwd)); clear; \(command)"
        term.startProcess(executable: "/bin/zsh", args: ["-lc", line], environment: env, execName: nil)

        Dispatcher.shared.register(Session(address: address, profile: profile, view: term))

        // O papel do terminal entra na fila em vez de ser escrito no pty agora: a
        // TUI acabou de ser lançada e ainda não tem quem leia stdin. O Dispatcher
        // já espera o `warmupMs` do perfil e o silêncio antes de entregar.
        if let prompt, !prompt.isEmpty, profile != nil {
            Dispatcher.shared.session(address)?.enqueue(prompt)
            Log.write("terminal[\(address)]: papel enfileirado (\(prompt.count) caracteres)")
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { Dispatcher.shared.unregister(address: address) }

    override var supportsEditing: Bool { true }

    override var removalWarning: String {
        "O processo do terminal é encerrado junto — o que estiver rodando nele para."
    }

    override func sessionRenamed(to session: String) {
        let updated = "\(session)/\(nodeID)"
        Dispatcher.shared.rekey(from: address, to: updated)
        address = updated
        baseTitle = updated
        refreshBadge()
    }

    /// Sem matar o pty na mão, o processo filho sobrevive à view e fica órfão
    /// até o app sair.
    override func prepareForRemoval() {
        Dispatcher.shared.unregister(address: address)
        if term.process.running { term.process.terminate() }
    }

    override func layout() {
        super.layout()
        term.frame = body.bounds
        // Encostado na borda direita, na altura da porta de saída que a aresta
        // usa. O card tem `masksToBounds`, então ele não pode sobrar para fora.
        let size = NodePortButton.size
        port.frame = NSRect(x: bounds.maxX - size - 1, y: bounds.midY - size / 2,
                            width: size, height: size)
    }

    /// Escreve no cabeçalho o que está acontecendo: o spinner enquanto roda, o
    /// aviso quando para e espera você, e a fila pendente — prompt disparado
    /// enquanto o agente trabalha fica visível em vez de sumir até alguém
    /// desconfiar.
    ///
    /// Chamado por um timer, então tudo aqui é barato de propósito: nenhuma
    /// leitura de tela, nenhuma alocação além das strings do rótulo.
    func refreshBadge() {
        let session = Dispatcher.shared.session(address)
        let activity = session?.activity ?? .dead
        let pending = session?.pending ?? 0

        var parts: [String] = []
        if let label = activity.label { parts.append(label) }
        if pending > 0 { parts.append("\(pending) na fila") }

        let suffix = parts.isEmpty ? "" : "   •  " + parts.joined(separator: "  •  ")
        let text = "\(symbol) \(baseTitle)\(suffix)"
        // O rótulo só é tocado quando o texto muda de fato: o spinner troca a
        // cada quadro, o resto quase nunca, e reatribuir string igual marca
        // needsDisplay à toa em todos os nós parados.
        if titleLabel.stringValue != text { titleLabel.stringValue = text }

        titleLabel.textColor = activity.color ?? accent
        setAlert(activity.needsAttention)
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}

// MARK: - Nó placeholder (o que ainda não existe, dito na cara)

final class PlaceholderNode: NodeView {
    init(frame: NSRect, title: String, message: String) {
        super.init(frame: frame, title: "◻ \(title)", accent: NSColor.systemGray)
        body.wantsLayer = true
        body.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor

        let label = NSTextField(labelWithString: message)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor(calibratedWhite: 1, alpha: 0.4)
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.tag = 1
        body.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        body.viewWithTag(1)?.frame = NSRect(x: 20, y: body.bounds.midY - 40,
                                            width: body.bounds.width - 40, height: 80)
    }
}

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
    let banner = NSTextField(labelWithString: "")
    let edgeLayer = EdgeLayerView()

    let toolbar = CanvasToolbar()

    /// De qual template esta sessão nasceu. Repassado à barra, que decide se
    /// mostra o botão de atualizar.
    var originTemplate: String? {
        didSet { toolbar.showsUpdateTemplate(originTemplate) }
    }
    private let overlay = ToolOverlay()

    /// Onde soltar um nó novo: retângulo já em coordenadas do documento.
    var onPlace: ((CanvasTool, NSRect) -> Void)?
    /// Nó movido, redimensionado ou criado — hora de gravar o sessions.json.
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
    /// Formulário para montar um terminal do zero.
    var onConfigureTerminal: (() -> Void)?
    /// Componentes salvos, para o menu da ferramenta de terminal.
    var componentNames: (() -> [String])?
    /// Ligação criada ou removida no canvas.
    var onCreateEdge: ((EdgeConfig) -> Void)?
    var onRemoveEdge: ((EdgeConfig) -> Void)?
    /// Clique na pastilha de limite da aresta.
    var onEditEdgeLimit: ((EdgeConfig) -> Void)?

    /// Ligações da sessão. Só terminal liga: editor e web não têm quem receba
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

        // NSScrollView já entrega pan (trackpad) e zoom (pinça) nativos,
        // renderizando as subviews de forma nítida em qualquer magnificação.
        // Atrás dos nós, como no n8n: a curva passa por baixo dos cards e some
        // sob eles em vez de riscar o terminal.
        edgeLayer.frame = doc.bounds
        edgeLayer.frameForNode = { [weak self] id in
            self?.nodes.first { $0.nodeID == id }?.frame
        }
        edgeLayer.onRemove = { [weak self] edge in self?.onRemoveEdge?(edge) }
        edgeLayer.onEditLimit = { [weak self] edge in self?.onEditEdgeLimit?(edge) }
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

        banner.font = .systemFont(ofSize: 12, weight: .medium)
        banner.textColor = .black
        banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor.systemOrange.cgColor
        banner.layer?.cornerRadius = 6
        banner.alignment = .center
        banner.isHidden = true
        addSubview(banner)

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
        toolbar.componentNames = { [weak self] in self?.componentNames?() ?? [] }
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
        addSubview(toolbar)

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

    /// Um monitor local vale para o app todo, e existe um canvas por sessão.
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
            edgeLayer.setHovered(edgeLayer.edge(near: inDoc))
            return event

        case .scrollWheel:
            // ⌘+scroll: zoom ancorado no cursor, como no Figma.
            guard event.modifierFlags.contains(.command), isOverCanvas(event) else { return event }
            zoomAtCursor(event)
            return nil

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
        return bounds.contains(point) && !toolbar.frame.contains(point)
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
            if current === toolbar { return false }
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

        // Exponencial: o passo é proporcional ao zoom atual, então a sensação é
        // a mesma em 0.3x e em 2x. Sinal negativo para casar com o Figma —
        // deslizar para cima aproxima.
        applyZoom(scroll.magnification * pow(1.0025, -delta),
                  keeping: event.locationInWindow)
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        overlay.frame = bounds
        banner.frame = NSRect(x: bounds.midX - 380, y: bounds.maxY - 52, width: 760, height: 30)

        let size = toolbar.fittingSize
        toolbar.frame = NSRect(x: (bounds.width - size.width) / 2,
                               y: bounds.minY + 24,
                               width: size.width, height: size.height)
    }

    func showBanner(_ text: String?) {
        guard let text else { banner.isHidden = true; return }
        banner.stringValue = text
        banner.isHidden = false
    }

    /// Pan e zoom passam os dois por aqui: o bounds do clip view muda nos dois
    /// casos, inclusive na pinça do trackpad.
    @objc private func viewMoved() { toolbar.showZoom(scroll.magnification) }

    // MARK: - Zoom

    /// Zoom que deixa um ponto da tela parado no lugar.
    ///
    /// `setMagnification(_:centeredAt:)` seria o caminho óbvio, mas ele espera o
    /// ponto no sistema do content view e na prática desloca o conteúdo para o
    /// centro — era isso que fazia todo zoom "saltar para o meio da janela".
    /// Medir o ponto antes e depois da troca de escala, e corrigir o offset pela
    /// diferença, é o que de fato ancora.
    private func applyZoom(_ value: CGFloat, keeping windowPoint: NSPoint) {
        let clamped = min(max(value, scroll.minMagnification), scroll.maxMagnification)
        guard abs(clamped - scroll.magnification) > 0.0001 else { return }

        // Crescer antes: em zoom out o viewport passa a cobrir mais unidades do
        // que o documento tem, e o scroll seria clampeado — o que sozinho já
        // desloca a vista.
        growDocumentIfNeeded(forMagnification: clamped)

        let magBefore = scroll.magnification
        let originBefore = scroll.contentView.bounds.origin
        let before = doc.convert(windowPoint, from: nil)
        scroll.magnification = clamped
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
        // Sem forçar o layout, o terminal nasce com frame zero e só descobre o
        // tamanho real na primeira interação — até lá o pty roda numa tela de
        // dimensão degenerada e o buffer sai vazio.
        node.layoutSubtreeIfNeeded()
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
                  !self.edges.contains(EdgeConfig(from: node.nodeID, to: target.nodeID))
            else { return }
            self.onCreateEdge?(EdgeConfig(from: node.nodeID, to: target.nodeID))
        }
        node.onRequestClose = { [weak self] node in self?.onRequestClose?(node) }
        node.onRequestSpace = { [weak self] shift in self?.makeSpace(shift) }
        node.onRequestEdit = { [weak self] node in self?.onRequestEditNode?(node) }
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

        guard size.width > doc.frame.width || size.height > doc.frame.height else { return }
        doc.setFrameSize(NSSize(width: max(size.width, doc.frame.width),
                                height: max(size.height, doc.frame.height)))
        doc.needsDisplay = true
        syncEdgeLayer()
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
        var origin = NSPoint(x: visible.minX + 40, y: visible.minY + 40)
        // Empilha em diagonal enquanto o lugar estiver ocupado, senão nós novos
        // nascem exatamente em cima uns dos outros.
        while nodes.contains(where: { abs($0.frame.minX - origin.x) < 8 && abs($0.frame.minY - origin.y) < 8 }) {
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

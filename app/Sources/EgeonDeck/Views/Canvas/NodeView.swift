import AppKit
import WebKit

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
    /// Duas linhas: nome em cima, caminho embaixo. O cabeçalho de uma linha só
    /// cabia o endereço inteiro em 11pt e nada mais — para saber em que pasta o
    /// terminal abriu era preciso rodar `pwd` nele.
    static let headerHeight: CGFloat = 46
    static let minSize = NSSize(width: 280, height: 180)
    static let gripSize: CGFloat = 16

    /// `id` dentro da bancada. Vazio nos nós que não vivem no
    /// workbenches.json (placeholder, portal) — a persistência os ignora.
    let nodeID: String

    /// Cor do tipo do nó. Guardada porque o alerta troca a borda e precisa
    /// saber para o que voltar.
    let accent: NSColor

    let titleLabel = NSTextField(labelWithString: "")
    /// Segunda linha: a pasta em que o nó abriu, ou o endereço da página.
    let subtitleLabel = NSTextField(labelWithString: "")
    /// Canto direito da primeira linha: o que está acontecendo agora — spinner,
    /// aviso, fila. Fora do título porque o título é identidade e não muda; isto
    /// pisca a cada quadro.
    let statusLabel = NSTextField(labelWithString: "")
    let body = NSView()
    private let grip = NodeResizeGrip()
    private let closeButton = ToolbarButton(symbols: ["xmark"], tooltip: "Remover nó", size: 30)
    // Lápis, e não os controles deslizantes: o botão edita o nó, e ninguém lê
    // `slider.horizontal.3` como "editar" — lia como "ajustes de mixagem".
    private let editButton = ToolbarButton(symbols: ["square.and.pencil", "pencil"],
                                           tooltip: "Configurar este nó", size: 30)
    /// Levar só este terminal para uma worktree. Estava no menu do botão direito, e
    /// menu de contexto é onde funcionalidade vai morrer: quem não sabe que existe
    /// não clica com o direito para descobrir.
    private let worktreeButton = ToolbarButton(symbols: ["arrow.triangle.branch"],
                                               tooltip: "Nova worktree para este terminal…",
                                               size: 30)

    /// A pasta em que este nó abriu, já encurtada para `~`.
    var subtitle: String {
        get { subtitleLabel.stringValue }
        set {
            guard subtitleLabel.stringValue != newValue else { return }
            subtitleLabel.stringValue = newValue
            subtitleLabel.toolTip = newValue
        }
    }

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

    /// "Leve este terminal para uma worktree nova."
    ///
    /// Por nó, e não só por bancada: uma frente de trabalho costuma ser dois
    /// repositórios, e levar o card do backend para a branch nova não deveria
    /// exigir duplicar a bancada inteira.
    var onRequestWorktree: ((NodeView) -> Void)?

    /// Arrasto pelo cabeçalho quando o card NÃO manda na própria posição — isto é,
    /// no mosaico. Em coordenadas de janela; quem resolve sobre qual painel o
    /// cursor está é o container, que é quem conhece o arranjo.
    var onHeaderDrag: ((NodeView, NSPoint) -> Void)?
    var onHeaderRelease: ((NodeView, NSPoint) -> Void)?

    /// Arrasto saindo do `+` deste nó, em coordenadas de janela. Quem converte
    /// para o documento e resolve o destino é o canvas.
    var onPortDrag: ((NodeView, NSPoint) -> Void)?
    var onPortRelease: ((NodeView, NSPoint) -> Void)?

    private var dragOffset: CGPoint?
    /// Arrasto de troca em curso (mosaico).
    private var swapping = false

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

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = accent
        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Caminho trunca no MEIO: o começo diz o projeto e o fim diz a pasta, e
        // são as duas pontas que identificam onde o terminal está. Cortar o fim
        // deixaria três cards com o mesmo texto visível.
        subtitleLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.58, alpha: 1)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitleLabel)

        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingHead
        addSubview(statusLabel)

        addSubview(body)
        addSubview(grip)
        addSubview(worktreeButton)
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
        worktreeButton.onClick = { [weak self] in
            guard let self else { return }
            self.onRequestWorktree?(self)
        }
        // Só nós que têm o que configurar. O editor não tem comando nem papel; o
        // que ele abre vem da pasta da bancada.
        editButton.isHidden = !supportsEditing
        // Só quem abre pasta pode ganhar worktree. O nó web não abre nenhuma.
        worktreeButton.isHidden = !supportsWorktree
    }

    /// Nó com configuração editável (comando, agente, pasta, papel).
    var supportsEditing: Bool { false }

    /// Nó que abre uma pasta, e portanto pode ganhar worktree própria. O nó `web`
    /// não abre pasta nenhuma.
    var supportsWorktree: Bool { false }

    /// Botão direito no cabeçalho: o que dá para fazer com este card.
    ///
    /// Só no cabeçalho: o corpo é do SwiftTerm e do WKWebView, cada um com o menu
    /// de contexto dele — roubá-lo tiraria o "colar" do terminal e o "inspecionar"
    /// do editor.
    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard local.y <= Self.headerHeight, supportsEditing || supportsWorktree else {
            return super.rightMouseDown(with: event)
        }

        let menu = NSMenu()
        if supportsEditing {
            menu.addItem(withTitle: "Configurar \(nodeID)…",
                         action: #selector(menuConfigure), keyEquivalent: "")
        }
        if supportsWorktree {
            menu.addItem(withTitle: "Nova worktree para este terminal…",
                         action: #selector(menuWorktree), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remover \(nodeID)…",
                     action: #selector(menuClose), keyEquivalent: "")
        menu.items.forEach { if $0.action != nil { $0.target = self } }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func menuConfigure() { onRequestEdit?(self) }
    @objc private func menuWorktree() { onRequestWorktree?(self) }
    @objc private func menuClose() { onRequestClose?(self) }

    /// O card manda na própria posição?
    ///
    /// No canvas sim. No mosaico não: quem dá o frame é o split view, e arrastar o
    /// cabeçalho lá chamaria `onRequestSpace` — que desloca o mundo do canvas e
    /// regrava o `workbenches.json` com coordenadas que não são de lá. A alça de
    /// resize e a porta de aresta desaparecem pelo mesmo motivo: brigariam com o
    /// divisor no quadro seguinte.
    var isFreeform = true {
        didSet {
            guard isFreeform != oldValue else { return }
            grip.isHidden = !isFreeform
            freeformDidChange()
        }
    }

    /// Gancho para a subclasse esconder o que só serve no canvas.
    func freeformDidChange() {}

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

    // MARK: - Rasterização

    private var appliedContentsScale: CGFloat = 0

    /// Rasteriza o card na resolução em que ele de fato aparece.
    ///
    /// `NSScrollView.magnification` é escala no layer, e layer rasteriza no
    /// `contentsScale` dele — que ninguém atualiza. O card era desenhado na
    /// escala da tela e esticado pela GPU: em 112% numa tela 1x, todo glifo
    /// passava por filtro bilinear e o canvas inteiro ficava embaçado.
    ///
    /// Quem chama é o canvas, a cada troca de zoom e de tela.
    func applyContentsScale(_ scale: CGFloat) {
        guard abs(scale - appliedContentsScale) > 0.001 else { return }
        appliedContentsScale = scale
        NodeView.rasterize(self, at: scale)
    }

    private static func rasterize(_ view: NSView, at scale: CGFloat) {
        // O WKWebView rasteriza num processo e num layer que não são nossos, e
        // pelo deviceScaleFactor da página — `contentsScale` no layer de cá não
        // muda nada. Quem manda nele é o override abaixo.
        if let web = view as? WKWebView {
            overrideDeviceScale(web, at: scale)
            return
        }
        if let layer = view.layer {
            rasterize(layer, at: scale)
            view.needsDisplay = true
        }
        view.subviews.forEach { rasterize($0, at: scale) }
    }

    /// Diz à página em quantos pixels por ponto ela está sendo mostrada.
    ///
    /// É o mesmo que o WebKit faz ao arrastar uma janela para o Retina; a
    /// diferença é que o zoom do canvas ele não enxerga, porque a magnificação
    /// mora num scroll view que não é dele. Sem isto o code-server desenha em 1x
    /// e chega esticado — resolvido o terminal, o editor era o que sobrava
    /// embaçado.
    ///
    /// API privada, então o `responds(to:)` não é decoração: sem ele, uma
    /// versão de WebKit que largue o seletor derruba o app. Perder a nitidez do
    /// editor é o pior que pode acontecer aqui.
    private static func overrideDeviceScale(_ web: WKWebView, at scale: CGFloat) {
        let selector = Selector(("_setOverrideDeviceScaleFactor:"))
        guard web.responds(to: selector), let imp = web.method(for: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        unsafeBitCast(imp, to: Setter.self)(web, selector, scale)
    }

    /// Sublayer não herda `contentsScale` do pai — cada um guarda o seu.
    private static func rasterize(_ layer: CALayer, at scale: CGFloat) {
        if layer.contentsScale != scale {
            layer.contentsScale = scale
            layer.setNeedsDisplay()
        }
        layer.sublayers?.forEach { rasterize($0, at: scale) }
    }

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
        // Uma linha: à esquerda a coluna do texto (título em cima, pasta embaixo),
        // à direita a linha dos botões, centrada na altura do cabeçalho inteiro.
        let botão: CGFloat = 30
        let margem: CGFloat = 12
        let entreBotões: CGFloat = 6
        let meio = (Self.headerHeight - botão) / 2

        // Da direita para a esquerda, e só os visíveis: nó sem worktree e sem
        // configuração fica com o X encostado na borda, sem buraco no meio.
        var x = bounds.width - margem
        var controles: CGFloat = 0
        for botãoDaVez in [closeButton, editButton, worktreeButton] where !botãoDaVez.isHidden {
            x -= botão
            botãoDaVez.frame = NSRect(x: x, y: meio, width: botão, height: botão)
            x -= entreBotões
            controles += botão + entreBotões
        }

        let disponível = max(0, bounds.width - margem * 2 - controles - 8)
        // Título toma o que precisa; o estado fica com o resto da linha. Assim
        // "front" não perde letra para caber "trabalhando · 2 na fila".
        //
        // Medido pela CÉLULA do rótulo. As duas alternativas erram:
        // `intrinsicContentSize` depende do frame atual, e como é esta linha que
        // define o frame, cada passada encolhia sobre a anterior; medir a string
        // com a fonte declarada erra por pouco, porque o `✦` do símbolo cai numa
        // fonte de fallback mais larga do que a que se mediu. Nos dois casos o
        // título virava "clau…" com 1300px de sobra na linha.
        titleLabel.sizeToFit()
        let larguraTítulo = min(disponível * 0.62, titleLabel.frame.width + 2)
        titleLabel.frame = NSRect(x: margem, y: 7,
                                  width: max(0, larguraTítulo), height: 18)
        // O estado acompanha a linha do título, e não o meio: ele fala do que o
        // agente está fazendo agora, que é o assunto do título.
        statusLabel.frame = NSRect(x: margem + larguraTítulo + 8, y: 10,
                                   width: max(0, disponível - larguraTítulo - 8), height: 13)
        subtitleLabel.frame = NSRect(x: margem, y: 29,
                                     width: max(0, bounds.width - margem * 2), height: 13)

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
        "O nó sai do canvas e do workbenches.json."
    }

    /// Chamado antes de sair da hierarquia. Solta o que não morre sozinho:
    /// processo de pty, carga de webview, registro em índice global.
    func prepareForRemoval() {}

    /// A bancada foi renomeada. O endereço de dispatch começa com o nome dela,
    /// então quem está registrado em algum índice precisa se re-registrar — sem
    /// derrubar o processo que já está rodando.
    func workbenchRenamed(to workbench: String) {}

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

    // Arrastar pelo cabeçalho move o nó no espaço do canvas. No mosaico, onde
    // quem dá o frame é o split view, o mesmo gesto troca este card de lugar com
    // aquele sob o cursor.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.y <= Self.headerHeight else { return super.mouseDown(with: event) }

        guard isFreeform else {
            swapping = true
            return
        }
        let inDoc = superview!.convert(event.locationInWindow, from: nil)
        dragOffset = CGPoint(x: inDoc.x - frame.minX, y: inDoc.y - frame.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        if swapping {
            onHeaderDrag?(self, event.locationInWindow)
            return
        }
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
        if swapping {
            swapping = false
            onHeaderRelease?(self, event.locationInWindow)
            return
        }
        guard dragOffset != nil else { return }
        dragOffset = nil
        onFrameChanged?(self)
    }
}


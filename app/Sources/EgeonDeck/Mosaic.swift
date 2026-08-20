import AppKit

/// De que jeito você está olhando a bancada.
///
/// Nos dois modos que desenham cards não são duas cópias do nó: o card é o MESMO
/// `NodeView`, e o que muda é quem lhe dá o frame. Tirar uma view de um pai e pôr
/// em outro não toca no processo — o pty segue ligado ao SwiftTerm e o WKWebView
/// não recarrega — e é isso que permite trocar de modo com cinco agentes
/// trabalhando. O chat não desenha card nenhum, mas também não os desmonta: o
/// canvas continua no lugar, coberto — nó fora da hierarquia não recebe layout, e
/// sem layout o pty nasce com zero colunas.
enum ViewMode: String, Codable {
    /// Bancada livre: posição, tamanho, zoom e arestas.
    case canvas
    /// A janela inteira dividida entre os nós, sem sobreposição e sem zoom.
    case mosaic
    /// A bancada como conversa: os transcripts dos agentes num thread só.
    case chat

    /// Os modos na ordem em que aparecem na barra e nas teclas ⌥⌘1..3.
    static let all: [ViewMode] = [.canvas, .mosaic, .chat]

    var label: String {
        switch self {
        case .canvas: return "Canvas"
        case .mosaic: return "Mosaico"
        case .chat:   return "Chat"
        }
    }

    var symbols: [String] {
        switch self {
        case .canvas: return ["square.on.square.dashed", "rectangle.dashed", "square.dashed"]
        case .mosaic: return ["rectangle.split.2x1", "square.split.2x1", "sidebar.right"]
        case .chat:   return ["bubble.left.and.bubble.right", "bubble.left", "message"]
        }
    }

    var tooltip: String {
        switch self {
        case .canvas: return "Canvas — nós soltos, com zoom e ligações (⌥⌘1)"
        case .mosaic: return "Mosaico — os mesmos nós dividindo a janela (⌥⌘2)"
        case .chat:   return "Chat — a bancada como conversa, sem os cards (⌥⌘3)"
        }
    }
}

/// As proporções que você arrastou no mosaico.
///
/// Fração e não ponto: a janela muda de tamanho entre um arranque e outro, e
/// posição de divisor em pontos reabriria o mosaico torto.
///
/// Aplicada só quando a contagem casa com o que está na tela. Nó criado ou
/// removido invalida a proporção salva, e aplicar uma lista de tamanho errado
/// entortaria o layout em vez de deixá-lo dividir igual.
struct MosaicLayout: Codable, Equatable {
    /// Largura de cada coluna, na ordem em que o mosaico as monta.
    var columns: [Double]?
    /// Altura de cada linha, coluna por coluna.
    var rows: [[Double]]?
    /// Quem está em qual painel: ids de nó, por coluna.
    ///
    /// Existe porque o arranjo deixou de ser derivado do tipo do nó. Derivado, não
    /// havia como trocar dois cards de lugar — a única ordem possível era
    /// editores, terminais, web, e dentro da coluna a do `workbenches.json`. Nulo, ou
    /// com id que não está mais na bancada, cai de volta na regra de tipo, que
    /// continua sendo o arranjo de quem nunca arrastou nada.
    var slots: [[String]]?
}

// MARK: - Split view com divisor arrastável e mínimo por painel

/// `NSSplitView` com a cara do app e um mínimo por painel.
///
/// O mínimo não é enfeite: um workbench de code-server abaixo de ~500pt vira uma
/// coluna de ícones, e um terminal de 40pt de altura não mostra nem o prompt.
final class MosaicSplit: NSSplitView, NSSplitViewDelegate {
    /// Mínimo de cada painel, na mesma ordem dos subviews. O que faltar cai no
    /// `fallbackMinimum`.
    var minimums: [CGFloat] = []
    var fallbackMinimum: CGFloat = 120

    /// Os painéis mudaram de tamanho — por arrasto seu ou por resize da janela.
    var onResized: (() -> Void)?

    init(vertical: Bool) {
        super.init(frame: .zero)
        isVertical = vertical
        dividerStyle = .thin
        delegate = self
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var dividerColor: NSColor { NSColor(calibratedWhite: 1, alpha: 0.07) }

    /// Mais grosso que o `.thin` desenha: a espessura também é a área de agarre,
    /// e 1pt de alvo é inclicável. Lê como espaço entre os cards.
    override var dividerThickness: CGFloat { 8 }

    // MARK: Eixo

    /// Tamanho do painel no eixo em que este split divide.
    private func extent(_ frame: NSRect) -> CGFloat { isVertical ? frame.width : frame.height }

    /// Onde o painel começa, na mesma escala que `setPosition(_:ofDividerAt:)`
    /// usa.
    ///
    /// `NSSplitView` horizontal conta de cima para baixo, e a resposta depende de
    /// ele estar flipped — coisa que a AppKit não promete entre versões. Derivar
    /// do próprio `isFlipped` é o que mantém min/max e `setPosition` no mesmo
    /// sistema.
    private func offset(_ frame: NSRect) -> CGFloat {
        if isVertical { return frame.minX }
        return isFlipped ? frame.minY : bounds.height - frame.maxY
    }

    private var span: CGFloat { isVertical ? bounds.width : bounds.height }

    private func minimum(at index: Int) -> CGFloat {
        index < minimums.count ? minimums[index] : fallbackMinimum
    }

    // MARK: Proporções

    /// Quanto do eixo cada painel ocupa agora. Soma 1.
    var fractions: [Double] {
        let sizes = subviews.map { extent($0.frame) }
        let total = sizes.reduce(0, +)
        guard total > 0 else { return [] }
        return sizes.map { Double($0 / total) }
    }

    /// Distribui os painéis pelas frações dadas, escrevendo frame por frame.
    ///
    /// Na mão, e não por `setPosition` ou `adjustSubviews`: o painel de uma coluna
    /// nasce com frame zero, e a distribuição proporcional da AppKit parte do
    /// tamanho anterior — de zero não sai proporção nenhuma. O resultado medido
    /// era a coluna do editor com **0pt de largura** e a dos terminais no mínimo,
    /// com 1350pt de janela sobrando vazios.
    ///
    /// Lista de tamanho diferente do número de painéis divide igual em vez de
    /// entortar: é o caso da proporção salva com quatro terminais reaberta com
    /// três.
    func spread(fractions: [Double]) {
        let count = subviews.count
        guard count > 0, span > 0 else { return }

        let usable = max(0, span - dividerThickness * CGFloat(count - 1))
        let shares = fractions.count == count
            ? fractions
            : Array(repeating: 1 / Double(count), count: count)

        var position: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            // O último fecha a conta: fração arredondada deixa sobra de 1pt, e ela
            // apareceria como uma tira do fundo na borda da janela.
            let size = index == count - 1
                ? max(0, span - position)
                : (usable * CGFloat(shares[index])).rounded()
            view.frame = frame(at: position, size: size)
            position += size + dividerThickness
        }
        needsDisplay = true
    }

    /// O retângulo de um painel que começa em `position` e mede `size` no eixo.
    ///
    /// O ramo não-flipped não é hipótese: sem ele o painel 0 de um split
    /// horizontal iria para BAIXO, e a ordem do `workbenches.json` apareceria de
    /// cabeça para baixo na tela.
    private func frame(at position: CGFloat, size: CGFloat) -> NSRect {
        if isVertical {
            return NSRect(x: position, y: 0, width: size, height: bounds.height)
        }
        let y = isFlipped ? position : bounds.height - position - size
        return NSRect(x: 0, y: y, width: bounds.width, height: size)
    }

    // MARK: NSSplitViewDelegate

    /// O divisor não pode passar do mínimo do painel que vem antes dele.
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex < subviews.count else { return proposedMinimumPosition }
        return offset(subviews[dividerIndex].frame) + minimum(at: dividerIndex)
    }

    /// Nem invadir o mínimo do painel que vem depois.
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        let next = dividerIndex + 1
        guard next < subviews.count else { return proposedMaximumPosition }
        let frame = subviews[next].frame
        return offset(frame) + extent(frame) - minimum(at: next) - dividerThickness
    }

    /// Alvo de arrasto maior do que a linha desenhada.
    ///
    /// O divisor desenha 8pt para ler como espaço entre os cards; a mão erra isso.
    /// A área efetiva sai 6pt para cada lado, então o cursor de resize aparece
    /// antes de você acertar o fio — e o corpo do card não perde nada, porque
    /// esses 6pt são de margem.
    func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
                   forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        isVertical ? drawnRect.insetBy(dx: -6, dy: 0) : drawnRect.insetBy(dx: 0, dy: -6)
    }

    /// Painel sumido não é o que se quer aqui: o card guarda um processo vivo, e
    /// colapsá-lo por arrasto o esconderia sem dizer para onde foi.
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    func splitViewDidResizeSubviews(_ notification: Notification) { onResized?() }
}

/// Moldura que marca o painel que vai receber o card arrastado.
///
/// Só desenho, e sem receber mouse: ela vive por cima dos cards durante o gesto, e
/// engolir o clique faria o próprio arrasto parar no meio.
final class MosaicDropHint: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.systemTeal.cgColor
        layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.12).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Mosaico

/// A bancada dividindo a janela: colunas por tipo de nó, cada coluna empilhada.
///
/// A ordem é fixa — editores, terminais, web — e dentro da coluna é a do
/// `workbenches.json`. Reordenar é editar o arquivo, que é como todo o resto da
/// configuração do app funciona. Coluna sem nó não aparece.
final class MosaicContainer: NSView {
    /// Sobra em volta, para o card não nascer encostado na borda da janela.
    private static let margin: CGFloat = 10

    /// Larguras mínimas por coluna. O editor é o que sofre: o code-server abaixo
    /// disso perde o explorer e sobra a activity bar.
    private static let minimumWidths: [CGFloat] = [520, 320, 360]
    private static let minimumRowHeight: CGFloat = 120

    /// Teto da rasterização, igual ao do canvas: acima disso o backing store
    /// cresce com o quadrado da escala sem ninguém ver diferença.
    private static let maxContentsScale: CGFloat = 3

    var onRequestClose: ((NodeView) -> Void)?
    var onRequestEditNode: ((NodeView) -> Void)?
    var onRequestNodeWorktree: ((NodeView) -> Void)?
    /// Divisor arrastado — hora de gravar as proporções.
    var onLayoutChanged: ((MosaicLayout) -> Void)?

    /// Proporções a reproduzir na próxima montagem. Nulo divide igual.
    var layoutRatios: MosaicLayout? {
        didSet {
            // O eco do próprio `publish` é ignorado: quem grava devolve o valor
            // para cá, e remontar por causa disso desfaria o arrasto no quadro
            // seguinte.
            guard layoutRatios != oldValue, layoutRatios != lastPublished else { return }
            let arranjoNovo = layoutRatios?.slots
            hasAppliedRatios = false
            // Arranjo diferente exige remontar as colunas; proporção diferente é só
            // redistribuir o que já está montado.
            if arranjoNovo != arrangement {
                arrangement = arranjoNovo
                rebuild()
            } else {
                needsLayout = true
            }
        }
    }

    private let columns = MosaicSplit(vertical: true)
    private var rows: [MosaicSplit] = []
    private var nodes: [NodeView] = []

    /// Quem está em qual painel, por id. Nulo é "nunca arrastei nada" — aí vale a
    /// regra de tipo.
    private var arrangement: [[String]]?

    /// Moldura sobre o painel que vai receber o card arrastado. Sem ela o gesto é
    /// cego: você solta e descobre depois com quem trocou.
    private let dropHint = MosaicDropHint()

    /// As frações salvas já foram reproduzidas nesta montagem?
    ///
    /// Uma vez só: depois disso quem manda são os divisores que você arrastou, e
    /// reaplicar a cada `layout()` desfaria o arrasto no quadro seguinte.
    private var hasAppliedRatios = false
    private var lastPublished: MosaicLayout?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).cgColor

        columns.minimums = Self.minimumWidths
        columns.fallbackMinimum = 320
        columns.onResized = { [weak self] in self?.publish() }
        addSubview(columns)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Montagem

    /// Recebe os nós da bancada e remonta as colunas.
    func arrange(_ list: [NodeView]) {
        nodes = list
        rebuild()
    }

    private func rebuild() {
        for row in rows { row.subviews.forEach { $0.removeFromSuperview() } }
        columns.subviews.forEach { $0.removeFromSuperview() }
        rows = []

        var widths: [CGFloat] = []
        for group in grouped() {
            let row = MosaicSplit(vertical: false)
            row.fallbackMinimum = Self.minimumRowHeight
            row.onResized = { [weak self] in self?.publish() }
            for node in group {
                adopt(node)
                row.addSubview(node)
            }
            rows.append(row)
            columns.addSubview(row)
            // O maior mínimo da coluna, e não o do primeiro: depois de uma troca,
            // o editor pode ser o segundo card da coluna, e o mínimo dele é o que
            // manda — abaixo de 520pt o workbench perde o explorer.
            widths.append(group.map { Self.minimumWidths[Self.column(of: $0)] }.max() ?? 320)
        }
        columns.minimums = widths

        hasAppliedRatios = false
        lastPublished = nil
        needsLayout = true
    }

    /// Os nós por coluna, na ordem em que as colunas aparecem.
    ///
    /// O arranjo que você arrastou tem prioridade; o que ele não cobrir entra pela
    /// regra de tipo. Cobrir parcialmente é o caso normal, não exceção: você cria
    /// um terminal depois de já ter arrumado a tela, e ele precisa aparecer em
    /// algum lugar sem desfazer o resto.
    private func grouped() -> [[NodeView]] {
        guard let arranged = arrangement else { return Self.byType(nodes) }

        let porID = Dictionary(nodes.map { ($0.nodeID, $0) }) { primeiro, _ in primeiro }
        var usados = Set<String>()
        var colunas: [[NodeView]] = []
        for coluna in arranged {
            let grupo = coluna.compactMap { id -> NodeView? in
                guard let node = porID[id], !usados.contains(id) else { return nil }
                usados.insert(id)
                return node
            }
            // Coluna que ficou vazia desaparece: nó removido não deixa vão.
            if !grupo.isEmpty { colunas.append(grupo) }
        }

        let novos = nodes.filter { !usados.contains($0.nodeID) }
        guard !novos.isEmpty else { return colunas }
        guard !colunas.isEmpty else { return Self.byType(novos) }

        // Nó novo procura a coluna de quem é do mesmo tipo; sem ela, abre coluna
        // própria na ponta.
        for node in novos {
            if let alvo = colunas.firstIndex(where: {
                Self.column(of: $0[0]) == Self.column(of: node)
            }) {
                colunas[alvo].append(node)
            } else {
                colunas.append([node])
            }
        }
        return colunas
    }

    /// O arranjo de quem nunca arrastou nada: editores, terminais, web — e dentro
    /// da coluna, a ordem do `workbenches.json`.
    private static func byType(_ list: [NodeView]) -> [[NodeView]] {
        var byColumn: [Int: [NodeView]] = [:]
        for node in list { byColumn[column(of: node), default: []].append(node) }
        return byColumn.keys.sorted().compactMap { byColumn[$0] }
    }

    /// Editor à esquerda porque é quem precisa de largura; web na ponta porque é
    /// quem menos precisa de olho em cima.
    private static func column(of node: NodeView) -> Int {
        if node is EditorNode { return 0 }
        if node is WebNode { return 2 }
        return 1
    }

    /// Prepara o card para viver num layout que não é o dele.
    ///
    /// Desligar os ganchos de geometria não é zelo: `onRequestSpace` desloca o
    /// mundo do canvas e `onFrameChanged` grava a posição no `workbenches.json` —
    /// aqui o frame vem do split view, e deixá-los ligados regravaria a montagem
    /// do canvas com as coordenadas do mosaico.
    private func adopt(_ node: NodeView) {
        node.isFreeform = false
        node.onFrameChanged = nil
        node.onFrameChanging = nil
        node.onRequestSpace = nil
        node.onPortDrag = nil
        node.onPortRelease = nil
        node.onRequestClose = { [weak self] node in self?.onRequestClose?(node) }
        node.onRequestEdit = { [weak self] node in self?.onRequestEditNode?(node) }
        node.onRequestWorktree = { [weak self] node in self?.onRequestNodeWorktree?(node) }
        node.onHeaderDrag = { [weak self] node, point in self?.dragging(node, to: point) }
        node.onHeaderRelease = { [weak self] node, point in self?.drop(node, at: point) }
        node.applyContentsScale(contentsScale)
    }

    // MARK: Trocar de lugar

    /// O card sob um ponto da janela, tirando o que está sendo arrastado.
    private func node(under point: NSPoint, excluding dragged: NodeView) -> NodeView? {
        let local = convert(point, from: nil)
        return nodes.first { node in
            node !== dragged && node.superview != nil
                && convert(node.bounds, from: node).contains(local)
        }
    }

    private func dragging(_ node: NodeView, to point: NSPoint) {
        guard let alvo = self.node(under: point, excluding: node) else {
            dropHint.removeFromSuperview()
            return
        }
        if dropHint.superview == nil { addSubview(dropHint, positioned: .above, relativeTo: nil) }
        dropHint.frame = convert(alvo.bounds, from: alvo)
    }

    private func drop(_ node: NodeView, at point: NSPoint) {
        dropHint.removeFromSuperview()
        guard let alvo = self.node(under: point, excluding: node) else { return }
        swap(node.nodeID, alvo.nodeID)
    }

    /// Troca dois cards de painel, por id.
    ///
    /// Troca, e não inserção: os dois cards existem e os dois painéis existem, então
    /// trocar preserva a contagem de painéis por coluna — e com ela as proporções
    /// que você já arrastou. Inserir mudaria o número de linhas de duas colunas ao
    /// mesmo tempo e jogaria fora os dois conjuntos de frações.
    @discardableResult
    func swap(_ primeiro: String, _ segundo: String) -> Bool {
        var arranjo = arrangement ?? Self.byType(nodes).map { $0.map(\.nodeID) }
        guard primeiro != segundo,
              let de = Self.position(of: primeiro, in: arranjo),
              let para = Self.position(of: segundo, in: arranjo) else { return false }

        arranjo[de.coluna][de.linha] = segundo
        arranjo[para.coluna][para.linha] = primeiro
        arrangement = arranjo
        rebuild()
        Log.write("mosaico: \"\(primeiro)\" e \"\(segundo)\" trocaram de lugar")

        // Publicar depois de aplicar as proporções, senão `publish` sai sem
        // frações — ele desiste enquanto o layout não rodou.
        DispatchQueue.main.async { [weak self] in
            self?.layoutSubtreeIfNeeded()
            self?.publish()
        }
        return true
    }

    private static func position(of id: String,
                                 in arranjo: [[String]]) -> (coluna: Int, linha: Int)? {
        for (coluna, lista) in arranjo.enumerated() {
            if let linha = lista.firstIndex(of: id) { return (coluna, linha) }
        }
        return nil
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        columns.frame = bounds.insetBy(dx: Self.margin, dy: Self.margin)

        guard !hasAppliedRatios, columns.bounds.width > 0, columns.bounds.height > 0,
              !rows.isEmpty else { return }
        hasAppliedRatios = true
        applyRatios()
    }

    private func applyRatios() {
        let saved = layoutRatios
        columns.spread(fractions: Self.usable(saved?.columns, count: rows.count)
                       ?? defaultColumnFractions())

        // Depois das colunas: a linha só sabe distribuir os cards quando já tem a
        // própria largura, e é o `spread` acima que a dá.
        for (index, row) in rows.enumerated() {
            let heights = saved?.rows
            let mine = heights?.indices.contains(index) == true ? heights?[index] : nil
            row.spread(fractions: Self.usable(mine, count: row.subviews.count) ?? [])
        }
    }

    /// Proporção salva que dá para usar, ou nada.
    ///
    /// Recusa fração degenerada. O arrasto não consegue produzir uma — o mínimo
    /// por painel barra antes —, mas o `workbenches.json` é feito para ser editado à
    /// mão, e um zero ali esconde um card sem dizer para onde ele foi. Foi
    /// exatamente esse o estrago de uma versão anterior deste arquivo: gravou
    /// `columns: [0, 1]` e escondia o editor a cada arranque.
    private static func usable(_ fractions: [Double]?, count: Int) -> [Double]? {
        guard let fractions, fractions.count == count,
              fractions.allSatisfy({ $0 > 0.02 }) else { return nil }
        return fractions
    }

    /// Sem proporção salva, a coluna do editor nasce com a mesma fatia do layout
    /// automático do canvas — quem já usou o app reconhece o arranjo.
    private func defaultColumnFractions() -> [Double] {
        guard rows.count > 1, let first = grouped().first, Self.column(of: first[0]) == 0
        else { return [] }
        let rest = (1 - 0.62) / Double(rows.count - 1)
        return [0.62] + Array(repeating: rest, count: rows.count - 1)
    }

    private func publish() {
        guard hasAppliedRatios, columns.bounds.width > 0 else { return }
        let layout = MosaicLayout(columns: columns.fractions,
                                  rows: rows.map { $0.fractions },
                                  slots: grouped().map { $0.map(\.nodeID) })
        // O resize da janela também dispara o aviso do split view, e sem esta
        // guarda o `workbenches.json` seria reescrito a cada pixel de arrasto da
        // borda.
        guard layout != lastPublished else { return }
        lastPublished = layout
        onLayoutChanged?(layout)
    }

    // MARK: Nitidez

    /// Aqui não há zoom, então basta a escala da tela. O que morde é o contrário:
    /// o card chega do canvas com a escala do último zoom aplicada, e sem
    /// reajustar o code-server fica embaçado no mosaico.
    private var contentsScale: CGFloat {
        min(window?.backingScaleFactor ?? 2, Self.maxContentsScale)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = contentsScale
        nodes.forEach { $0.applyContentsScale(scale) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        let scale = contentsScale
        nodes.forEach { $0.applyContentsScale(scale) }
    }
}

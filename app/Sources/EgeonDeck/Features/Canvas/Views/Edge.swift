import AppKit

// MARK: - Geometria

/// Como uma aresta vai da origem ao destino.
enum EdgeRoute {
    /// Destino à direita: Bézier direta, tangentes horizontais.
    case direct(from: NSPoint, to: NSPoint)
    /// Destino à esquerda: desce por baixo dos dois cards, volta e sobe. Cantos
    /// em ângulo reto, arredondados.
    case loop(corners: [NSPoint])
    /// Um card embaixo do outro: da base do de cima ao topo do de baixo,
    /// tangentes verticais. Pelas portas laterais, quem está na mesma coluna
    /// parece "atrás" e a linha dava a volta inteira por baixo do de baixo
    /// para entrar pela esquerda dele.
    case stacked(from: NSPoint, to: NSPoint)

    var isStacked: Bool {
        if case .stacked = self { return true }
        return false
    }
}

/// Traçado no estilo n8n.
///
/// A regra que importa veio de ler o `getEdgeRenderData.ts` deles: aresta para
/// trás não é a mesma curva com outros parâmetros, é **outra rota**. Ida e volta
/// ficam em faixas diferentes e por isso não têm como se cruzar — e o retorno
/// parece um retorno, em vez de uma linha que some atrás dos cards.
enum EdgeCurve {
    /// Raio das bolinhas de porta.
    static let portRadius: CGFloat = 4
    /// Lado do triângulo da ponta, em pontos de TELA — não encolhe com o zoom, e é
    /// por isso que 12 aqui bastam. A 9, medindo documento, ela era um engrossamento
    /// da linha; a 20, grande demais ao lado do card.
    static let arrowSize: CGFloat = 12

    /// Constantes do n8n. `loopClearance` é adaptação: lá o `EDGE_PADDING_BOTTOM`
    /// é 130 fixo, o que funciona porque um nó do n8n tem ~100pt de altura. Aqui
    /// um terminal passa de 380, e 130 abaixo da porta ainda cai dentro do card
    /// — a volta ficaria escondida atrás dele. Então a faixa é medida a partir da
    /// base do card mais baixo.
    static let loopOffsetX: CGFloat = 40
    static let loopClearance: CGFloat = 46
    static let cornerRadius: CGFloat = 16
    /// Zona morta para o destino "quase" alinhado não virar loop.
    static let backwardThreshold: CGFloat = 20

    /// Não existe mais "segunda volta do par": ida e volta são uma linha só
    /// (`EdgeLink`), então duas curvas nunca disputam a mesma faixa. A faixa
    /// afastada e o corredor deslocado que resolviam isso saíram junto — ADR-028.
    static func route(from sourceFrame: NSRect, to targetFrame: NSRect) -> EdgeRoute {
        if let stacked = stackedRoute(sourceFrame, targetFrame) { return stacked }
        let source = sourcePort(sourceFrame)
        let target = targetPort(targetFrame)
        guard source.x - backwardThreshold > target.x else {
            return .direct(from: source, to: target)
        }
        let lane = max(sourceFrame.maxY, targetFrame.maxY) + loopClearance
        let out = loopOffsetX
        return .loop(corners: [
            source,
            NSPoint(x: source.x + out, y: source.y),
            NSPoint(x: source.x + out, y: lane),
            NSPoint(x: target.x - out, y: lane),
            NSPoint(x: target.x - out, y: target.y),
            target
        ])
    }

    /// Quanto da largura do card mais estreito tem de estar sob o outro para
    /// os dois contarem como coluna. Metade: deslocados menos que isso, a
    /// linha vertical ainda é a curta; mais, já se lê como "ao lado".
    static let stackOverlap: CGFloat = 0.5

    /// Os dois cards estão um sobre o outro, sem se tocar na vertical. A rota
    /// vai sempre do de cima para o de baixo, seja qual for a origem — a ponta
    /// é que diz o sentido. Coordenadas do documento, flipped: y cresce para
    /// baixo.
    static func stackedRoute(_ a: NSRect, _ b: NSRect) -> EdgeRoute? {
        let overlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        guard overlap >= stackOverlap * min(a.width, b.width) else { return nil }
        let (upper, lower) = a.minY <= b.minY ? (a, b) : (b, a)
        guard lower.minY - upper.maxY > backwardThreshold else { return nil }
        // No meio da faixa que os dois dividem: com cards de larguras ou
        // posições diferentes, a linha sai e entra reta.
        let x = (max(a.minX, b.minX) + min(a.maxX, b.maxX)) / 2
        return .stacked(from: NSPoint(x: x, y: upper.maxY), to: NSPoint(x: x, y: lower.minY))
    }

    /// Se a rota entre estes dois cards sai reta, sem dar a volta por baixo. É como
    /// o desenho escolhe qual dos dois pontas do par é a origem do traçado: a linha
    /// fica reta quando pode, e a volta sobra para quem de fato está atrás.
    static func prefersDirect(from sourceFrame: NSRect, to targetFrame: NSRect) -> Bool {
        if stackedRoute(sourceFrame, targetFrame) != nil { return sourceFrame.minY <= targetFrame.minY }
        return sourcePort(sourceFrame).x - backwardThreshold <= targetPort(targetFrame).x
    }

    /// Portas no meio vertical do card, como no n8n. No cabeçalho elas ficariam
    /// em cima dos botões de fechar e configurar.
    static func sourcePort(_ frame: NSRect) -> NSPoint {
        NSPoint(x: frame.maxX, y: frame.midY)
    }

    static func targetPort(_ frame: NSRect) -> NSPoint {
        NSPoint(x: frame.minX, y: frame.midY)
    }

    /// Onde a fileira de controles da aresta (direção, limite, remover)
    /// começa, em y. Na linha deitada ela sobe acima do meio para não cobrir
    /// a linha; na de pé, subir é deslizar ao longo dela — os controles iam
    /// parar longe do meio. Ali se centram no ponto médio, sobre a linha.
    static func controlsTop(route: EdgeRoute, midpoint: NSPoint,
                            height: CGFloat, lift: CGFloat) -> CGFloat {
        route.isStacked ? midpoint.y - height / 2 : midpoint.y - height - lift
    }

    static func path(_ route: EdgeRoute) -> NSBezierPath {
        let path = NSBezierPath()
        switch route {
        case let .direct(source, target), let .stacked(source, target):
            let (c1, c2) = controls(route)
            path.move(to: source)
            path.curve(to: target, controlPoint1: c1, controlPoint2: c2)
        case let .loop(corners):
            path.move(to: corners[0])
            for i in 1..<(corners.count - 1) {
                // `appendArc(from:to:radius:)` desenha a reta até o ponto de
                // tangência e arredonda o canto. O raio é limitado pelo trecho
                // mais curto, senão dois cantos próximos se comem.
                let radius = min(cornerRadius,
                                 segment(corners[i - 1], corners[i]) / 2,
                                 segment(corners[i], corners[i + 1]) / 2)
                path.appendArc(from: corners[i], to: corners[i + 1], radius: radius)
            }
            path.line(to: corners[corners.count - 1])
        }
        return path
    }

    private static func segment(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        max(0.0001, sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2)))
    }

    /// Pontos de controle da cúbica: na horizontal para a rota direta, na
    /// vertical para a empilhada — é o que faz a linha sair e entrar reta na
    /// borda de onde parte. Loop não tem curva.
    private static func controls(_ route: EdgeRoute) -> (NSPoint, NSPoint) {
        switch route {
        case let .direct(source, target):
            let reach = min(300, max(70, (target.x - source.x) * 0.5))
            return (NSPoint(x: source.x + reach, y: source.y),
                    NSPoint(x: target.x - reach, y: target.y))
        case let .stacked(source, target):
            let reach = min(300, max(40, (target.y - source.y) * 0.5))
            return (NSPoint(x: source.x, y: source.y + reach),
                    NSPoint(x: target.x, y: target.y - reach))
        case let .loop(corners):
            return (corners[0], corners[corners.count - 1])
        }
    }

    /// Polilinha densa do traçado. Serve para o teste de proximidade e para
    /// achar o meio — os dois precisam funcionar igual nas duas rotas, e medir
    /// por comprimento é o que faz o meio do loop cair no meio do caminho, e não
    /// no meio da lista de cantos.
    static func polyline(_ route: EdgeRoute) -> [NSPoint] {
        switch route {
        case let .direct(source, target), let .stacked(source, target):
            let (c1, c2) = controls(route)
            return (0...48).map { step in
                let t = CGFloat(step) / 48, u = 1 - t
                return NSPoint(
                    x: u*u*u*source.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*target.x,
                    y: u*u*u*source.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*target.y)
            }
        case let .loop(corners):
            return corners
        }
    }

    /// A mesma polilinha, subdividida a cada ~8pt.
    ///
    /// O teste de proximidade precisa disto: na rota de loop, `polyline` devolve
    /// só os seis cantos, e um trecho reto de 1500pt entre dois deles não teria
    /// nenhuma amostra no meio — passar o cursor ali não acharia a aresta.
    static func densePolyline(_ route: EdgeRoute) -> [NSPoint] {
        let coarse = polyline(route)
        guard coarse.count >= 2 else { return coarse }
        var dense: [NSPoint] = [coarse[0]]
        for i in 1..<coarse.count {
            let a = coarse[i - 1], b = coarse[i]
            let steps = max(1, Int(segment(a, b) / 8))
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                dense.append(NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return dense
    }

    /// Extremidades do traçado com a direção em que ele chega e sai.
    ///
    /// A ponta mora aqui e não no meio, e é uma decisão revista: no meio ela nunca
    /// se esconde, mas também não é onde se procura o sentido de uma seta. `start`
    /// é a saída da porta de origem, e `startTangent` aponta PARA FORA do card — é
    /// a direção da ponta de quem aciona no sentido contrário.
    static func endpoints(_ route: EdgeRoute)
        -> (start: NSPoint, startTangent: CGVector, end: NSPoint, endTangent: CGVector) {
        switch route {
        case let .direct(source, target), let .stacked(source, target):
            let (c1, c2) = controls(route)
            // Derivada da cúbica em t=0 e t=1: com os controles na horizontal ela é
            // horizontal também, e é o que faz a ponta encostar reta na borda do
            // card em vez de entrar torta.
            return (source, normalized(from: c1, to: source),
                    target, normalized(from: c2, to: target))
        case let .loop(corners):
            let n = corners.count
            return (corners[0], normalized(from: corners[1], to: corners[0]),
                    corners[n - 1], normalized(from: corners[n - 2], to: corners[n - 1]))
        }
    }

    private static func normalized(from a: NSPoint, to b: NSPoint) -> CGVector {
        let length = segment(a, b)
        return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
    }

    /// Ponto e direção no meio do traçado, medido por comprimento. É onde os
    /// controles do hover se penduram.
    static func midpoint(_ route: EdgeRoute) -> (NSPoint, CGVector) {
        let points = polyline(route)
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + segment(points[i - 1], points[i]))
        }
        let half = lengths[lengths.count - 1] / 2
        let index = lengths.firstIndex { $0 >= half } ?? 1
        let i = max(1, index)

        let a = points[i - 1], b = points[i]
        let span = segment(a, b)
        let t = (half - lengths[i - 1]) / span
        let point = NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        return (point, CGVector(dx: (b.x - a.x) / span, dy: (b.y - a.y) / span))
    }
}

// MARK: - Porta de saída

/// O `+` na borda direita do terminal, como no n8n: diz que dali sai conexão, e
/// é de onde você arrasta para criar uma.
///
/// Vive dentro do nó, e não na camada de arestas, por causa do mouse: a camada
/// fica atrás dos cards e o SwiftTerm engole o clique inteiro. Subview do nó
/// adicionada por último fica na frente do terminal e recebe o arrasto.
final class NodePortButton: NSView {
    /// Arrasto em curso, em coordenadas de janela.
    var onDrag: ((NSPoint) -> Void)?
    var onRelease: ((NSPoint) -> Void)?

    private var hovering = false { didSet { needsDisplay = true } }
    private var dragging = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    static let size: CGFloat = 18

    override var isFlipped: Bool { true }

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

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func draw(_ dirtyRect: NSRect) {
        let active = hovering || dragging
        let circle = bounds.insetBy(dx: 2, dy: 2)
        (active ? NSColor.systemOrange : NSColor(calibratedWhite: 0.25, alpha: 1)).setFill()
        NSBezierPath(ovalIn: circle).fill()

        let plus = NSBezierPath()
        let inset = circle.insetBy(dx: 4, dy: 4)
        plus.move(to: NSPoint(x: inset.minX, y: inset.midY))
        plus.line(to: NSPoint(x: inset.maxX, y: inset.midY))
        plus.move(to: NSPoint(x: inset.midX, y: inset.minY))
        plus.line(to: NSPoint(x: inset.midX, y: inset.maxY))
        plus.lineWidth = 1.6
        plus.lineCapStyle = .round
        (active ? NSColor.black : NSColor(calibratedWhite: 1, alpha: 0.6)).setStroke()
        plus.stroke()
    }

    override func mouseDown(with event: NSEvent) { dragging = true }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onDrag?(event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        onRelease?(event.locationInWindow)
    }
}

// MARK: - Camada de desenho

/// Desenha as arestas atrás dos nós.
///
/// View separada, e não desenho dentro do `CanvasDocument`: o documento pinta o
/// grid e é enorme, e invalidá-lo inteiro a cada pixel de arrasto de nó
/// repintaria o grid junto. Aqui só as curvas são refeitas.
final class EdgeLayerView: NSView {
    /// Resolve o frame atual de um nó pelo id. Vem do canvas, porque o que manda
    /// é onde o nó está agora, não onde o JSON diz que ele estava.
    var frameForNode: ((String) -> NSRect?)?

    /// As arestas como vivem no `workbenches.json`. A tela desenha as LIGAÇÕES
    /// derivadas daqui: um par com os dois sentidos é uma linha, não duas.
    var edges: [EdgeConfig] = [] {
        didSet {
            links = EdgeLink.collapse(edges)
            // Re-resolve o realce contra a lista nova, em vez de só conferir se ele
            // continua existindo. `EdgeLink` é igual pelo PAR, então o objeto
            // guardado sobrevive a uma troca de direção carregando os flags
            // antigos — e o botão desenhava o glifo do estado anterior enquanto a
            // linha já mostrava o novo. Some junto se o par saiu.
            hovered = hovered.flatMap { antigo in links.first { $0 == antigo } }
            needsDisplay = true
        }
    }

    private(set) var links: [EdgeLink] = []

    /// Ligação sob o cursor. Recebe destaque e mostra os controles.
    private(set) var hovered: EdgeLink?

    /// Ligação sendo desenhada agora: origem fixa, ponta seguindo o mouse.
    var pending: (from: String, to: NSPoint)? { didSet { needsDisplay = true } }

    /// Clique no X. Leva a ligação inteira — os dois sentidos —, porque na tela ela
    /// é uma linha só e remover metade do que se vê seria pior que remover tudo.
    var onRemove: ((EdgeLink) -> Void)?
    /// Clique na pastilha do limite.
    var onEditLimit: ((EdgeLink) -> Void)?
    /// Clique no botão de direção: ida → ida e volta → volta.
    var onCycleDirection: ((EdgeLink) -> Void)?

    override var isFlipped: Bool { true }

    /// Quanto vale um ponto de TELA em unidades de documento.
    ///
    /// O canvas é um scroll view magnificado, e o layer escala tudo que está dentro
    /// dele: a 0.5x a ponta de 20pt virava 10px e o alvo de clique do botão de
    /// direção, 16px — pequeno para o que ele decide. Então tudo que existe para ser
    /// LIDO ou CLICADO — ponta, bolinha, botões, glifo, espessura, tolerância — é
    /// medido em pontos de tela e multiplicado por isto. O traçado em si não: ele
    /// liga dois cards, e são os cards que escalam.
    ///
    /// O piso de 0.05 é contra divisão por zero na animação de zoom.
    private var screenPoint: CGFloat {
        let magnification = enclosingScrollView?.magnification ?? 1
        return magnification > 0.05 ? 1 / magnification : 20
    }

    /// Não recebe clique nenhum por padrão: as arestas passam por baixo dos nós,
    /// e o hit test só responde onde há de fato uma curva ou o botão dela.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitButton(at: point) != nil else { return nil }
        return self
    }

    // MARK: Traçado

    /// Onde a linha de uma ligação passa, e em qual extremidade vai cada ponta.
    private struct Laid {
        let route: EdgeRoute
        /// A extremidade em que o traçado termina leva ponta.
        let headAtEnd: Bool
        let headAtStart: Bool
    }

    private func layout(_ link: EdgeLink) -> Laid? {
        guard let frameA = frameForNode?(link.a),
              let frameB = frameForNode?(link.b) else { return nil }
        let aFirst = EdgeCurve.prefersDirect(from: frameA, to: frameB)
            || !EdgeCurve.prefersDirect(from: frameB, to: frameA)
        let route = aFirst
            ? EdgeCurve.route(from: frameA, to: frameB)
            : EdgeCurve.route(from: frameB, to: frameA)
        // A ponta fica onde o sentido CHEGA: `a→b` desenha ponta do lado de b, e
        // quem é o lado de b depende de quem virou origem do traçado.
        return Laid(route: route,
                    headAtEnd: aFirst ? link.aToB : link.bToA,
                    headAtStart: aFirst ? link.bToA : link.aToB)
    }

    override func draw(_ dirtyRect: NSRect) {
        for link in links {
            guard let laid = layout(link) else { continue }
            draw(laid, highlighted: link == hovered)
        }

        if let pending, let source = frameForNode?(pending.from) {
            // Arrastando, o destino ainda é o cursor e não um card: rota direta,
            // tracejada, sem decidir loop por um ponto que vai mudar. Com as duas
            // pontas, porque é bidirecional que vai nascer quando você soltar.
            draw(Laid(route: .direct(from: EdgeCurve.sourcePort(source), to: pending.to),
                      headAtEnd: true, headAtStart: true),
                 highlighted: true, dashed: true)
        }

        if let hovered { drawControls(for: hovered) }
    }

    private func draw(_ laid: Laid, highlighted: Bool, dashed: Bool = false) {
        let z = screenPoint
        let path = EdgeCurve.path(laid.route)
        path.lineWidth = (highlighted ? 2.5 : 1.8) * z
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if dashed { path.setLineDash([6 * z, 5 * z], count: 2, phase: 0) }

        let color = highlighted
            ? NSColor.systemOrange
            : NSColor(calibratedWhite: 1, alpha: 0.32)
        color.setStroke()
        path.stroke()

        // Ponta e bolinha em cor OPACA, e não na cor translúcida da linha: o
        // triângulo cresce por cima do traçado, e com os dois a 32% os alphas somam
        // — dá para ver o fio atravessando a seta por dentro. Opaco no tom que a
        // linha translúcida aparenta sobre o canvas, então a seta não brilha mais
        // que a linha; ela só tapa o que passa por baixo.
        let solid = highlighted ? NSColor.systemOrange : NSColor(calibratedWhite: 0.4, alpha: 1)

        let ends = EdgeCurve.endpoints(laid.route)
        // Bolinha só na extremidade sem ponta: as duas no mesmo lugar viram um
        // borrão, e a ponta já diz que a linha encosta ali.
        if !laid.headAtStart { drawPort(ends.start, color: solid) }
        if !laid.headAtEnd { drawPort(ends.end, color: solid) }
        if laid.headAtStart { drawHead(at: ends.start, direction: ends.startTangent, color: solid) }
        if laid.headAtEnd { drawHead(at: ends.end, direction: ends.endTangent, color: solid) }
    }

    private func drawPort(_ point: NSPoint, color: NSColor) {
        let radius = EdgeCurve.portRadius * screenPoint
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - radius, y: point.y - radius,
                                    width: radius * 2, height: radius * 2)).fill()
    }

    /// Triângulo com o vértice encostado na borda do card e o corpo para fora dele.
    ///
    /// Para fora de propósito: crescer para dentro cobriria o cabeçalho do card, e
    /// é ali que ficam o título e os avisos de estado.
    private func drawHead(at tip: NSPoint, direction: CGVector, color: NSColor) {
        let size = EdgeCurve.arrowSize * screenPoint
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let base = NSPoint(x: tip.x - direction.dx * size, y: tip.y - direction.dy * size)

        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: NSPoint(x: base.x + normal.dx * size * 0.42,
                              y: base.y + normal.dy * size * 0.42))
        head.line(to: NSPoint(x: base.x - normal.dx * size * 0.42,
                              y: base.y - normal.dy * size * 0.42))
        head.close()
        color.setFill()
        head.fill()
    }

    // MARK: Controles no hover

    /// Controles do tamanho de alvo de clique de verdade. Eram 24pt, e num canvas
    /// afastado tanto o alvo quanto o glifo ficavam pequenos para o que decidem —
    /// direção da ligação e remoção.
    private static let buttonSize: CGFloat = 32
    private static let pillSize = NSSize(width: 68, height: 32)
    private static let controlGap: CGFloat = 7
    /// Altura entre a curva e a base dos controles.
    private static let controlLift: CGFloat = 14

    /// Onde ficam os três controles da ligação sob o cursor.
    ///
    /// Acima da curva, e não sobre ela: em cima da linha eles tapam a ponta da
    /// seta justamente quando você precisa conferir o sentido antes de mexer.
    private func controlRects(for link: EdgeLink)
        -> (direction: NSRect, pill: NSRect, remove: NSRect)? {
        guard let laid = layout(link) else { return nil }
        let (point, _) = EdgeCurve.midpoint(laid.route)
        let z = screenPoint
        let pill = NSSize(width: Self.pillSize.width * z, height: Self.pillSize.height * z)
        let button = Self.buttonSize * z, gap = Self.controlGap * z
        let total = button + gap + pill.width + gap + button
        let y = EdgeCurve.controlsTop(route: laid.route, midpoint: point,
                                      height: max(pill.height, button), lift: Self.controlLift * z)
        let left = point.x - total / 2
        return (NSRect(x: left, y: y, width: button, height: button),
                NSRect(x: left + button + gap, y: y, width: pill.width, height: pill.height),
                NSRect(x: left + total - button, y: y, width: button, height: button))
    }

    /// Área invisível que mantém os controles no ar.
    ///
    /// Sem ela o realce é decidido só pela distância à curva, e os controles ficam
    /// acima dela: subir o mouse para clicar sai da zona e eles somem antes de
    /// você chegar. O retângulo cobre os botões e desce colando na linha,
    /// fechando o vão por onde o cursor passa.
    private func hoverHull(for link: EdgeLink) -> NSRect? {
        guard let rects = controlRects(for: link), let laid = layout(link) else { return nil }
        let (point, _) = EdgeCurve.midpoint(laid.route)
        let controls = rects.direction.union(rects.pill).union(rects.remove)
        let z = screenPoint
        if laid.route.isStacked { return controls.insetBy(dx: -10 * z, dy: -8 * z) }
        return NSRect(x: controls.minX, y: controls.minY,
                      width: controls.width, height: point.y - controls.minY + 6 * z)
            .insetBy(dx: -10 * z, dy: -8 * z)
    }

    private func drawControls(for link: EdgeLink) {
        guard let rects = controlRects(for: link), let laid = layout(link) else { return }

        // O glifo mostra o que a linha faz AGORA, na orientação em que ela está
        // desenhada — clicar troca para o próximo estado.
        let glyph: String
        if laid.headAtEnd && laid.headAtStart { glyph = "↔" }
        else if laid.headAtEnd { glyph = "→" }
        else { glyph = "←" }
        drawRoundButton(rects.direction, glyph: glyph, fontSize: 19 * screenPoint)

        drawLimitPill(link, in: rects.pill)
        drawRemoveButton(rects.remove)
    }

    private func drawRoundButton(_ rect: NSRect, glyph: String, fontSize: CGFloat) {
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.systemOrange.setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5 * screenPoint, dy: 0.5 * screenPoint))
        ring.lineWidth = screenPoint
        ring.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.systemOrange
        ]
        let size = (glyph as NSString).size(withAttributes: attributes)
        (glyph as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes)
    }

    private func drawRemoveButton(_ rect: NSRect) {
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let z = screenPoint
        NSColor.systemOrange.setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5 * z, dy: 0.5 * z))
        ring.lineWidth = z
        ring.stroke()

        let cross = NSBezierPath()
        let inset = rect.insetBy(dx: 9.5 * z, dy: 9.5 * z)
        cross.move(to: NSPoint(x: inset.minX, y: inset.minY))
        cross.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        cross.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        cross.line(to: NSPoint(x: inset.minX, y: inset.maxY))
        cross.lineWidth = 2 * z
        cross.lineCapStyle = .round
        NSColor.systemOrange.setStroke()
        cross.stroke()
    }

    /// Quantas idas e voltas esta ligação permite. `∞` = sem limite próprio, vale só
    /// o teto da bancada.
    private func drawLimitPill(_ link: EdgeLink, in rect: NSRect) {
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2,
                     yRadius: rect.height / 2).fill()
        let z = screenPoint
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5 * z, dy: 0.5 * z),
                                xRadius: rect.height / 2, yRadius: rect.height / 2)
        ring.lineWidth = z
        NSColor.systemOrange.setStroke()
        ring.stroke()

        let text = "↻ \(link.maxSends.map(String.init) ?? "∞")"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 17 * z, weight: .semibold),
            .foregroundColor: NSColor.systemOrange
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes)
    }

    private func hitButton(at point: NSPoint) -> EdgeLink? {
        guard let hovered, let rects = controlRects(for: hovered) else { return nil }
        return rects.direction.contains(point) || rects.pill.contains(point)
            || rects.remove.contains(point) ? hovered : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let link = hovered, let rects = controlRects(for: link) else { return }
        if rects.remove.contains(point) {
            onRemove?(link)
        } else if rects.pill.contains(point) {
            onEditLimit?(link)
        } else if rects.direction.contains(point) {
            onCycleDirection?(link)
        }
    }

    // MARK: Hover

    /// Qual ligação está perto deste ponto. Amostra a curva em vez de resolver a
    /// cúbica: a tolerância de clique é maior que o erro da amostragem, e o custo
    /// é irrelevante para a quantidade de arestas que cabe num canvas.
    func link(near point: NSPoint, tolerance: CGFloat = 14) -> EdgeLink? {
        // Tolerância em pontos de tela também: afastado, 14 unidades de documento
        // viram 7px e a linha foge do cursor.
        let reach = tolerance * screenPoint
        // A ligação já realçada ganha primeiro: enquanto o cursor estiver na área
        // dos controles dela, é ela que continua no ar. Sem esta precedência, uma
        // curva vizinha passando perto rouba o realce no meio do seu clique.
        if let hovered, hoverHull(for: hovered)?.contains(point) == true { return hovered }

        var best: (link: EdgeLink, distance: CGFloat)?
        for link in links {
            guard let laid = layout(link) else { continue }
            var closest = CGFloat.greatestFiniteMagnitude
            for sample in EdgeCurve.densePolyline(laid.route) {
                let dx = sample.x - point.x, dy = sample.y - point.y
                closest = min(closest, sqrt(dx*dx + dy*dy))
            }
            if closest <= reach, closest < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (link, closest)
            }
        }
        return best?.link
    }

    func setHovered(_ link: EdgeLink?) {
        guard link != hovered else { return }
        hovered = link
        needsDisplay = true
    }
}

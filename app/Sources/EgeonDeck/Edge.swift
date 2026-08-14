import AppKit

/// Uma ligação dirigida entre dois nós da mesma sessão: `from` pode acionar
/// `to`.
///
/// Sempre de mão única. Ida e volta são duas arestas, desenhadas separadamente,
/// e é de propósito: um tipo "bidirecional" cobriria só o ciclo de dois e
/// deixaria A→B→C→A sem tratamento. Com uma seta só, ciclo de dois e de três são
/// o mesmo mecanismo — e aparecem os dois na tela.
struct EdgeConfig: Codable, Equatable {
    var from: String
    var to: String

    /// Quantas vezes esta seta pode disparar na mesma conversa. Nil = sem limite
    /// próprio, vale só o teto da sessão.
    ///
    /// Num par ligado nos dois sentidos, este é o número de idas e voltas: com 2,
    /// A fala, B responde, A fala, B responde, e a próxima é cortada.
    ///
    /// Só aperta, nunca afrouxa. O teto da sessão continua valendo por cima —
    /// e tem de continuar, porque limite por seta não segura `A→B→C→A`: ali cada
    /// seta dispara uma vez só e o contador nunca chega perto.
    var maxSends: Int? = EdgeConfig.defaultSends

    /// Duas idas e voltas: delega, recebe, ajusta, recebe. É o ciclo útil mais
    /// comum, e o próximo já costuma ser repetição.
    ///
    /// Baixo de propósito. Turno de agente degrada com a quantidade de rodadas
    /// mesmo sobrando contexto — a "inércia conversacional" —, e no
    /// multi-agente 40% das falhas catalogadas pelo MAST são desalinhamento
    /// entre agentes, que só tem mais chance de aparecer a cada volta. Somando
    /// que isto roda enquanto você está longe da máquina, errar para menos custa
    /// uma rodada a mais pedida por você; errar para mais custa tempo e token
    /// sem ninguém olhando.
    static let defaultSends = 2

    /// Igualdade só por origem e destino: é o que identifica a ligação. Duas
    /// arestas entre o mesmo par não existem, e comparar o limite junto faria
    /// `contains` falhar depois de você editar o número.
    static func == (a: EdgeConfig, b: EdgeConfig) -> Bool {
        a.from == b.from && a.to == b.to
    }
}

extension EdgeConfig {
    /// O `Decodable` sintetizado ignora o valor padrão da propriedade: aresta
    /// gravada antes de `maxSends` existir voltaria com nil, ou seja, sem limite
    /// nenhum — o oposto do que o padrão quer dizer.
    ///
    /// Chave ausente e `null` explícito são coisas diferentes aqui: ausente herda
    /// o padrão, `null` desliga o limite desta seta e deixa só o teto da sessão.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(String.self, forKey: .from)
        to = try container.decode(String.self, forKey: .to)
        maxSends = container.contains(.maxSends)
            ? try container.decodeIfPresent(Int.self, forKey: .maxSends)
            : EdgeConfig.defaultSends
    }
}

// MARK: - Geometria

/// Como uma aresta vai da origem ao destino.
enum EdgeRoute {
    /// Destino à direita: Bézier direta, tangentes horizontais.
    case direct(from: NSPoint, to: NSPoint)
    /// Destino à esquerda: desce por baixo dos dois cards, volta e sobe. Cantos
    /// em ângulo reto, arredondados.
    case loop(corners: [NSPoint])
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
    static let arrowSize: CGFloat = 9

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

    /// Afastamento do corredor vertical da segunda volta. Ver `isSecondary`.
    static let laneGap: CGFloat = 28

    /// Esta aresta é a "segunda" do par, e por isso dá a volta por cima.
    ///
    /// Com dois terminais empilhados na mesma coluna, as DUAS direções viram
    /// loop: mesmas portas em x, mesma faixa, e medido dá 0pt de distância — uma
    /// desenha exatamente por cima da outra. Só afastar a faixa não resolve,
    /// porque os corredores verticais continuam no mesmo x.
    ///
    /// Então uma volta desce e a outra sobe, com corredores em x diferentes.
    /// Sobra um único cruzamento, onde o trecho de saída de uma atravessa o
    /// corredor da outra — inevitável quando os dois cards ocupam a mesma faixa
    /// horizontal, e muito melhor que sobreposição total.
    ///
    /// Quem é a segunda é decidido pela ordem dos nomes, não pela ordem em que
    /// você desenhou: assim não troca quando o arquivo é reescrito.
    static func isSecondary(_ edge: EdgeConfig, among edges: [EdgeConfig]) -> Bool {
        edges.contains(EdgeConfig(from: edge.to, to: edge.from)) && edge.from > edge.to
    }

    static func route(from sourceFrame: NSRect, to targetFrame: NSRect,
                      secondary: Bool = false) -> EdgeRoute {
        let source = sourcePort(sourceFrame)
        let target = targetPort(targetFrame)
        guard source.x - backwardThreshold > target.x else {
            return .direct(from: source, to: target)
        }
        let lane = secondary
            ? min(sourceFrame.minY, targetFrame.minY) - loopClearance
            : max(sourceFrame.maxY, targetFrame.maxY) + loopClearance
        let out = loopOffsetX + (secondary ? laneGap : 0)
        return .loop(corners: [
            source,
            NSPoint(x: source.x + out, y: source.y),
            NSPoint(x: source.x + out, y: lane),
            NSPoint(x: target.x - out, y: lane),
            NSPoint(x: target.x - out, y: target.y),
            target
        ])
    }

    /// Portas no meio vertical do card, como no n8n. No cabeçalho elas ficariam
    /// em cima dos botões de fechar e configurar.
    static func sourcePort(_ frame: NSRect) -> NSPoint {
        NSPoint(x: frame.maxX, y: frame.midY)
    }

    static func targetPort(_ frame: NSRect) -> NSPoint {
        NSPoint(x: frame.minX, y: frame.midY)
    }

    static func path(_ route: EdgeRoute) -> NSBezierPath {
        let path = NSBezierPath()
        switch route {
        case let .direct(source, target):
            let (c1, c2) = controls(from: source, to: target)
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

    private static func controls(from source: NSPoint,
                                 to target: NSPoint) -> (NSPoint, NSPoint) {
        let dx = target.x - source.x
        let reach = min(300, max(70, dx * 0.5))
        return (NSPoint(x: source.x + reach, y: source.y),
                NSPoint(x: target.x - reach, y: target.y))
    }

    /// Polilinha densa do traçado. Serve para o teste de proximidade e para
    /// achar o meio — os dois precisam funcionar igual nas duas rotas, e medir
    /// por comprimento é o que faz o meio do loop cair no meio do caminho, e não
    /// no meio da lista de cantos.
    static func polyline(_ route: EdgeRoute) -> [NSPoint] {
        switch route {
        case let .direct(source, target):
            let (c1, c2) = controls(from: source, to: target)
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

    /// Ponto e direção no meio do traçado, medido por comprimento. É onde a
    /// ponta da seta vai.
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

    var edges: [EdgeConfig] = [] { didSet { needsDisplay = true } }

    /// Aresta sob o cursor. Recebe destaque e mostra o alvo de remoção.
    private(set) var hovered: EdgeConfig?

    /// Ligação sendo desenhada agora: origem fixa, ponta seguindo o mouse.
    var pending: (from: String, to: NSPoint)? { didSet { needsDisplay = true } }

    /// Clique no X de uma aresta.
    var onRemove: ((EdgeConfig) -> Void)?
    /// Clique na pastilha do limite.
    var onEditLimit: ((EdgeConfig) -> Void)?

    override var isFlipped: Bool { true }

    /// Não recebe clique nenhum por padrão: as arestas passam por baixo dos nós,
    /// e o hit test só responde onde há de fato uma curva ou o botão dela.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitButton(at: point) != nil else { return nil }
        return self
    }

    override func draw(_ dirtyRect: NSRect) {
        for edge in edges {
            guard let source = frameForNode?(edge.from),
                  let target = frameForNode?(edge.to) else { continue }
            draw(EdgeCurve.route(from: source, to: target,
                                 secondary: EdgeCurve.isSecondary(edge, among: edges)),
                 highlighted: edge == hovered)
        }

        if let pending, let source = frameForNode?(pending.from) {
            // Arrastando, o destino ainda é o cursor e não um card: rota direta,
            // tracejada, sem decidir loop por um ponto que vai mudar.
            draw(.direct(from: EdgeCurve.sourcePort(source), to: pending.to),
                 highlighted: true, dashed: true)
        }

        if let hovered { drawRemoveButton(for: hovered) }
    }

    private func draw(_ route: EdgeRoute, highlighted: Bool, dashed: Bool = false) {
        let path = EdgeCurve.path(route)
        path.lineWidth = highlighted ? 2.5 : 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if dashed { path.setLineDash([6, 5], count: 2, phase: 0) }

        let color = highlighted
            ? NSColor.systemOrange
            : NSColor(calibratedWhite: 1, alpha: 0.32)
        color.setStroke()
        path.stroke()

        color.setFill()
        let ends = EdgeCurve.polyline(route)
        for port in [ends[0], ends[ends.count - 1]] {
            NSBezierPath(ovalIn: NSRect(x: port.x - EdgeCurve.portRadius,
                                        y: port.y - EdgeCurve.portRadius,
                                        width: EdgeCurve.portRadius * 2,
                                        height: EdgeCurve.portRadius * 2)).fill()
        }
        drawArrow(route, color: color)
    }

    /// Ponta no meio do traçado, como no n8n: na extremidade ela ficaria
    /// escondida atrás do card de destino, e é justamente o sentido que a seta
    /// existe para dizer.
    private func drawArrow(_ route: EdgeRoute, color: NSColor) {
        let (point, direction) = EdgeCurve.midpoint(route)
        let size = EdgeCurve.arrowSize
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)

        let tip = NSPoint(x: point.x + direction.dx * size * 0.6,
                          y: point.y + direction.dy * size * 0.6)
        let back = NSPoint(x: point.x - direction.dx * size * 0.5,
                           y: point.y - direction.dy * size * 0.5)

        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: NSPoint(x: back.x + normal.dx * size * 0.45,
                              y: back.y + normal.dy * size * 0.45))
        head.line(to: NSPoint(x: back.x - normal.dx * size * 0.45,
                              y: back.y - normal.dy * size * 0.45))
        head.close()
        color.setFill()
        head.fill()
    }

    // MARK: Controles no hover

    private static let buttonSize: CGFloat = 24
    private static let pillSize = NSSize(width: 50, height: 24)
    private static let controlGap: CGFloat = 6
    /// Altura entre a curva e a base dos controles.
    private static let controlLift: CGFloat = 12

    /// Onde ficam os dois controles da aresta sob o cursor.
    ///
    /// Acima da curva, e não sobre ela: em cima da linha eles tapam a ponta da
    /// seta justamente quando você precisa conferir o sentido antes de mexer.
    private func controlRects(for edge: EdgeConfig) -> (pill: NSRect, remove: NSRect)? {
        guard let source = frameForNode?(edge.from),
              let target = frameForNode?(edge.to) else { return nil }
        let (point, _) = EdgeCurve.midpoint(
            EdgeCurve.route(from: source, to: target,
                            secondary: EdgeCurve.isSecondary(edge, among: edges)))
        let pill = Self.pillSize, button = Self.buttonSize, gap = Self.controlGap
        let total = pill.width + gap + button
        let y = point.y - max(pill.height, button) - Self.controlLift
        let left = point.x - total / 2
        return (NSRect(x: left, y: y, width: pill.width, height: pill.height),
                NSRect(x: left + pill.width + gap, y: y, width: button, height: button))
    }

    /// Área invisível que mantém os controles no ar.
    ///
    /// Sem ela o realce é decidido só pela distância à curva, e os controles ficam
    /// acima dela: subir o mouse para clicar sai da zona e eles somem antes de
    /// você chegar. O retângulo cobre os dois botões e desce colando na linha,
    /// fechando o vão por onde o cursor passa.
    private func hoverHull(for edge: EdgeConfig) -> NSRect? {
        guard let rects = controlRects(for: edge),
              let source = frameForNode?(edge.from),
              let target = frameForNode?(edge.to) else { return nil }
        let (point, _) = EdgeCurve.midpoint(
            EdgeCurve.route(from: source, to: target,
                            secondary: EdgeCurve.isSecondary(edge, among: edges)))
        let controls = rects.pill.union(rects.remove)
        // Da linha até o topo dos botões, com folga em volta.
        return NSRect(x: controls.minX, y: controls.minY,
                      width: controls.width, height: point.y - controls.minY + 6)
            .insetBy(dx: -10, dy: -8)
    }

    private func drawRemoveButton(for edge: EdgeConfig) {
        guard let rects = controlRects(for: edge) else { return }
        drawLimitPill(edge, in: rects.pill)

        let rect = rects.remove
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.systemOrange.setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        ring.lineWidth = 1
        ring.stroke()

        let cross = NSBezierPath()
        let inset = rect.insetBy(dx: 7, dy: 7)
        cross.move(to: NSPoint(x: inset.minX, y: inset.minY))
        cross.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        cross.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        cross.line(to: NSPoint(x: inset.minX, y: inset.maxY))
        cross.lineWidth = 1.5
        cross.lineCapStyle = .round
        NSColor.systemOrange.setStroke()
        cross.stroke()
    }

    /// Quantas idas e voltas esta seta permite. `∞` = sem limite próprio, vale só
    /// o teto da sessão.
    private func drawLimitPill(_ edge: EdgeConfig, in rect: NSRect) {
        NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2,
                     yRadius: rect.height / 2).fill()
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: rect.height / 2, yRadius: rect.height / 2)
        ring.lineWidth = 1
        NSColor.systemOrange.setStroke()
        ring.stroke()

        let text = "↻ \(edge.maxSends.map(String.init) ?? "∞")"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.systemOrange
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes)
    }

    private func hitButton(at point: NSPoint) -> EdgeConfig? {
        guard let hovered, let rects = controlRects(for: hovered) else { return nil }
        return (rects.remove.contains(point) || rects.pill.contains(point)) ? hovered : nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let edge = hovered, let rects = controlRects(for: edge) else { return }
        if rects.remove.contains(point) {
            onRemove?(edge)
        } else if rects.pill.contains(point) {
            onEditLimit?(edge)
        }
    }

    // MARK: Hover

    /// Qual aresta está perto deste ponto. Amostra a curva em vez de resolver a
    /// cúbica: a tolerância de clique é maior que o erro da amostragem, e o custo
    /// é irrelevante para a quantidade de arestas que cabe num canvas.
    func edge(near point: NSPoint, tolerance: CGFloat = 14) -> EdgeConfig? {
        // A aresta já realçada ganha primeiro: enquanto o cursor estiver na área
        // dos controles dela, é ela que continua no ar. Sem esta precedência, uma
        // curva vizinha passando perto rouba o realce no meio do seu clique.
        if let hovered, hoverHull(for: hovered)?.contains(point) == true { return hovered }

        var best: (edge: EdgeConfig, distance: CGFloat)?
        for edge in edges {
            guard let sourceFrame = frameForNode?(edge.from),
                  let targetFrame = frameForNode?(edge.to) else { continue }
            let route = EdgeCurve.route(from: sourceFrame, to: targetFrame,
                                        secondary: EdgeCurve.isSecondary(edge, among: edges))
            var closest = CGFloat.greatestFiniteMagnitude
            for sample in EdgeCurve.densePolyline(route) {
                let dx = sample.x - point.x, dy = sample.y - point.y
                closest = min(closest, sqrt(dx*dx + dy*dy))
            }
            if closest <= tolerance, closest < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (edge, closest)
            }
        }
        return best?.edge
    }

    func setHovered(_ edge: EdgeConfig?) {
        guard edge != hovered else { return }
        hovered = edge
        needsDisplay = true
    }
}

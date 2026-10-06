import CoreGraphics

/// O arranjo que o maestro dá à bancada quando a monta (ADR-066).
///
/// Desenha a hierarquia em vez de empilhar onde houver vaga: o maestro à
/// esquerda; os agentes em grade ao lado; os terminais normais numa faixa
/// embaixo, mais baixos — são log, não conversa; editor e navegador por
/// último, com o tamanho que já têm. Coordenadas do documento do canvas, que é
/// flipped: y cresce para baixo.
enum MaestroLayout {
    static let margin: CGFloat = 40
    static let gap: CGFloat = 40
    /// Vão entre agentes quando há seta desenhada entre eles: a linha, a
    /// curva e as duas pontas precisam de onde aparecer. Com o vão de cards
    /// soltos a seta vira um traço escondido entre duas bordas.
    static let linkedGap: CGFloat = 160
    static let agent = CGSize(width: 720, height: 460)
    static let shell = CGSize(width: 640, height: 320)

    /// Colunas da grade de agentes: dois lado a lado até quatro, três dali em
    /// diante — mais que isso o card fica longe demais para ler sem zoom.
    static func columns(for count: Int) -> Int {
        count <= 1 ? 1 : count <= 4 ? 2 : 3
    }

    /// O maestro fica onde está — posição e tamanho são escolha do usuário,
    /// e ele é a âncora: o time se arruma à direita dele, alinhado pelo topo.
    /// Só sem frame (bancada nunca desenhada) ele ganha uma coluna da altura do
    /// time.
    static func frames(for nodes: [NodeConfig], edges: [EdgeConfig] = []) -> [String: CGRect] {
        let maestros = nodes.filter(\.isMaestro)
        let workers = nodes.filter { $0.type == .agent && !$0.isMaestro }
        let shells = nodes.filter { $0.type == .shell }
        let others = nodes.filter { $0.type == .editor || $0.type == .web }

        let ids = Set(workers.map(\.id))
        let linked = edges.contains { ids.contains($0.from) && ids.contains($0.to) }
        let teamGap = linked ? linkedGap : gap

        var frames: [String: CGRect] = [:]
        let columns = columns(for: workers.count)
        let rows = workers.isEmpty ? 1 : (workers.count + columns - 1) / columns
        let teamHeight = CGFloat(rows) * agent.height + CGFloat(rows - 1) * teamGap

        var origin = CGPoint(x: margin, y: margin)
        if let anchor = maestros.compactMap(\.frame).first {
            origin = CGPoint(x: anchor.minX, y: anchor.minY)
        }
        var x = origin.x
        for maestro in maestros {
            let frame = maestro.frame
                ?? CGRect(x: x, y: origin.y, width: agent.width, height: teamHeight)
            frames[maestro.id] = frame
            x = max(x, frame.maxX + gap)
        }
        for (i, node) in workers.enumerated() {
            frames[node.id] = CGRect(x: x + CGFloat(i % columns) * (agent.width + teamGap),
                                     y: origin.y + CGFloat(i / columns) * (agent.height + teamGap),
                                     width: agent.width, height: agent.height)
        }

        // A faixa de baixo quebra na largura do que está em cima, para a
        // bancada continuar um bloco só.
        let top = frames.values.map(\.maxY).max() ?? origin.y
        let width = max(frames.values.map(\.maxX).max() ?? 0, origin.x + agent.width)
        var cursor = CGPoint(x: origin.x, y: frames.isEmpty ? origin.y : top + gap)
        var rowHeight: CGFloat = 0
        for node in shells + others {
            let size = node.type == .shell ? shell
                : (node.frame?.size ?? CGSize(width: agent.width, height: agent.height))
            if cursor.x > origin.x, cursor.x + size.width > width {
                cursor = CGPoint(x: origin.x, y: cursor.y + rowHeight + gap)
                rowHeight = 0
            }
            frames[node.id] = CGRect(origin: cursor, size: size)
            cursor.x += size.width + gap
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

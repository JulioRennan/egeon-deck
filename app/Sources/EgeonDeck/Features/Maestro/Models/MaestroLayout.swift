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
        if linked {
            for (id, frame) in layered(workers.map(\.id), edges: edges,
                                       origin: CGPoint(x: x, y: origin.y)) {
                frames[id] = frame
            }
        } else {
            for (i, node) in workers.enumerated() {
                frames[node.id] = CGRect(x: x + CGFloat(i % columns) * (agent.width + teamGap),
                                         y: origin.y + CGFloat(i / columns) * (agent.height + teamGap),
                                         width: agent.width, height: agent.height)
            }
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

    /// Os agentes pelo fluxo das setas desenhadas, da esquerda para a direita.
    ///
    /// Ancorado à DIREITA, no destino: quem mais recebe do que manda (entradas
    /// menos saídas, contando toda seta desenhada) é para onde o trabalho
    /// converge, e fica na última coluna. Cada outro card fica a tantas
    /// colunas dele quanto o caminho MAIS CURTO de setas até lá. Contar da
    /// esquerda pelo caminho mais longo transformava qualquer ciclo numa fila
    /// (`testador → planejador → dev ↔ testador` virava uma linha de três);
    /// pela distância ao destino, os dois que apontam para o `dev` ficam na
    /// mesma coluna, empilhados, e ele no meio deles.
    ///
    /// Na coluna, cada card se centra na altura média dos vizinhos da coluna
    /// à esquerda que apontam para ele — as curvas chegam simétricas.
    /// Sobreposição empurra para baixo. Sem destino claro (só pares de ida e
    /// volta, ou um ciclo redondo), tudo numa coluna, empilhado.
    static func layered(_ ids: [String], edges: [EdgeConfig],
                        origin: CGPoint) -> [String: CGRect] {
        let members = Set(ids)
        let links = edges.filter { members.contains($0.from) && members.contains($0.to) && $0.from != $0.to }
        var score = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        for edge in links { score[edge.to]! += 1; score[edge.from]! -= 1 }
        let top = score.values.max() ?? 0
        let sinks = top > 0 ? ids.filter { score[$0] == top } : []

        // Distância de cada um ao destino, andando as setas para trás.
        var distance: [String: Int] = [:]
        var frontier = sinks
        for sink in sinks { distance[sink] = 0 }
        while !frontier.isEmpty {
            var next: [String] = []
            for id in frontier {
                for edge in links where edge.to == id && distance[edge.from] == nil {
                    distance[edge.from] = distance[id]! + 1
                    next.append(edge.from)
                }
            }
            frontier = next
        }
        // Quem não chega ao destino (solto, ou sem destino nenhum) vai para a
        // coluna mais à esquerda.
        let deepest = distance.values.max() ?? 0
        let column = Dictionary(uniqueKeysWithValues: ids.map { ($0, deepest - (distance[$0] ?? deepest)) })

        var frames: [String: CGRect] = [:]
        let step = agent.height + linkedGap
        for c in 0...(column.values.max() ?? 0) {
            let here = ids.filter { column[$0] == c }
            let wanted = Dictionary(uniqueKeysWithValues: here.map { id -> (String, CGFloat) in
                let centers = links.filter { $0.to == id }.compactMap { edge -> CGFloat? in
                    guard let from = frames[edge.from], column[edge.from]! < c else { return nil }
                    return from.midY
                }
                let y = centers.isEmpty ? .greatestFiniteMagnitude
                    : centers.reduce(0, +) / CGFloat(centers.count) - agent.height / 2
                return (id, y)
            })
            var next = origin.y
            for (rank, id) in here.enumerated().sorted(by: {
                (wanted[$0.element]!, $0.offset) < (wanted[$1.element]!, $1.offset)
            }).map(\.element).enumerated() {
                let desired = wanted[id]! == .greatestFiniteMagnitude
                    ? origin.y + CGFloat(rank) * step : wanted[id]!
                let y = max(desired, next)
                frames[id] = CGRect(x: origin.x + CGFloat(c) * (agent.width + linkedGap), y: y,
                                    width: agent.width, height: agent.height)
                next = y + step
            }
        }
        return frames
    }
}

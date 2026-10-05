import CoreGraphics

/// O arranjo que o maestro dá à bancada quando a monta (ADR-066).
///
/// Desenha a hierarquia em vez de empilhar onde houver vaga: o maestro numa
/// coluna à esquerda, da altura do time; os agentes em grade ao lado; os
/// terminais normais numa faixa embaixo, mais baixos — são log, não conversa;
/// editor e navegador por último, com o tamanho que já têm. Coordenadas do
/// documento do canvas, que é flipped: y cresce para baixo.
enum MaestroLayout {
    static let margin: CGFloat = 40
    static let gap: CGFloat = 24
    static let agent = CGSize(width: 720, height: 460)
    static let shell = CGSize(width: 640, height: 320)

    /// Colunas da grade de agentes: dois lado a lado até quatro, três dali em
    /// diante — mais que isso o card fica longe demais para ler sem zoom.
    static func columns(for count: Int) -> Int {
        count <= 1 ? 1 : count <= 4 ? 2 : 3
    }

    static func frames(for nodes: [NodeConfig]) -> [String: CGRect] {
        let maestros = nodes.filter(\.isMaestro)
        let workers = nodes.filter { $0.type == .agent && !$0.isMaestro }
        let shells = nodes.filter { $0.type == .shell }
        let others = nodes.filter { $0.type == .editor || $0.type == .web }

        var frames: [String: CGRect] = [:]
        let columns = columns(for: workers.count)
        let rows = workers.isEmpty ? 1 : (workers.count + columns - 1) / columns
        let teamHeight = CGFloat(rows) * agent.height + CGFloat(rows - 1) * gap

        var x = margin
        for maestro in maestros {
            frames[maestro.id] = CGRect(x: x, y: margin, width: agent.width, height: teamHeight)
            x += agent.width + gap
        }
        for (i, node) in workers.enumerated() {
            frames[node.id] = CGRect(x: x + CGFloat(i % columns) * (agent.width + gap),
                                     y: margin + CGFloat(i / columns) * (agent.height + gap),
                                     width: agent.width, height: agent.height)
        }

        // A faixa de baixo quebra na largura do que está em cima, para a
        // bancada continuar um bloco só.
        let top = frames.values.map(\.maxY).max() ?? margin
        let width = max(frames.values.map(\.maxX).max() ?? 0, margin + agent.width)
        var cursor = CGPoint(x: margin, y: (frames.isEmpty ? margin : top + gap))
        var rowHeight: CGFloat = 0
        for node in shells + others {
            let size = node.type == .shell ? shell
                : (node.frame?.size ?? CGSize(width: agent.width, height: agent.height))
            if cursor.x > margin, cursor.x + size.width > width {
                cursor = CGPoint(x: margin, y: cursor.y + rowHeight + gap)
                rowHeight = 0
            }
            frames[node.id] = CGRect(origin: cursor, size: size)
            cursor.x += size.width + gap
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

import Foundation

// MARK: - Arrastar aba para reordenar

/// A conta do arrasto da faixa, sem view nenhuma: onde cada pastilha pousa e
/// para qual posição a que está na mão deve ir.
///
/// A barra lateral reordena com uma **linha de inserção**: a linha arrastada
/// fica parada e um risco aparece onde ela vai cair. Aqui é o contrário — a
/// pastilha acompanha o cursor e as vizinhas deslizam para abrir espaço, como no
/// VS Code. Isso só funciona se a ordem for recalculada a cada passo do mouse, e
/// é isso que esta conta faz.
enum TabDragLayout {
    /// O x de cada pastilha, na ordem, começando em `start` com `gap` entre elas.
    static func offsets(widths: [CGFloat], start: CGFloat, gap: CGFloat) -> [CGFloat] {
        var out: [CGFloat] = []
        var x = start
        for width in widths {
            out.append(x)
            x += width + gap
        }
        return out
    }

    /// Para qual índice vai a pastilha arrastada, dado o CENTRO dela.
    ///
    /// A troca acontece quando o centro da arrastada passa o centro da vizinha —
    /// e não quando as bordas se tocam. Com bordas, abas de larguras diferentes
    /// trocavam de lugar duas vezes no mesmo movimento: a arrastada abria espaço,
    /// a vizinha escorregava para trás dela e o critério se satisfazia de novo na
    /// direção oposta, e a faixa tremia.
    static func destination(center: CGFloat, dragging index: Int, widths: [CGFloat],
                            start: CGFloat, gap: CGFloat) -> Int {
        guard widths.indices.contains(index) else { return index }
        let xs = offsets(widths: widths, start: start, gap: gap)
        var target = index
        // Para a direita: passar o centro de quem está à frente.
        for i in (index + 1)..<widths.count where center > xs[i] + widths[i] / 2 {
            target = i
        }
        // Para a esquerda: passar o centro de quem está atrás.
        if target == index {
            for i in stride(from: index - 1, through: 0, by: -1)
            where center < xs[i] + widths[i] / 2 {
                target = i
            }
        }
        return target
    }

    /// Reordena tirando de `from` e enfiando em `to`.
    static func moved<T>(_ list: [T], from: Int, to: Int) -> [T] {
        guard list.indices.contains(from), list.indices.contains(to), from != to else { return list }
        var out = list
        let item = out.remove(at: from)
        out.insert(item, at: to)
        return out
    }
}

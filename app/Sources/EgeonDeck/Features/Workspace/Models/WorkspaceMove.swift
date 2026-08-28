import Foundation

// MARK: - Reordenar a árvore

/// Mover workspace, projeto e bancada de lugar. Funções puras: recebem a
/// árvore, devolvem a árvore nova — quem grava e quem redesenha é o dono do
/// estado (ADR-051).
///
/// A bancada é o caso delicado: a lista dela é **plana e indexada por
/// posição**, e é por índice que o app inteiro a endereça (`shells`,
/// `activeIndex`, o socket). Por isso mover devolve também o mapa
/// `índice antigo → novo`: sem ele, os terminais na tela apontariam para a
/// bancada errada — o mesmo cuidado que remover já tomava.
enum WorkspaceMove {
    /// Workspace para outra posição na barra. `to` é a posição final desejada
    /// na lista já sem ele.
    static func workspace(_ id: String, to position: Int,
                          in spaces: [WorkspaceConfig]) -> [WorkspaceConfig]? {
        guard let from = spaces.firstIndex(where: { $0.id == id }) else { return nil }
        var out = spaces
        let moved = out.remove(at: from)
        out.insert(moved, at: clamp(position, out.count))
        return out == spaces ? nil : out
    }

    /// Projeto para um workspace (o mesmo ou outro), na posição `position`
    /// dentro dele. Mudar de workspace não toca nas bancadas: elas seguem o
    /// projeto pelo `project` que já guardam.
    static func project(_ id: String, toWorkspace target: String, at position: Int,
                        in spaces: [WorkspaceConfig]) -> [WorkspaceConfig]? {
        guard let source = spaces.firstIndex(where: { $0.project(withID: id) != nil }),
              let destination = spaces.firstIndex(where: { $0.id == target }),
              let from = spaces[source].projects.firstIndex(where: { $0.id == id })
        else { return nil }
        var out = spaces
        let moved = out[source].projects.remove(at: from)
        out[destination].projects.insert(moved, at: clamp(position, out[destination].projects.count))
        return out == spaces ? nil : out
    }

    /// Bancada para um projeto, na posição `position` **dentro daquele
    /// projeto** — é assim que a barra pensa, e a lista plana se ajusta.
    /// Devolve a lista nova e o mapa dos índices que mudaram de lugar.
    static func workbench(_ index: Int, toProject project: String, at position: Int,
                          in benches: [WorkbenchConfig]) -> (list: [WorkbenchConfig],
                                                             map: [Int: Int])? {
        guard index >= 0, index < benches.count else { return nil }
        var moved = benches[index]
        var rest = benches
        rest.remove(at: index)

        // A posição dentro do projeto vira posição na lista plana: o lugar da
        // n-ésima bancada dele, ou logo depois da última quando é o fim.
        let members = rest.indices.filter { rest[$0].project == project }
        let target: Int
        if members.isEmpty {
            target = rest.count
        } else if position >= members.count {
            target = members[members.count - 1] + 1
        } else {
            target = members[max(0, position)]
        }
        moved.project = project
        let landing = clamp(target, rest.count)
        rest.insert(moved, at: landing)

        // Nada mudou: mesmo lugar e mesmo projeto. `WorkbenchConfig` não é
        // Equatable (tem nós, arestas, mosaico), então a comparação é de
        // posição e projeto — o que esta operação mexe.
        guard landing != index || benches[index].project != project else { return nil }
        return (rest, map(from: index, to: landing))
    }

    /// Para onde foi cada índice quando um item saiu de `from` e entrou em
    /// `to`. Só quem está entre os dois se desloca.
    static func map(from: Int, to: Int) -> [Int: Int] {
        guard from != to else { return [:] }
        var out = [from: to]
        if from < to {
            for i in (from + 1)...to { out[i] = i - 1 }
        } else {
            for i in to..<from { out[i] = i + 1 }
        }
        return out
    }

    private static func clamp(_ value: Int, _ upper: Int) -> Int {
        max(0, min(value, upper))
    }
}

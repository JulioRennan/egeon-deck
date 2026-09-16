import Foundation

// MARK: - Uma aba de bancada

/// O que uma aba mostra, derivado de quem está aberto e do estado dos
/// terminais. Dado puro: a view só desenha, e o teste roda sem tela.
///
/// Existe porque a barra lateral é o catálogo — tudo que existe, na árvore de
/// workspaces — e com dezenas de bancadas ela não responde à pergunta do dia a
/// dia: *o que está aberto agora, e qual delas quer alguma coisa de mim?*. As
/// abas respondem só isso, na ordem em que você abriu.
struct WorkbenchTab: Equatable {
    let id: String
    let name: String
    /// A que está na tela.
    let isActive: Bool
    /// Os mesmos três avisos da barra lateral, na mesma ordem fixa: trabalhando,
    /// precisa de você, terminou (ADR-024). Ordenar por urgência faria a bolinha
    /// trocar de lugar conforme a bancada anda.
    let summary: ActivitySummary

    var isWorking: Bool { summary.working > 0 || summary.starting > 0 }
    var wantsAttention: Bool { summary.attention > 0 }
    var isDone: Bool { summary.done > 0 }

    /// A aba inteira como texto — é o que o socket devolve e o que o teste lê.
    var line: String {
        var out = isActive ? "▸ " : "  "
        out += name
        if isWorking { out += " ⠿" }
        if wantsAttention { out += " ●!" }
        if isDone { out += " ●" }
        return out
    }
}

enum WorkbenchTabs {
    /// As abas, na ordem de `open`. Bancada que saiu da lista de configs (foi
    /// removida) não vira aba órfã — some sozinha.
    static func build(open: [String], configs: [WorkbenchConfig], active: String?,
                      activity: [String: ActivitySummary]) -> [WorkbenchTab] {
        open.compactMap { id in
            guard let config = configs.first(where: { $0.id == id }) else { return nil }
            return WorkbenchTab(id: id, name: config.name, isActive: id == active,
                                summary: activity[config.name] ?? ActivitySummary())
        }
    }

    /// Fechar uma aba: quem entra no lugar é a vizinha da direita, e na falta
    /// dela a da esquerda — como em qualquer editor. `nil` quando não sobra
    /// nenhuma.
    static func neighbour(of id: String, in open: [String]) -> String? {
        guard let i = open.firstIndex(of: id) else { return nil }
        if i + 1 < open.count { return open[i + 1] }
        if i > 0 { return open[i - 1] }
        return nil
    }
}

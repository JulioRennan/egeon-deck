import Foundation

// MARK: - Achar a bancada

/// A tradução entre os três jeitos de apontar para uma bancada: a **posição**
/// na lista (que é como a barra lateral pensa, porque ela desenha uma árvore
/// ordenada), o **id** (8 hex, que nasce com a bancada e sobrevive a rename e a
/// arrasto) e o **nome** (que é como o socket e os endereços falam).
///
/// Existe porque o app guardava tudo por posição — `shells[Int]`,
/// `edgeControllers[Int]`, closures que capturavam o índice por valor —, e
/// posição envelhece: remover ou mover uma bancada deslocava todo mundo à
/// direita e obrigava a reindexar os dicionários e religar as closures à mão.
/// Com uma janela por bancada isso deixa de ser incômodo e vira defeito: a
/// janela guardaria um número que amanhece apontando para outra bancada.
enum WorkbenchLookup {
    static func id(at index: Int, in configs: [WorkbenchConfig]) -> String? {
        guard index >= 0, index < configs.count else { return nil }
        return configs[index].id
    }

    static func index(ofID id: String, in configs: [WorkbenchConfig]) -> Int? {
        configs.firstIndex { $0.id == id }
    }

    static func index(ofName name: String, in configs: [WorkbenchConfig]) -> Int? {
        configs.firstIndex { $0.name == name }
    }

    static func id(ofName name: String, in configs: [WorkbenchConfig]) -> String? {
        configs.first { $0.name == name }?.id
    }

    /// `bancada/nó` — o endereço que o Dispatcher entende. Nome de bancada pode
    /// ter espaço, nunca barra, então a primeira barra separa (`maxSplits: 1`).
    static func split(address: String) -> (workbench: String, node: String)? {
        let parts = address.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}

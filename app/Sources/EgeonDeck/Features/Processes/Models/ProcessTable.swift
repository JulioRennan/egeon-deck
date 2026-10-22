import Foundation

/// Um processo como o sistema o entrega, antes de saber se é nosso.
struct RawProcess: Equatable {
    var pid: Int32
    var ppid: Int32
    var started: Date
    /// O `p_comm`: curto, mas é por ele que se reconhece outro Egeon Deck.
    var name: String
    var command: String
    var environment: [String: String] = [:]
}

/// Um processo lançado pelo Egeon: debaixo do app, ou órfão.
struct EgeonProcess: Equatable {
    var pid: Int32
    var ppid: Int32
    var started: Date
    var command: String
    /// O endereço do nó (`bancada/id`). `nil` é do próprio app, fora de terminal.
    var node: String?
    /// O pai morreu e o processo ficou de pé — o que ninguém mais vai encerrar.
    var orphan: Bool
}

/// Quem é do Egeon entre os processos do usuário (ADR-083).
///
/// Dois caminhos, porque um só não basta: o que descende deste app é dele pela
/// árvore, mesmo que tenha limpado o ambiente; o que perdeu o pai só se
/// reconhece pela marca. Processo debaixo de OUTRO Egeon Deck (o dev, visto do
/// estável) é daquele, e não aparece aqui nem como órfão.
enum ProcessTable {
    static let appName = "EgeonDeck"

    static func classify(_ all: [RawProcess], app: Int32, deck: String) -> [EgeonProcess] {
        var children: [Int32: [RawProcess]] = [:]
        for process in all where process.pid != process.ppid {
            children[process.ppid, default: []].append(process)
        }
        var result: [EgeonProcess] = []
        var seen: Set<Int32> = [app]

        func walk(_ parent: Int32, node: String?, orphan: Bool) {
            for child in children[parent] ?? [] where seen.insert(child.pid).inserted {
                let own = ProcessMark.node(in: child.environment) ?? node
                result.append(EgeonProcess(pid: child.pid, ppid: child.ppid, started: child.started,
                                           command: child.command, node: own, orphan: orphan))
                walk(child.pid, node: own, orphan: orphan)
            }
        }
        walk(app, node: nil, orphan: false)

        // Os outros apps e tudo debaixo deles saem antes de procurar órfão.
        for other in all where other.name == appName && other.pid != app {
            var stack = [other.pid]
            while let pid = stack.popLast() {
                guard seen.insert(pid).inserted else { continue }
                stack += (children[pid] ?? []).map(\.pid)
            }
        }

        // Do mais velho para o mais novo: o primeiro marcado de uma árvore órfã
        // leva os filhos, que entram com a marca dele se não tiverem a própria.
        for process in all.sorted(by: { $0.started < $1.started })
        where !seen.contains(process.pid) {
            guard let node = ProcessMark.node(in: process.environment) else { continue }
            // App aberto com `open` de um terminal do Egeon (o Docker Desktop
            // que um agente subiu) leva o ambiente de quem pediu — a marca
            // inclusa —, mas é outro app, de pé por conta própria. O que o
            // distingue é o bundle: o launchd põe o dele, e tudo que desce do
            // Egeon carrega o do Egeon.
            if let bundle = process.environment[ProcessMark.bundleVariable],
               !bundle.hasPrefix(ProcessMark.bundlePrefix) { continue }
            // Sem `EGEON_DECK` é de antes da marca: não dá para saber o flavor,
            // e esconder seria pior que mostrar a mais.
            if let owner = process.environment[ProcessMark.deck], owner != deck { continue }
            seen.insert(process.pid)
            result.append(EgeonProcess(pid: process.pid, ppid: process.ppid, started: process.started,
                                       command: process.command, node: node, orphan: true))
            walk(process.pid, node: node, orphan: true)
        }

        // O `zsh -lc` de um agente leva o system prompt na linha de comando, e
        // o kernel corta o buffer antes de chegar ao ambiente — nem o `ps -E` o
        // lê. Os filhos dele têm a marca; de baixo para cima, o pai a pega
        // deles (filho sempre entra depois do pai).
        var byParent: [Int32: String] = [:]
        for index in result.indices.reversed() {
            if result[index].node == nil { result[index].node = byParent[result[index].pid] }
            if let node = result[index].node { byParent[result[index].ppid] = node }
        }
        return result
    }
}

extension ProcessTable {
    /// Filhos, netos e assim por diante — sem a raiz.
    static func descendants(of root: Int32, in all: [RawProcess]) -> [RawProcess] {
        var children: [Int32: [RawProcess]] = [:]
        for process in all where process.pid != process.ppid {
            children[process.ppid, default: []].append(process)
        }
        var result: [RawProcess] = []
        var seen: Set<Int32> = [root]
        var stack = children[root] ?? []
        while let process = stack.popLast() {
            guard seen.insert(process.pid).inserted else { continue }
            result.append(process)
            stack += children[process.pid] ?? []
        }
        return result
    }
}

extension EgeonProcess {
    func json(now: Date = Date()) -> [String: Any] {
        ["pid": Int(pid), "ppid": Int(ppid), "node": node ?? "app", "orphan": orphan,
         "age": max(0, Int(now.timeIntervalSince(started))), "command": command]
    }
}

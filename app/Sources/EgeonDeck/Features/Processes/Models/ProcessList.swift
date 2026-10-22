import Foundation

/// Como a janela "Processos" mostra a lista (ADR-083).
enum ProcessList {
    /// Órfãos primeiro, que é o que se veio procurar; dentro de cada grupo por
    /// nó, e no nó do mais velho para o mais novo — o pai antes dos filhos.
    static func ordered(_ processes: [EgeonProcess]) -> [EgeonProcess] {
        processes.sorted { a, b in
            if a.orphan != b.orphan { return a.orphan }
            let x = a.node ?? "", y = b.node ?? ""
            if x != y { return x < y }
            if a.started != b.started { return a.started < b.started }
            return a.pid < b.pid
        }
    }

    /// Idade com a unidade que importa: o órfão de 19 dias tem que gritar
    /// diferente do de 40 segundos.
    static func age(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        switch s {
        case ..<60: return "\(s) s"
        case ..<3600: return "\(s / 60) min"
        case ..<86_400: return "\(s / 3600) h \(s % 3600 / 60) min"
        default: return "\(s / 86_400) d \(s % 86_400 / 3600) h"
        }
    }
}

import Foundation

/// A cor de uma bancada: a sombra em volta do canvas e o ponto ao lado do
/// título, para reconhecer a bancada antes de ler o nome (ADR-086).
///
/// Sem laranja, verde e vermelho: são "precisa de você", "terminou" e erro nos
/// badges e anéis (ADR-024), e uma bancada laranja pareceria pedir atenção o
/// tempo todo.
enum WorkbenchColor: String, CaseIterable, Codable {
    case blue, violet, pink, cyan, indigo, sand, magenta

    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .blue: return (0.29, 0.56, 1.00)
        case .violet: return (0.62, 0.42, 1.00)
        case .pink: return (1.00, 0.45, 0.70)
        case .cyan: return (0.25, 0.82, 0.95)
        case .indigo: return (0.40, 0.42, 0.95)
        case .sand: return (0.93, 0.80, 0.45)
        case .magenta: return (0.88, 0.30, 0.90)
        }
    }

    /// A menos usada entre as que já existem, e no empate a primeira da paleta.
    ///
    /// Gravada, e não tirada de um hash do id: com sete cores e seis abas, o
    /// hash repete cor em quase toda combinação — e duas bancadas da mesma cor
    /// são justamente a confusão que a cor existe para evitar.
    static func pick(used: [WorkbenchColor?]) -> WorkbenchColor {
        let counts = Dictionary(used.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
        return allCases.min { counts[$0, default: 0] < counts[$1, default: 0] } ?? .blue
    }

    /// Bancada gravada antes da cor existir ganha uma ao carregar, na ordem da
    /// lista — as primeiras sete saem todas diferentes.
    static func assignMissing(_ list: inout [WorkbenchConfig]) {
        for index in list.indices where list[index].color == nil {
            list[index].color = pick(used: list.map(\.color))
        }
    }
}

extension WorkbenchConfig {
    /// Esta bancada, com cor escolhida contra as que já estão em `others`.
    func colored(among others: [WorkbenchConfig]) -> WorkbenchConfig {
        guard color == nil else { return self }
        var copy = self
        copy.color = WorkbenchColor.pick(used: others.map(\.color))
        return copy
    }
}

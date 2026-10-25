import Foundation

/// A cor de uma bancada: a sombra em volta do canvas e o ponto ao lado do
/// título, para reconhecer a bancada antes de ler o nome (ADR-086).
///
/// A paleta são os tons 400 do Material, na ordem do círculo cromático — é a
/// grade que a bolinha do título abre. A escolha automática fica nas sete de
/// `automatic`: laranja, verde e vermelho são "precisa de você", "terminou" e
/// erro nos badges e anéis (ADR-024), e o app não põe numa bancada uma cor que
/// pareça pedir atenção o tempo todo. Escolhida à mão, vale qualquer uma.
enum WorkbenchColor: String, CaseIterable, Codable {
    case red, coral, peach, orange, amber, sand, yellow, lime
    case lightGreen, green, teal, cyan, sky, blue, indigo, deepPurple
    case violet, purple, magenta, pink, raspberry, brown, slate, grey

    /// As que o app escolhe sozinho, na ordem de preferência.
    static let automatic: [WorkbenchColor] = [.blue, .violet, .pink, .cyan, .indigo, .sand, .magenta]

    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .red: return Self.hex(0xEF5350)
        case .coral: return Self.hex(0xFF7043)
        case .peach: return Self.hex(0xFFAB91)
        case .orange: return Self.hex(0xFFA726)
        case .amber: return Self.hex(0xFFCA28)
        case .sand: return (0.93, 0.80, 0.45)
        case .yellow: return Self.hex(0xFFEE58)
        case .lime: return Self.hex(0xD4E157)
        case .lightGreen: return Self.hex(0x9CCC65)
        case .green: return Self.hex(0x66BB6A)
        case .teal: return Self.hex(0x26A69A)
        case .cyan: return (0.25, 0.82, 0.95)
        case .sky: return Self.hex(0x29B6F6)
        case .blue: return (0.29, 0.56, 1.00)
        case .indigo: return (0.40, 0.42, 0.95)
        case .deepPurple: return Self.hex(0x7E57C2)
        case .violet: return (0.62, 0.42, 1.00)
        case .purple: return Self.hex(0xAB47BC)
        case .magenta: return (0.88, 0.30, 0.90)
        case .pink: return (1.00, 0.45, 0.70)
        case .raspberry: return Self.hex(0xEC407A)
        case .brown: return Self.hex(0x8D6E63)
        case .slate: return Self.hex(0x78909C)
        case .grey: return Self.hex(0xBDBDBD)
        }
    }

    private static func hex(_ value: Int) -> (red: Double, green: Double, blue: Double) {
        (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// O nome na grade e no menu.
    var label: String {
        switch self {
        case .red: return "Vermelho"
        case .coral: return "Coral"
        case .peach: return "Pêssego"
        case .orange: return "Laranja"
        case .amber: return "Âmbar"
        case .sand: return "Areia"
        case .yellow: return "Amarelo"
        case .lime: return "Lima"
        case .lightGreen: return "Verde-claro"
        case .green: return "Verde"
        case .teal: return "Verde-azulado"
        case .cyan: return "Ciano"
        case .sky: return "Celeste"
        case .blue: return "Azul"
        case .indigo: return "Anil"
        case .deepPurple: return "Roxo"
        case .violet: return "Violeta"
        case .purple: return "Púrpura"
        case .magenta: return "Magenta"
        case .pink: return "Rosa"
        case .raspberry: return "Framboesa"
        case .brown: return "Marrom"
        case .slate: return "Ardósia"
        case .grey: return "Cinza"
        }
    }

    /// Aceita o nome do caso ou o rótulo, sem caixa nem acento — é o que chega
    /// pela rota de controle.
    init?(named raw: String) {
        func fold(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        let key = fold(raw)
        guard let found = Self.allCases.first(where: { fold($0.rawValue) == key || fold($0.label) == key })
        else { return nil }
        self = found
    }

    /// A menos usada entre as que já existem, e no empate a primeira da paleta.
    ///
    /// Gravada, e não tirada de um hash do id: com sete cores e seis abas, o
    /// hash repete cor em quase toda combinação — e duas bancadas da mesma cor
    /// são justamente a confusão que a cor existe para evitar.
    static func pick(used: [WorkbenchColor?]) -> WorkbenchColor {
        let counts = Dictionary(used.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
        return automatic.min { counts[$0, default: 0] < counts[$1, default: 0] } ?? .blue
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

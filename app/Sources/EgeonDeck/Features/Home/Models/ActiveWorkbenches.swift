import Foundation

/// A aba "Ativas" da barra lateral (ADR-082): as bancadas de pé, da que rodou
/// por último para a que rodou há mais tempo, separadas em quem rodou nas
/// últimas 24 horas e quem está parada há mais que isso.
struct ActiveWorkbenches: Equatable {
    var recent: [Int] = []
    var stale: [Int] = []

    static let window: TimeInterval = 24 * 3600

    /// `lastActive` é o último instante com alguma fase do cronômetro andando.
    /// Bancada que nunca rodou vai para o fim das paradas — está de pé, mas
    /// não há o que ordenar nela. Empate pela posição na lista, para a ordem
    /// não pular entre um quadro e outro.
    init(live: Set<Int>, lastActive: [Int: Date], now: Date = Date()) {
        let sorted = live.sorted { a, b in
            switch (lastActive[a], lastActive[b]) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a < b
            }
        }
        for index in sorted {
            if let date = lastActive[index], now.timeIntervalSince(date) < Self.window {
                recent.append(index)
            } else {
                stale.append(index)
            }
        }
    }

    init() {}

    var isEmpty: Bool { recent.isEmpty && stale.isEmpty }
}

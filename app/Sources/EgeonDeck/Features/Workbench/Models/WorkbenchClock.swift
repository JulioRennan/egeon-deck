import Foundation

/// Quanto tempo a bancada passou rodando, esperando você e em erro (ADR-074).
///
/// As três fases são exclusivas e somam o tempo de relógio em que a bancada
/// estava viva e fazendo alguma coisa — com cinco agentes trabalhando juntos,
/// conta um segundo por segundo, não cinco. Parada sem pendência (todos
/// terminaram, ou nem subiram) não conta em nenhuma.
struct WorkbenchClock: Codable, Equatable {
    enum Phase: String, Codable {
        case running
        case waiting
        case failed
    }

    var running: TimeInterval = 0
    var waiting: TimeInterval = 0
    var failed: TimeInterval = 0

    /// O maior passo que um tique soma. O laço roda a cada 0,12s; um buraco
    /// maior é o Mac dormindo ou o app travado, e esse tempo não foi de
    /// trabalho de ninguém.
    static let maxStep: TimeInterval = 2

    /// A fase da bancada pelo estado dos terminais dela. Erro primeiro, depois
    /// você: um agente parado pedindo algo trava a bancada mesmo com outro
    /// trabalhando — é a mesma prioridade da borda (laranja sobre verde).
    static func phase(for summary: ActivitySummary) -> Phase? {
        if summary.failed > 0 { return .failed }
        if summary.attention > 0 { return .waiting }
        if summary.working + summary.background > 0 { return .running }
        return nil
    }

    mutating func add(_ seconds: TimeInterval, to phase: Phase) {
        let step = min(max(0, seconds), Self.maxStep)
        switch phase {
        case .running: running += step
        case .waiting: waiting += step
        case .failed:  failed += step
        }
    }

    subscript(phase: Phase) -> TimeInterval {
        switch phase {
        case .running: return running
        case .waiting: return waiting
        case .failed:  return failed
        }
    }

    /// "00:42", "12:05", "1:05:12" — minuto e segundo sempre, como relógio;
    /// a hora só quando existe.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

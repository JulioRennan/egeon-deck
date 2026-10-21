import Foundation

/// Quanto tempo a bancada passou rodando, esperando você e em erro (ADR-074).
///
/// Cada fase conta um segundo por segundo enquanto houver pelo menos um
/// terminal nela — com cinco agentes trabalhando juntos, um segundo, não cinco.
/// As fases andam juntas: um agente perguntando algo não para o relógio de
/// quem segue trabalhando ao lado (ADR-078). Parada sem pendência (todos
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

    /// As fases em curso pelo estado dos terminais da bancada (ADR-078).
    ///
    /// Esperar você é só pergunta e permissão: quem aguarda um vizinho está em
    /// `background` e conta como trabalho, porque o trabalho seguiu no outro
    /// card. O erro sai das outras duas — o desistido conta em `attention` e a
    /// tentativa agendada em `background`, e nenhum dos dois é você nem trabalho.
    static func phases(for summary: ActivitySummary) -> Set<Phase> {
        var out: Set<Phase> = []
        let gaveUp = summary.failed - summary.retrying
        if summary.failed > 0 { out.insert(.failed) }
        if summary.attention - gaveUp > 0 { out.insert(.waiting) }
        if summary.working + summary.background - summary.retrying > 0 { out.insert(.running) }
        return out
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

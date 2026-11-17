import Foundation

/// O turno que morreu por erro da API, como o gancho `StopFailure` conta
/// (ADR-072).
///
/// Sem isto o agente parava como se tivesse terminado, e a única saída era ir
/// até ele e mandar um "oi". O que se faz com a falha depende do tipo: erro
/// passageiro tenta de novo sozinho; limite de uso também, esperando mais;
/// conta, login e pedido inválido não melhoram repetindo — param e te chamam.
struct ApiFailure: Equatable {
    /// O `error` do payload, como o CLI manda (`overloaded`, `rate_limit`…).
    let error: String
    /// O `error_details`, quando vem — a mensagem que a API deu.
    let detail: String?

    enum Kind: Equatable {
        case transient
        case rateLimit
        /// Repetir não resolve.
        case fatal
    }

    var kind: Kind {
        switch error {
        case "overloaded", "server_error", "unknown": return .transient
        case "rate_limit":                           return .rateLimit
        default:                                     return .fatal
        }
    }

    /// Quanto esperar antes da tentativa `attempt` (1, 2, 3…). `nil` é
    /// desistir: erro sem volta, ou as tentativas acabaram.
    func delay(attempt: Int) -> TimeInterval? {
        let schedule: [TimeInterval]
        switch kind {
        case .transient: schedule = [30, 120, 300]
        // Limite de uso volta em minutos, às vezes horas: tentar a cada 30s só
        // gastaria tentativa.
        case .rateLimit: schedule = [120, 600, 1800]
        case .fatal:     return nil
        }
        guard attempt >= 1, attempt <= schedule.count else { return nil }
        return schedule[attempt - 1]
    }

    static let maxAttempts = 3

    /// Em português, para o card e o chat.
    var label: String {
        switch error {
        case "overloaded":            return "API sobrecarregada"
        case "server_error":          return "erro no servidor da API"
        case "rate_limit":            return "limite de uso"
        case "authentication_failed": return "login falhou"
        case "billing_error":         return "problema de cobrança"
        case "account_on_hold":       return "conta suspensa"
        case "invalid_request":       return "pedido inválido"
        case "model_not_found":       return "modelo não encontrado"
        case "max_output_tokens":     return "resposta passou do limite"
        case "unknown":               return "erro desconhecido"
        default:                      return error
        }
    }

    /// O que vai para o agente na tentativa de novo — o "oi" que você mandava,
    /// dizendo por quê.
    var retryPrompt: String {
        "A última chamada à API falhou (\(label)). Continue de onde parou."
    }

    init(error: String, detail: String? = nil) {
        self.error = error
        self.detail = detail
    }

    /// Lido da query de `/activity?event=failure`: `error` e `detail`.
    init?(query: [String: String]) {
        guard let error = query["error"], !error.isEmpty else { return nil }
        self.init(error: error, detail: query["detail"].flatMap { $0.isEmpty ? nil : $0 })
    }
}

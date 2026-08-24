import Foundation

// MARK: - Um turno de conversa

/// Um passo que o agente deu para responder: comando, edição, leitura.
struct ChatStep: Equatable {
    /// `$` comando · `±` edição · `→` outro uso de ferramenta.
    let glyph: String
    let text: String
}

/// Seu prompt e o que o agente fez com ele. O contrato é genérico: quem sabe
/// ler o arquivo do CLI é o `TranscriptReader` do agente.
struct ChatTurn: Equatable {
    /// Identidade do turno — o `uuid` que o CLI grava na linha do prompt. Dois
    /// "oi" seguidos são dois turnos; texto e hora não bastam para separá-los.
    let id: String
    let prompt: String
    let promptAt: Date
    var steps: [ChatStep] = []
    var replyText = ""
    var replyAt: Date?

    var hasReply: Bool { !replyText.isEmpty || !steps.isEmpty }
}

protocol TranscriptReader {
    func turns(at url: URL) -> [ChatTurn]
}

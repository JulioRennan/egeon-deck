import Foundation

// MARK: - Um turno de conversa

/// Um passo que o agente deu para responder: comando, edição, leitura, envio.
struct ChatStep: Equatable {
    /// `$` comando · `±` edição · `→` outro uso de ferramenta · `⇄` egeon send.
    let glyph: String
    let text: String
    /// Endereço `bancada/id` quando o passo foi um `egeon send` — é por ele que
    /// a resposta do outro agente encontra a bolha de quem perguntou.
    var sendTo: String? = nil
}

/// Uma mensagem trocada entre agentes, já achatada para caber na bolha de quem
/// começou: quem mandou, para quem, o texto e o que o destino fez com ela.
struct ChatExchange: Equatable {
    let fromId: String
    let toId: String
    let text: String
    let at: Date
    let steps: Int
    /// O que o destino escreveu no próprio terminal ao atender — nota, não
    /// mensagem: a mensagem de volta, se houver, é outro `ChatExchange`.
    let note: String
}

/// Seu prompt e o que o agente fez com ele. O contrato é genérico: quem sabe
/// ler o arquivo do CLI é o `TranscriptReader` do agente.
struct ChatTurn: Equatable {
    /// Identidade do turno — o `uuid` que o CLI grava na linha do prompt. Dois
    /// "oi" seguidos são dois turnos; texto e hora não bastam para separá-los.
    let id: String
    let prompt: String
    let promptAt: Date
    /// Endereço do agente que mandou o prompt, quando não foi você. Turno assim
    /// é sub-conversa: vive dentro da bolha de quem começou, não no topo.
    var from: String? = nil
    var steps: [ChatStep] = []
    var replyText = ""
    var replyAt: Date?
    /// A cadeia agente↔agente que este turno disparou, em ordem de tempo.
    var exchanges: [ChatExchange] = []

    var hasReply: Bool { !replyText.isEmpty || !steps.isEmpty || !exchanges.isEmpty }
}

protocol TranscriptReader {
    func turns(at url: URL) -> [ChatTurn]
}

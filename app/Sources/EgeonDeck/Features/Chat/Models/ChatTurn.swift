import Foundation

// MARK: - Um turno de conversa

/// Um passo que o agente deu para responder: comando, edição, leitura, envio —
/// e o que voltou dele. É o que o terminal mostra, peneirado: a linha do
/// passo, o comando por extenso, o diff da edição, a saída com teto (ADR-039).
struct ChatStep: Equatable, Codable {
    /// `$` comando · `±` edição · `→` outro uso de ferramenta · `⇄` egeon send.
    let glyph: String
    let text: String
    /// Endereço `bancada/id` quando o passo foi um `egeon send` — é por ele que
    /// a resposta do outro agente encontra a bolha de quem perguntou.
    var sendTo: String? = nil
    /// O `tool_use_id` do CLI: é por ele que o resultado encontra o passo.
    var toolId: String? = nil
    /// O comando por extenso (Bash), ou a entrada compacta de outra ferramenta.
    var detail: String? = nil
    /// Linhas do patch, no formato do diff unificado (` `, `-`, `+`), com teto.
    var diff: [String]? = nil
    /// Prévia da saída, com teto de linhas e bytes; a última linha avisa quanto
    /// ficou de fora.
    var output: String? = nil
    var isError: Bool = false

    init(glyph: String, text: String, sendTo: String? = nil, toolId: String? = nil,
         detail: String? = nil, diff: [String]? = nil, output: String? = nil,
         isError: Bool = false) {
        self.glyph = glyph
        self.text = text
        self.sendTo = sendTo
        self.toolId = toolId
        self.detail = detail
        self.diff = diff
        self.output = output
        self.isError = isError
    }

    /// Tolerante ao que falta: os campos do passo inteiro nasceram depois do
    /// histórico, e as linhas antigas só têm `glyph`, `text` e `sendTo`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        glyph = try c.decodeIfPresent(String.self, forKey: .glyph) ?? "→"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        sendTo = try c.decodeIfPresent(String.self, forKey: .sendTo)
        toolId = try c.decodeIfPresent(String.self, forKey: .toolId)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        diff = try c.decodeIfPresent([String].self, forKey: .diff)
        output = try c.decodeIfPresent(String.self, forKey: .output)
        isError = try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
    }

    /// Tetos do que vai para o histórico: sem eles o `chat.jsonl` viraria o
    /// transcript de novo, e a ADR-037 existe para ele não virar.
    static let maxOutputLines = 40
    static let maxOutputBytes = 2048
    static let maxDiffLines = 200

    /// `+a −b` do diff, para o cabeçalho do grupo.
    var diffCounts: (added: Int, removed: Int)? {
        guard let diff, !diff.isEmpty else { return nil }
        return (diff.filter { $0.hasPrefix("+") }.count, diff.filter { $0.hasPrefix("-") }.count)
    }

    /// Corta por linhas E por bytes, e diz o que cortou. Saída de ferramenta
    /// chega a dezenas de KB numa linha só (JSON, base64): só o teto de linhas
    /// não segura.
    static func capped(_ text: String, lines maxLines: Int = maxOutputLines,
                       bytes maxBytes: Int = maxOutputBytes) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var note: String?
        if lines.count > maxLines {
            note = "… +\(lines.count - maxLines) linhas"
            lines = Array(lines.prefix(maxLines))
        }
        var out = lines.joined(separator: "\n")
        if out.utf8.count > maxBytes {
            var cut = String(decoding: Array(out.utf8.prefix(maxBytes)), as: UTF8.self)
            if let last = cut.lastIndex(of: "\n"), cut.distance(from: last, to: cut.endIndex) < 200 {
                cut = String(cut[..<last])
            }
            out = cut
            note = "… \(text.utf8.count) bytes ao todo"
        }
        if let note { out += "\n" + note }
        return out
    }
}

/// Um elo da cadeia do turno, na ordem em que o agente o produziu: um
/// parágrafo de prosa ou um passo. É a cadeia que a bolha desenha —
/// "vou olhar X", três comandos, "achei", uma edição, a resposta — e não
/// "todos os passos, depois todo o texto" (ADR-039).
enum ChatPart: Equatable, Codable {
    case text(String)
    case step(ChatStep)

    private enum CodingKeys: String, CodingKey { case kind, text, step, glyph, sendTo }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        // Tipo que não existe mais (a "troca" achatada da sub-conversa, que
        // nunca foi gravada) cai em prosa vazia, e o turno a descarta.
        switch try c.decode(String.self, forKey: .kind) {
        case "step":
            if let step = try c.decodeIfPresent(ChatStep.self, forKey: .step) {
                self = .step(step)
            } else {
                self = .step(ChatStep(glyph: try c.decodeIfPresent(String.self, forKey: .glyph) ?? "→",
                                      text: text,
                                      sendTo: try c.decodeIfPresent(String.self, forKey: .sendTo)))
            }
        default:
            self = .text(text)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try c.encode("text", forKey: .kind)
            try c.encode(text, forKey: .text)
        case .step(let step):
            try c.encode("step", forKey: .kind)
            try c.encode(step, forKey: .step)
        }
    }
}

/// Seu prompt e o que o agente fez com ele. O contrato é genérico: quem sabe
/// ler o arquivo do CLI é o leitor do perfil (`ClaudeTranscript.lastTurn`);
/// daí em diante o turno é do app, gravado no histórico (ADR-037).
struct ChatTurn: Equatable, Codable {
    /// Identidade do turno — o `uuid` que o CLI grava na linha do prompt. Dois
    /// "oi" seguidos são dois turnos; texto e hora não bastam para separá-los.
    let id: String
    let prompt: String
    let promptAt: Date
    /// Endereço do agente que mandou o prompt, quando não foi você. A bolha
    /// dele fica no topo como qualquer outra, com quem mandou em cima (ADR-042).
    var from: String? = nil
    var steps: [ChatStep] = []
    var replyText = ""
    var replyAt: Date?
    /// Prosa e passos na ordem em que saíram. `steps` e `replyText` continuam
    /// existindo — são as somas que a citação e o histórico antigo
    /// usam; a bolha desenha por aqui.
    var parts: [ChatPart] = []

    init(id: String, prompt: String, promptAt: Date, from: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.promptAt = promptAt
        self.from = from
    }

    var hasReply: Bool { !replyText.isEmpty || !steps.isEmpty }

    /// A cadeia para desenhar. Registro gravado antes da cadeia existir não tem
    /// `parts`: reconstrói na forma antiga — passos, depois o texto.
    var chain: [ChatPart] {
        if !parts.isEmpty { return parts }
        var out = steps.map(ChatPart.step)
        if !replyText.isEmpty { out.append(.text(replyText)) }
        return out
    }

    /// O último bloco de prosa da cadeia — o que está sendo dito agora.
    var lastText: String? {
        for part in chain.reversed() { if case .text(let text) = part { return text } }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, prompt, promptAt, from, steps, replyText, replyAt, parts
    }

    /// Tolerante ao que falta: `parts` nasceu depois do histórico (ADR-039), e
    /// as linhas antigas do `chat.jsonl` não a têm.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        prompt = try c.decode(String.self, forKey: .prompt)
        promptAt = try c.decode(Date.self, forKey: .promptAt)
        from = try c.decodeIfPresent(String.self, forKey: .from)
        steps = try c.decodeIfPresent([ChatStep].self, forKey: .steps) ?? []
        replyText = try c.decodeIfPresent(String.self, forKey: .replyText) ?? ""
        replyAt = try c.decodeIfPresent(Date.self, forKey: .replyAt)
        // Chave `exchanges` de arquivo antigo é ignorada; elo de tipo extinto
        // decodifica como prosa vazia e sai aqui.
        parts = (try c.decodeIfPresent([ChatPart].self, forKey: .parts) ?? [])
            .filter { if case .text("") = $0 { return false } else { return true } }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(promptAt, forKey: .promptAt)
        try c.encodeIfPresent(from, forKey: .from)
        try c.encode(steps, forKey: .steps)
        try c.encode(replyText, forKey: .replyText)
        try c.encodeIfPresent(replyAt, forKey: .replyAt)
        try c.encode(parts, forKey: .parts)
    }
}

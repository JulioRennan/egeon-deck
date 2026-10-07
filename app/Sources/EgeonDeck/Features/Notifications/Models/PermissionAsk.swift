import Foundation

/// Um pedido de permissão do CLI, aberto enquanto o diálogo dele está na tela
/// (ADR-068).
///
/// Vem do gancho `PermissionRequest`, que dispara quando o diálogo vai ser
/// mostrado — depois das regras e do classificador do modo auto, então só
/// chega aqui o que de fato iria perguntar a você.
struct PermissionAsk: Equatable {
    let id: String
    /// `bancada/id` do terminal que pediu.
    let address: String
    let tool: String
    /// Uma linha: o comando, o arquivo, a URL — o que se aprova.
    let summary: String
    /// A descrição que o próprio agente deu, quando deu.
    let detail: String?
    /// As regras que o CLI ofereceria no "sim, e não pergunte mais", cruas,
    /// para voltar a ele do jeito que vieram.
    let suggestions: [[String: Any]]
    /// O `tool_input` cru: a resposta de uma pergunta volta nele, com as
    /// escolhas somadas.
    let input: [String: Any]
    let openedAt: Date

    /// Uma pergunta do `AskUserQuestion`. Ela passa pelo mesmo gancho que a
    /// permissão — medido —, e respondê-la é permitir a ferramenta com as
    /// respostas dentro.
    struct Question: Equatable {
        let question: String
        let header: String?
        let options: [String]
        let multiSelect: Bool
    }

    var questions: [Question] {
        guard tool == "AskUserQuestion" else { return [] }
        return (input["questions"] as? [[String: Any]] ?? []).compactMap { raw in
            guard let question = raw["question"] as? String else { return nil }
            let options = (raw["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            return Question(question: question, header: raw["header"] as? String,
                            options: options, multiSelect: raw["multiSelect"] as? Bool ?? false)
        }
    }

    var canAlwaysAllow: Bool { !suggestions.isEmpty }

    init(id: String, address: String, tool: String, summary: String, detail: String? = nil,
         suggestions: [[String: Any]] = [], input: [String: Any] = [:], openedAt: Date = Date()) {
        self.id = id
        self.address = address
        self.tool = tool
        self.summary = summary
        self.detail = detail
        self.suggestions = suggestions
        self.input = input
        self.openedAt = openedAt
    }

    /// Montado do payload do gancho. `nil` sem `tool_name`.
    ///
    /// Das sugestões fica fora o `setMode`: ele troca o modo da sessão inteira
    /// ("aceitar edições", "modo auto"), e "sempre permitir isto" não pode
    /// virar "permitir tudo" sem você ler.
    init?(id: String, address: String, payload: [String: Any], openedAt: Date = Date()) {
        guard let tool = payload["tool_name"] as? String, !tool.isEmpty else { return nil }
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let suggestions = (payload["permission_suggestions"] as? [[String: Any]] ?? [])
            .filter { ($0["type"] as? String) != "setMode" }
        self.init(id: id, address: address, tool: tool,
                  summary: Self.summary(tool: tool, input: input),
                  detail: (input["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                  suggestions: suggestions, input: input, openedAt: openedAt)
    }

    /// O campo que diz o que se aprova, por ferramenta; o resto vai como JSON
    /// compacto, cortado.
    static func summary(tool: String, input: [String: Any]) -> String {
        if tool == "AskUserQuestion",
           let first = (input["questions"] as? [[String: Any]])?.first?["question"] as? String {
            return clip(first)
        }
        for key in ["command", "file_path", "notebook_path", "url", "pattern", "path", "query"] {
            if let value = input[key] as? String, !value.isEmpty { return clip(value) }
        }
        guard !input.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return tool }
        return clip(text)
    }

    private static func clip(_ text: String, limit: Int = 600) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    static func == (a: PermissionAsk, b: PermissionAsk) -> Bool {
        a.id == b.id && a.address == b.address && a.tool == b.tool && a.summary == b.summary
            && a.detail == b.detail && a.suggestions.count == b.suggestions.count
            && a.questions == b.questions
    }

    /// A saída que responde as perguntas: a ferramenta permitida, com o
    /// `tool_input` original e as escolhas em `answers`, pela pergunta. Mais de
    /// uma escolha (multiSelect) vai separada por vírgula, como o CLI grava.
    func answerOutput(_ choices: [String: [String]]) -> [String: Any] {
        var updated = input
        updated["answers"] = choices.mapValues { $0.joined(separator: ", ") }
        return ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                       "decision": ["behavior": "allow", "updatedInput": updated]]]
    }

    /// Toda pergunta tem pelo menos uma escolha, e só entre as opções dela.
    func accepts(_ choices: [String: [String]]) -> Bool {
        let questions = self.questions
        guard !questions.isEmpty else { return false }
        return questions.allSatisfy { q in
            guard let picked = choices[q.question], !picked.isEmpty else { return false }
            return (q.multiSelect || picked.count == 1) && picked.allSatisfy(q.options.contains)
        }
    }
}

/// O que você respondeu.
enum PermissionAnswer: String {
    case allow
    /// Permite e grava as regras que o CLI sugeriu.
    case always
    case deny

    /// A saída do gancho, como o Claude Code lê em
    /// `hookSpecificOutput.decision`. "Sempre" sem sugestão é só "permitir".
    func hookOutput(suggestions: [[String: Any]]) -> [String: Any] {
        var decision: [String: Any]
        switch self {
        case .allow:
            decision = ["behavior": "allow"]
        case .always:
            decision = ["behavior": "allow"]
            if !suggestions.isEmpty { decision["updatedPermissions"] = suggestions }
        case .deny:
            decision = ["behavior": "deny", "message": "Negado pelo usuário no Egeon Deck."]
        }
        return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
    }
}

import Foundation

// MARK: - O transcript do Claude Code, como turnos

/// Lê o JSONL que o Claude Code grava por conversa. Uma linha por evento; as
/// que interessam são `user` com texto (seu prompt) e `assistant` (texto e
/// `tool_use`). `tool_result` vem como `user`, e attachment/system/progress
/// são ruído para o chat.
struct ClaudeTranscript: TranscriptReader {
    func turns(at url: URL) -> [ChatTurn] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return Self.parse(text)
    }

    static func parse(_ jsonl: String) -> [ChatTurn] {
        var turns: [ChatTurn] = []
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            // A maior parte do arquivo é attachment e snapshot — linhas enormes
            // que não interessam. Procurar o tipo antes de decodificar JSON é o
            // que faz um transcript de dezenas de MB ser lido em tempo útil.
            // A linha inteira, e não só o começo: `type` vem depois de
            // parentUuid, cwd, sessionId e afins.
            guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\"")
            else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let entry = object as? [String: Any],
                  let type = entry["type"] as? String,
                  let message = entry["message"] as? [String: Any] else { continue }
            let at = (entry["timestamp"] as? String).flatMap(Self.date) ?? Date()

            switch type {
            case "user":
                guard let raw = Self.promptText(message["content"]),
                      entry["isMeta"] as? Bool != true else { continue }
                let id = entry["uuid"] as? String ?? "t-\(at.timeIntervalSince1970)-\(turns.count)"
                let envelope = Self.agentEnvelope(raw)
                turns.append(ChatTurn(id: id, prompt: envelope?.text ?? raw, promptAt: at,
                                      from: envelope?.from))
            case "assistant":
                guard !turns.isEmpty,
                      let blocks = message["content"] as? [[String: Any]] else { continue }
                for block in blocks {
                    switch block["type"] as? String {
                    case "text":
                        let text = Self.strippingMarkers(block["text"] as? String ?? "")
                        guard !text.isEmpty else { continue }
                        turns[turns.count - 1].replyText +=
                            (turns[turns.count - 1].replyText.isEmpty ? "" : "\n\n") + text
                        turns[turns.count - 1].replyAt = at
                    case "tool_use":
                        turns[turns.count - 1].steps.append(Self.step(block))
                        turns[turns.count - 1].replyAt = at
                    default: continue
                    }
                }
            default: continue
            }
        }
        return turns
    }

    /// Prompt seu: string, ou blocos de texto. `tool_result` não é prompt, e
    /// `<command-…>` é comando de barra que a TUI registra como mensagem.
    private static func promptText(_ content: Any?) -> String? {
        var text: String
        if let string = content as? String {
            text = string
        } else if let blocks = content as? [[String: Any]] {
            let parts = blocks.compactMap { block -> String? in
                block["type"] as? String == "text" ? block["text"] as? String : nil
            }
            guard !parts.isEmpty else { return nil }
            text = parts.joined(separator: "\n")
        } else {
            return nil
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("<command-"), !text.hasPrefix("<local-command")
        else { return nil }
        return text
    }

    /// O envelope que o Dispatcher põe em mensagem de outro agente: primeira
    /// linha `[egeon] mensagem de bancada/id`, o texto, e um rodapé fixo de
    /// aviso. Devolve quem mandou e só o texto.
    static func agentEnvelope(_ prompt: String) -> (from: String, text: String)? {
        let header = "[egeon] mensagem de "
        guard prompt.hasPrefix(header) else { return nil }
        var lines = prompt.split(separator: "\n", omittingEmptySubsequences: false)
        let from = String(lines.removeFirst().dropFirst(header.count))
            .trimmingCharacters(in: .whitespaces)
        if let trailer = lines.firstIndex(where: { $0.hasPrefix("Quem escreveu foi outro agente") }) {
            lines = Array(lines[..<trailer])
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (from, text)
    }

    private static func step(_ block: [String: Any]) -> ChatStep {
        let name = block["name"] as? String ?? "?"
        let input = block["input"] as? [String: Any] ?? [:]
        switch name {
        case "Bash":
            let command = input["command"] as? String ?? ""
            if let target = Self.sendTarget(in: command) {
                return ChatStep(glyph: "⇄", text: "egeon send \(target)", sendTo: target)
            }
            return ChatStep(glyph: "$", text: input["description"] as? String
                            ?? (command.isEmpty ? "bash" : command))
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return ChatStep(glyph: "±", text: Self.shortPath(input["file_path"] as? String))
        case "Read":
            return ChatStep(glyph: "→", text: "read \(Self.shortPath(input["file_path"] as? String))")
        default:
            return ChatStep(glyph: "→", text: name)
        }
    }

    /// O endereço num `egeon send <bancada/id>`, se o comando for um.
    static func sendTarget(in command: String) -> String? {
        guard let range = command.range(of: #"egeon\s+send\s+(\S+)"#, options: .regularExpression)
        else { return nil }
        let match = command[range]
        return match.split(separator: " ", omittingEmptySubsequences: true).last.map(String.init)
    }

    private static func shortPath(_ path: String?) -> String {
        guard let path else { return "" }
        let parts = path.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
    }

    /// Como o último turno terminou, lido do transcript e não da tela.
    ///
    /// O gancho `Stop` chega antes de a TUI pintar a última linha, e a tela
    /// ainda mostra o marcador do turno PASSADO — era daí que "terminou" virava
    /// "precisa de você". O transcript já tem a resposta inteira quando o
    /// gancho dispara, então é ele quem diz qual dos dois marcadores fechou o
    /// turno. `nil` quando o agente não escreveu marcador nenhum.
    ///
    /// Só a cauda do arquivo: transcript passa de dezenas de MB, e o que
    /// interessa é a última mensagem do assistente.
    /// O marcador e QUANDO ele foi gravado. O instante importa porque o gancho
    /// `Stop` pode chegar antes de o CLI escrever a linha: sem a data, o
    /// marcador do turno passado passaria pelo deste.
    struct LastMarker: Equatable {
        var marker: HookEvent.Marker?
        var at: Date?
    }

    static func lastMarker(at url: URL, marker: MarkerConfig,
                           tailBytes: Int = 512 * 1024) -> LastMarker? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return lastMarker(in: text, marker: marker)
    }

    static func lastMarker(in jsonl: String, marker: MarkerConfig) -> LastMarker? {
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"type\":\"assistant\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let entry = object as? [String: Any],
                  entry["type"] as? String == "assistant",
                  let message = entry["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { continue }
            // O último bloco de texto do último assistant é onde o marcador
            // mora. Linha de assistant só com tool_use não é fim de turno:
            // segue procurando para cima.
            guard let text = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String
            else { continue }
            let at = (entry["timestamp"] as? String).flatMap(Self.date)
            let ask = text.range(of: marker.ask, options: .backwards)
            let done = text.range(of: marker.done, options: .backwards)
            switch (ask, done) {
            case let (a?, d?): return LastMarker(marker: a.lowerBound > d.lowerBound ? .ask : .ok, at: at)
            case (_?, nil):    return LastMarker(marker: .ask, at: at)
            case (nil, _?):    return LastMarker(marker: .ok, at: at)
            case (nil, nil):   return LastMarker(marker: nil, at: at)
            }
        }
        return nil
    }

    /// Os marcadores do protocolo Egeon (`[[ED:ok]]`, `[[ED:ask]]`) são para o
    /// app, não para você ler na bolha.
    static func strippingMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[\[ED:(ok|ask)\]\]"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()

    private static func date(_ raw: String) -> Date? {
        isoFractional.date(from: raw) ?? iso.date(from: raw)
    }
}

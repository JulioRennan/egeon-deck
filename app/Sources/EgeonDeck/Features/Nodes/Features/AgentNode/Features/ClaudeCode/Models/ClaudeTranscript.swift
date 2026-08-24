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
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let entry = object as? [String: Any],
                  let type = entry["type"] as? String,
                  let message = entry["message"] as? [String: Any] else { continue }
            let at = (entry["timestamp"] as? String).flatMap(Self.date) ?? Date()

            switch type {
            case "user":
                guard let prompt = Self.promptText(message["content"]),
                      entry["isMeta"] as? Bool != true else { continue }
                turns.append(ChatTurn(prompt: prompt, promptAt: at))
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

    private static func step(_ block: [String: Any]) -> ChatStep {
        let name = block["name"] as? String ?? "?"
        let input = block["input"] as? [String: Any] ?? [:]
        switch name {
        case "Bash":
            return ChatStep(glyph: "$", text: input["description"] as? String
                            ?? input["command"] as? String ?? "bash")
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return ChatStep(glyph: "±", text: Self.shortPath(input["file_path"] as? String))
        case "Read":
            return ChatStep(glyph: "→", text: "read \(Self.shortPath(input["file_path"] as? String))")
        default:
            return ChatStep(glyph: "→", text: name)
        }
    }

    private static func shortPath(_ path: String?) -> String {
        guard let path else { return "" }
        let parts = path.split(separator: "/")
        return parts.suffix(2).joined(separator: "/")
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

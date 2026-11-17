import Foundation

/// O consumo que o Claude Code grava no transcript (ADR-085): cada resposta do
/// modelo traz `message.usage`, repetido em toda linha da mesma mensagem —
/// uma por bloco de conteúdo. Conta-se cada `message.id` uma vez.
enum ClaudeUsage {
    private static let assistantMark = Data("\"type\":\"assistant\"".utf8)
    private static let usageMark = Data("\"usage\"".utf8)

    /// `after`: o último id do trecho anterior do mesmo arquivo — a leitura
    /// incremental pode partir no meio das linhas de uma mensagem.
    static func entries(in data: Data, after lastId: String? = nil) -> [UsageEntry] {
        var out: [UsageEntry] = []
        var seen: Set<String> = lastId.map { [$0] } ?? []
        var cursor = data.startIndex
        while cursor < data.endIndex {
            let end = data[cursor...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[cursor..<end]
            cursor = end < data.endIndex ? data.index(after: end) : end
            // Antes do JSON: a maioria das linhas é ferramenta e prompt, e
            // decodificar todas custa caro num transcript de MB.
            guard line.range(of: assistantMark) != nil, line.range(of: usageMark) != nil,
                  let entry = entry(fromLine: line), seen.insert(entry.id).inserted else { continue }
            out.append(entry)
        }
        return out
    }

    static func entry(fromLine line: Data) -> UsageEntry? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any] else { return nil }
        return entry(fromMessage: message)
    }

    static func entry(fromMessage message: [String: Any]) -> UsageEntry? {
        guard let usage = message["usage"] as? [String: Any],
              let id = message["id"] as? String,
              let model = message["model"] as? String,
              // Resposta que o próprio CLI fabrica (erro, interrupção): não
              // passou pelo modelo e vem com uso zero.
              model != "<synthetic>" else { return nil }
        func int(_ key: String, in dict: [String: Any] = usage) -> Int { (dict[key] as? NSNumber)?.intValue ?? 0 }
        var tokens = TokenUsage(input: int("input_tokens"), output: int("output_tokens"),
                                cacheRead: int("cache_read_input_tokens"))
        let written = int("cache_creation_input_tokens")
        if let split = usage["cache_creation"] as? [String: Any] {
            tokens.cacheWrite5m = int("ephemeral_5m_input_tokens", in: split)
            tokens.cacheWrite1h = int("ephemeral_1h_input_tokens", in: split)
            // O que a divisão não explica fica no de 5 minutos, o padrão da API.
            tokens.cacheWrite5m += max(0, written - tokens.cacheWrite)
        } else {
            tokens.cacheWrite5m = written
        }
        return UsageEntry(id: id, model: model, fast: usage["speed"] as? String == "fast", usage: tokens)
    }

    /// Os transcripts de uma conversa: o dela e os dos subagentes, que o CLI
    /// grava em `<sessão>/subagents/` e também são pagos.
    static func files(for transcript: URL) -> [URL] {
        let folder = transcript.deletingPathExtension().appendingPathComponent("subagents")
        let subagents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "jsonl" } ?? []
        return [transcript] + subagents.sorted { $0.path < $1.path }
    }
}

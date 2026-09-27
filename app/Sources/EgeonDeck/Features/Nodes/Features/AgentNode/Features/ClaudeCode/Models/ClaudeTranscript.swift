import Foundation

// MARK: - O transcript do Claude Code, como turnos

/// Lê o JSONL que o Claude Code grava por conversa. Uma linha por evento; as
/// que interessam são `user` com texto (seu prompt) e `assistant` (texto e
/// `tool_use`). `tool_result` vem como `user`, e attachment/system/progress
/// são ruído para o chat.
enum ClaudeTranscript {
    static func parse(_ jsonl: String) -> [ChatTurn] {
        parseDetailed(jsonl).turns
    }

    /// O que o agente estava fazendo quando a leitura parou: o tipo do último
    /// bloco do assistant. `thinking` é raciocínio em curso — vale mostrar
    /// "pensando…", não o conteúdo (ADR-029).
    enum LastBlock: Equatable { case text, tool, thinking }

    static func parseDetailed(_ jsonl: String) -> (turns: [ChatTurn], last: LastBlock?) {
        let scanned = scan(Data(jsonl.utf8))
        return (scanned.turns, scanned.last)
    }

    /// A varredura com onde cada turno começa no arquivo — a leitura ao vivo
    /// parte dali na vez seguinte em vez de reler a cauda inteira.
    struct Scan {
        var turns: [ChatTurn] = []
        var last: LastBlock?
        /// Byte (relativo ao início de `data`) da linha do prompt de cada turno,
        /// na ordem de `turns`.
        var promptOffsets: [Int] = []
    }

    private static let userMark = Data("\"type\":\"user\"".utf8)
    private static let assistantMark = Data("\"type\":\"assistant\"".utf8)

    /// Linha a linha em bytes. Em `String`, `split` e `contains` andam grafema
    /// a grafema: 4 MB de cauda custavam dezenas de ms por leitura, várias
    /// vezes por segundo enquanto o agente trabalha.
    static func scan(_ data: Data) -> Scan {
        var out = Scan()
        var turns: [ChatTurn] = []
        var last: LastBlock?
        var cursor = data.startIndex
        while cursor < data.endIndex {
            let lineEnd = data[cursor...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[cursor..<lineEnd]
            let offset = cursor - data.startIndex
            cursor = lineEnd + 1
            // A maior parte do arquivo é attachment e snapshot — linhas enormes
            // que não interessam. Procurar o tipo antes de decodificar JSON é o
            // que faz um transcript de dezenas de MB ser lido em tempo útil.
            // A linha inteira, e não só o começo: `type` vem depois de
            // parentUuid, cwd, sessionId e afins.
            guard !line.isEmpty,
                  line.range(of: Self.userMark) != nil || line.range(of: Self.assistantMark) != nil
            else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let entry = object as? [String: Any],
                  let type = entry["type"] as? String,
                  let message = entry["message"] as? [String: Any] else { continue }
            let at = (entry["timestamp"] as? String).flatMap(Self.date) ?? Date()

            switch type {
            case "user":
                // Devolução de ferramenta vem como `user`: não é prompt, é o
                // resultado de um passo deste turno — encontra o passo pelo id.
                if let blocks = message["content"] as? [[String: Any]],
                   blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
                    guard !turns.isEmpty else { continue }
                    for block in blocks where block["type"] as? String == "tool_result" {
                        Self.attach(result: block, structured: entry["toolUseResult"],
                                    to: &turns[turns.count - 1])
                    }
                    continue
                }
                guard let raw = Self.promptText(message["content"]),
                      entry["isMeta"] as? Bool != true else { continue }
                let id = entry["uuid"] as? String ?? "t-\(at.timeIntervalSince1970)-\(turns.count)"
                let envelope = Self.agentEnvelope(raw)
                turns.append(ChatTurn(id: id, prompt: envelope?.text ?? raw, promptAt: at,
                                      from: envelope?.from))
                out.promptOffsets.append(offset)
                last = nil
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
                        turns[turns.count - 1].parts.append(.text(text))
                        turns[turns.count - 1].replyAt = at
                        last = .text
                    case "tool_use":
                        let step = Self.step(block)
                        turns[turns.count - 1].steps.append(step)
                        turns[turns.count - 1].parts.append(.step(step))
                        turns[turns.count - 1].replyAt = at
                        last = .tool
                    case "thinking":
                        last = .thinking
                    default: continue
                    }
                }
            default: continue
            }
        }
        out.turns = turns
        out.last = last
        return out
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
    /// linha `[ED] mensagem de bancada/id` e o texto. Devolve quem mandou e
    /// só o texto.
    ///
    /// `[egeon]` é a marca anterior (ADR-055) e continua sendo reconhecida: o
    /// histórico do chat e os transcripts do CLI já gravados têm mensagens com
    /// ela, e deixar de aceitá-la faria a bolha antiga perder o remetente.
    static func agentEnvelope(_ prompt: String) -> (from: String, text: String)? {
        let headers = ["\(DispatchRequest.tag) mensagem de ", "[egeon] mensagem de "]
        guard let header = headers.first(where: prompt.hasPrefix) else { return nil }
        var lines = prompt.split(separator: "\n", omittingEmptySubsequences: false)
        let from = String(lines.removeFirst().dropFirst(header.count))
            .trimmingCharacters(in: .whitespaces)
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (from, text)
    }

    /// O passo como o terminal o mostra: a linha, o comando por extenso, e —
    /// para edição — o diff já na hora do `tool_use`, antes de o resultado
    /// voltar: é o que se quer acompanhar ao vivo.
    private static func step(_ block: [String: Any]) -> ChatStep {
        let name = block["name"] as? String ?? "?"
        let input = block["input"] as? [String: Any] ?? [:]
        let id = block["id"] as? String
        switch name {
        case "Bash":
            let command = input["command"] as? String ?? ""
            if let target = Self.sendTarget(in: command) {
                return ChatStep(glyph: "⇄", text: "egeon send \(target)", sendTo: target, toolId: id,
                                detail: Self.heredocBody(of: command))
            }
            let description = input["description"] as? String
            return ChatStep(glyph: "$", text: description ?? (command.isEmpty ? "bash" : command),
                            toolId: id, detail: description == nil ? nil : command)
        case "Edit":
            return ChatStep(glyph: "±", text: Self.shortPath(input["file_path"] as? String), toolId: id,
                            diff: Self.diff(old: input["old_string"] as? String ?? "",
                                            new: input["new_string"] as? String ?? ""))
        case "MultiEdit":
            let edits = input["edits"] as? [[String: Any]] ?? []
            let lines = edits.flatMap { edit in
                Self.diff(old: edit["old_string"] as? String ?? "", new: edit["new_string"] as? String ?? "") ?? []
            }
            return ChatStep(glyph: "±", text: Self.shortPath(input["file_path"] as? String), toolId: id,
                            diff: Self.cappedDiff(lines))
        case "Write":
            let content = input["content"] as? String ?? ""
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map { "+" + $0 }
            return ChatStep(glyph: "±", text: Self.shortPath(input["file_path"] as? String), toolId: id,
                            diff: Self.cappedDiff(lines))
        case "NotebookEdit":
            return ChatStep(glyph: "±", text: Self.shortPath(input["notebook_path"] as? String), toolId: id)
        case "Read":
            return ChatStep(glyph: "→", text: "read \(Self.shortPath(input["file_path"] as? String))",
                            toolId: id)
        default:
            return ChatStep(glyph: "→", text: name, toolId: id, detail: Self.compactInput(input))
        }
    }

    /// Diff sem LCS: o `old_string` de um Edit é curto e localizado; `-` para o
    /// que saiu, `+` para o que entrou é o que o terminal mostra também. O
    /// `structuredPatch` do resultado, com contexto, substitui isto ao chegar.
    static func diff(old: String, new: String) -> [String]? {
        var lines: [String] = []
        if !old.isEmpty {
            lines += old.split(separator: "\n", omittingEmptySubsequences: false).map { "-" + $0 }
        }
        if !new.isEmpty {
            lines += new.split(separator: "\n", omittingEmptySubsequences: false).map { "+" + $0 }
        }
        return cappedDiff(lines)
    }

    /// Vazio é nil: edição sem texto não tem diff a mostrar.
    private static func cappedDiff(_ lines: [String]) -> [String]? {
        guard !lines.isEmpty else { return nil }
        guard lines.count > ChatStep.maxDiffLines else { return lines }
        return Array(lines.prefix(ChatStep.maxDiffLines)) + ["… +\(lines.count - ChatStep.maxDiffLines) linhas"]
    }

    /// O texto de um `egeon send … <<'MB' … MB`: o que foi dito, sem a moldura.
    private static func heredocBody(of command: String) -> String? {
        let lines = command.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 2 else { return nil }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }

    /// Entrada de ferramenta genérica em uma linha por chave, sem afogar:
    /// `pattern: foo · path: app/` diz o que o Grep procurou.
    private static func compactInput(_ input: [String: Any]) -> String? {
        let pairs = input.keys.sorted().compactMap { key -> String? in
            guard let value = input[key] else { return nil }
            let text: String
            if let string = value as? String { text = string }
            else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
                    let string = String(data: data, encoding: .utf8) { text = string }
            else { text = "\(value)" }
            let oneLine = text.replacingOccurrences(of: "\n", with: " ")
            return "\(key): \(oneLine.count > 160 ? String(oneLine.prefix(160)) + "…" : oneLine)"
        }
        return pairs.isEmpty ? nil : pairs.joined(separator: "\n")
    }

    /// Casa o resultado com o passo pelo `tool_use_id` e guarda a prévia. O
    /// `toolUseResult` estruturado vale mais que o texto: `stdout`/`stderr`
    /// do Bash sem a moldura, o `structuredPatch` do Edit com contexto, o
    /// número de linhas do Read em vez do arquivo inteiro.
    private static func attach(result block: [String: Any], structured: Any?, to turn: inout ChatTurn) {
        guard let id = block["tool_use_id"] as? String,
              let index = turn.parts.lastIndex(where: {
                  if case .step(let step) = $0 { return step.toolId == id } else { return false }
              }),
              case .step(var step) = turn.parts[index] else { return }
        let isError = block["is_error"] as? Bool == true
        var output: String?
        let payload = structured as? [String: Any]
        if let payload, let patch = payload["structuredPatch"] as? [[String: Any]], !patch.isEmpty {
            // Com o cabeçalho `@@` de cada trecho: é dele que a vista lado a
            // lado tira o número de linha de cada versão.
            let lines = patch.flatMap { hunk -> [String] in
                let header = DiffHunk.header(oldStart: hunk["oldStart"] as? Int ?? 0,
                                             oldLines: hunk["oldLines"] as? Int ?? 0,
                                             newStart: hunk["newStart"] as? Int ?? 0,
                                             newLines: hunk["newLines"] as? Int ?? 0)
                return [header] + (hunk["lines"] as? [String] ?? [])
            }
            step.diff = cappedDiff(lines) ?? step.diff
        }
        if let payload, let file = payload["file"] as? [String: Any], let n = file["numLines"] as? Int {
            // O que foi lido, e não só "119 linhas": recolhido o passo mostra a
            // conta, aberto mostra o texto realçado pela extensão do arquivo
            // (ADR-044/046). O teto do `capped` é o que impede o arquivo
            // inteiro de virar histórico.
            let total = (file["totalLines"] as? Int).map { $0 > n ? " de \($0)" : "" } ?? ""
            let content = (file["content"] as? String) ?? ""
            output = content.isEmpty ? "\(n) linha\(n == 1 ? "" : "s")\(total)" : content
        } else if let payload, payload["stdout"] != nil || payload["stderr"] != nil {
            let out = (payload["stdout"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let err = (payload["stderr"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            output = [out, err].filter { !$0.isEmpty }.joined(separator: "\n")
        } else if step.glyph == "±" {
            output = nil
        } else if let text = block["content"] as? String {
            output = text
        } else if let blocks = block["content"] as? [[String: Any]] {
            let texts = blocks.compactMap { b -> String? in
                switch b["type"] as? String {
                case "text": return b["text"] as? String
                case "image": return "[imagem]"
                default: return nil
                }
            }
            output = texts.joined(separator: "\n")
        }
        if isError, output == nil || output?.isEmpty == true, let text = block["content"] as? String {
            output = text
        }
        step.output = output.map { ChatStep.capped($0) }.flatMap { $0.isEmpty ? nil : $0 }
        step.isError = isError
        turn.parts[index] = .step(step)
        if let stepIndex = turn.steps.lastIndex(where: { $0.toolId == id }) { turn.steps[stepIndex] = step }
    }

    /// O endereço num `egeon send <bancada/id>`, se o comando for um.
    static func sendTarget(in command: String) -> String? {
        // Só espaço e tab entre as palavras, e o alvo sem `<`: num heredoc
        // torto, `send\nMB` e `send <<'MB'` passavam por endereço.
        guard let regex = try? NSRegularExpression(pattern: #"egeon[ \t]+send[ \t]+([^\s<]+)"#),
              let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let range = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[range])
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
        guard let text = tail(of: url, bytes: tailBytes) else { return nil }
        return lastMarker(in: text, marker: marker)
    }

    /// O último turno inteiro — prompt, passos, resposta — para o histórico do
    /// chat (ADR-037).
    ///
    /// Cauda maior que a do marcador: um turno com muitas ferramentas passa
    /// fácil de 512 KB, e o prompt dele ficaria de fora. E a cauda pode cortar
    /// justamente a linha do prompt — aí o parse devolve o turno ANTERIOR
    /// inteiro, que parece certo. `notBefore` é o instante do `prompt` deste
    /// turno: turno mais velho que isso não é ele, e o arquivo é lido inteiro.
    static func lastTurn(at url: URL, notBefore: Date? = nil,
                         tailBytes: Int = 2 * 1024 * 1024) -> ChatTurn? {
        guard let text = tail(of: url, bytes: tailBytes) else { return nil }
        if let turn = parse(text).last, notBefore.map({ turn.promptAt >= $0 }) ?? true {
            return turn
        }
        guard let whole = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(whole).last
    }

    /// O turno EM CURSO, para a bolha ao vivo (ADR-039): a cadeia até onde o
    /// CLI já gravou, e o que ele estava fazendo no fim dela.
    ///
    /// Diferente de `lastTurn`, não cai para o arquivo inteiro: isto roda a
    /// cada mudança do transcript durante o turno, e um transcript de dezenas
    /// de MB relido a cada segundo pesaria. Turno mais velho que o `prompt`
    /// deste (a cauda cortou a linha do prompt, ou a linha ainda não foi
    /// gravada) devolve nil, e a bolha fica em "trabalhando…".
    struct LiveTurn: Equatable {
        var turn: ChatTurn
        var last: LastBlock?
        /// Byte do arquivo onde a linha do prompt deste turno começa. A
        /// leitura seguinte parte daqui (`from:`): só o turno em curso é
        /// relido, não os 4 MB de turnos velhos atrás dele.
        var promptOffset: UInt64 = 0
    }

    static func liveTurn(at url: URL, notBefore: Date?, from offset: UInt64 = 0,
                         tailBytes: Int = 4 * 1024 * 1024) -> LiveTurn? {
        guard var read = read(url, from: offset, tailBytes: tailBytes) else { return nil }
        var scanned = scan(read.data)
        // Offset de uma conversa que já não existe (arquivo trocado ou
        // encolhido): sem turno a partir dele, volta à cauda.
        if scanned.turns.isEmpty, offset > 0, let again = Self.read(url, from: 0, tailBytes: tailBytes) {
            read = again
            scanned = scan(read.data)
        }
        guard let turn = scanned.turns.last, let promptOffset = scanned.promptOffsets.last
        else { return nil }
        // Folga porque o gancho `prompt` e a linha do prompt nascem no mesmo
        // segundo, em ordem que não se controla.
        if let notBefore, turn.promptAt < notBefore.addingTimeInterval(-5) { return nil }
        return LiveTurn(turn: turn, last: scanned.last,
                        promptOffset: read.base + UInt64(promptOffset))
    }

    /// Do byte `offset` ao fim — é o turno em curso, do tamanho que for. Sem
    /// offset (ou com um que passou do fim do arquivo), só a cauda.
    private static func read(_ url: URL, from offset: UInt64,
                             tailBytes: Int) -> (data: Data, base: UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let tailStart = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        let start = offset > 0 && offset <= size ? offset : tailStart
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return (data, start)
    }

    private static func tail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .utf8)
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
            return LastMarker(marker: marker.latest(in: text), at: at)
        }
        return nil
    }

    /// O modelo que respondeu por último, pelo nome completo que o CLI grava
    /// (`claude-fable-5`). É a única fonte literal: o apelido pedido na flag
    /// (`sonnet`) não diz qual versão o CLI resolveu, e `padrão` não diz nada.
    /// `<synthetic>` é resposta fabricada pela TUI, não modelo — pula.
    static func lastModel(at url: URL, tailBytes: Int = 256 * 1024) -> String? {
        guard let text = tail(of: url, bytes: tailBytes) else { return nil }
        return lastModel(in: text)
    }

    static func lastModel(in jsonl: String) -> String? {
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard line.contains("\"type\":\"assistant\""),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let entry = object as? [String: Any],
                  entry["type"] as? String == "assistant",
                  let message = entry["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  !model.isEmpty, !model.hasPrefix("<") else { continue }
            return model
        }
        return nil
    }

    /// Os marcadores do protocolo Egeon (`[[ED:ok]]`, `[[ED:ask]]`) são para o
    /// app, não para você ler na bolha.
    static func strippingMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[\[ED:(ok|ask|wait)\]\]"#, with: "",
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

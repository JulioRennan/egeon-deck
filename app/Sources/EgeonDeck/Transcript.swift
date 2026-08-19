import Foundation

// MARK: - O que uma mensagem carrega

/// Uma linha de diff: `+`, `-` ou espaço para contexto.
struct DiffLine {
    let mark: Character
    let text: String
}

/// Um arquivo que o agente mexeu, do jeito que dá para ler sem abrir o editor.
struct EditBlock {
    let file: String
    let add: Int
    let del: Int
    let lines: [DiffLine]
}

/// Os pedaços de uma mensagem de agente, na ordem em que ele produziu.
enum ChatBlock {
    /// Prosa: o que ele te disse.
    case prose(String)
    /// Comando ou trecho de código, em fonte fixa.
    case code(String)
    /// Arquivo editado, com o diff.
    case edit(EditBlock)
    /// Ferramenta que não rende bloco — uma linha e pronto ("leu Canvas.swift").
    case tool(String)
}

/// Uma entrada do thread.
///
/// `id` é o uuid do transcript, e é por ele que a view sabe o que já desenhou:
/// o thread é remontado a cada leitura, e sem identidade estável a rolagem
/// pularia a cada turno novo.
struct ChatEntry {
    enum Kind {
        /// Fato do app: terminal subiu, processo morreu, gancho relatou.
        case system
        /// Você falando com um agente.
        case user
        /// O agente respondendo.
        case agent
        /// Um agente acionando outro — o envelope `[egeon] mensagem de X`.
        case link
        /// O CLI pedindo permissão. Só o card; responder é no terminal.
        case approval
    }

    var id: String
    var kind: Kind
    /// Nó que produziu — id curto, sem o nome da sessão. Nil em `.user`.
    var author: String?
    /// Nó que recebeu. Preenchido em `.user` e em `.link`.
    var recipients: [String] = []
    var at: Date
    var text: String = ""
    var blocks: [ChatBlock] = []
    /// Fato ruim: processo caiu, comando saiu diferente de zero.
    var alert = false

    var timeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: at)
    }
}

// MARK: - Leitura do transcript do CLI

/// Lê o JSONL que o CLI grava e devolve mensagens.
///
/// É a única fonte do thread, e é de propósito. A tela do terminal não serve —
/// ela é TUI e mente de dois jeitos já medidos (ADR-011). O transcript é o que o
/// CLI de fato registrou, tem timestamp de verdade, distingue prosa de chamada
/// de ferramenta, e **sobrevive a fechar o app**: o thread volta inteiro no
/// arranque seguinte sem o app ter de guardar nada.
///
/// O caminho vem do gancho, que recebe `transcript_path` no payload. Não é
/// derivado de `sessionId` + convenção de pasta: isso amarraria o app ao
/// `CLAUDE_CONFIG_DIR` do usuário, que não é assunto dele.
final class TranscriptReader {
    private let url: URL
    /// Até onde já foi lido. Turno novo são bytes no fim do arquivo — reler o
    /// arquivo inteiro a cada 0,5s num transcript de 20 MB trava a UI.
    private var offset: UInt64 = 0
    private var entries: [ChatEntry] = []
    /// Sobra de uma leitura que pegou o arquivo no meio de uma linha.
    private var pending = Data()

    /// Um transcript de conversa longa passa de 20 MB. Abrir o modo Chat não
    /// pode custar isso — o que interessa é o fim da conversa.
    private static let tailLimit: UInt64 = 512 * 1024

    init(url: URL) { self.url = url }

    /// O que o transcript tem, do fim para trás, até o teto de cauda.
    ///
    /// Chamado pelo laço do modo Chat. Devolve tudo o que já foi lido, não só o
    /// novo: quem monta o thread junta vários transcripts e precisa da lista
    /// inteira para ordenar por tempo.
    func read(author: String) -> [ChatEntry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return entries }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0

        // Arquivo encolheu: só acontece se a conversa foi trocada por baixo dos
        // panos. Recomeça, senão o offset antigo cai no meio de uma linha nova.
        if size < offset { offset = 0; entries = []; pending = Data() }

        // Primeira leitura de um arquivo grande começa pela cauda. A linha
        // partida do começo é descartada abaixo, no split.
        if offset == 0, size > Self.tailLimit { offset = size - Self.tailLimit }

        guard size > offset else { return entries }
        try? handle.seek(toOffset: offset)
        guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return entries }
        offset = size

        var buffer = pending + chunk
        pending = Data()
        // Sem \n no fim, a última linha ainda está sendo escrita: guardar para a
        // próxima leitura, senão ela entra truncada e o JSON não parseia.
        if buffer.last != 0x0A {
            if let cut = buffer.lastIndex(of: 0x0A) {
                pending = Data(buffer[buffer.index(after: cut)...])
                buffer = Data(buffer[..<cut])
            } else {
                pending = buffer
                return entries
            }
        }

        // A primeira linha da primeira leitura pode estar cortada pela cauda. Ela
        // cai sozinha no parse do JSON, sem precisar de caso especial.
        for line in buffer.split(separator: 0x0A) {
            guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }
            entries.append(contentsOf: Self.parse(entry, author: author))
        }
        return entries
    }

    // MARK: Uma linha do JSONL

    private static func parse(_ raw: [String: Any], author: String) -> [ChatEntry] {
        // Sidechain é subagente. O thread é a conversa da sessão, e o trabalho
        // interno de um subagente ali é ruído que abafa o que você precisa ler.
        if raw["isSidechain"] as? Bool == true { return [] }
        guard let at = date(raw["timestamp"]) else { return [] }
        let uuid = raw["uuid"] as? String ?? UUID().uuidString
        guard let message = raw["message"] as? [String: Any] else { return [] }

        switch raw["type"] as? String {
        case "user":   return [userEntry(message, id: uuid, at: at, author: author)].compactMap { $0 }
        case "assistant": return assistantEntries(message, id: uuid, at: at, author: author)
        default: return []
        }
    }

    /// Uma entrada `user` do transcript é uma de quatro coisas, e só duas viram
    /// mensagem.
    ///
    /// `content` em array é devolução de ferramenta — resultado de `Bash`, de
    /// `Read` —, e não é ninguém falando. `content` em texto pode ser: você
    /// digitando, um dispatch do app, o envelope de outro agente, ou o eco de um
    /// comando de barra da TUI, que é interface e não conversa.
    private static func userEntry(_ message: [String: Any], id: String, at: Date,
                                  author: String) -> ChatEntry? {
        guard let text = message["content"] as? String else { return nil }
        let clean = strip(text)
        guard !clean.isEmpty else { return nil }

        // Eco de comando de barra e aviso de comando local: a TUI escreve isso no
        // transcript, mas não é mensagem de ninguém.
        if clean.hasPrefix("<command-name>") || clean.hasPrefix("<local-command")
            || clean.hasPrefix("<command-message>") { return nil }

        // Envelope de agente para agente. O prefixo é montado pelo app em
        // `DispatchRequest.agentEnvelope`, então é ele quem diz quem falou — o
        // texto não é palavra do agente sobre a própria identidade.
        if let sender = envelopeSender(clean) {
            return ChatEntry(id: id, kind: .link, author: sender, recipients: [author],
                             at: at, text: envelopeBody(clean))
        }

        return ChatEntry(id: id, kind: .user, recipients: [author], at: at,
                         text: dispatchBody(clean))
    }

    private static func assistantEntries(_ message: [String: Any], id: String, at: Date,
                                         author: String) -> [ChatEntry] {
        guard let content = message["content"] as? [[String: Any]] else { return [] }
        var blocks: [ChatBlock] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                let text = (block["text"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Marcador de protocolo é conversa do app com o app.
                let visible = text.replacingOccurrences(
                    of: "\\[\\[ED:(ok|ask)\\]\\]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !visible.isEmpty { blocks.append(.prose(visible)) }
            // Raciocínio não entra: é rascunho, é longo, e não foi dito a você.
            case "thinking": continue
            case "tool_use":
                if let block = toolBlock(block) { blocks.append(block) }
            default: continue
            }
        }
        guard !blocks.isEmpty else { return [] }
        return [ChatEntry(id: id, kind: .agent, author: author, at: at, blocks: blocks)]
    }

    // MARK: Ferramenta virando bloco

    /// O que cada ferramenta rende na tela.
    ///
    /// Edit e Write viram diff, porque é o que você quer conferir sem abrir o
    /// arquivo. Bash vira o comando. O resto vira uma linha: saber que ele leu
    /// `Canvas.swift` basta, e despejar o arquivo lido enterraria a resposta.
    private static func toolBlock(_ block: [String: Any]) -> ChatBlock? {
        let name = block["name"] as? String ?? "?"
        let input = block["input"] as? [String: Any] ?? [:]

        switch name {
        case "Edit":
            guard let file = input["file_path"] as? String else { return .tool("editou") }
            return .edit(diff(file: file,
                              old: input["old_string"] as? String ?? "",
                              new: input["new_string"] as? String ?? ""))

        case "Write":
            guard let file = input["file_path"] as? String else { return .tool("escreveu") }
            let body = input["content"] as? String ?? ""
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            return .edit(EditBlock(file: short(file), add: lines.count, del: 0,
                                   lines: cap(lines.map { DiffLine(mark: "+", text: String($0)) })))

        case "Bash":
            let command = input["command"] as? String ?? ""
            return command.isEmpty ? .tool("rodou um comando") : .code("$ " + command)

        case "Read":   return .tool("leu " + short(input["file_path"] as? String ?? ""))
        case "Grep":   return .tool("buscou " + (input["pattern"] as? String ?? ""))
        case "Glob":   return .tool("listou " + (input["pattern"] as? String ?? ""))
        case "TodoWrite", "ExitPlanMode": return nil
        default:       return .tool("usou " + name)
        }
    }

    /// Diff de um `Edit`, com as linhas iguais nas pontas viradas contexto.
    ///
    /// Não é LCS: o `Edit` já entrega o antes e o depois de um trecho pequeno, e
    /// o que falta para ler é só onde ele começa. Casar prefixo e sufixo dá isso
    /// por dois laços, e erra para o lado seguro — mostra mais linha marcada do
    /// que o mínimo, nunca menos.
    private static func diff(file: String, old: String, new: String) -> EditBlock {
        let before = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let after = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var head = 0
        while head < before.count, head < after.count, before[head] == after[head] { head += 1 }
        var tail = 0
        while tail < before.count - head, tail < after.count - head,
              before[before.count - 1 - tail] == after[after.count - 1 - tail] { tail += 1 }

        let removed = Array(before[head..<(before.count - tail)])
        let added = Array(after[head..<(after.count - tail)])

        var lines: [DiffLine] = []
        // Uma linha de contexto de cada lado: é o que situa o trecho sem virar
        // um arquivo inteiro na tela.
        if head > 0 { lines.append(DiffLine(mark: " ", text: before[head - 1])) }
        lines += removed.map { DiffLine(mark: "-", text: $0) }
        lines += added.map { DiffLine(mark: "+", text: $0) }
        if tail > 0 { lines.append(DiffLine(mark: " ", text: before[before.count - tail])) }

        return EditBlock(file: short(file), add: added.count, del: removed.count,
                         lines: cap(lines))
    }

    /// Teto de linhas por bloco. Diff de 400 linhas empurra a conversa para fora
    /// da tela, e o que você lê no chat é o resumo — o arquivo está no editor.
    private static let maxLines = 24

    private static func cap(_ lines: [DiffLine]) -> [DiffLine] {
        guard lines.count > maxLines else { return lines }
        return Array(lines.prefix(maxLines))
            + [DiffLine(mark: " ", text: "… \(lines.count - maxLines) linhas a mais")]
    }

    // MARK: Texto

    /// Tira do texto o que o app e o CLI enfiaram nele.
    ///
    /// `system-reminder` é injeção de contexto, e num prompt seu ele é maior que
    /// a mensagem — deixá-lo faria o thread virar despejo de configuração.
    private static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: "<system-reminder>[\\s\\S]*?</system-reminder>",
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Quem mandou, quando a mensagem é envelope de agente.
    private static func envelopeSender(_ text: String) -> String? {
        let header = "[egeon] mensagem de "
        guard text.hasPrefix(header) else { return nil }
        let line = text.split(separator: "\n", maxSplits: 1)[0].dropFirst(header.count)
        // Chega como endereço completo (`sessão/id`); o id curto é o que a tela
        // mostra, porque no thread a sessão é sempre a mesma.
        let id = String(line.split(separator: "/").last ?? "")
        return id.isEmpty ? nil : id
    }

    /// O corpo do envelope, sem o cabeçalho nem o rodapé de procedência — os
    /// dois são instrução para o agente, e na tela você já vê de quem veio pela
    /// própria linha.
    private static func envelopeBody(_ text: String) -> String {
        var body = text
        if let end = body.range(of: "\n\n") { body = String(body[end.upperBound...]) }
        if let footer = body.range(of: "\nQuem escreveu foi outro agente") {
            body = String(body[..<footer.lowerBound])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prompt montado pelo app: tira o cabeçalho `[egeon]` e a instrução do
    /// rodapé, que são andaime e não o que você escreveu.
    private static func dispatchBody(_ text: String) -> String {
        guard text.hasPrefix("[egeon]") else { return text }
        var body = text
        if let end = body.range(of: "\n\n") { body = String(body[end.upperBound...]) }
        for tail in ["\n\nAplique no código.",
                     "\n\nReescreva o arquivo endereçando cada ponto."] {
            if let range = body.range(of: tail) { body = String(body[..<range.lowerBound]) }
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func short(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        let file = path[path.index(after: slash)...]
        // Duas partes: `sync/adapter.ts` distingue o que só o nome não distingue,
        // e o caminho inteiro não cabe no cabeçalho do bloco.
        let rest = path[..<slash]
        guard let previous = rest.lastIndex(of: "/") else { return path }
        return String(rest[rest.index(after: previous)...]) + "/" + String(file)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

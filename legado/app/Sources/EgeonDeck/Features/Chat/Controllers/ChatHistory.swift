import Foundation

/// O histórico do chat de uma bancada em disco (ADR-037): a conversa corrente
/// em `workbenches/<id>/chat.jsonl`, uma linha por turno; as arquivadas em
/// `workbenches/<id>/chat-archive/chat-<início>_<fim>.jsonl`, nomeadas pelo
/// período que cobrem — do primeiro prompt à última resposta.
///
/// JSON e não banco porque o que se guarda é o que o chat mostra — uns KB por
/// turno — e não o transcript do CLI. Só-append, legível com `jq`, editável à
/// mão como todo arquivo do `~/.egeon`.
///
/// "Limpar a conversa" é arquivar: o `chat.jsonl` vai para `chat-archive/` e
/// um novo começa vazio. Nada é apagado, e a conversa do CLI dentro de cada
/// agente continua a mesma; o que muda é o que o chat monta na tela. A
/// corrente fica na raiz de propósito: é a que você abre.
final class ChatHistory {
    static let shared = ChatHistory(workbenches: Flavor.current.workbenchesDirectory)

    let workbenches: URL
    private let queue: DispatchQueue
    /// Chaves já gravadas na conversa corrente, por bancada. Carregado do
    /// arquivo no primeiro toque; zera ao arquivar.
    private var seen: [String: Set<String>] = [:]

    init(workbenches: URL) {
        self.workbenches = workbenches
        self.queue = DispatchQueue(label: "\(Flavor.current.identifier).chat-history")
    }

    func directory(forWorkbench id: String) -> URL {
        workbenches.appendingPathComponent(id)
    }

    /// A conversa corrente. Pode ainda não existir.
    func current(forWorkbench id: String) -> URL {
        directory(forWorkbench: id).appendingPathComponent(Self.currentName)
    }

    func archiveDirectory(forWorkbench id: String) -> URL {
        directory(forWorkbench: id).appendingPathComponent(Self.archiveName)
    }

    /// As conversas arquivadas, da mais antiga à mais recente.
    func archived(forWorkbench id: String) -> [URL] {
        let dir = archiveDirectory(forWorkbench: id)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix(Self.prefix) && $0.hasSuffix(Self.suffix) }
            .sorted()
            .map { dir.appendingPathComponent($0) }
    }

    /// O período de uma conversa arquivada — lido do nome, para listar sem
    /// abrir o arquivo.
    static func period(of file: URL) -> (start: Date, end: Date)? {
        let name = file.lastPathComponent
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let parts = name.dropFirst(prefix.count).dropLast(suffix.count).split(separator: "_")
        guard parts.count >= 2, let start = clock.date(from: String(parts[0])),
              let end = clock.date(from: String(parts[1])) else { return nil }
        return (start, end)
    }

    /// Do primeiro prompt à última resposta. É a data da CONVERSA, não a da
    /// limpeza: quem procura "a vez que o revisor achou o bug" lembra de
    /// quando foi, não de quando limpou.
    static func period(of records: [ChatRecord]) -> (start: Date, end: Date)? {
        let starts = records.map(\.turn.promptAt)
        let ends = records.map { $0.turn.replyAt ?? $0.turn.promptAt }
        guard let start = starts.min(), let end = ends.max() else { return nil }
        return (start, max(start, end))
    }

    func append(_ record: ChatRecord, workbench id: String) {
        queue.async { [self] in
            let url = current(forWorkbench: id)
            if seen[id] == nil {
                seen[id] = Set(Self.read(url).map(\.key))
            }
            guard seen[id]?.contains(record.key) != true else { return }
            guard let data = try? Self.encoder.encode(record) else {
                Log.write("chat[\(id)/\(record.node)]: turno não serializável, não gravado")
                return
            }
            seen[id]?.insert(record.key)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let handle = FileHandle(forWritingAtPath: url.path) {
                handle.seekToEndOfFile()
                handle.write(data + Data("\n".utf8))
                try? handle.close()
            } else {
                try? (data + Data("\n".utf8)).write(to: url)
            }
            Log.write("chat[\(id)/\(record.node)]: turno gravado")
        }
    }

    /// Arquiva a conversa corrente e começa outra. Devolve para onde a antiga
    /// foi, ou nil se não havia o que arquivar — conversa vazia não vira
    /// arquivo vazio na pasta.
    @discardableResult
    func archive(workbench id: String, at now: Date = Date()) -> URL? {
        queue.sync {
            let file = current(forWorkbench: id)
            guard !Self.isEmpty(file) else { return nil }
            let fm = FileManager.default
            let dir = archiveDirectory(forWorkbench: id)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // Arquivo com linhas que não decodificam não fica sem data: vale o
            // instante da limpeza para as duas pontas.
            let period = Self.period(of: Self.read(file)) ?? (now, now)
            let stamp = Self.clock.string(from: period.start) + "_" + Self.clock.string(from: period.end)
            var target = dir.appendingPathComponent(Self.prefix + stamp + Self.suffix)
            // Mesmo período duas vezes (conversa restaurada e limpa de novo):
            // sufixo, em vez de sobrescrever. `_` e não `-`: ordena depois de `.`.
            var n = 2
            while fm.fileExists(atPath: target.path) {
                target = dir.appendingPathComponent(Self.prefix + stamp + "_\(n)" + Self.suffix)
                n += 1
            }
            do {
                try fm.moveItem(at: file, to: target)
            } catch {
                Log.write("chat[\(id)]: não consegui arquivar \(file.lastPathComponent) — \(error)")
                return nil
            }
            seen[id] = []
            return target
        }
    }

    /// Os turnos de uma conversa; sem `file`, a corrente.
    func load(workbench id: String, file: URL? = nil) -> [ChatRecord] {
        Self.read(file ?? current(forWorkbench: id))
    }

    /// Espera o que já foi pedido terminar de gravar. Existe para teste.
    func flush() { queue.sync {} }

    /// Linha que não decodifica é pulada, não derruba a conversa: arquivo
    /// editado à mão ou meia linha de um crash não podem apagar o resto.
    static func read(_ url: URL) -> [ChatRecord] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? decoder.decode(ChatRecord.self, from: Data(line.utf8))
        }
    }

    private static func isEmpty(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0) == 0
    }

    static let currentName = "chat.jsonl"
    static let archiveName = "chat-archive"
    private static let prefix = "chat-"
    private static let suffix = ".jsonl"

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// Fração de segundo entra: dois agentes respondendo no mesmo segundo se
    /// ordenam por ela, e o chat cruza os turnos por tempo.
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, container in
            var c = container.singleValueContainer()
            try c.encode(iso.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "data inválida: \(raw)"))
            }
            return date
        }
        return decoder
    }()
}

import Foundation

/// Mantém o consumo de cada bancada em dia (ADR-085): lê o que os transcripts
/// dos agentes ganharam, soma no `usage.json` e avisa a tela.
///
/// Por relógio, além do fim de turno: o custo anda enquanto o agente trabalha,
/// e a leitura é só do que o arquivo cresceu — um `stat` quando nada mudou.
final class UsageStore {
    static let shared = UsageStore()
    static let didChange = Notification.Name("egeon.usage.changed")

    /// Uma fonte de consumo: o nó e o transcript que o gancho relatou.
    struct Source: Equatable {
        var node: String
        var transcript: String
    }

    /// Bancada (id) → nós com transcript. Lido na fila principal.
    var sources: (() -> [String: [Source]])?

    /// O que a tela lê. Só a fila principal escreve.
    private(set) var ledgers: [String: UsageLedger] = [:]
    var prices: PriceTable { PriceTable.current }

    private var working: [String: UsageLedger] = [:]
    private let queue = DispatchQueue(label: "\(Flavor.current.identifier).usage", qos: .utility)
    private var timer: Timer?
    private var busy = false

    func start() {
        PriceTable.seedFileIfMissing()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 2
    }

    /// O `pricing.json` editado à mão e o Claude Code atualizado valem na
    /// próxima leitura, sem reiniciar — para o que entrar dali em diante.
    private var pricesStamp: Date?
    private var catalogPrices: [String: ModelPrice]?

    private func reloadPricesIfChanged() -> Bool {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: PriceTable.file.path))?[.modificationDate] as? Date
        let catalog = ClaudeModelCatalog.installedPrices()
        guard stamp != pricesStamp || catalog != catalogPrices else { return false }
        let first = catalogPrices == nil
        pricesStamp = stamp
        catalogPrices = catalog
        let next = PriceTable.load(catalog: catalog)
        guard next != PriceTable.current else { return false }
        PriceTable.current = next
        let counted = Dictionary(grouping: next.origin.values, by: { $0 }).mapValues(\.count)
        Log.write("consumo: tabela de preços \(first ? "carregada" : "mudou, vale daqui para frente") — "
                  + "Claude Code \(counted[.claudeCode] ?? 0), embutida \(counted[.builtIn] ?? 0), "
                  + "pricing.json \(counted[.file] ?? 0)")
        return true
    }

    func ledger(for workbench: String) -> UsageLedger { ledgers[workbench] ?? UsageLedger() }

    /// Chamar da fila principal.
    func refresh() {
        if reloadPricesIfChanged(), !ledgers.isEmpty {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
        guard !busy, let all = sources?() else { return }
        busy = true
        let prices = prices
        queue.async { [self] in
            var changed: [String: UsageLedger] = [:]
            for (workbench, list) in all {
                var ledger = working[workbench] ?? load(workbench, sources: list, prices: prices)
                let before = ledger
                ledger.settle(prices)
                for source in list {
                    for file in ClaudeUsage.files(for: URL(fileURLWithPath: source.transcript)) {
                        read(file, node: source.node, into: &ledger, prices: prices)
                    }
                }
                working[workbench] = ledger
                if ledger != before || ledgers[workbench] == nil {
                    save(ledger, workbench: workbench)
                    changed[workbench] = ledger
                }
            }
            DispatchQueue.main.async { [self] in
                busy = false
                guard !changed.isEmpty else { return }
                ledgers.merge(changed) { _, new in new }
                NotificationCenter.default.post(name: Self.didChange, object: nil)
            }
        }
    }

    private func read(_ file: URL, node: String, into ledger: inout UsageLedger, prices: PriceTable) {
        let path = file.path
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64 else { return }
        let offset = ledger.cursors[path]?.offset ?? 0
        // Encolheu: foi reescrito. Recomeçar contaria de novo o que já entrou.
        if size < offset { ledger.cursors[path] = .init(offset: size, lastId: nil); return }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        // Só o Claude Code grava consumo no transcript hoje; outro CLI entra
        // pelo leitor dele, quando existir.
        ledger.absorb(chunk: data, of: path, node: node, prices: prices) { ClaudeUsage.entries(in: $0, after: $1) }
    }

    private static func file(_ workbench: String) -> URL {
        Flavor.current.workbenchDirectory(workbench).appendingPathComponent("usage.json")
    }

    private func save(_ ledger: UsageLedger, workbench: String) {
        let url = Self.file(workbench)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(ledger).write(to: url, options: .atomic)
    }

    /// Do disco; na primeira vez, com o passado que a trilha deixa achar —
    /// as conversas de antes de cada `/clear`.
    private func load(_ workbench: String, sources: [Source], prices: PriceTable) -> UsageLedger {
        if let data = try? Data(contentsOf: Self.file(workbench)),
           let ledger = try? JSONDecoder().decode(UsageLedger.self, from: data) {
            return ledger
        }
        // Lido no fim de `refresh`, com o resto: o `settle` congela o que
        // entrou sem preço — e o formato de antes, que só tinha tokens.
        var ledger = UsageLedger()
        let current = Set(sources.map(\.transcript))
        for (node, transcript) in pastTranscripts(workbench) where !current.contains(transcript.path) {
            for file in ClaudeUsage.files(for: transcript) {
                read(file, node: node, into: &ledger, prices: prices)
            }
        }
        Log.write("consumo: bancada \(workbench) começou o registro com \(ledger.cursors.count) transcript(s) do passado")
        return ledger
    }

    private func pastTranscripts(_ workbench: String) -> [(String, URL)] {
        let folder = Flavor.current.workbenchDirectory(workbench)
        let traces = [folder.appendingPathComponent("trace.md")]
            + ((try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("trace-archive"),
                                                             includingPropertiesForKeys: nil)) ?? [])
        let stamps = traces.flatMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map(TraceConversations.parse) ?? []
        }
        guard !stamps.isEmpty else { return [] }
        let index = Self.transcriptIndex()
        return stamps.compactMap { stamp in
            index[stamp.prefix.lowercased()].map { (stamp.node, $0) }
        }
    }

    /// Prefixo de 8 → transcript, em todos os `~/.claude*/projects/*/`.
    private static func transcriptIndex() -> [String: URL] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var index: [String: URL] = [:]
        let configs = ((try? fm.contentsOfDirectory(atPath: home.path)) ?? []).filter { $0.hasPrefix(".claude") }
        for config in configs {
            let projects = home.appendingPathComponent(config).appendingPathComponent("projects")
            for project in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)) ?? []
                where file.pathExtension == "jsonl" {
                    index[String(file.deletingPathExtension().lastPathComponent.prefix(8)).lowercased()] = file
                }
            }
        }
        return index
    }
}

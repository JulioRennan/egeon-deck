import Foundation

/// Os cronômetros de todas as bancadas, somados a cada tique e guardados em
/// `workbenches/<id>/clock.json` (ADR-074).
///
/// Por `id`, e não por nome, como tudo que é da bancada: renomear não zera.
/// O disco é gravado de tempos em tempos, e não a cada tique — perder alguns
/// segundos num encerramento brusco não muda a leitura.
final class WorkbenchClocks {
    static let shared = WorkbenchClocks(directory: Flavor.current.workbenchesDirectory)

    let directory: URL
    private var clocks: [String: WorkbenchClock] = [:]
    private var dirty: Set<String> = []
    private var lastTick: Date?
    private var lastSave: Date?
    static let saveInterval: TimeInterval = 15

    init(directory: URL) {
        self.directory = directory
    }

    func file(forWorkbench id: String) -> URL {
        directory.appendingPathComponent(id).appendingPathComponent("clock.json")
    }

    func clock(for id: String) -> WorkbenchClock {
        if let clock = clocks[id] { return clock }
        let loaded = (try? Data(contentsOf: file(forWorkbench: id)))
            .flatMap { try? JSONDecoder().decode(WorkbenchClock.self, from: $0) } ?? WorkbenchClock()
        clocks[id] = loaded
        return loaded
    }

    /// Soma o tempo desde o tique anterior a cada fase em curso de cada
    /// bancada. Bancada fora de `phases` (parada, ou sem terminais de pé) não anda.
    func tick(_ phases: [String: Set<WorkbenchClock.Phase>], now: Date = Date()) {
        defer { lastTick = now }
        guard let lastTick else { lastSave = now; return }
        let elapsed = now.timeIntervalSince(lastTick)
        for (id, current) in phases where !current.isEmpty {
            var clock = clock(for: id)
            for phase in current { clock.add(elapsed, to: phase) }
            clocks[id] = clock
            dirty.insert(id)
        }
        if now.timeIntervalSince(lastSave ?? now) >= Self.saveInterval { flush(now: now) }
    }

    /// "Limpar a bancada" e o menu do cronômetro: começa outro período.
    func reset(_ id: String) {
        clocks[id] = WorkbenchClock()
        dirty.insert(id)
        flush()
    }

    func flush(now: Date = Date()) {
        lastSave = now
        for id in dirty {
            guard let clock = clocks[id], let data = try? JSONEncoder().encode(clock) else { continue }
            let url = file(forWorkbench: id)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        dirty.removeAll()
    }
}

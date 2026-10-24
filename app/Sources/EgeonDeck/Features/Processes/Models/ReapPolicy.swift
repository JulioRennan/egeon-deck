import Foundation

/// A limpeza periódica dos órfãos (ADR-083): de quanto em quanto tempo, a
/// partir de que idade, e quem nunca entra. Em `processes.json`, editável à mão;
/// chave que faltar fica no padrão.
struct ReapPolicy: Codable, Equatable {
    var enabled = true
    var intervalMinutes: Double = 10
    /// A idade é a do processo, não a de órfão — o kernel não diz quando o pai
    /// morreu. Uma hora deixa de fora o que acabou de se soltar de um build.
    var minAgeMinutes: Double = 60

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        intervalMinutes = max(1, try c.decodeIfPresent(Double.self, forKey: .intervalMinutes) ?? 10)
        minAgeMinutes = max(0, try c.decodeIfPresent(Double.self, forKey: .minAgeMinutes) ?? 60)
    }

    static var file: URL { Flavor.current.config("processes.json") }

    static func load() -> ReapPolicy {
        guard let data = try? Data(contentsOf: file),
              let policy = try? JSONDecoder().decode(ReapPolicy.self, from: data) else { return ReapPolicy() }
        return policy
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: Self.file, options: .atomic)
    }

    /// O daemon do Claude Code é órfão de propósito: segura as sessões em
    /// segundo plano dele, e encerrá-lo por relógio levaria uma delas no meio.
    static func isSpared(_ command: String) -> Bool {
        command.contains("bg-pty-host") || command.contains("bg-spare")
            || (command.contains("claude") && command.contains(" daemon run"))
    }

    func victims(in processes: [EgeonProcess], now: Date = Date()) -> [EgeonProcess] {
        var children: [Int32: [Int32]] = [:]
        for process in processes { children[process.ppid, default: []].append(process.pid) }
        var spared: Set<Int32> = []
        var stack = processes.filter { Self.isSpared($0.command) }.map(\.pid)
        while let pid = stack.popLast() {
            guard spared.insert(pid).inserted else { continue }
            stack += children[pid] ?? []
        }
        // A idade é a da família: o filho que um laço relança nasce de novo a
        // cada queda e nunca chegaria à idade mínima sozinho.
        let orphans = Dictionary(processes.filter(\.orphan).map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        func familyStart(_ process: EgeonProcess) -> Date {
            var oldest = process.started
            var current = process
            var hops = 0
            while current.ppid > 1, let parent = orphans[current.ppid], hops < 64 {
                oldest = min(oldest, parent.started)
                current = parent
                hops += 1
            }
            return oldest
        }
        return processes.filter {
            $0.orphan && !spared.contains($0.pid)
                && now.timeIntervalSince(familyStart($0)) >= minAgeMinutes * 60
        }
    }
}

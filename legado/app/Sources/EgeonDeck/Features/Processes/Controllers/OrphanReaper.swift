import Foundation

/// O relógio que encerra os órfãos velhos (ADR-083). Rede de segurança: o
/// grosso morre junto com o nó (`ProcessScanner.terminateTree`); aqui cai o
/// que escapou — app que caiu, processo que se soltou sozinho.
final class OrphanReaper {
    static let shared = OrphanReaper()
    static let didReap = Notification.Name("egeon.processes.reaped")

    private(set) var policy = ReapPolicy.load()
    private(set) var last: (date: Date, count: Int)?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "\(Flavor.current.identifier).reaper", qos: .utility)

    func start() {
        timer?.invalidate()
        timer = nil
        guard policy.enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: policy.intervalMinutes * 60, repeats: true) { [weak self] _ in
            self?.reap()
        }
        timer?.tolerance = 30
    }

    func setEnabled(_ on: Bool) {
        policy = ReapPolicy.load()
        policy.enabled = on
        policy.save()
        Log.write("processos: limpeza automática \(on ? "ligada" : "desligada")")
        start()
    }

    func reap() {
        queue.async { [weak self] in _ = self?.reapNow() }
    }

    /// Bloqueia: chamar fora da fila principal. É o que `/processes/reap` usa
    /// para conferir sem esperar o relógio.
    func reapNow(dry: Bool = false) -> [EgeonProcess] {
        let policy = DispatchQueue.main.sync { self.policy }
        let victims = policy.victims(in: ProcessScanner.scan())
        if dry { return victims }
        let killed = victims.isEmpty ? [] : ProcessScanner.terminate(Set(victims.map(\.pid)))
        DispatchQueue.main.async {
            self.last = (Date(), killed.count)
            NotificationCenter.default.post(name: Self.didReap, object: nil)
        }
        return killed
    }
}

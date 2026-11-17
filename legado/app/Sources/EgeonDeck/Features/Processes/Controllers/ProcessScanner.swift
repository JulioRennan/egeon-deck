import Darwin
import Foundation

/// Lê os processos do usuário direto do kernel e diz quais são do Egeon
/// (ADR-083). `sysctl` e não `ps -E`: um `ps` por processo para ler o ambiente
/// são centenas de subprocessos a cada atualização da janela.
enum ProcessScanner {
    /// Bloqueia: chamar fora da fila principal.
    static func scan() -> [EgeonProcess] {
        ProcessTable.classify(rawProcesses(), app: getpid(), deck: Flavor.current.identifier)
    }

    /// Encerra só o que a leitura de agora diz ser do Egeon — um pid que veio de
    /// fora não basta, ele pode já ter sido reaproveitado por outro processo.
    /// Sem `pids`, os órfãos todos.
    static func terminate(_ pids: Set<Int32>? = nil) -> [EgeonProcess] {
        let targets = scan().filter { pids?.contains($0.pid) ?? $0.orphan }
        for process in targets {
            kill(process.pid, SIGTERM)
        }
        if !targets.isEmpty {
            Log.write("processos: SIGTERM em \(targets.count) — "
                      + targets.map { "\($0.pid) \($0.node ?? "app")" }.joined(separator: ", "))
        }
        return targets
    }

    /// Encerra tudo o que descende de `root` (sem ele), de qualquer grupo.
    ///
    /// O `killpg` no shell do nó não basta: o Bash do Claude Code põe cada
    /// comando num grupo próprio, e o servidor que um agente subiu sobrevivia
    /// ao nó, órfão, por dias. A árvore é lida AGORA, enquanto ainda existe —
    /// depois que o shell morre, os filhos já são do launchd. O daemon do Claude
    /// Code não é atingido: ele se solta da árvore assim que nasce.
    ///
    /// Quem ignorar o SIGTERM leva SIGKILL depois de `grace`, se ainda for o
    /// mesmo processo (pid e início): pid reaproveitado não paga pelo antigo.
    static func terminateTree(of root: Int32, grace: TimeInterval = 2, reason: String) {
        let tree = ProcessTable.descendants(of: root, in: rawProcesses(withArguments: false))
        guard !tree.isEmpty else { return }
        tree.forEach { kill($0.pid, SIGTERM) }
        Log.write("processos: \(reason) — SIGTERM em \(tree.count) descendente(s) do pid \(root)")
        guard grace > 0 else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) {
            let alive = Dictionary(rawProcesses(withArguments: false).map { ($0.pid, $0.started) },
                                   uniquingKeysWith: { a, _ in a })
            let stubborn = tree.filter { alive[$0.pid] == $0.started }
            guard !stubborn.isEmpty else { return }
            stubborn.forEach { kill($0.pid, SIGKILL) }
            Log.write("processos: \(reason) — SIGKILL em \(stubborn.count) que ignoraram o SIGTERM")
        }
    }

    /// A árvore sem linha de comando nem ambiente: barata o bastante para
    /// rodar na remoção de um nó.
    static func tree() -> [RawProcess] { rawProcesses(withArguments: false) }

    static func environment(of pid: Int32) -> [String: String]? {
        arguments(of: pid)?.environment
    }

    private static func rawProcesses(withArguments: Bool = true) -> [RawProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        // Folga: entre medir e ler, processos nascem.
        size += size / 8
        var table = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &table, &size, nil, 0) == 0 else { return [] }
        table.removeLast(table.count - size / MemoryLayout<kinfo_proc>.stride)

        return table.map { info in
            let pid = info.kp_proc.p_pid
            let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let start = info.kp_proc.p_un.__p_starttime
            let args = withArguments ? arguments(of: pid) : nil
            let command = args?.arguments.joined(separator: " ") ?? name
            return RawProcess(pid: pid, ppid: info.kp_eproc.e_ppid,
                              started: Date(timeIntervalSince1970: Double(start.tv_sec)
                                            + Double(start.tv_usec) / 1_000_000),
                              name: name, command: command.isEmpty ? name : command,
                              environment: args?.environment ?? [:])
        }
    }

    private static func arguments(of pid: Int32) -> ProcessArguments? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcessArguments(procargs: Data(buffer.prefix(size)))
    }
}

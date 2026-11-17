import AppKit

/// Fecha o app de desktop que o Egeon abriu quando o último que o usava sai
/// (ADR-084). Abrir conta pela marca no processo do app; usar, pelo que se vê
/// na hora de fechar — conexão viva com ele e, no Docker, container de pé.
final class AppKeeper {
    static let shared = AppKeeper()

    private var claims = AppClaims.load()
    private let queue = DispatchQueue(label: "\(Flavor.current.identifier).apps", qos: .utility)

    var snapshot: [String: Any] {
        queue.sync {
            ["apps": claims.apps.mapValues { ["launched": $0.launched, "users": $0.users.sorted()] }]
        }
    }

    /// Chamar da fila principal, na remoção de verdade, depois de os nós saírem
    /// do Dispatcher — reiniciar o agente (modelo, esforço, regras) não larga
    /// app nenhum. `paths`: bancada → pastas, de todas as bancadas.
    func release(_ leaving: Set<String>, paths: [String: [String]]) {
        guard !leaving.isEmpty else { return }
        let live = Set(Dispatcher.shared.activeAddresses).subtracting(leaving)
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (String, Int32)? in
            guard let bundle = app.bundleIdentifier, !bundle.hasPrefix(ProcessMark.bundlePrefix) else { return nil }
            return (bundle, app.processIdentifier)
        }
        queue.async { [self] in
            var launchers: [String: String] = [:]
            // De qual app aberto pelo launchd cada um descende: a janela do
            // Docker Desktop é outro bundle, mas leva o `__CFBundleIdentifier`
            // do motor — é parte dele, até quando já não é filha na árvore.
            var job: [Int32: String] = [:]
            for (bundle, pid) in apps {
                guard let environment = ProcessScanner.environment(of: pid) else { continue }
                job[pid] = environment[ProcessMark.bundleVariable]
                launchers[bundle] = AppClaims.opener(of: bundle, environment: environment)
            }
            for bundle in claims.release(leaving, live: live, launchers: launchers) {
                guard let pid = apps.first(where: { $0.0 == bundle })?.1 else { continue }
                let (users, reason) = stillUsing(bundle, pid: pid, live: live, leaving: leaving, paths: paths)
                if !users.isEmpty || reason != nil {
                    claims.apps[bundle] = AppClaims.Entry(launched: true, users: users)
                    Log.write("apps: \(bundle) segue aberto — "
                              + (reason ?? "em uso por \(users.sorted().joined(separator: ", "))"))
                    continue
                }
                Log.write("apps: \(bundle) fechado — \(leaving.sorted().joined(separator: ", ")) era o último a usar")
                let family = apps.filter { $0.1 != pid && job[$0.1] == bundle }.map(\.1)
                close(pid, bundle: bundle, with: family, among: apps)
            }
            claims.save()
        }
    }

    /// O ⌘Q no app e, antes, nos apps que são parte dele — filhos na árvore ou
    /// do mesmo lançamento (`relatives`). O motor do Docker ignora o pedido de
    /// saída; quem obedece é a janela do Docker Desktop, e ela leva o motor.
    private func close(_ pid: Int32, bundle: String, with relatives: [Int32], among apps: [(String, Int32)]) {
        let tree = Set(ProcessTable.descendants(of: pid, in: ProcessScanner.tree()).map(\.pid))
        let family = Array(Set(apps.filter { tree.contains($0.1) }.map(\.1) + relatives)) + [pid]
        DispatchQueue.main.async {
            family.forEach { NSRunningApplication(processIdentifier: $0)?.terminate() }
        }
        queue.asyncAfter(deadline: .now() + 15) {
            guard kill(pid, 0) == 0 else { return }
            Log.write("apps: \(bundle) pedido para fechar, mas segue aberto após 15 s")
        }
    }

    /// Os nós de pé que ainda usam o app. `reason` não nulo segura o app sem
    /// herdeiro — o caso em que não se sabe de quem é o uso.
    private func stillUsing(_ bundle: String, pid: Int32, live: Set<String>, leaving: Set<String>,
                            paths: [String: [String]]) -> (Set<String>, String?) {
        var users = connected(to: pid, live: live)
        if bundle == "com.docker.docker" {
            guard let dirs = containerDirs() else { return (users, "não deu para listar os containers") }
            // `/tmp` e `/private/tmp`: o compose grava um, a bancada pode ter o outro.
            let real = { (path: String) in URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
            let owners = ContainerOwners(workingDirs: dirs.map { $0.isEmpty ? $0 : real($0) },
                                         paths: paths.mapValues { $0.map(real) })
            if owners.unknown { return (users, "há container de fora das bancadas") }
            let bench = { (address: String) in String(address.split(separator: "/").first ?? "") }
            let liveBenches = Set(live.map(bench))
            let leavingBenches = Set(leaving.map(bench)).subtracting(liveBenches)
            users.formUnion(live.filter { owners.benches.contains(bench($0)) })
            // Bancada parada (não a que sai) com container de pé: o banco dela
            // vai estar lá quando ela voltar.
            if let idle = owners.benches.subtracting(liveBenches).subtracting(leavingBenches).sorted().first {
                return (users, "há container da bancada \(idle), parada")
            }
        }
        return (users, nil)
    }

    /// Os nós de pé com algum processo ligado por socket ao app ou aos filhos
    /// dele — o `docker compose up` de outra bancada falando com o Docker.
    private func connected(to app: Int32, live: Set<String>) -> Set<String> {
        let appPids = Set([app] + ProcessTable.descendants(of: app, in: ProcessScanner.tree()).map(\.pid))
        let ours = ProcessScanner.scan().filter { !$0.orphan && live.contains($0.node ?? "") }
        guard !ours.isEmpty, let output = Self.run("/usr/sbin/lsof", ["-U", "-F", "pdn"]) else { return [] }
        let hits = SocketTable(lsof: output).connected(Set(ours.map(\.pid)), to: appPids)
        return Set(ours.filter { hits.contains($0.pid) }.compactMap(\.node))
    }

    /// `nil` quando o Docker não responde: aí não se sabe o que está rodando.
    private func containerDirs() -> [String]? {
        guard let output = Self.run("/Applications/Docker.app/Contents/Resources/bin/docker",
                                    ["ps", "--format", #"{{.Label "com.docker.compose.project.working_dir"}}"#],
                                    requireSuccess: true) else { return nil }
        // Uma linha por container, vazia quando ele não tem o rótulo — e essa
        // conta: é container sem dono.
        var lines = output.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func run(_ path: String, _ arguments: [String], requireSuccess: Bool = false) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if requireSuccess, process.terminationStatus != 0 { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

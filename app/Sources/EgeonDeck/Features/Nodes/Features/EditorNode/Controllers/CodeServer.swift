import Foundation

/// Sobe e supervisiona um `code-server` local — o build web do VSCode, que é a
/// única forma de ter o workbench de verdade DENTRO de uma view nossa
/// (ADR-003; macOS não reparenta janela de outro processo).
///
/// Uma instância só serve todos os workspaces: cada nó de editor abre a mesma
/// origem com `?folder=<path>` diferente.
final class CodeServer {
    static let shared = CodeServer()

    /// Porta fixa e alta: previsível para depurar com `curl`, e o `?folder=`
    /// distingue os workspaces sem precisar de um processo por pasta.
    let port = Flavor.current.codeServerPort

    private(set) var isReady = false
    private var process: Process?
    private var readyHandlers: [() -> Void] = []

    /// Relançamentos automáticos seguidos. Existe para não entrar em laço quando
    /// a causa da morte não passa (porta tomada por outro app, binário quebrado).
    private var restarts = 0
    private static let maxRestarts = 3
    /// `stop()` intencional não deve disparar o relançamento.
    private var stopping = false

    private let root = URL(fileURLWithPath:
        Flavor.current.config("code-server").path)

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    func url(forFolder path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "folder", value: path)]
        return components.url!
    }

    private init() {}

    // MARK: - Binário

    /// Homebrew instala em prefixos diferentes por arquitetura, e o app lançado
    /// pelo Finder não herda o PATH do shell — daí a busca explícita.
    private func resolveBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/code-server",
            "/usr/local/bin/code-server",
            NSString(string: "~/.local/bin/code-server").expandingTildeInPath
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Último recurso: procurar no PATH herdado.
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for dir in envPath.split(separator: ":") {
                let candidate = "\(dir)/code-server"
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        return nil
    }

    /// Configurações do workbench que o app garante.
    ///
    /// `security.workspace.trust.enabled: false` é o que importa: sem isso todo
    /// workspace abre em Restricted Mode atrás de um diálogo de confiança, e as
    /// pastas aqui são as que o próprio usuário configurou.
    ///
    /// As duas de git existem porque uma bancada do Egeon é UMA frente de
    /// trabalho: abrir o repositório principal fazia o VSCode achar todas as
    /// worktrees dele e listar cada uma como um repositório à parte no Source
    /// Control — a tela enchia de repositório que não é o desta bancada. Quem
    /// quiser ver outra worktree abre outra bancada, que é o que o worktree do
    /// Egeon faz.
    ///
    /// `egeon.socketPath` é do flavor, e tem de ser: o padrão da extensão é
    /// `~/.egeon/sock`, então o code-server do dev mandava os request changes
    /// para o app ESTÁVEL — chegavam, no terminal errado, sem erro nenhum.
    private static var managedSettings: [String: Any] {
        [
            "security.workspace.trust.enabled": false,
            "workbench.startupEditor": "none",
            "telemetry.telemetryLevel": "off",
            "update.mode": "none",
            "window.menuBarVisibility": "hidden",
            "workbench.colorTheme": "Default Dark Modern",
            "git.detectWorktrees": false,
            "git.openRepositoryInParentFolders": "never",
            "egeon.socketPath": ControlSocket.path
        ]
    }

    /// Escreve as configurações que faltam, e só elas.
    ///
    /// Chave por chave, e não "escreve tudo se o arquivo não existir": era assim
    /// antes, e quem já tinha o arquivo — todo mundo que usou uma versão
    /// anterior — nunca recebia uma configuração nova. O que você editou fica de
    /// pé: uma chave já presente não é tocada.
    private func seedSettings() {
        let userDir = root.appendingPathComponent("user-data/User")
        let file = userDir.appendingPathComponent("settings.json")
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)

        var settings = (try? Data(contentsOf: file))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]

        var added: [String] = []
        for (key, value) in Self.managedSettings where settings[key] == nil {
            settings[key] = value
            added.append(key)
        }
        guard !added.isEmpty else { return }

        if let data = try? JSONSerialization.data(withJSONObject: settings,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file)
            Log.write("code-server: settings.json — chaves escritas: "
                      + added.sorted().joined(separator: ", "))
        }
    }

    /// Garante a extensão de review de markdown instalada, a partir da cópia que
    /// vive dentro do bundle.
    ///
    /// O app instala, e não um script que alguém tem de lembrar de rodar, porque
    /// a extensão é parte do produto: sem ela o `.md` abre como texto e o request
    /// changes não existe. Quem recebe o app copiado não tem o repositório para
    /// rodar script nenhum.
    ///
    /// Symlink, e não cópia: o code-server varre a pasta de extensões e segue
    /// link (ADR-004). Refeito a cada arranque porque o `make.sh` apaga o bundle
    /// inteiro, e o link do arranque anterior aponta para o que não existe mais.
    private func seedExtension() {
        guard let source = Bundle.main.resourceURL?
            .appendingPathComponent("extension"),
              FileManager.default.fileExists(atPath: source.path) else {
            // `swift run` não tem bundle, e aí a extensão vem do install.sh.
            Log.write("code-server: extensão não veio no bundle — "
                      + "rode extension/install.sh se precisar dela", key: "extension.missing")
            return
        }

        let version = (try? Data(contentsOf: source.appendingPathComponent("package.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0?["version"] as? String } ?? "0.1.0"

        let dir = root.appendingPathComponent("extensions")
        let link = dir.appendingPathComponent("egeon.spec-\(version)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        clearObsolete(in: dir, id: "egeon.spec-\(version)")

        // `destinationOfSymbolicLink` e não `fileExists`: link quebrado responde
        // que não existe, e aí o create falharia com "arquivo já existe".
        let current = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        guard current != source.path else { return }

        try? FileManager.default.removeItem(at: link)
        do {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            Log.write("code-server: extensão instalada — \(link.path) -> \(source.path)")
        } catch {
            Log.write("code-server: não consegui instalar a extensão — \(error)")
        }
    }

    /// Tira a nossa extensão do `.obsolete` do code-server.
    ///
    /// Ele marca ali o que considera desinstalado e ignora na varredura. Duas
    /// pastas apontando para a mesma extensão — que é o que sobra de uma
    /// renomeação — são lidas como o mesmo id, e ele "desinstala" a duplicata:
    /// a extensão some sem erro nenhum, e reinstalar não resolve enquanto a
    /// marca continuar lá.
    ///
    /// Só a nossa chave sai; o resto do arquivo é dele.
    private func clearObsolete(in directory: URL, id: String) {
        let file = directory.appendingPathComponent(".obsolete")
        guard let data = try? Data(contentsOf: file),
              var marks = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              marks[id] != nil else { return }

        marks[id] = nil
        if let updated = try? JSONSerialization.data(withJSONObject: marks) {
            try? updated.write(to: file)
            Log.write("code-server: \(id) estava marcada como desinstalada — marca removida")
        }
    }

    // MARK: - Ciclo de vida

    func start() {
        guard process == nil else { return }
        guard let binary = resolveBinary() else {
            Log.write("code-server: binário não encontrado — instale com `brew install code-server`")
            return
        }

        // Um code-server sobrando de uma execução anterior ainda segura a 8391.
        // Subir um segundo em cima disso morre com EADDRINUSE — e o pior é que o
        // healthz do órfão responde 200, então o app anuncia "pronto", carrega os
        // editores, e o workbench morre junto com o órfão poucos segundos depois.
        switch portHolder() {
        case .none:
            break
        case .codeServer(let pid):
            Log.write("code-server: porta \(port) já tomada pelo pid \(pid) de uma execução "
                      + "anterior — encerrando o órfão antes de subir")
            kill(pid, SIGTERM)
            waitForPortRelease()
        case .other(let pid, let name):
            Log.write("code-server: porta \(port) ocupada por \(name) (pid \(pid)), que não é "
                      + "code-server — não vou matar; o nó de editor fica sem workbench")
            return
        }

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        seedSettings()
        seedExtension()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = [
            "--bind-addr", "127.0.0.1:\(port)",
            // Sem autenticação porque o socket é loopback e o app é o único
            // cliente. Nada disso escuta em interface externa.
            "--auth", "none",
            "--disable-telemetry",
            "--disable-update-check",
            "--user-data-dir", root.appendingPathComponent("user-data").path,
            "--extensions-dir", root.appendingPathComponent("extensions").path
        ]

        // PATH enriquecido também aqui, e não só nos terminais: as extensões do
        // workbench rodam num extension host filho deste processo, e é com este
        // PATH que a extensão Dart procura o SDK do Flutter. Com o mínimo do
        // launchd ela não acha o `flutter` e o debug não sobe.
        task.environment = AppEnvironment.forChildProcess()

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                Log.write("code-server: \(line)")
            }
        }

        // Morrer calado é o que fez o workbench sumir sem ninguém entender: o
        // processo caía e nada notava, porque nada olhava.
        task.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async { self?.handleDeath(of: finished) }
        }

        do {
            try task.run()
            process = task
            stopping = false
            Log.write("code-server: iniciado (pid \(task.processIdentifier)) em \(baseURL)")
            waitUntilReady()
        } catch {
            Log.write("code-server: falha ao iniciar: \(error)")
        }
    }

    private func handleDeath(of task: Process) {
        // `stop()` já zerou `process`; comparar impede tratar um encerramento
        // pedido como queda.
        guard !stopping, process === task else { return }
        process = nil
        isReady = false

        guard restarts < Self.maxRestarts else {
            Log.write("code-server: caiu (status \(task.terminationStatus)) e já tentei "
                      + "\(restarts)x — desisto. Nós de editor ficam sem workbench.")
            return
        }
        restarts += 1
        Log.write("code-server: caiu (status \(task.terminationStatus)) — relançando "
                  + "(tentativa \(restarts)/\(Self.maxRestarts))")
        // Folga para a porta ser liberada de fato antes da próxima tentativa.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.start() }
    }

    func stop() {
        guard let task = process else { return }
        stopping = true
        process = nil
        isReady = false

        task.terminate()

        // SIGTERM é assíncrono: sem esperar, o app sai enquanto o processo ainda
        // segura a 8391, e o próximo arranque morre com EADDRINUSE.
        let deadline = Date().addingTimeInterval(3)
        while task.isRunning && Date() < deadline { usleep(50_000) }

        if task.isRunning {
            Log.write("code-server: não saiu com SIGTERM em 3s — mandando SIGKILL")
            kill(task.processIdentifier, SIGKILL)
            task.waitUntilExit()
        }
        Log.write("code-server: encerrado")
    }

    // MARK: - Quem está na porta

    private enum PortHolder {
        case none
        case codeServer(pid_t)
        case other(pid_t, String)
    }

    /// `lsof` em vez de tentar dar bind: dar bind para testar cria uma corrida
    /// com o processo que vai realmente escutar.
    private func portHolder() -> PortHolder {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice

        guard (try? lsof.run()) != nil else { return .none }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        lsof.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8),
              let first = text.split(whereSeparator: \.isNewline).first,
              let pid = pid_t(first.trimmingCharacters(in: .whitespaces)) else { return .none }

        let command = commandLine(of: pid)
        return command.contains("code-server") || command.contains("vscode")
            ? .codeServer(pid)
            : .other(pid, URL(fileURLWithPath: command.split(separator: " ").first.map(String.init) ?? command).lastPathComponent)
    }

    private func commandLine(of pid: pid_t) -> String {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "command=", "-p", "\(pid)"]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func waitForPortRelease() {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if case .none = portHolder() { return }
            usleep(100_000)
        }
        Log.write("code-server: porta \(port) segue ocupada após 5s de espera")
    }

    /// Só carregar a webview quando o servidor responde: WKWebView que bate em
    /// porta morta mostra página de erro e não tenta de novo sozinho.
    private func waitUntilReady(attempt: Int = 0) {
        guard attempt < 60 else {
            Log.write("code-server: não ficou pronto após 30s")
            return
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("healthz"))
        request.timeoutInterval = 2

        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                DispatchQueue.main.async {
                    // O 200 pode vir de um code-server que não é o nosso. Se o
                    // processo que subimos já morreu, anunciar "pronto" faz os
                    // editores carregarem de um servidor que vai sumir.
                    guard let task = self.process, task.isRunning else {
                        Log.write("code-server: healthz 200 mas o processo que subi não está "
                                  + "vivo — 8391 é de outra instância, não vou marcar pronto")
                        return
                    }
                    let wasRestart = self.restarts > 0
                    self.isReady = true
                    Log.write("code-server: pronto em \(self.baseURL) (healthz 200)")

                    // Nós que já estavam na tela apontam para o servidor morto.
                    if wasRestart { EditorRegistry.reloadAll() }

                    self.readyHandlers.forEach { $0() }
                    self.readyHandlers.removeAll()

                    // Só zera o contador depois de um tempo de pé: zerar na hora
                    // transformaria um "sobe, responde, cai" em laço infinito.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                        guard let self, self.process === task, task.isRunning else { return }
                        self.restarts = 0
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.waitUntilReady(attempt: attempt + 1)
                }
            }
        }.resume()
    }

    func whenReady(_ handler: @escaping () -> Void) {
        if isReady { handler() } else { readyHandlers.append(handler) }
    }
}

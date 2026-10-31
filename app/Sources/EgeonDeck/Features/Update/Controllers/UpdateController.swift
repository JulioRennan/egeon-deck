import AppKit

/// Procura versão nova, baixa, confere e troca o app (ADR-089).
///
/// Nunca reinicia sozinho: o terminal morre com o app (ADR-010), e reiniciar por
/// conta própria derrubaria agentes no meio do trabalho. No automático ele só
/// baixa, e a troca acontece quando você fechar o app.
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case available(AvailableUpdate)
        case downloading(AvailableUpdate)
        case ready(String)
    }

    private struct Settings: Codable { var auto = false }

    static let feed = URL(string: "https://api.github.com/repos/JulioRennan/egeon-deck/releases/latest")!
    private static let interval: TimeInterval = 6 * 60 * 60
    private static let settingsFile = Flavor.current.config("update.json")

    private(set) var state = State.idle
    private var settings: Settings
    private var timer: Timer?
    private var restartWhenReady = false
    private var swapLaunched = false

    /// Mostra o aviso de versão nova.
    var onPrompt: ((AvailableUpdate) -> Void)?
    /// Resposta a quem perguntou pelo menu: título e texto.
    var onMessage: ((String, String) -> Void)?

    private let installer = UpdateInstaller(
        destination: Bundle.main.bundleURL,
        bundleID: Bundle.main.bundleIdentifier ?? "",
        installedVersion: UpdateController.installedVersion)

    static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    init() {
        settings = (try? Data(contentsOf: Self.settingsFile))
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    var auto: Bool {
        get { settings.auto }
        set {
            settings.auto = newValue
            try? JSONEncoder().encode(settings).write(to: Self.settingsFile)
            Log.write("atualização: automático \(newValue ? "ligado" : "desligado")")
            if newValue, case .available(let update) = state { download(update) }
        }
    }

    /// Só no estável: o dev é reconstruído a toda hora, e o número dele não diz nada.
    func start() {
        guard !Flavor.current.isDev else { return }
        // Bundle que esperava uma troca que não aconteceu (o app caiu): pode estar
        // velho, e baixar de novo é barato.
        installer.discardStaged()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.check(.launch) }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.check(.periodic)
        }
    }

    func check(_ reason: UpdatePolicy.Reason, feed: URL = UpdateController.feed) {
        switch state {
        case .checking, .downloading: return
        case .ready, .available, .idle: break
        }
        let previous = state
        state = .checking
        var request = URLRequest(url: feed)
        request.setValue("EgeonDeck/\(Self.installedVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard ok, let data, let update = AvailableUpdate.parse(release: data) else {
                    self.state = previous
                    Log.write("atualização: consulta falhou — \(error?.localizedDescription ?? "resposta inesperada")")
                    if reason == .manual {
                        self.onMessage?("Não deu para procurar atualizações",
                                        "Confira a internet e tente de novo.")
                    }
                    return
                }
                self.handle(update, reason: reason, previous: previous)
            }
        }.resume()
    }

    private func handle(_ update: AvailableUpdate, reason: UpdatePolicy.Reason, previous: State) {
        let newer = update.isNewer(than: Self.installedVersion)
        Log.write("atualização: publicada \(update.version), instalada \(Self.installedVersion)")
        // Já baixada: a versão pronta continua valendo.
        if case .ready(let version) = previous, version == update.version {
            state = previous
            if reason == .manual { onPrompt?(update) }
            return
        }
        state = newer ? .available(update) : .idle
        switch UpdatePolicy.action(newer: newer, reason: reason, auto: auto) {
        case .nothing, .showInMenu: break
        case .sayUpToDate:
            onMessage?("Você está na última versão", "\(Flavor.current.displayName) \(Self.installedVersion).")
        case .prompt: onPrompt?(update)
        case .downloadQuietly: download(update)
        }
    }

    /// O clique em "Atualizar e reiniciar".
    func updateAndRestart(_ update: AvailableUpdate) {
        if case .ready(let version) = state, version == update.version {
            restart()
            return
        }
        restartWhenReady = true
        download(update)
    }

    /// O clique no menu quando já está baixada.
    func restart() {
        guard launchSwap(reopen: true) else { return }
        NSApp.terminate(nil)
    }

    private func download(_ update: AvailableUpdate) {
        guard installer.canInstall else {
            restartWhenReady = false
            state = .available(update)
            fail("O app não está num lugar onde possa ser trocado (\(installer.destination.path)). "
                 + "Mova-o para /Applications e tente de novo.")
            return
        }
        guard let signatureURL = update.signature else {
            restartWhenReady = false
            state = .available(update)
            fail("A versão \(update.version) foi publicada sem assinatura, e o app não instala o que não pode conferir.")
            return
        }
        state = .downloading(update)
        Log.write("atualização: baixando \(update.version)")
        let installer = self.installer
        URLSession.shared.dataTask(with: signatureURL) { signature, signatureResponse, _ in
            URLSession.shared.dataTask(with: update.zip) { zip, zipResponse, _ in
                let fetched = (signatureResponse as? HTTPURLResponse)?.statusCode == 200
                    && (zipResponse as? HTTPURLResponse)?.statusCode == 200
                var outcome: Result<String, Error>
                if fetched, let zip, let signature {
                    do {
                        outcome = .success(try installer.prepare(zip: zip, signature: String(decoding: signature, as: UTF8.self)))
                    } catch { outcome = .failure(error) }
                } else {
                    outcome = .failure(UpdateInstaller.Failure.notInstallable("o download falhou"))
                }
                DispatchQueue.main.async { [weak self] in self?.prepared(update, outcome) }
            }.resume()
        }.resume()
    }

    private func prepared(_ update: AvailableUpdate, _ outcome: Result<String, Error>) {
        switch outcome {
        case .success(let version):
            state = .ready(version)
            Log.write("atualização: \(version) pronta em \(installer.staged.path)")
            if restartWhenReady {
                restartWhenReady = false
                restart()
            }
        case .failure(let error):
            restartWhenReady = false
            state = .available(update)
            fail("A atualização não foi instalada: \(error)")
        }
    }

    private func fail(_ text: String) {
        Log.write("atualização: \(text)")
        onMessage?("Não deu para atualizar", text)
    }

    @discardableResult
    private func launchSwap(reopen: Bool) -> Bool {
        guard !swapLaunched else { return true }
        do {
            try installer.launchSwap(pid: ProcessInfo.processInfo.processIdentifier, reopen: reopen,
                                     log: Flavor.current.config("update.log"))
            swapLaunched = true
            Log.write("atualização: troca agendada para a saída do app")
            return true
        } catch {
            fail("Não consegui preparar a troca: \(error)")
            return false
        }
    }

    /// O app está saindo: com a opção ligada e a versão pronta, a troca vai agora.
    func applicationWillTerminate() {
        guard auto, case .ready = state, installer.isStaged else { return }
        launchSwap(reopen: false)
    }

    // MARK: Menu

    var menuTitle: String {
        switch state {
        case .idle: return "Procurar atualizações…"
        case .checking: return "Procurando atualizações…"
        case .available(let update): return "Atualizar para a versão \(update.version)…"
        case .downloading(let update): return "Baixando a versão \(update.version)…"
        case .ready(let version): return "Reiniciar para atualizar para a versão \(version)"
        }
    }

    var menuEnabled: Bool {
        switch state {
        case .checking, .downloading: return false
        case .idle, .available, .ready: return true
        }
    }

    func menuClicked() {
        switch state {
        case .available(let update): onPrompt?(update)
        case .ready: onPrompt?(readyUpdate)
        default: check(.manual)
        }
    }

    /// A versão pronta, para o aviso: as novidades já não importam nesse ponto.
    private var readyUpdate: AvailableUpdate {
        var version = Self.installedVersion
        if case .ready(let ready) = state { version = ready }
        return AvailableUpdate(version: version, notes: "", page: Self.feed, zip: Self.feed, signature: nil)
    }

    /// O estado como dados, para a rota `/update`.
    func snapshot() -> [String: Any] {
        var out: [String: Any] = ["auto": auto, "installed": Self.installedVersion,
                                  "menu": menuTitle, "staged": installer.isStaged]
        switch state {
        case .idle: out["state"] = "idle"
        case .checking: out["state"] = "checking"
        case .available(let update): out["state"] = "available"; out["version"] = update.version
        case .downloading(let update): out["state"] = "downloading"; out["version"] = update.version
        case .ready(let version): out["state"] = "ready"; out["version"] = version
        }
        return out
    }

    /// `/update?install=1`: o mesmo que o clique, sem o aviso.
    func installAvailable() {
        if case .available(let update) = state { updateAndRestart(update) }
        else if case .ready = state { restart() }
    }
}

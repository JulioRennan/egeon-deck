import AppKit

// egeon — PoC 04
// Sidebar de sessões + canvas por sessão com terminais reais.
// Terminais do tipo `agent` são alvos endereçáveis do dispatcher, que recebe
// prompts pelo socket de controle em ~/.egeon/sock.
//
// O nó `editor` é code-server num WKWebView. Ancorar a janela real do VSCode por
// Accessibility API foi abandonado (ADR-001/ADR-003): o macOS não deixa uma
// janela de outro processo ficar DENTRO da nossa. O porquê está no ADR; o código
// saiu.

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var root: RootView!

    var configs: [SessionConfig] = []
    var agents: [String: AgentProfile] = [:]
    /// Criados sob demanda e mantidos vivos: trocar de aba não mata terminal.
    var canvases: [Int: CanvasContainer] = [:]
    var activeIndex = -1

    let control = ControlSocket()
    var badgeTimer: Timer?
    /// Debounce da gravação do sessions.json.
    var persistTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.reset()
        configs = SessionStore.load()
        agents = AgentStore.load()
        Log.write("Egeon Deck iniciando — \(configs.count) sessões, "
                  + "\(agents.count) perfis de agente")

        // Escrito no arranque, e não na primeira worktree: é um arquivo feito
        // para ser lido e ajustado, e para isso precisa existir antes.
        Worktree.installCopyScript()
        AgentHooks.install()
EgeonCLI.install()

        buildMenu()

        let screen = NSScreen.screens.first ?? NSScreen.main!
        window = NSWindow(
            contentRect: screen.visibleFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.setFrame(screen.visibleFrame, display: false)
        window.title = Flavor.current.displayName
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1)

        let sidebar = Sidebar(configs: configs)
        sidebar.onSelect = { [weak self] index in self?.activate(index) }
        sidebar.onCreate = { [weak self] in self?.createSession() }
        sidebar.onCreateFromWorktree = { [weak self] in self?.createSessionFromWorktree() }
        sidebar.onRename = { [weak self] index in self?.renameSession(index) }
        sidebar.onDuplicateAsWorktree = { [weak self] index in
            self?.duplicateSessionAsWorktree(index)
        }
        sidebar.onRemove = { [weak self] index in self?.confirmRemoveSession(index) }
        sidebar.onEditVisitLimit = { [weak self] index in self?.editVisitLimit(index) }
        root = RootView(sidebar: sidebar)
        window.contentView = root

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Sobe o code-server antes dos nós: EditorNode espera o healthz e só
        // então carrega, evitando WKWebView batendo em porta morta.
        CodeServer.shared.start()

        AppControl.sessionNames = { [weak self] in self?.configs.map(\.name) ?? [] }
        AppControl.canvasGeometry = { [weak self] in self?.canvasGeometry() ?? [:] }
        AppControl.sessionEdges = { [weak self] name in
            self?.configs.first { $0.name == name }?.edgeList ?? []
        }
        AppControl.sessionVisitLimit = { [weak self] name in
            self?.configs.first { $0.name == name }?.visitLimit ?? 3
        }
        AppControl.nodeRole = { [weak self] address in
            let parts = address.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return self?.configs.first { $0.name == parts[0] }?
                .nodes.first { $0.id == parts[1] }?.prompt
        }
        AppControl.recordSession = { [weak self] target, id in
            self?.recordSession(target: target, id: id)
        }
        AppControl.activateSession = { [weak self] name in
            guard let self, let index = self.configs.firstIndex(where: { $0.name == name })
            else { return false }
            self.activate(index)
            return true
        }

        // Sem sessões, a barra da esquerda explica o + e o canvas fica de fora.
        if configs.isEmpty {
            Log.write("nenhuma sessão configurada — use + na barra lateral")
        } else {
            activate(0)
        }

        Dispatcher.shared.start()
        control.start()

        // 0.12s é o passo do spinner: mais lento ele engasga, mais rápido não
        // acrescenta nada que o olho veja. Quem desenha compara antes de
        // escrever, então nó e linha parados não custam redesenho.
        //
        // A barra lateral é atualizada junto e à parte do canvas: ela mostra as
        // sessões inativas, cujo canvas nem existe na hierarquia de views.
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.canvases[self.activeIndex]?.refreshBadges()
            self.root.sidebar.showActivity(Dispatcher.shared.activitySummary())
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // O debounce pode estar pendente; um arrasto feito segundos antes de
        // sair não pode se perder.
        persistTimer?.invalidate()
        for index in canvases.keys { syncFrames(index: index) }
        SessionStore.save(configs)

        control.stop()
        CodeServer.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Sessões

    private func activate(_ index: Int) {
        guard index >= 0, index < configs.count, index != activeIndex else { return }
        let canvas = canvases[index] ?? build(index)
        activeIndex = index
        root.show(canvas)
        root.sidebar.select(index)
        root.sidebar.markLive(index)
        window.title = "\(Flavor.current.displayName) — \(configs[index].name)"
        Log.write("sessão ativa: \(configs[index].name)")
    }

    // MARK: - Criar, renomear e remover sessão

    /// Pasta primeiro, nome depois: o nome quase sempre é o da pasta, então
    /// perguntar na ordem inversa faria você digitar o que o app já sabe.
    private func createSession() {
        let panel = NSOpenPanel()
        panel.title = "Pasta da sessão"
        panel.message = "Escolha a pasta — pode ser um repositório ou uma worktree."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar esta pasta"

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard let (name, template) = askSessionNameAndTemplate(
            suggested: folder.lastPathComponent) else { return }

        var config = SessionConfig(
            name: SessionStore.availableName(basedOn: name, taken: configs.map(\.name)),
            path: (folder.path as NSString).abbreviatingWithTildeInPath,
            nodes: template.flatMap { TemplateStore.template(named: $0)?.instantiate() } ?? [],
            template: template)

        // Frames vindos do template já servem; sem template a sessão nasce vazia
        // e você monta pela barra.
        if config.nodes.isEmpty { config.nodes = [] }

        configs.append(config)
        root.sidebar.reload(configs)
        Log.write("sessão \"\(config.name)\" criada em \(config.path)"
                  + (template.map { " a partir do template \"\($0)\"" } ?? " vazia"))
        schedulePersist()
        activate(configs.count - 1)
    }

    /// Cria uma worktree do repositório escolhido e abre uma sessão nela.
    ///
    /// O ponto de partida é o HEAD atual, em uma branch nova — o git recusa a
    /// mesma branch em duas worktrees, por design.
    private func createSessionFromWorktree() {
        let panel = NSOpenPanel()
        panel.title = "Repositório de origem"
        panel.message = "Escolha o repositório. A worktree sai do commit em que ele está agora."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar este repositório"
        guard panel.runModal() == .OK, let repo = panel.url else { return }

        let status: Worktree.Status
        do {
            status = try Worktree.status(of: repo.path)
        } catch {
            presentError("Não consegui ler o repositório", error)
            return
        }

        let suggestedBranch = Worktree.availableBranch(basedOn: status.branch, in: repo.path)
        guard let form = askWorktreeForm(status: status,
                                         repoRoot: status.repoRoot,
                                         suggestedBranch: suggestedBranch) else { return }

        let created: Worktree.Created
        do {
            created = try Worktree.create(from: status.repoRoot,
                                          branch: form.branch,
                                          destination: form.destination,
                                          carryDirty: true)
        } catch {
            presentError("Não consegui criar a worktree", error)
            return
        }

        var config = SessionConfig(
            name: SessionStore.availableName(basedOn: Worktree.sanitize(created.branch),
                                             taken: configs.map(\.name)),
            path: (created.path as NSString).abbreviatingWithTildeInPath,
            nodes: form.template.flatMap { TemplateStore.template(named: $0)?.instantiate() } ?? [],
            template: form.template)
        if config.nodes.isEmpty { config.nodes = [] }

        configs.append(config)
        root.sidebar.reload(configs)
        schedulePersist()
        activate(configs.count - 1)

        // A cópia do que o git não versiona roda depois de a sessão existir: com
        // node_modules e Pods no meio, esperar por ela antes de mostrar qualquer
        // coisa pareceria travamento.
        let canvas = canvases[configs.count - 1]
        canvas?.showBanner("Copiando o que o git não versiona (.env, node_modules, build…)")
        Worktree.copyUnversioned(from: status.repoRoot, to: created.path) { summary in
            canvas?.showBanner(summary)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { canvas?.showBanner(nil) }
        }
    }

    /// Duplica a sessão numa worktree nova, com os mesmos nós.
    ///
    /// Partir da sessão em vez do `+` é o que dispensa escolher template: o que
    /// se quer é "outra igual a esta, em outra branch".
    private func duplicateSessionAsWorktree(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let origin = configs[index]

        let status: Worktree.Status
        do {
            status = try Worktree.status(of: origin.url.path)
        } catch {
            presentError("\"\(origin.name)\" não é um repositório git", error)
            return
        }

        let suggested = Worktree.availableBranch(basedOn: status.branch, in: origin.url.path)
        guard let form = askWorktreeForm(status: status,
                                         repoRoot: status.repoRoot,
                                         suggestedBranch: suggested,
                                         inheriting: origin) else { return }

        let created: Worktree.Created
        do {
            created = try Worktree.create(from: status.repoRoot,
                                          branch: form.branch,
                                          destination: form.destination,
                                          carryDirty: true)
        } catch {
            presentError("Não consegui criar a worktree", error)
            return
        }

        // `cwd` é relativo à raiz da sessão, então os nós valem nos dois casos
        // sem reescrita: cada terminal e o editor resolvem dentro da worktree.
        let nodes = Self.relativized(origin.nodes, originRoot: origin.url.path)
        let worktreePath = (created.path as NSString).abbreviatingWithTildeInPath

        let alvo: Int
        switch form.target {
        case .newSession:
            // As ligações vêm junto: elas são parte da montagem, tanto quanto os
            // nós. A aresta guarda id de nó, e a duplicação preserva os ids, então
            // a rede da worktree nasce igual à da origem — quem podia acionar
            // quem continua podendo, no checkout novo.
            let config = SessionConfig(
                name: SessionStore.availableName(basedOn: Worktree.sanitize(created.branch),
                                                 taken: configs.map(\.name)),
                path: worktreePath,
                nodes: nodes,
                template: origin.template,
                edges: origin.edges,
                maxVisits: origin.maxVisits)
            configs.append(config)
            alvo = configs.count - 1
            root.sidebar.reload(configs)
            activate(alvo)
            Log.write("sessão \"\(origin.name)\" duplicada em \"\(config.name)\" "
                      + "(\(nodes.count) nós, worktree \(created.path))")

        case .moveCurrent:
            configs[index].path = worktreePath
            configs[index].nodes = nodes
            alvo = index

            // O canvas inteiro é remontado: um pty não muda de diretório depois
            // de aberto, e reconstruir reaproveita o mesmo caminho de sempre em
            // vez de um segundo, quase igual, só para esta situação.
            if let canvas = canvases[index] {
                canvas.nodes.forEach { $0.prepareForRemoval() }
                canvases[index] = nil
                if index == activeIndex { root.show(NSView()) }
            }
            activeIndex = -1
            root.sidebar.reload(configs)
            activate(index)
            Log.write("sessão \"\(origin.name)\" movida para a worktree \(created.path) "
                      + "— \(nodes.count) nós reiniciados lá")
        }

        schedulePersist()

        let canvas = canvases[alvo]
        canvas?.showBanner("Copiando o que o git não versiona (.env, node_modules, build…)")
        Worktree.copyUnversioned(from: status.repoRoot, to: created.path) { summary in
            canvas?.showBanner(summary)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { canvas?.showBanner(nil) }
        }
    }

    /// Converte `cwd` absoluto em relativo à raiz da sessão.
    ///
    /// Um caminho absoluto sobreviveria à duplicação apontando para o checkout de
    /// origem: o terminal da worktree abriria na pasta errada, e nada avisaria.
    /// Prepara os nós da sessão de origem para nascerem na worktree: `cwd`
    /// relativo à raiz nova, e sem a conversa de quem serviu de molde.
    private static func relativized(_ nodes: [NodeConfig], originRoot: String) -> [NodeConfig] {
        var result = nodes.map(\.withoutConversation)
        for i in result.indices {
            guard let cwd = result[i].cwd, cwd.hasPrefix("/") || cwd.hasPrefix("~") else { continue }
            let expanded = (cwd as NSString).expandingTildeInPath
            if expanded == originRoot {
                result[i].cwd = nil
            } else if expanded.hasPrefix(originRoot + "/") {
                result[i].cwd = String(expanded.dropFirst(originRoot.count + 1))
            } else {
                // Fora do repositório: não há equivalente na worktree, então cai
                // na raiz dela em vez de continuar apontando para outro lugar.
                Log.write("duplicar: nó \"\(result[i].id)\" tinha cwd fora do repositório "
                          + "(\(cwd)) — passou a usar a raiz da worktree")
                result[i].cwd = nil
            }
        }
        return result
    }

    /// O que fazer com a worktree recém-criada.
    private enum WorktreeDestination {
        /// Sessão nova na lista; a de origem continua intacta e rodando.
        case newSession
        /// A sessão atual passa a apontar para a worktree. Os terminais são
        /// reiniciados lá — não há como trocar o diretório de um pty em curso.
        case moveCurrent
    }

    private struct WorktreeForm {
        let branch: String
        let destination: String
        let template: String?
        let target: WorktreeDestination
    }

    private func askWorktreeForm(status: Worktree.Status,
                                 repoRoot: String,
                                 suggestedBranch: String,
                                 inheriting origin: SessionConfig? = nil) -> WorktreeForm? {
        let alert = NSAlert()
        alert.messageText = "Nova worktree de \((repoRoot as NSString).lastPathComponent)"
        alert.informativeText = worktreeSummary(status: status)
        alert.addButton(withTitle: "Criar")
        alert.addButton(withTitle: "Cancelar")

        // Duplicando há duas saídas; a partir do `+`, sem sessão de origem, só
        // faz sentido abrir uma nova.
        let offersMove = origin != nil
        // 200 e não 178: com a altura anterior o segundo radio e sua explicação
        // caíam em cima do rótulo "BRANCH NOVA", que fica em y=95.
        let height: CGFloat = offersMove ? 200 : 108
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: height))

        func label(_ text: String, y: CGFloat) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 10, weight: .semibold)
            field.textColor = .secondaryLabelColor
            field.frame = NSRect(x: 0, y: y, width: 380, height: 13)
            return field
        }

        // Radio e não popup: as duas saídas são diferentes o bastante para
        // precisarem estar visíveis lado a lado — uma reinicia processos, a outra
        // não.
        let newSessionRadio = NSButton(radioButtonWithTitle:
            "Abrir uma sessão nova na worktree", target: nil, action: nil)
        let moveRadio = NSButton(radioButtonWithTitle:
            "Mudar esta sessão para a worktree", target: nil, action: nil)

        // Precisa continuar vivo enquanto o modal roda: é ele quem responde pelos
        // cliques dos radios.
        let radios = RadioGroup([newSessionRadio, moveRadio])

        if offersMove {
            container.addSubview(label("O QUE FAZER", y: 187))

            newSessionRadio.frame = NSRect(x: 0, y: 167, width: 380, height: 18)
            newSessionRadio.state = .on
            container.addSubview(newSessionRadio)

            let newHint = NSTextField(labelWithString:
                "Nada aqui é reiniciado; você troca entre as duas na barra.")
            newHint.font = .systemFont(ofSize: 10)
            newHint.textColor = .secondaryLabelColor
            newHint.frame = NSRect(x: 18, y: 152, width: 362, height: 14)
            container.addSubview(newHint)

            moveRadio.frame = NSRect(x: 0, y: 132, width: 380, height: 18)
            container.addSubview(moveRadio)

            let moveHint = NSTextField(labelWithString:
                "Os terminais reiniciam na pasta nova — o que estiver rodando neles para.")
            moveHint.font = .systemFont(ofSize: 10)
            moveHint.textColor = .secondaryLabelColor
            moveHint.maximumNumberOfLines = 2
            moveHint.frame = NSRect(x: 18, y: 116, width: 362, height: 14)
            container.addSubview(moveHint)
        }

        container.addSubview(label("BRANCH NOVA", y: 95))
        let branchField = NSTextField(frame: NSRect(x: 0, y: 70, width: 380, height: 22))
        branchField.stringValue = suggestedBranch
        container.addSubview(branchField)

        container.addSubview(label("PASTA DA WORKTREE", y: 52))
        let pathField = NSTextField(frame: NSRect(x: 0, y: 27, width: 380, height: 22))
        pathField.stringValue = Worktree.suggestedPath(repoRoot: repoRoot, branch: suggestedBranch)
        pathField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        container.addSubview(pathField)

        // Renomear a branch reflete no caminho sugerido, desde que você não tenha
        // editado o caminho à mão.
        var pathTouched = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: pathField, queue: .main) { _ in
                pathTouched = true
            }
        let branchObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: branchField, queue: .main) { _ in
                guard !pathTouched else { return }
                pathField.stringValue = Worktree.suggestedPath(
                    repoRoot: repoRoot, branch: branchField.stringValue)
            }
        defer {
            NotificationCenter.default.removeObserver(observer)
            NotificationCenter.default.removeObserver(branchObserver)
        }

        // Duplicando, os nós vêm da sessão de origem e não há template a escolher
        // — mostrar um seletor aqui só ofereceria uma decisão já tomada.
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 22))
        let vazio = "Começar vazia"
        if let origin {
            let inherited = NSTextField(labelWithString:
                "Os \(origin.nodes.count) nós de \"\(origin.name)\" ficam cada um na "
                + "pasta equivalente dentro da worktree.")
            inherited.font = .systemFont(ofSize: 11)
            inherited.textColor = .secondaryLabelColor
            inherited.maximumNumberOfLines = 2
            inherited.frame = NSRect(x: 0, y: -2, width: 380, height: 28)
            container.addSubview(inherited)
        } else {
            picker.addItem(withTitle: vazio)
            let templates = TemplateStore.names
            if !templates.isEmpty {
                picker.menu?.addItem(.separator())
                picker.addItems(withTitles: templates)
            }
            container.addSubview(picker)
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = branchField

        // `NSButton.target` não retém: sem prender a vida do grupo ao modal, o
        // ARC pode liberá-lo assim que sai do último uso — e os radios voltam a
        // não responder.
        let response = withExtendedLifetime(radios) { alert.runModal() }
        guard response == .alertFirstButtonReturn else { return nil }

        let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = (pathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                           as NSString).expandingTildeInPath
        guard !branch.isEmpty, !destination.isEmpty else { return nil }

        if origin != nil {
            return WorktreeForm(branch: branch, destination: destination, template: nil,
                                target: moveRadio.state == .on ? .moveCurrent : .newSession)
        }
        let chosen = picker.titleOfSelectedItem
        return WorktreeForm(branch: branch, destination: destination,
                            template: chosen == vazio ? nil : chosen,
                            target: .newSession)
    }

    /// Diz exatamente o que vai junto. "Leva tudo" sem detalhar é o tipo de
    /// promessa que só se descobre quebrada depois.
    private func worktreeSummary(status: Worktree.Status) -> String {
        var linhas = ["Sai de \(status.branch), no commit atual."]
        if status.hasDirtyTracked {
            linhas.append("As mudanças não commitadas vão junto — e continuam também no original.")
        }
        if !status.untracked.isEmpty {
            linhas.append("\(status.untracked.count) arquivo(s) novo(s) vão junto.")
        }
        linhas.append("O que o .gitignore esconde (.env, node_modules, build…) é copiado depois, "
                      + "por \(Flavor.current.config("worktree-copy.sh").path).")
        return linhas.joined(separator: "\n")
    }

    private func presentError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = "\(error)"
        alert.runModal()
        Log.write("\(title): \(error)")
    }

    /// Um diálogo só para nome e template: são a mesma decisão ("o que é esta
    /// sessão"), e separar em dois passos só adiciona cliques.
    private func askSessionNameAndTemplate(suggested: String) -> (String, String?)? {
        let alert = NSAlert()
        alert.messageText = "Nova sessão"
        alert.informativeText = "O nome é a primeira parte do endereço de dispatch."
        alert.addButton(withTitle: "Criar")
        alert.addButton(withTitle: "Cancelar")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 54))

        let field = NSTextField(frame: NSRect(x: 0, y: 30, width: 280, height: 24))
        field.stringValue = suggested
        field.placeholderString = "nome da sessão"
        container.addSubview(field)

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let vazio = "Começar vazia"
        picker.addItem(withTitle: vazio)
        let templates = TemplateStore.names
        if !templates.isEmpty {
            picker.menu?.addItem(.separator())
            picker.addItems(withTitles: templates)
        }
        container.addSubview(picker)

        alert.accessoryView = container
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = picker.titleOfSelectedItem
        return (name.isEmpty ? suggested : name, chosen == vazio ? nil : chosen)
    }

    /// Renomear mexe no endereço de dispatch, então os alvos vivos são
    /// re-registrados — sem derrubar terminal nem recarregar o editor.
    private func renameSession(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let current = configs[index].name

        let alert = NSAlert()
        alert.messageText = "Renomear sessão"
        alert.informativeText = "\"\(current)\" é a primeira parte do endereço de dispatch "
            + "(\(current)/…). Os alvos abertos passam a atender pelo nome novo."
        alert.addButton(withTitle: "Renomear")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, typed != current else { return }

        let taken = configs.enumerated().filter { $0.offset != index }.map(\.element.name)
        let name = SessionStore.availableName(basedOn: typed, taken: taken)

        configs[index].name = name
        canvases[index]?.nodes.forEach { $0.sessionRenamed(to: name) }
        root.sidebar.reload(configs)
        root.sidebar.select(activeIndex)
        markLiveSessions()
        if index == activeIndex { window.title = "\(Flavor.current.displayName) — \(name)" }
        Log.write("sessão \"\(current)\" renomeada para \"\(name)\"")
        schedulePersist()
    }

    private func confirmRemoveSession(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let config = configs[index]
        let live = canvases[index] != nil
        // Só worktree ligada: oferecer isso para o checkout principal seria
        // oferecer apagar o repositório.
        let isWorktree = config.exists && Worktree.isLinkedWorktree(config.url.path)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remover a sessão \"\(config.name)\"?"
        alert.informativeText = live
            ? "Os terminais abertos são encerrados."
            : "A sessão sai da lista."
        alert.addButton(withTitle: "Remover")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true

        var checkbox: NSButton?
        if isWorktree {
            let box = NSButton(checkboxWithTitle: "Também apagar a worktree do disco",
                               target: nil, action: nil)
            box.state = .off
            let hint = NSTextField(labelWithString:
                "\(config.path)\nDesmarcado, a pasta fica onde está e você pode reabri-la depois.")
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = .secondaryLabelColor
            hint.maximumNumberOfLines = 2

            let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 52))
            box.frame = NSRect(x: 0, y: 30, width: 360, height: 18)
            hint.frame = NSRect(x: 18, y: 0, width: 342, height: 28)
            container.addSubview(box)
            container.addSubview(hint)
            alert.accessoryView = container
            checkbox = box
        } else {
            alert.informativeText += " A pasta \(config.path) não é tocada."
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard checkbox?.state == .on else {
            removeSession(index)
            return
        }
        guard confirmWorktreeLosses(config) else { return }

        // Apagar antes de tirar a sessão da lista: se o git recusar, você fica com
        // a sessão e com a pasta, em vez de perder a sessão e ficar com a pasta.
        do {
            try Worktree.remove(config.url.path)
        } catch {
            presentError("A sessão não foi removida", error)
            return
        }
        removeSession(index)
    }

    /// Segundo passo, só quando há trabalho a perder. `worktree remove` precisa de
    /// `--force` aqui — a worktree nasce suja de propósito — e forçar sem mostrar
    /// o que morre seria apagar às escuras.
    private func confirmWorktreeLosses(_ config: SessionConfig) -> Bool {
        guard let losses = try? Worktree.losses(in: config.url.path) else { return true }
        guard !losses.isEmpty else { return true }

        var linhas: [String] = []
        if !losses.modified.isEmpty {
            linhas.append("\(losses.modified.count) arquivo(s) com mudanças não commitadas:")
            linhas.append(contentsOf: losses.modified.prefix(6).map { "   \($0)" })
            if losses.modified.count > 6 {
                linhas.append("   … e outros \(losses.modified.count - 6)")
            }
        }
        if !losses.untracked.isEmpty {
            linhas.append("\(losses.untracked.count) arquivo(s) novo(s), nunca commitados.")
        }
        if losses.unpushedCommits > 0 {
            linhas.append("\(losses.unpushedCommits) commit(s) ainda não enviados — esses "
                          + "sobrevivem na branch \(Worktree.branchOf(config.url.path) ?? "?"), "
                          + "que não é apagada.")
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Isto apaga trabalho não commitado"
        alert.informativeText = linhas.joined(separator: "\n")
        alert.addButton(withTitle: "Apagar mesmo assim")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func removeSession(_ index: Int) {
        let name = configs[index].name

        // Solta os processos antes de perder a referência ao canvas.
        if let canvas = canvases[index] {
            canvas.nodes.forEach { $0.prepareForRemoval() }
            if index == activeIndex { root.show(NSView()) }
        }

        // Os canvases são indexados por posição, e remover do meio desloca todo
        // mundo à direita — reindexar aqui evita canvas apontando para a sessão
        // errada.
        configs.remove(at: index)
        var reindexed: [Int: CanvasContainer] = [:]
        for (key, canvas) in canvases where key != index {
            reindexed[key > index ? key - 1 : key] = canvas
        }
        canvases = reindexed

        // wire() capturou o índice antigo por valor; religa com o novo.
        for (key, canvas) in canvases { wire(canvas, index: key) }

        activeIndex = -1
        root.sidebar.reload(configs)
        Log.write("sessão \"\(name)\" removida")
        schedulePersist()

        if !configs.isEmpty { activate(min(index, configs.count - 1)) }
        else { window.title = "Egeon Deck" }
    }

    private func markLiveSessions() {
        root.sidebar.markLive(indices: Set(canvases.keys))
    }

    // MARK: - Templates

    /// Salva o canvas atual como preset. O que vira template é o `SessionConfig`
    /// já sincronizado, então o layout gravado é o que está na tela.
    private func saveCurrentAsTemplate() {
        guard activeIndex >= 0, activeIndex < configs.count else { return }
        syncFrames(index: activeIndex)

        let session = configs[activeIndex]
        guard !session.nodes.isEmpty else {
            let empty = NSAlert()
            empty.messageText = "Canvas vazio"
            empty.informativeText = "Monte os nós que você quer no preset e salve de novo."
            empty.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Salvar como template"
        alert.informativeText = Self.templateSummary(of: session)
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "nome do template"
        // O nome da sessão, e não o do template de origem: este botão cria um
        // preset novo. Atualizar o de origem é o botão ao lado.
        field.stringValue = session.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if TemplateStore.template(named: name) != nil {
            let overwrite = NSAlert()
            overwrite.alertStyle = .warning
            overwrite.messageText = "Já existe um template \"\(name)\""
            overwrite.informativeText = "Substituir pelo canvas atual?"
            overwrite.addButton(withTitle: "Substituir")
            overwrite.addButton(withTitle: "Cancelar")
            guard overwrite.runModal() == .alertFirstButtonReturn else { return }
        }

        TemplateStore.put(TemplateStore.capture(from: session), named: name)
        configs[activeIndex].template = name
        // A sessão passa a ter origem: o botão de atualizar aparece agora, sem
        // esperar o próximo arranque.
        canvases[activeIndex]?.originTemplate = name
        schedulePersist()
    }

    /// Regrava o template de que esta sessão nasceu, com o canvas de agora.
    ///
    /// Botão separado do "salvar como", e não o mesmo com o nome pré-preenchido:
    /// são intenções diferentes. Uma cria um preset novo e pede nome; a outra
    /// atualiza um que já existe e já tem nome — pedir de novo só cria a chance
    /// de errar uma letra e nascer um template gêmeo.
    ///
    /// Editar o template não mexe em quem já nasceu dele: os valores foram
    /// copiados na criação, e as sessões existentes seguem como estão.
    private func updateOriginTemplate(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let session = configs[index]
        guard let name = session.template else { return }

        guard !session.nodes.isEmpty else {
            let empty = NSAlert()
            empty.messageText = "Canvas vazio"
            empty.informativeText = "Um template sem nós não abre nada. "
                + "Monte o canvas e atualize de novo."
            empty.runModal()
            return
        }

        // O template pode ter sido apagado desde que esta sessão nasceu: aí não
        // há o que atualizar, e virar um "salvar como" silencioso seria pior.
        guard TemplateStore.template(named: name) != nil else {
            let sumiu = NSAlert()
            sumiu.messageText = "O template \"\(name)\" não existe mais"
            sumiu.informativeText = "Use \"salvar como template\" para criá-lo de novo."
            sumiu.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Atualizar o template \"\(name)\"?"
        alert.informativeText = Self.templateSummary(of: session)
            + "\n\nAs sessões que já nasceram deste template não mudam."
        alert.addButton(withTitle: "Atualizar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        TemplateStore.put(TemplateStore.capture(from: session), named: name)
        Log.write("template \"\(name)\" atualizado a partir da sessão \"\(session.name)\"")
    }

    /// Diz o que está sendo salvo, em uma linha: sem isso o diálogo pede um nome
    /// para algo que o usuário não vê.
    private static func templateSummary(of session: SessionConfig) -> String {
        var counts: [NodeKind: Int] = [:]
        for node in session.nodes { counts[node.type, default: 0] += 1 }

        let rótulos: [(NodeKind, String, String)] = [
            (.editor, "editor", "editores"),
            (.agent, "agente", "agentes"),
            (.shell, "terminal", "terminais"),
            (.web, "web", "webs")
        ]
        let partes = rótulos.compactMap { kind, singular, plural -> String? in
            guard let n = counts[kind], n > 0 else { return nil }
            return "\(n) \(n == 1 ? singular : plural)"
        }

        return partes.joined(separator: ", ")
            + " — com posição, tamanho, pasta de cada nó e "
            + "\(session.path) como pasta inicial."
    }

    /// Layout de quem ainda não tem frame gravado: editor à esquerda, o resto
    /// empilhado à direita. Um nó só passa por aqui uma vez — na primeira vez o
    /// resultado é escrito no sessions.json e a partir daí manda o arquivo.
    private func defaultFrames(for config: SessionConfig) -> [String: NSRect] {
        let size = root.contentFrame.size
        let margin: CGFloat = 40
        let gap: CGFloat = 16
        let usableW = max(900, size.width - margin * 2)
        let usableH = max(600, size.height - margin * 2)
        let editorW = (usableW * 0.62).rounded()
        let columnX = margin + editorW + gap
        let columnW = usableW - editorW - gap

        let stacked = config.nodes.filter { $0.type != .editor }
        let rowH = stacked.isEmpty ? usableH
            : ((usableH - gap * CGFloat(stacked.count - 1)) / CGFloat(stacked.count)).rounded()

        var frames: [String: NSRect] = [:]
        var row = 0
        for node in config.nodes {
            if node.type == .editor {
                frames[node.id] = NSRect(x: margin, y: margin, width: editorW, height: usableH)
            } else {
                frames[node.id] = NSRect(x: columnX,
                                         y: margin + CGFloat(row) * (rowH + gap),
                                         width: columnW, height: rowH)
                row += 1
            }
        }
        return frames
    }

    /// Como o terminal sobe: a linha de comando e, quando não houver jeito
    /// melhor, um texto a ser digitado depois.
    ///
    /// Dois textos entram no system prompt: o protocolo de marcador de fim de
    /// turno (sempre, ADR-011) e o papel deste terminal (quando houver). Vão na
    /// linha de comando sempre que o CLI aceitar. Injetar depois significa colar
    /// e apertar Enter na TUI — que é lento, aparece na tela como se alguém
    /// tivesse digitado, gasta um turno da conversa e ainda pode falhar se a TUI
    /// não estiver pronta. A flag entrega tudo já dentro do processo, antes do
    /// primeiro byte de saída.
    /// Como este nó fala com os outros, para o system prompt.
    ///
    /// Não lista os vizinhos: a lista envelhece. O catálogo antigo era montado no
    /// arranque, então uma aresta criada depois nunca chegava — a seta aparecia no
    /// canvas e a ligação estava morta até você recriar o nó. Aqui vai só o
    /// caminho para PERGUNTAR, e a resposta é sempre a de agora.
    ///
    /// Vai em todo nó de agente, com ou sem aresta hoje, pelo mesmo motivo: quem
    /// sobe sem vizinho pode ganhar um no minuto seguinte.
    ///
    /// O texto é curto de propósito. Ele entra em toda conversa deste terminal, e
    /// é prefixo de cache — quanto menos muda, melhor.
    private static func catalog(for node: NodeConfig,
                                in config: SessionConfig,
                                agents: [String: AgentProfile]) -> String? {
        guard node.type == .agent else { return nil }
        return """
            Este terminal é um nó do Egeon Deck e tem vizinhos endereçáveis. \
            Use o comando `egeon`:

              egeon peers                     quem você pode acionar agora
              egeon send <endereço> <<'MB'    manda o texto para ele
              (o que você quer dizer)
              MB

            Lista vazia significa que ninguém está ligado a você neste momento; \
            ela muda enquanto você trabalha, então consulte na hora em vez de \
            confiar na memória. Acionar não é obrigatório, e responder a uma \
            mensagem também não. Endereço fora da lista é recusado, e uma cadeia \
            longa demais de agentes falando entre si também — quando isso \
            acontecer, volte a falar com o Julio em vez de insistir.
            """
    }

    private static func launchPlan(for node: NodeConfig,
                                   profile: AgentProfile?,
                                   catalog: String?) -> (command: String,
                                                         promptToInject: String?) {
        let base = node.cmd
            ?? profile.map { $0.command.joined(separator: " ") }
            ?? "exec /bin/zsh -l"

        guard node.type == .agent, let profile,
              let text = profile.systemPromptText(role: node.prompt, catalog: catalog)
        else { return (base, nil) }

        if let arguments = profile.systemPromptArguments(for: text), profile.runsOwnBinary(base) {
            var extras = arguments
            // O gancho de relato entra junto: é o que faz o app saber quando VOCÊ
            // troca de conversa dentro da TUI.
            if let report = profile.reportArguments(hookFile: AgentHooks.settingsFile.path) {
                extras += report
            }
            let flags = " " + extras.map(AppEnvironment.shellQuote).joined(separator: " ")
            return (sessionCommand(base: base, flags: flags, node: node, profile: profile), nil)
        }

        // CLI sem flag de system prompt (ou `cmd` trocado por outro programa):
        // resta injetar como primeira mensagem. Vale a pena junto de um papel
        // que já ia ser injetado de qualquer jeito; só pelo protocolo, não —
        // seria gastar um turno em toda sessão para um marcador que se dilui
        // depois de vinte mensagens. Aí o terminal fica só com o silêncio.
        guard let role = node.prompt, !role.isEmpty else {
            if profile.attentionConfig.activeMarker != nil {
                Log.write("agente \(profile.displayName): sem flag de system prompt, "
                          + "o protocolo de marcador não sobe — a detecção fica só no "
                          + "silêncio", key: "marker.\(profile.displayName)")
            }
            return (base, nil)
        }
        return (base, text)
    }

    /// A linha de comando que retoma a conversa deste terminal, ou cria a
    /// primeira.
    ///
    /// Retomar e criar são flags diferentes no CLI: `--session-id` num id que já
    /// existe é recusado com `already in use`. Então a primeira subida cria, e as
    /// seguintes retomam.
    ///
    /// O `||` é a rede: `--resume` de um id cujo arquivo de conversa não existe
    /// mais — porque você limpou, ou porque a criação falhou antes de o CLI
    /// gravar — sai com 1, e aí a mesma linha cria a conversa com aquele id em vez
    /// de deixar o terminal morto. Medido nas duas situações no Claude Code
    /// 2.1.229.
    private static func sessionCommand(base: String, flags: String,
                                       node: NodeConfig, profile: AgentProfile) -> String {
        guard profile.keepsSession, let id = node.sessionId,
              let resume = profile.sessionArguments(profile.resume, id: id),
              let fresh = profile.sessionArguments(profile.newSession, id: id) else {
            return base + flags
        }
        func line(_ arguments: [String]) -> String {
            base + " " + arguments.map(AppEnvironment.shellQuote).joined(separator: " ") + flags
        }
        // `sessionStarted` diz se já houve uma primeira subida: sem isso a linha
        // de estreia mostraria "No conversation found" antes de criar.
        return node.hasStartedSession ? "\(line(resume)) || \(line(fresh))" : line(fresh)
    }

    /// Garante que um nó de agente tenha id de sessão próprio antes de subir.
    ///
    /// Ponto único: os cinco lugares que criam nó passam por aqui, então gerar o
    /// id em outro lugar não faz sentido.
    private func prepared(_ node: NodeConfig, index: Int) -> NodeConfig {
        guard node.type == .agent,
              let profile = node.agent.flatMap({ agents[$0] }), profile.keepsSession,
              let position = configs[index].nodes.firstIndex(where: { $0.id == node.id })
        else { return node }

        if configs[index].nodes[position].sessionId == nil {
            configs[index].nodes[position].sessionId = UUID().uuidString
            schedulePersist()
            Log.write("sessão \(configs[index].name): nó \"\(node.id)\" ganhou conversa "
                      + "\(configs[index].nodes[position].sessionId ?? "?")")
        }
        return configs[index].nodes[position]
    }

    /// O CLI relatou qual conversa está aberta neste terminal.
    ///
    /// Chamado a cada prompt do agente, então só grava quando o valor muda de
    /// fato — senão seria uma reescrita do sessions.json por mensagem sua.
    private func recordSession(target: String, id: String) {
        let parts = target.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let index = configs.firstIndex(where: { $0.name == parts[0] }),
              let position = configs[index].nodes.firstIndex(where: { $0.id == parts[1] }),
              configs[index].nodes[position].sessionId != id else { return }

        let anterior = configs[index].nodes[position].sessionId ?? "nenhuma"
        configs[index].nodes[position].sessionId = id
        configs[index].nodes[position].sessionStarted = true
        schedulePersist()
        Log.write("conversa[\(target)]: \(anterior) → \(id)")
    }

    private func makeNode(_ raw: NodeConfig, in config: SessionConfig, frame: NSRect) -> NodeView {
        let index = configs.firstIndex { $0.name == config.name } ?? -1
        let node = index >= 0 ? prepared(raw, index: index) : raw
        let address = config.address(of: node)
        let title = "\(config.name)/\(node.id)"

        switch node.type {
        case .editor:
            return EditorNode(frame: frame, address: address, title: title,
                              folder: config.directory(for: node))

        case .web:
            let web = WebNode(frame: frame, address: address, title: title,
                              url: node.url, profile: node.profile)
            web.onStateChanged = { [weak self] web in
                self?.updateWebNode(session: config.name, id: node.id,
                                    url: web.currentURL, profile: web.profileName)
            }
            return web

        case .shell, .agent:
            let profile = node.agent.flatMap { agents[$0] }
            if node.type == .agent && profile == nil {
                Log.write("sessão \(config.name): perfil de agente "
                          + "'\(node.agent ?? "?")' não existe em agents.json")
            }
            let launch = Self.launchPlan(
                for: node, profile: profile,
                catalog: Self.catalog(for: node, in: config, agents: agents))

            let terminal = TerminalNode(frame: frame, address: address, title: title,
                                        cwd: config.directory(for: node),
                                        command: launch.command, profile: profile,
                                        config: node.config,
                                        prompt: launch.promptToInject)
            if index >= 0, node.sessionId != nil, !node.hasStartedSession,
               let position = configs[index].nodes.firstIndex(where: { $0.id == node.id }) {
                configs[index].nodes[position].sessionStarted = true
                schedulePersist()
            }
            return terminal
        }
    }

    private func build(_ index: Int) -> CanvasContainer {
        let canvas = CanvasContainer(frame: root.contentFrame)
        canvases[index] = canvas
        wire(canvas, index: index)

        guard configs[index].exists else {
            canvas.showBanner("Caminho não existe: \(configs[index].path) — edite \(Flavor.current.config("sessions.json").path)")
            Log.write("sessão \(configs[index].name): caminho inexistente \(configs[index].path)")
            return canvas
        }

        let defaults = defaultFrames(for: configs[index])
        for i in configs[index].nodes.indices {
            let node = configs[index].nodes[i]
            var frame = node.frame
                ?? defaults[node.id]
                ?? NSRect(x: 40, y: 40, width: 720, height: 460)

            // Nó gravado em coordenada negativa não é alcançável: o scroll não
            // vai a x<0 nem y<0, então não há gesto que o traga de volta. Isso
            // era possível antes do arrasto ganhar limite, e o arquivo pode ter
            // ficado com nós lá.
            if frame.minX < 0 || frame.minY < 0 {
                Log.write("sessão \(configs[index].name): nó \"\(node.id)\" estava fora do "
                          + "documento em (\(Int(frame.minX)),\(Int(frame.minY))) — resgatado")
                frame.origin.x = max(0, frame.minX)
                frame.origin.y = max(0, frame.minY)
            }

            configs[index].nodes[i].setFrame(frame)
            canvas.add(makeNode(node, in: configs[index], frame: frame))
        }
        schedulePersist()

        DispatchQueue.main.async {
            canvas.scroll.contentView.scroll(to: NSPoint(x: 20, y: 20))
            canvas.scroll.reflectScrolledClipView(canvas.scroll.contentView)
        }
        return canvas
    }

    // MARK: - Barra de ações

    private func wire(_ canvas: CanvasContainer, index: Int) {
        canvas.onPlace = { [weak self] tool, rect in self?.place(tool, rect: rect, index: index) }
        canvas.onLayoutChanged = { [weak self] in
            self?.syncFrames(index: index)
            self?.schedulePersist()
        }
        canvas.onRequestClose = { [weak self] node in self?.confirmRemoval(of: node, index: index) }
        canvas.onSaveTemplate = { [weak self] in self?.saveCurrentAsTemplate() }
        canvas.onUpdateTemplate = { [weak self] in self?.updateOriginTemplate(index) }
        canvas.originTemplate = configs[index].template
        canvas.onNewWorktree = { [weak self] in self?.duplicateSessionAsWorktree(index) }
        canvas.componentNames = { ComponentStore.names }
        canvas.onConfigureTerminal = { [weak self] in self?.configureNewTerminal(index: index) }
        canvas.onRequestEditNode = { [weak self] node in
            self?.editNode(node, index: index)
        }
        canvas.onCreateEdge = { [weak self] edge in self?.addEdge(edge, index: index) }
        canvas.onRemoveEdge = { [weak self] edge in self?.removeEdge(edge, index: index) }
        canvas.onEditEdgeLimit = { [weak self] edge in self?.editEdgeLimit(edge, index: index) }
        canvas.edges = configs[index].edgeList
    }

    // MARK: - Ligações entre terminais

    private func addEdge(_ edge: EdgeConfig, index: Int) {
        guard index >= 0, index < configs.count, let canvas = canvases[index] else { return }
        var edges = configs[index].edgeList
        guard !edges.contains(edge) else { return }
        edges.append(edge)
        configs[index].edges = edges
        canvas.edges = edges
        schedulePersist()

        let session = configs[index].name
        Log.write("aresta[\(session)]: \(edge.from) → \(edge.to)")

        // Ciclo é legítimo — revisor e implementador são exatamente isso — mas
        // não pode ser silencioso: é ele que faz duas máquinas conversarem sem
        // você no meio.
        if let cycle = Self.cycle(through: edge, in: edges) {
            let limit = configs[index].visitLimit
            canvas.showBanner("Ciclo: \(cycle.joined(separator: " → ")) — "
                              + "cada terminal entra \(limit)× na mesma cadeia, depois recusa")
            Log.write("aresta[\(session)]: ciclo \(cycle.joined(separator: " → ")), "
                      + "limite de \(limit) visitas")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak canvas] in
                canvas?.showBanner(nil)
            }
        }
    }

    /// Teto de revisitas da sessão — a rede, não o botão do dia a dia.
    private func editVisitLimit(_ index: Int) {
        guard index >= 0, index < configs.count else { return }

        let alert = NSAlert()
        alert.messageText = "Limite de conversa — \(configs[index].name)"
        alert.informativeText = "Quantas vezes um mesmo terminal pode entrar numa cadeia de "
            + "mensagens entre agentes antes de o Egeon Deck cortar.\n\n"
            + "Isto é a rede de segurança da sessão inteira: é o único limite que segura um "
            + "ciclo de três ou mais terminais, onde cada ligação dispara uma vez só. O ajuste "
            + "do dia a dia é na pastilha da própria seta, no canvas."
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = String(configs[index].visitLimit)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn,
              let typed = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }

        configs[index].maxVisits = max(1, typed)
        schedulePersist()
        Log.write("sessão \(configs[index].name): teto de visitas = \(configs[index].visitLimit)")
    }

    /// Quantas idas e voltas esta ligação permite.
    ///
    /// Vazio = sem limite próprio, sobra o teto da sessão. O diálogo diz isso na
    /// cara porque "vazio" e "zero" são coisas opostas aqui, e errar entre os
    /// dois é a diferença entre liberar e travar.
    private func editEdgeLimit(_ edge: EdgeConfig, index: Int) {
        guard index >= 0, index < configs.count, let canvas = canvases[index] else { return }
        let current = configs[index].edgeList.first { $0 == edge }?.maxSends

        let alert = NSAlert()
        alert.messageText = "\(edge.from) → \(edge.to)"
        alert.informativeText = "Quantas vezes esta ligação pode disparar numa mesma conversa. "
            + "Num par ligado nos dois sentidos, é o número de idas e voltas.\n\n"
            + "Vazio = sem limite próprio; vale só o teto da sessão "
            + "(\(configs[index].visitLimit) visitas por terminal)."
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = current.map(String.init) ?? ""
        field.placeholderString = "sem limite"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = typed.isEmpty ? nil : Int(typed)
        // Texto que não é número vira nada em vez de virar "sem limite": você
        // digitou algo, e interpretar isso como "libera" é o erro mais caro
        // possível nesse campo.
        if !typed.isEmpty, limit == nil { return }
        guard let position = configs[index].edgeList.firstIndex(where: { $0 == edge }) else { return }

        configs[index].edges?[position].maxSends = limit.map { max(1, $0) }
        canvas.edges = configs[index].edgeList
        schedulePersist()
        Log.write("aresta[\(configs[index].name)]: \(edge.from) → \(edge.to) "
                  + "limite \(limit.map(String.init) ?? "nenhum")")
    }

    private func removeEdge(_ edge: EdgeConfig, index: Int) {
        guard index >= 0, index < configs.count, let canvas = canvases[index] else { return }
        var edges = configs[index].edgeList
        edges.removeAll { $0 == edge }
        configs[index].edges = edges
        canvas.edges = edges
        schedulePersist()
        Log.write("aresta[\(configs[index].name)]: removida \(edge.from) → \(edge.to)")
    }

    /// Caminho de volta de `edge.to` até `edge.from`, se existir — ou seja, o
    /// ciclo que esta aresta acabou de fechar. Busca em largura: o ciclo mais
    /// curto é o que descreve melhor o que foi criado.
    private static func cycle(through edge: EdgeConfig, in edges: [EdgeConfig]) -> [String]? {
        var queue: [[String]] = [[edge.to]]
        var seen: Set<String> = [edge.to]
        while let path = queue.first {
            queue.removeFirst()
            let last = path[path.count - 1]
            if last == edge.from { return path + [edge.to] }
            for next in edges.filter({ $0.from == last }).map(\.to) where !seen.contains(next) {
                seen.insert(next)
                queue.append(path + [next])
            }
        }
        return nil
    }

    /// Remover é irreversível dentro do app — o nó sai do canvas e do
    /// sessions.json — então passa por confirmação, com o aviso que o próprio
    /// tipo de nó dá sobre o que se perde.
    private func confirmRemoval(of node: NodeView, index: Int) {
        guard index >= 0, index < configs.count, let canvas = canvases[index] else { return }

        let name = node.nodeID.isEmpty ? "este nó" : "\"\(node.nodeID)\""
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remover \(name) do sessão \(configs[index].name)?"
        alert.informativeText = node.removalWarning
        alert.addButton(withTitle: "Remover")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true

        // Folha na janela em vez de modal solto: o canvas fica visível atrás, e
        // dá pra conferir qual nó está sendo apagado.
        guard let window else {
            if alert.runModal() == .alertFirstButtonReturn { remove(node, index: index, from: canvas) }
            return
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.remove(node, index: index, from: canvas)
        }
    }

    private func remove(_ node: NodeView, index: Int, from canvas: CanvasContainer) {
        let id = node.nodeID
        canvas.remove(node)
        if !id.isEmpty {
            configs[index].nodes.removeAll { $0.id == id }
            // Aresta apontando para nó que não existe mais viraria alvo morto no
            // catálogo do agente: ele leria um endereço e o dispatch recusaria.
            let orphans = configs[index].edgeList.filter { $0.from == id || $0.to == id }
            if !orphans.isEmpty {
                configs[index].edges = configs[index].edgeList.filter {
                    $0.from != id && $0.to != id
                }
                canvas.edges = configs[index].edgeList
                Log.write("sessão \(configs[index].name): \(orphans.count) ligação(ões) "
                          + "removida(s) junto com \"\(id)\"")
            }
            Log.write("sessão \(configs[index].name): nó \"\(id)\" removido")
        }
        schedulePersist()
    }

    /// Cria um nó onde a ferramenta foi solta e grava no sessions.json.
    private func place(_ tool: CanvasTool, rect: NSRect, index: Int) {
        guard let kind = tool.nodeKind, index >= 0, index < configs.count,
              let canvas = canvases[index] else { return }

        if kind == .shell {
            // Componente escolhido no menu pula o formulário: ele já traz tipo,
            // agente, comando, pasta e papel — perguntar de novo seria repetir
            // uma decisão já tomada.
            if let name = canvas.pendingComponent,
               let component = ComponentStore.component(named: name) {
                place(component: component, rect: rect, index: index)
                return
            }

            // Sem componente, o terminal é configurado antes de existir. O
            // retângulo que você acabou de marcar é preservado, então o formulário
            // não custa a posição nem o tamanho.
            let dialog = ComponentDialog(
                title: "Novo terminal",
                confirmLabel: "Criar",
                agents: agents,
                initial: Component(name: "", kind: .agent, agent: "claude"))
            guard let result = dialog.run() else { return }
            if result.saveAsComponent { ComponentStore.put(result.component) }
            place(component: result.component, rect: rect, index: index)
            return
        }

        var node = NodeConfig(type: kind, id: nextID(prefix: tool.idPrefix, in: configs[index]))
        node.setFrame(rect)
        if kind == .web {
            node.url = WebNode.homeURL
            node.profile = WebProfileStore.defaultName
        }

        configs[index].nodes.append(node)
        canvas.add(makeNode(node, in: configs[index], frame: rect))
        Log.write("sessão \(configs[index].name): nó \(kind.rawValue) \"\(node.id)\" criado")
        schedulePersist()
    }

    // MARK: - Componentes

    /// Abre o formulário e cria o terminal no primeiro lugar livre do canvas.
    private func configureNewTerminal(index: Int) {
        guard index >= 0, index < configs.count, let canvas = canvases[index] else { return }

        let dialog = ComponentDialog(
            title: "Novo terminal",
            confirmLabel: "Criar",
            agents: agents,
            initial: Component(name: "", kind: .agent, agent: "claude"))
        guard let result = dialog.run() else { return }

        if result.saveAsComponent { ComponentStore.put(result.component) }

        let rect = canvas.spawnRect(size: CanvasTool.terminal.defaultNodeSize)
        place(component: result.component, rect: rect, index: index)
    }

    /// Materializa um componente como nó. O id vem do nome, então o endereço de
    /// dispatch fica legível: `deck/revisor`.
    private func place(component: Component, rect: NSRect, index: Int) {
        guard index >= 0, index < configs.count, let canvas = canvases[index] else { return }

        let id = nextID(prefix: ComponentStore.identifier(from: component.name),
                        in: configs[index])
        var node = ComponentStore.instantiate(component, id: id)
        node.setFrame(rect)

        configs[index].nodes.append(node)
        canvas.add(makeNode(node, in: configs[index], frame: rect))
        Log.write("sessão \(configs[index].name): \(node.type.rawValue) \"\(id)\" criado"
                  + (component.prompt == nil ? "" : " com papel"))
        schedulePersist()
    }

    /// Configura um nó já na tela.
    ///
    /// Nome, comando, agente e pasta definem como o processo foi lançado, então
    /// mudá-los exige um processo novo — não há como reconfigurar um pty em
    /// andamento. O diálogo avisa antes.
    private func editNode(_ node: NodeView, index: Int) {
        guard index >= 0, index < configs.count, let canvas = canvases[index],
              let position = configs[index].nodes.firstIndex(where: { $0.id == node.nodeID })
        else { return }

        let current = configs[index].nodes[position]
        let dialog = ComponentDialog(
            title: "Configurar \(current.id)",
            confirmLabel: "Aplicar",
            agents: agents,
            initial: ComponentStore.capture(from: current, name: current.component ?? current.id))
        guard let result = dialog.run() else { return }

        if result.saveAsComponent { ComponentStore.put(result.component) }

        let component = result.component
        let renamed = ComponentStore.identifier(from: component.name)
        let newID = renamed == current.id
            ? current.id
            : nextID(prefix: renamed, in: configs[index])

        var updated = ComponentStore.instantiate(component, id: newID)
        updated.setFrame(node.frame)

        let sameProcess = updated.type == current.type
            && updated.agent == current.agent
            && updated.cmd == current.cmd
            && updated.config == current.config
            && updated.cwd == current.cwd
            && updated.prompt == current.prompt

        configs[index].nodes[position] = updated

        if sameProcess && newID == current.id {
            schedulePersist()
            return
        }

        // Troca o nó por um novo: o antigo é encerrado explicitamente para o pty
        // não ficar órfão.
        canvas.remove(node)
        canvas.add(makeNode(updated, in: configs[index], frame: node.frame))
        Log.write("sessão \(configs[index].name): nó \"\(current.id)\" reconfigurado"
                  + (newID == current.id ? "" : " e renomeado para \"\(newID)\""))
        schedulePersist()
    }

    /// `sh`, `sh-2`, `sh-3`… O id entra no endereço de dispatch, então precisa
    /// ser único dentro da sessão.
    private func nextID(prefix: String, in config: SessionConfig) -> String {
        let taken = Set(config.nodes.map(\.id))
        if !taken.contains(prefix) { return prefix }
        var n = 2
        while taken.contains("\(prefix)-\(n)") { n += 1 }
        return "\(prefix)-\(n)"
    }

    // MARK: - Persistência

    /// Lê de volta o que está na tela. A view é a verdade sobre posição: o
    /// usuário acabou de arrastar.
    private func syncFrames(index: Int) {
        guard index >= 0, index < configs.count, let canvas = canvases[index] else { return }
        var byID: [String: NSRect] = [:]
        for node in canvas.nodes where !node.nodeID.isEmpty { byID[node.nodeID] = node.frame }
        for i in configs[index].nodes.indices {
            if let rect = byID[configs[index].nodes[i].id] {
                configs[index].nodes[i].setFrame(rect)
            }
        }
    }

    private func updateWebNode(session: String, id: String, url: String, profile: String) {
        guard let index = configs.firstIndex(where: { $0.name == session }),
              let node = configs[index].nodes.firstIndex(where: { $0.id == id }) else { return }
        guard configs[index].nodes[node].url != url
                || configs[index].nodes[node].profile != profile else { return }
        configs[index].nodes[node].url = url
        configs[index].nodes[node].profile = profile
        schedulePersist()
    }

    /// Navegar dispara `onStateChanged` a cada redirect; arrastar dispara ao
    /// soltar. Sem o debounce o JSON seria reescrito dezenas de vezes por
    /// minuto sem ninguém pedir.
    private func schedulePersist() {
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self else { return }
            SessionStore.save(self.configs)
        }
    }

    // MARK: - Geometria (para dirigir e verificar gestos de fora)

    /// Onde cada nó está na tela, em coordenadas com origem no topo — as do
    /// CGEvent. Estimar isso a partir de uma captura de tela erra, sobretudo com
    /// zoom aplicado: 26pt de cabeçalho viram 11pt a 43%.
    private func canvasGeometry() -> [String: Any] {
        guard let canvas = canvases[activeIndex], let window else { return [:] }
        let screenHeight = (window.screen ?? NSScreen.main)?.frame.height ?? 0

        /// AppKit mede a tela de baixo para cima; o CGEvent, de cima para baixo.
        func toTopLeft(_ rect: NSRect) -> [String: Int] {
            [
                "x": Int(rect.minX.rounded()),
                "y": Int((screenHeight - rect.maxY).rounded()),
                "w": Int(rect.width.rounded()),
                "h": Int(rect.height.rounded())
            ]
        }

        func onScreen(_ view: NSView, _ rect: NSRect) -> NSRect {
            window.convertToScreen(view.convert(rect, to: nil))
        }

        var nodes: [[String: Any]] = []
        for node in canvas.nodes {
            let header = NSRect(x: 0, y: 0, width: node.bounds.width, height: NodeView.headerHeight)
            let headerScreen = onScreen(node, header)
            // Ponto de arrasto: dentro do cabeçalho, à esquerda do rótulo e longe
            // do botão de fechar.
            let grabX = headerScreen.minX + min(6, headerScreen.width / 4)
            let grabY = screenHeight - headerScreen.midY

            nodes.append([
                "id": node.nodeID,
                "kind": String(describing: type(of: node)),
                "docFrame": ["x": Int(node.frame.minX), "y": Int(node.frame.minY),
                             "w": Int(node.frame.width), "h": Int(node.frame.height)],
                "screenFrame": toTopLeft(onScreen(node, node.bounds)),
                "screenHeader": toTopLeft(headerScreen),
                "grabPoint": ["x": Int(grabX.rounded()), "y": Int(grabY.rounded())]
            ])
        }

        return [
            "session": activeIndex < configs.count ? configs[activeIndex].name : "?",
            "magnification": Double((canvas.scroll.magnification * 1000).rounded()) / 1000,
            "docSize": ["w": Int(canvas.doc.frame.width), "h": Int(canvas.doc.frame.height)],
            "scrollOrigin": ["x": Int(canvas.scroll.contentView.bounds.origin.x),
                             "y": Int(canvas.scroll.contentView.bounds.origin.y)],
            "canvasOnScreen": toTopLeft(onScreen(canvas, canvas.bounds)),
            "nodes": nodes
        ]
    }

    // MARK: - Menu

    @objc func nextSession() { activate((activeIndex + 1) % max(1, configs.count)) }

    private var activeCanvas: CanvasContainer? { canvases[activeIndex] }

    @objc func zoomIn() { activeCanvas?.stepZoom(1) }
    @objc func zoomOut() { activeCanvas?.stepZoom(-1) }
    @objc func zoomReset() { activeCanvas?.zoom(to: 1) }

    /// Um key equivalent de menu é consultado antes do responder chain, então um
    /// item habilitado engole a tecla mesmo com o cursor dentro do editor.
    /// Desabilitar devolve a tecla a quem tem o foco — ⌘1…⌘4 focam grupos de
    /// editor no workbench, e ⌘=/⌘− dão zoom no código.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let canvasOnly: Set<Selector> = [
            #selector(pickCursorTool), #selector(pickTerminalTool),
            #selector(pickEditorTool), #selector(pickWebTool),
            #selector(zoomIn), #selector(zoomOut), #selector(zoomReset)
        ]
        guard let action = menuItem.action, canvasOnly.contains(action) else { return true }
        guard let canvas = activeCanvas else { return false }
        return !canvas.focusIsInsideNode
    }

    @objc func pickCursorTool() { activeCanvas?.tool = .cursor }
    @objc func pickTerminalTool() { activeCanvas?.tool = .terminal }
    @objc func pickEditorTool() { activeCanvas?.tool = .editor }
    @objc func pickWebTool() { activeCanvas?.tool = .web }

    @objc func copyTargets() {
        let list = Dispatcher.shared.addresses.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(list, forType: .string)
        Log.write("alvos copiados:\n\(list)")
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Próxima sessão", action: #selector(nextSession), keyEquivalent: "]")
        // ⇧⌘T e não ⌘T: o ⌘T agora arma a ferramenta de terminal, e dois itens
        // com o mesmo atalho fazem só o primeiro do menu disparar.
        appMenu.addItem(withTitle: "Copiar alvos de dispatch",
                        action: #selector(copyTargets), keyEquivalent: "t")
            .keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.items.forEach {
            if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self }
        }
        appItem.submenu = appMenu
        main.addItem(appItem)

        // O menu Editar existe pelos atalhos, não pelos itens — ninguém vai
        // colar pelo menu.
        //
        // ⌘C e ⌘V não são teclas que a view interpreta: são key equivalents,
        // procurados no `mainMenu` e despachados pelo responder chain. Sem menu
        // nenhum com `copy:`/`paste:`, ⌘V caía como keyDown no terminal, que o
        // ignora — e copiar e colar não funcionava em lugar nenhum do app,
        // terminal e code-server incluídos. O SwiftTerm já implementa os dois
        // seletores; faltava quem os chamasse.
        //
        // `target` fica nulo de propósito: é o que faz o comando descer pelo
        // responder chain até o terminal ou o WKWebView com foco.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Editar")
        editMenu.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        // `cut:` entra pelo WKWebView e pelos campos de texto. No terminal não
        // pega: o SwiftTerm declara `cut(sender:)`, que não é o seletor `cut:`.
        editMenu.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Selecionar tudo",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Ferramentas e zoom moram no menu porque é de lá que os atalhos
        // funcionam sem monitor de evento: ⌘V/⌘T/⌘W, ⌘+/⌘−/⌘0.
        let canvasItem = NSMenuItem()
        let canvasMenu = NSMenu(title: "Canvas")
        // Números, não letras. ⌘V/⌘T/⌘E/⌘W parecem naturais para as ferramentas,
        // mas um key equivalent de menu é consultado ANTES do responder chain:
        // ⌘V deixaria de colar em todo o app, e ⌘W, ⌘E e ⌘T são fechar aba e
        // navegação dentro do workbench.
        canvasMenu.addItem(withTitle: "Cursor", action: #selector(pickCursorTool), keyEquivalent: "1")
        canvasMenu.addItem(withTitle: "Novo terminal", action: #selector(pickTerminalTool), keyEquivalent: "2")
        canvasMenu.addItem(withTitle: "Novo VSCode", action: #selector(pickEditorTool), keyEquivalent: "3")
        canvasMenu.addItem(withTitle: "Novo web", action: #selector(pickWebTool), keyEquivalent: "4")
        canvasMenu.addItem(.separator())
        canvasMenu.addItem(withTitle: "Aproximar", action: #selector(zoomIn), keyEquivalent: "=")
        canvasMenu.addItem(withTitle: "Afastar", action: #selector(zoomOut), keyEquivalent: "-")
        canvasMenu.addItem(withTitle: "Zoom 100%", action: #selector(zoomReset), keyEquivalent: "0")
        canvasMenu.items.forEach { $0.target = self }
        canvasItem.submenu = canvasMenu
        main.addItem(canvasItem)

        NSApp.mainMenu = main
    }
}

/// Raiz: sidebar fixa à esquerda + área de canvas trocável.
final class RootView: NSView {
    static let sidebarWidth: CGFloat = 220

    let sidebar: Sidebar
    private var content: NSView?

    init(sidebar: Sidebar) {
        self.sidebar = sidebar
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        addSubview(sidebar)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var contentFrame: NSRect {
        NSRect(x: Self.sidebarWidth, y: 0,
               width: max(0, bounds.width - Self.sidebarWidth), height: bounds.height)
    }

    func show(_ view: NSView) {
        guard content !== view else { return }
        content?.removeFromSuperview()
        view.frame = contentFrame
        addSubview(view)
        content = view
    }

    override func layout() {
        super.layout()
        sidebar.frame = NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: bounds.height)
        content?.frame = contentFrame
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

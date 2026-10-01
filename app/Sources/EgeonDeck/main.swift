import AppKit

// egeon — PoC 04
// Sidebar de bancadas + canvas por bancada com terminais reais.
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

    var configs: [WorkbenchConfig] = []
    var agents: [String: AgentProfile] = [:]
    /// Criados sob demanda e mantidos vivos: trocar de bancada não mata terminal.
    ///
    /// Por **id** e não por posição: a lista se reordena (arrasto na barra) e
    /// encolhe (remoção), e um shell chaveado por posição obrigava a reindexar o
    /// dicionário e a religar as closures que haviam capturado o número. Ver
    /// `WorkbenchLookup`.
    var shells: [String: WorkbenchShell] = [:]
    /// A árvore por cima das bancadas: workspace → projeto (ADR-043). A lista de
    /// bancadas continua plana; isto só diz de quem cada uma é.
    var workspaces: [WorkspaceConfig] = []
    /// Controllers de aresta, um por bancada, criados sob demanda. As closures
    /// deles resolvem a bancada pelo id na hora da chamada, então o controller
    /// continua valendo depois de a bancada ser reconstruída, renomeada ou
    /// arrastada para outro projeto.
    var edgeControllers: [String: EdgeController] = [:]
    /// A bancada que está na sua frente, por id.
    ///
    /// Era uma posição, e posição não sobrevive a arrastar a barra: o mapa do
    /// movimento tinha de corrigi-la a cada reordenação. Com uma janela por
    /// bancada isto passa a ser "a janela que tem o foco"; até lá, é a que está
    /// na tela. `nil` = nenhuma.
    var activeID: String?

    /// A mesma coisa como posição, para quem fala com a barra lateral — que
    /// desenha uma árvore ordenada. `-1` = nenhuma.
    var activeIndex: Int { activeID.flatMap { index(ofID: $0) } ?? -1 }

    /// As bancadas ABERTAS, na ordem em que você as abriu — é a faixa de abas.
    ///
    /// Separada de `shells` de propósito: fechar a aba tira da faixa e **não**
    /// encerra os terminais (o shell continua montado, a bancada continua
    /// trabalhando). Encerrar de verdade continua sendo remover a bancada.
    var openTabs: [String] = []

    /// O shell de uma POSIÇÃO na lista. A barra lateral desenha uma árvore
    /// ordenada e fala por índice; o armazenamento é por id. A tradução mora
    /// aqui, num lugar só.
    func shell(at index: Int) -> WorkbenchShell? {
        guard let id = WorkbenchLookup.id(at: index, in: configs) else { return nil }
        return shells[id]
    }

    func workbenchID(at index: Int) -> String? {
        WorkbenchLookup.id(at: index, in: configs)
    }

    func index(ofID id: String) -> Int? {
        WorkbenchLookup.index(ofID: id, in: configs)
    }

    func config(ofID id: String) -> WorkbenchConfig? {
        index(ofID: id).map { configs[$0] }
    }

    /// As posições das bancadas que estão montadas — o que a barra lateral
    /// pinta como "de pé".
    var liveIndices: Set<Int> {
        Set(shells.keys.compactMap { WorkbenchLookup.index(ofID: $0, in: configs) })
    }

    let control = ControlSocket()
    var badgeTimer: Timer?
    /// Debounce da gravação do workbenches.json.
    var persistTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Antes de qualquer outra linha, e a ordem é o mecanismo: a linha seguinte
        // zera o log da instância viva, e a de depois carrega o workbenches.json —
        // é ter estado em memória que dá a esta cópia o poder de sobrescrever o da
        // outra, porque a gravação é do array inteiro pelo debounce.
        //
        // A ADR-032 já impede o roubo do socket, e com ela a segunda cópia subia
        // inteira, só sem socket: duas janelas iguais, os mesmos terminais abertos
        // duas vezes nas mesmas pastas, dois code-servers na mesma porta se matando
        // por "órfão de execução anterior", e o workbenches.json ficando com o
        // snapshot de quem gravou por último — aresta e nó da outra sumindo sem log.
        // A segunda instância não é caso de uso a suportar; é acidente a barrar.
        //
        // E acidente comum: bundle em quarentena o macOS executa de uma cópia em
        // `AppTranslocation`, então todo `.app` com este bundle id em disco — um
        // `.zip` aberto em Downloads, o `build/` de uma worktree — sobe como se
        // fosse o instalado, e abrir "Egeon" pelo Spotlight vira sorteio.
        if let owner = ControlSocket.listenerPID() {
            Log.write("recusado: já existe \(Flavor.current.displayName) de pé (pid \(owner))"
                      + " — esta cópia é \(Bundle.main.bundleURL.path)")
            let alerta = NSAlert()
            alerta.alertStyle = .warning
            alerta.messageText = "\(Flavor.current.displayName) já está aberto"
            alerta.informativeText = """
                Há uma cópia de pé (pid \(owner)). As duas dividiriam \
                \(Flavor.current.configDirectory.path), o socket de controle e a porta \
                \(Flavor.current.codeServerPort) — e a segunda sobrescreve as bancadas da \
                primeira. Esta vai sair.

                Esta cópia: \(Bundle.main.bundleURL.path)
                """
            alerta.addButton(withTitle: "Sair")
            NSApp.activate(ignoringOtherApps: true)
            alerta.runModal()
            // `exit` e não `NSApp.terminate`: terminate passa pelo
            // `applicationWillTerminate`, que grava o workbenches.json — e aqui ele
            // está vazio, o que apagaria as bancadas de quem está trabalhando.
            exit(0)
        }

        Log.reset()
        configs = WorkbenchStore.load()
        workspaces = WorkspaceStore.load() ?? []
        agents = AgentStore.load()
        Log.write("Egeon Deck iniciando — \(configs.count) bancadas, "
                  + "\(workspaces.count) workspaces, \(agents.count) perfis de agente")
        reconcileWorkspaces()
        // Link que alguém apagou à mão, ou repositório que mudou de lugar no
        // arquivo: a pasta do multi-projeto é derivada, e é refeita a cada arranque.
        MultiProjectLinks.syncAll(workspaces)

        // Escrito no arranque, e não na primeira worktree: é um arquivo feito
        // para ser lido e ajustado, e para isso precisa existir antes.
        Worktree.installCopyScript()
        ClaudeHooks.install()
        ClaudeSkill.install()
        EgeonCLI.install()
        ShellHook.install()

        buildMenu()

        let screen = Self.startupScreen()
        // O dev abre menor e lembra o tamanho: ele sobe a cada rebuild, e uma
        // janela de tela inteira em cima do estável a cada `dev.sh` é o que
        // atrapalha. O estável continua tomando a tela.
        let devFrame = screen.visibleFrame.insetBy(dx: screen.visibleFrame.width * 0.15,
                                                   dy: screen.visibleFrame.height * 0.12)
        let startFrame = Flavor.current == .dev ? devFrame : screen.visibleFrame
        window = NSWindow(
            contentRect: startFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        if Flavor.current == .dev {
            window.setFrameAutosaveName("janela-dev")
            if !window.setFrameUsingName("janela-dev") {
                window.setFrame(startFrame, display: false)
            }
        } else {
            window.setFrame(startFrame, display: false)
        }
        // Sem texto na barra de título: quem diz a bancada é a barra do app, logo
        // abaixo, e o nome do flavor repetido ali só empilhava rótulo. O dev
        // continua reconhecível pelo ícone no Dock.
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1)

        let sidebar = Sidebar(workspaces: workspaces, configs: configs)
        sidebar.onSelect = { [weak self] index in self?.activate(index) }
        sidebar.onToggleCollapse = { [weak self] in self?.root.toggleCollapsed() }
        sidebar.onCreate = { [weak self] in self?.createWorkbench() }
        sidebar.onCreateFromWorktree = { [weak self] in self?.createWorkbenchFromWorktree() }
        sidebar.onCreateInProject = { [weak self] id in self?.createWorkbench(inProject: id) }
        sidebar.onCreateFromWorktreeInProject = { [weak self] id in
            self?.createWorkbenchFromWorktree(inProject: id)
        }
        sidebar.onCreateWorkspace = { [weak self] in self?.createWorkspace() }
        sidebar.onEditWorkspace = { [weak self] id in self?.editWorkspace(id) }
        sidebar.onRemoveWorkspace = { [weak self] id in self?.confirmRemoveWorkspace(id) }
        sidebar.onRemoveProject = { [weak self] ws, id in self?.confirmRemoveProject(ws, id) }
        sidebar.onToggleGroup = { [weak self] item in self?.toggleGroup(item) }
        sidebar.onMoveWorkspace = { [weak self] id, position in
            _ = self?.moveWorkspace(id, to: position)
        }
        sidebar.onMoveProject = { [weak self] id, workspace, position, stored in
            _ = self?.moveProject(id, toWorkspace: workspace, at: position, stored: stored)
        }
        sidebar.onToggleStored = { [weak self] workspace, id, stored in
            self?.storeProject(id, in: workspace, stored: stored)
        }
        sidebar.onToggleDrawer = { [weak self] id in self?.toggleDrawer(id) }
        sidebar.onMoveWorkbench = { [weak self] index, project, position in
            _ = self?.moveWorkbench(index, toProject: project, at: position)
        }
        sidebar.onRename = { [weak self] index in self?.renameWorkbench(index) }
        sidebar.onDuplicateAsWorktree = { [weak self] index in
            self?.duplicateWorkbenchAsWorktree(index)
        }
        sidebar.onRemove = { [weak self] index in self?.confirmRemoveWorkbench(index) }
        sidebar.onEditVisitLimit = { [weak self] index in self?.editVisitLimit(index) }
        sidebar.onEditRules = { [weak self] index in self?.editWorkbenchRules(index) }
        sidebar.onClear = { [weak self] index in self?.confirmClearWorkbench(index) }
        root = RootView(sidebar: sidebar)
        window.contentView = root

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Sobe o code-server antes dos nós: EditorNode espera o healthz e só
        // então carrega, evitando WKWebView batendo em porta morta.
        CodeServer.shared.start()

        AppControl.workbenchNames = { [weak self] in self?.configs.map(\.name) ?? [] }
        AppControl.workspacesSnapshot = { [weak self] in self?.workspacesSnapshot() ?? [:] }
        AppControl.canvasGeometry = { [weak self] in self?.canvasGeometry() ?? [:] }
        AppControl.makeWorktree = { [weak self] target, branch, nodeBranches in
            self?.makeWorktree(target: target, branch: branch, nodeBranches: nodeBranches)
                ?? ["ok": false, "error": "app encerrando"]
        }
        // O Claude Code se atualiza com o app aberto; o catálogo novo vale para os
        // cards que já estão na tela, sem reiniciar ninguém.
        ClaudeModelCatalog.onUpdate = { [weak self] catalog in
            guard let self else { return }
            for config in self.configs {
                guard let shell = self.shells[config.id] else { continue }
                for node in config.nodes {
                    guard let profile = node.agent.flatMap({ self.agents[$0] }),
                          ClaudeModelCatalog.applies(to: profile),
                          let view = shell.nodes.first(where: { $0.nodeID == node.id }) as? TerminalNode
                    else { continue }
                    view.apply(catalog: catalog)
                }
            }
        }
        AppControl.setNodeModel = { [weak self] target, choice in
            guard let self else { return "app encerrando" }
            let parts = target.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let index = self.configs.firstIndex(where: { $0.name == parts[0] })
            else { return "bancada desconhecida '\(target)'" }
            guard let node = self.shell(at: index)?.nodes.first(where: { $0.nodeID == parts[1] })
            else { return "nó desconhecido '\(target)'" }
            guard let config = self.configs[index].nodes.first(where: { $0.id == parts[1] }),
                  config.type == .agent,
                  let profile = config.agent.flatMap({ self.agents[$0] })
            else { return "'\(target)' não é um agente" }
            switch choice {
            case .model where !profile.offersModels:
                return "'\(target)' não é um agente que aceite modelo"
            case .effort where !profile.offersEfforts:
                return "'\(target)' não é um agente que aceite esforço"
            case .ultracode where profile.ultracode == nil:
                return "'\(target)' não é um agente com ultracode"
            default:
                break
            }
            self.changeModel(of: node, to: choice, index: index)
            return nil
        }
        AppControl.setViewMode = { [weak self] raw in
            guard let self, let mode = ViewMode(rawValue: raw),
                  let shell = self.shell(at: self.activeIndex) else { return nil }
            shell.show(mode)
            return mode.rawValue
        }
        AppControl.toggleSidebar = { [weak self] in
            guard let self else { return false }
            self.root.toggleCollapsed()
            return self.root.isCollapsed
        }
        AppControl.collapseSidebar = { [weak self] state in
            guard let self else { return false }
            self.root.setCollapsed(state)
            return self.root.isCollapsed
        }
        AppControl.workbenchEdges = { [weak self] name in
            self?.configs.first { $0.name == name }?.edgeList ?? []
        }
        AppControl.workbenchVisitLimit = { [weak self] name in
            self?.configs.first { $0.name == name }?.visitLimit ?? 3
        }
        AppControl.nodeRole = { [weak self] address in
            let parts = address.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return self?.configs.first { $0.name == parts[0] }?
                .nodes.first { $0.id == parts[1] }?.effectivePrompt
        }
        AppControl.nodeIdentity = { [weak self] address in
            let parts = address.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let self,
                  let config = self.configs.first(where: { $0.name == parts[0] }),
                  let node = config.nodes.first(where: { $0.id == parts[1] }) else { return nil }
            let cli = node.agent.flatMap { self.agents[$0]?.displayName } ?? node.agent
            return (cli, self.literalModel(workbench: parts[0], nodeID: parts[1]), node.conversationId,
                    config.id)
        }
        AppControl.turnEnded = { [weak self] address, transcript, notBefore in
            let parts = address.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let self, let transcript,
                  let config = self.configs.first(where: { $0.name == parts[0] }),
                  let node = config.nodes.first(where: { $0.id == parts[1] }),
                  node.type == .agent else { return }
            // Carimbo na main (lê configs); a leitura do transcript, que chega
            // a MB, vai para fundo — é o que o chat também faz.
            let record = (conversation: node.conversationId,
                          cli: node.agent.flatMap { self.agents[$0]?.displayName } ?? node.agent,
                          model: self.literalModel(workbench: parts[0], nodeID: parts[1]))
            let workbenchID = config.id
            DispatchQueue.global(qos: .utility).async {
                // Só o Claude Code grava transcript hoje; outro CLI entra pelo
                // leitor do perfil dele, quando existir.
                guard let turn = ClaudeTranscript.lastTurn(at: transcript, notBefore: notBefore)
                else { return }
                ChatHistory.shared.append(ChatRecord(node: parts[1], conversation: record.conversation,
                                                     cli: record.cli, model: record.model, turn: turn),
                                          workbench: workbenchID)
            }
        }
        AppControl.clearWorkbench = { [weak self] name, done in
            guard let self, let index = self.configs.firstIndex(where: { $0.name == name })
            else { return done(["ok": false, "error": "bancada desconhecida '\(name)'"]) }
            self.clearWorkbench(index, completion: done)
        }
        AppControl.clearChat = { [weak self] name in
            guard let self, let index = self.configs.firstIndex(where: { $0.name == name })
            else { return ["ok": false, "error": "bancada desconhecida '\(name)'"] }
            let config = self.configs[index]
            let archived = ChatHistory.shared.archive(workbench: config.id)
            // A thread guarda eco e turno ao vivo em memória: arquivar o arquivo
            // sem avisá-la deixava mensagem órfã na tela (ADR-059).
            self.shell(at: index)?.chat.clearedHistory()
            guard let archived else {
                return ["ok": true, "workbench": name, "archived": NSNull(),
                        "detail": "conversa já estava vazia"]
            }
            Log.write("chat[\(name)]: conversa limpa — arquivada em \(archived.lastPathComponent)")
            return ["ok": true, "workbench": name, "archived": archived.path]
        }
        AppControl.recordConversation = { [weak self] target, id, transcript in
            self?.recordConversation(target: target, id: id, transcript: transcript)
        }
        AppControl.tabsSnapshot = { [weak self] in
            guard let self else { return [:] }
            let list = self.tabs()
            return ["open": list.map(\.line),
                    "active": self.activeID.flatMap { self.config(ofID: $0)?.name } ?? "",
                    "visible": self.shell(at: self.activeIndex)?.tabsAreVisible ?? false,
                    "placement": self.shell(at: self.activeIndex)?.tabs.placement ?? [],
                    "inset": self.shell(at: self.activeIndex)?.tabsInset ?? -1,
                    "count": list.count]
        }
        AppControl.moveTab = { [weak self] name, position in
            guard let self, let id = WorkbenchLookup.id(ofName: name, in: self.configs)
            else { return ["ok": false, "error": "bancada desconhecida '\(name)'"] }
            guard let from = self.openTabs.firstIndex(of: id) else {
                return ["ok": false, "error": "'\(name)' não está na faixa"]
            }
            guard position >= 0, position < self.openTabs.count else {
                return ["ok": false, "error": "posição fora da faixa (0…\(self.openTabs.count - 1))"]
            }
            // Pela view, e não direto no array: é o mesmo caminho do arrasto,
            // com a mesma animação — verificar o atalho não vale se ele passa
            // por outro lugar.
            let order = self.shell(at: self.activeIndex)?.tabs.move(id: id, to: position)
                ?? TabDragLayout.moved(self.openTabs, from: from, to: position)
            self.reorderTabs(order)
            return ["ok": true, "moved": name, "to": position]
        }
        AppControl.closeTab = { [weak self] name in
            guard let self, let id = WorkbenchLookup.id(ofName: name, in: self.configs)
            else { return ["ok": false, "error": "bancada desconhecida '\(name)'"] }
            guard self.openTabs.contains(id) else {
                return ["ok": false, "error": "'\(name)' não está na faixa"]
            }
            self.closeTab(id)
            return ["ok": true, "closed": name]
        }
        AppControl.chatState = { [weak self] name in
            guard let self, let index = self.configs.firstIndex(where: { $0.name == name })
            else { return nil }
            var out = self.shell(at: index)?.chat.snapshot() ?? [:]
            out["workbench"] = name
            out["mode"] = (self.shell(at: index)?.mode ?? self.configs[index].viewMode).rawValue
            return out
        }
        AppControl.chatScroll = { [weak self] name, edge in
            guard let self, let index = self.configs.firstIndex(where: { $0.name == name })
            else { return }
            self.shell(at: index)?.chat.scroll(edge)
        }
        AppControl.chatFocus = { [weak self] name, id in
            guard let self, let index = self.configs.firstIndex(where: { $0.name == name })
            else { return }
            self.shell(at: index)?.chat.focusFromOutside(id)
        }
        AppControl.moveInTree = { [weak self] kind, id, parent, position in
            guard let self else { return ["ok": false, "error": "app indisponível"] }
            let ok: Bool
            switch kind {
            case "workspace": ok = self.moveWorkspace(id, to: position)
            case "project":   ok = self.moveProject(id, toWorkspace: parent, at: position)
            case "store", "unstore":
                self.storeProject(id, in: parent, stored: kind == "store")
                ok = true
            case "drawer":
                self.toggleDrawer(id)
                ok = true
            case "workbench":
                guard let index = self.configs.firstIndex(where: { $0.name == id || $0.id == id })
                else { return ["ok": false, "error": "bancada desconhecida '\(id)'"] }
                ok = self.moveWorkbench(index, toProject: parent, at: position)
            default:
                return ["ok": false,
                        "error": "kind é workspace, project, workbench, store, unstore ou drawer"]
            }
            return ["ok": ok, "tree": AppControl.workspacesSnapshot?() ?? [:]]
        }
        AppControl.chatExpandStep = { [weak self] name, blockId in
            guard let self, let index = self.configs.firstIndex(where: { $0.name == name })
            else { return }
            self.shell(at: index)?.chat.toggleStep(id: blockId)
        }
        AppControl.chatCompose = { [weak self] name, text, send in
            guard let self,
                  let index = self.configs.firstIndex(where: { $0.name == name }),
                  let shell = self.shell(at: index), shell.mode == .chat
            else { return nil }
            return shell.chat.compose(text, send: send)
        }
        AppControl.workbenchOwning = { [weak self] folder in
            self?.workbenchOwning(folder: folder)
        }
        AppControl.setEdgeDirection = { [weak self] workbench, from, to, direction in
            guard let self,
                  let index = self.configs.firstIndex(where: { $0.name == workbench })
            else { return ["ok": false, "error": "bancada desconhecida '\(workbench)'"] }
            return self.edgeController(for: index)?
                .apply(from: from, to: to, direction: direction)
                ?? ["ok": false, "error": "bancada desconhecida '\(workbench)'"]
        }

        AppControl.swapMosaic = { [weak self] workbench, first, second in
            guard let self,
                  let index = self.configs.firstIndex(where: { $0.name == workbench })
            else { return ["ok": false, "error": "bancada desconhecida '\(workbench)'"] }
            guard self.shell(at: index)?.swapInMosaic(first, second) == true else {
                return ["ok": false,
                        "error": "não trocou — nó desconhecido, ou a bancada não está em mosaico"]
            }
            return ["ok": true, "workbench": workbench, "swapped": [first, second]]
        }
        AppControl.cardSnapshot = { [weak self] target, file in
            self?.cardSnapshot(target: target, file: file) ?? "erro: app encerrando"
        }
        AppControl.removeWorkbench = { [weak self] name, purge in
            self?.removeWorkbench(named: name, purge: purge)
                ?? ["ok": false, "error": "app encerrando"]
        }
        AppControl.activateWorkbench = { [weak self] name in
            guard let self, let index = self.configs.firstIndex(where: { $0.name == name })
            else { return false }
            self.activate(index)
            return true
        }

        // Sem bancadas, a barra da esquerda explica o + e o canvas fica de fora.
        if configs.isEmpty {
            Log.write("nenhuma bancada configurada — use + na barra lateral")
        } else {
            restoreTabs()
        }

        Dispatcher.shared.start()
        control.start()

        // 0.12s é o passo do spinner: mais lento ele engasga, mais rápido não
        // acrescenta nada que o olho veja. Quem desenha compara antes de
        // escrever, então nó e linha parados não custam redesenho.
        //
        // A barra lateral é atualizada junto e à parte do canvas: ela mostra as
        // bancadas inativas, cujo canvas nem existe na hierarquia de views.
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.shell(at: self.activeIndex)?.refreshBadges()
            let activity = Dispatcher.shared.activitySummary()
            self.root.sidebar.showActivity(activity)
            // A faixa mostra o MESMO estado da barra lateral, e no mesmo quadro
            // do spinner: são os dois lugares onde uma bancada que não está na
            // tela consegue te chamar.
            self.shell(at: self.activeIndex)?.showTabs(
                WorkbenchTabs.build(open: self.openTabs, configs: self.configs,
                                    active: self.activeID, activity: activity))
        }
    }

    /// Em qual tela a janela nasce.
    ///
    /// O dev vai para a tela mais à esquerda, e o estável fica na principal. Os
    /// dois abrem maximizados, então sem isso o rebuild joga o dev em cima do
    /// estável — que é onde os agentes de verdade estão trabalhando.
    ///
    /// Mais à esquerda pelo `minX` do frame, e não `screens.first`: a primeira da
    /// lista é a que tem a barra de menu, que pode ser qualquer uma.
    private static func startupScreen() -> NSScreen {
        let screens = NSScreen.screens
        guard Flavor.current.isDev,
              let leftmost = screens.min(by: { $0.frame.minX < $1.frame.minX })
        else { return screens.first ?? NSScreen.main! }
        return leftmost
    }

    func applicationWillTerminate(_ notification: Notification) {
        // O debounce pode estar pendente; um arrasto feito segundos antes de
        // sair não pode se perder.
        persistTimer?.invalidate()
        for index in liveIndices { syncFrames(index: index) }
        recordTabOrder()
        WorkbenchStore.save(configs)

        control.stop()
        CodeServer.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Bancadas

    private func activate(_ index: Int) {
        guard index >= 0, index < configs.count, index != activeIndex else { return }
        let shell = shell(at: index) ?? build(index)
        let previous = activeIndex
        activeID = configs[index].id
        if !openTabs.contains(configs[index].id) {
            openTabs.append(configs[index].id)
            schedulePersist()
        }
        refreshTabs()
        revealInSidebar(index)
        root.show(shell)
        // O layout da barra é do MODO, e o modo é por bancada: entrar numa bancada em
        // mosaico tem de tirar a barra de cima do conteúdo.
        root.setMosaic(shell.mode != .canvas)
        root.sidebar.select(index)
        root.sidebar.markLive(index)
        // Trocar de bancada dá por visto o "terminou" das DUAS: a que você abre,
        // porque chegou nela, e a que você deixa, porque estava na sua frente. É
        // aviso que não pede nada de você — manter o verde aceso depois disso é
        // pedir que você o apague à mão.
        if previous >= 0, previous < configs.count {
            Dispatcher.shared.workbenchOpened(configs[previous].name)
        }
        Dispatcher.shared.workbenchOpened(configs[index].name)
        Log.write("bancada ativa: \(configs[index].name)")
    }

    // MARK: - A faixa de bancadas abertas

    /// Reabre as bancadas que estavam na faixa quando o app fechou, na mesma
    /// ordem, e volta para a que estava na frente.
    ///
    /// Com teto: cada bancada sobe vários processos, e um arquivo com dez
    /// marcadas — depois de um crash, por exemplo — faria o arranque abrir tudo
    /// de uma vez. O resto continua na barra lateral, a um clique.
    private func restoreTabs() {
        let saved = configs.enumerated()
            .filter { $0.element.tabOrder != nil }
            .sorted { ($0.element.tabOrder ?? 0) < ($1.element.tabOrder ?? 0) }
        guard !saved.isEmpty else { return activate(0) }

        let teto = 6
        if saved.count > teto {
            Log.write("abas: \(saved.count) bancadas estavam abertas — reabrindo as \(teto) "
                      + "primeiras; as outras continuam na barra lateral")
        }
        let list = Array(saved.prefix(teto))
        // Cada uma tem de passar pela tela: um shell montado fora da hierarquia
        // nunca recebe passe de layout, e sem layout o terminal nasce com zero
        // colunas (ver `WorkbenchShell.place`). Por isso abrir é ativar.
        for (index, _) in list { activate(index) }
        // E a ordem da faixa é a do arquivo, não a ordem em que elas subiram.
        openTabs = list.map { $0.element.id }
        let front = list.first { $0.element.tabActive == true } ?? list[0]
        activeID = nil
        activate(front.offset)
        Log.write("abas restauradas: \(list.map { $0.element.name }.joined(separator: ", "))")
    }

    /// A faixa vai para o disco junto com o resto da bancada.
    private func recordTabOrder() {
        for i in configs.indices {
            configs[i].tabOrder = openTabs.firstIndex(of: configs[i].id)
            configs[i].tabActive = configs[i].id == activeID ? true : nil
        }
    }

    /// Redesenha a faixa do shell na tela. Só ele: as abas são a moldura da
    /// bancada que você está vendo, e as outras redesenham quando chegarem à
    /// frente.
    private func refreshTabs() {
        guard let shell = shell(at: activeIndex) else { return }
        shell.showTabs(tabs())
    }

    private func tabs() -> [WorkbenchTab] {
        WorkbenchTabs.build(open: openTabs, configs: configs, active: activeID,
                            activity: Dispatcher.shared.activitySummary())
    }

    /// Você arrastou uma aba. A ordem da faixa é SUA: ela não é a da barra
    /// lateral (que é a árvore de projetos) nem a ordem em que as bancadas
    /// abriram, e é por isso que ela mora em `openTabs` e vai para o disco.
    private func reorderTabs(_ order: [String]) {
        guard Set(order) == Set(openTabs) else { return }
        openTabs = order
        schedulePersist()
        // As outras faixas montadas — as das bancadas que estão abertas mas não
        // na tela — remontam quando chegarem à frente.
        refreshTabs()
        Log.write("abas reordenadas: "
                  + order.compactMap { config(ofID: $0)?.name }.joined(separator: ", "))
    }

    /// Fechar a aba: sai da faixa e a bancada continua exatamente como estava —
    /// terminais rodando, conversa inteira, pronta para voltar pela barra
    /// lateral. Fechar não é encerrar.
    private func closeTab(_ id: String) {
        guard openTabs.contains(id) else { return }
        let next = WorkbenchTabs.neighbour(of: id, in: openTabs)
        openTabs.removeAll { $0 == id }
        if activeID == id {
            if let next, let index = index(ofID: next) {
                activeID = nil
                activate(index)
            } else {
                // Última aba: a bancada some da tela, e a barra lateral volta a
                // ser o único caminho de volta — como era antes de ela abrir.
                activeID = nil
                root.show(NSView())
                reloadSidebar()
            }
        }
        refreshTabs()
        schedulePersist()
        Log.write("aba fechada: \(configs.first { $0.id == id }?.name ?? id) "
                  + "— a bancada continua de pé")
    }

    // MARK: - Criar, renomear e remover bancada

    /// Pasta primeiro, nome depois: o nome quase sempre é o da pasta, então
    /// perguntar na ordem inversa faria você digitar o que o app já sabe.
    /// Com `project`, a pasta já está decidida — é a do projeto — e a bancada
    /// nasce dele. Sem, você escolhe a pasta e o app acha (ou cria) o projeto.
    private func createWorkbench(inProject projectID: String? = nil) {
        let folder: URL
        if let projectID, let project = project(withID: projectID), project.requiresWorktree {
            createMultiWorktree(project)
            return
        } else if let projectID, let project = project(withID: projectID) {
            folder = project.url
        } else {
            let panel = NSOpenPanel()
            panel.title = "Pasta da bancada"
            panel.message = "Escolha a pasta — pode ser um repositório ou uma worktree."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Usar esta pasta"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            // A pasta de links de um multi-projeto, escolhida à mão, é o mesmo
            // multi-projeto: bancada dele só em worktree.
            if let multi = workspaces.lazy.flatMap(\.projects)
                .first(where: { $0.requiresWorktree && $0.owns(path: url.path) }) {
                createMultiWorktree(multi)
                return
            }
            folder = url
        }
        guard let (name, template) = askWorkbenchNameAndTemplate(
            suggested: folder.lastPathComponent) else { return }

        let preset = template.flatMap { WorkbenchTemplateStore.template(named: $0) }
        var config = WorkbenchConfig(
            name: WorkbenchStore.availableName(basedOn: name, taken: configs.map(\.name)),
            path: (folder.path as NSString).abbreviatingWithTildeInPath,
            nodes: preset?.instantiate() ?? [],
            template: template,
            project: projectID)

        // O modo vem do preset: um template desenhado em mosaico abre em mosaico.
        config.view = preset?.view
        config.mosaic = preset?.mosaic

        // Frames vindos do template já servem; sem template a bancada nasce vazia
        // e você monta pela barra.
        if config.nodes.isEmpty { config.nodes = [] }

        configs.append(config)
        reconcileWorkspaces()
        Log.write("bancada \"\(config.name)\" criada em \(config.path)"
                  + (template.map { " a partir do template \"\($0)\"" } ?? " vazia"))
        schedulePersist()
        activate(configs.count - 1)
    }

    /// Cria uma worktree do repositório escolhido e abre uma bancada nela.
    ///
    /// O ponto de partida é o HEAD atual, em uma branch nova — o git recusa a
    /// mesma branch em duas worktrees, por design.
    private func createWorkbenchFromWorktree(inProject projectID: String? = nil) {
        let repo: URL
        if let projectID, let project = project(withID: projectID), project.isMulti {
            createMultiWorktree(project)
            return
        } else if let projectID, let project = project(withID: projectID) {
            repo = project.url
        } else {
            let panel = NSOpenPanel()
            panel.title = "Repositório de origem"
            panel.message = "Escolha o repositório. A worktree sai do commit em que ele está agora."
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Usar este repositório"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            repo = url
        }

        let status: Worktree.Status
        do {
            status = try Worktree.status(of: repo.path)
        } catch {
            presentError("Não consegui ler o repositório", error)
            return
        }

        // Você pode ter escolhido uma worktree em vez do checkout principal: sair
        // dela aninharia worktree dentro de worktree.
        let repoRoot = Worktree.mainRepo(of: repo.path) ?? status.repoRoot
        let suggestedBranch = Worktree.availableBranch(basedOn: status.branch, in: repoRoot)
        guard let form = askWorktreeForm(status: status,
                                         repoRoot: repoRoot,
                                         suggestedBranch: suggestedBranch) else { return }

        let created: Worktree.Created
        do {
            created = try Worktree.create(
                from: repoRoot,
                branch: form.branch,
                destination: Worktree.suggestedPath(repoRoot: repoRoot, branch: form.branch),
                carryDirty: true)
        } catch {
            presentError("Não consegui criar a worktree", error)
            return
        }

        var config = WorkbenchConfig(
            name: WorkbenchStore.availableName(basedOn: Worktree.sanitize(created.branch),
                                             taken: configs.map(\.name)),
            path: (created.path as NSString).abbreviatingWithTildeInPath,
            nodes: form.template.flatMap { WorkbenchTemplateStore.template(named: $0)?.instantiate() } ?? [],
            template: form.template,
            project: projectID)
        if config.nodes.isEmpty { config.nodes = [] }

        configs.append(config)
        reconcileWorkspaces()
        schedulePersist()
        activate(configs.count - 1)

        // A cópia do que o git não versiona roda depois de a bancada existir: com
        // node_modules e Pods no meio, esperar por ela antes de mostrar qualquer
        // coisa pareceria travamento.
        //
        // Worktree reaproveitada não é copiada: ela já tem o `.env` e as
        // dependências dela, e passar por cima seria estragar o que se pediu para
        // reusar.
        copyUnversioned(created.reused ? [] : [(repoRoot, created.path)],
                        into: configs.count - 1)
    }

    /// Bancada de multi-projeto em worktree: a mesma branch em cada repositório,
    /// todas dentro de uma pasta só (ADR-065).
    ///
    /// Repositório que recusa não derruba os outros: a bancada nasce com o que
    /// deu, e o alerta diz o que faltou — é o mesmo critério do worktree por
    /// terminal, em que a vizinha que falha não impede a principal.
    private func createMultiWorktree(_ project: ProjectConfig, inheriting origin: WorkbenchConfig? = nil) {
        guard let space = workspaces.first(where: { $0.project(withID: project.id) != nil }) else { return }
        let members = space.members(of: project)
        guard !members.isEmpty else {
            presentError("\"\(project.name)\" não junta pasta nenhuma",
                         Worktree.Failure.notARepo(project.path))
            return
        }
        guard let form = MultiWorktreeForm.ask(
            project: project, links: MultiProject.linkNames(for: members).map(\.name),
            offersTemplate: origin == nil) else { return }

        let opened = openMultiWorktree(project, members: members, branch: form.branch,
                                       overrides: form.overrides,
                                       template: form.template, inheriting: origin)
        guard opened.index != nil else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Nenhuma worktree foi criada"
            alert.informativeText = opened.failures.joined(separator: "\n")
            alert.runModal()
            return
        }
        if !opened.failures.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Algumas worktrees ficaram de fora"
            alert.informativeText = opened.failures.joined(separator: "\n")
            alert.runModal()
        }
    }

    /// A criação em si, sem diálogo — o socket também chega aqui. `index` nil é
    /// nenhum repositório aceitou, e aí não há bancada.
    private func openMultiWorktree(_ project: ProjectConfig, members: [ProjectConfig],
                                   branch: String, overrides: [String: String] = [:],
                                   template: String?, inheriting origin: WorkbenchConfig?)
        -> (index: Int?, root: String, failures: [String]) {
        let links = MultiProject.linkNames(for: members)
        let branches = MultiProject.branches(for: links.map(\.name), workbench: branch,
                                             overrides: overrides)
        let root = MultiProject.worktreeRoot(project: project, members: members, branch: branch)
        do {
            try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        } catch {
            return (nil, root, ["\(root): \(error)"])
        }

        var pending: [(repo: String, path: String)] = []
        var failures: [String] = []
        for (link, member) in zip(links, members) {
            let repoRoot = Worktree.mainRepo(of: member.url.path) ?? member.url.path
            let destination = (root as NSString).appendingPathComponent(link.name)
            do {
                let created = try Worktree.create(from: repoRoot, branch: branches[link.name] ?? branch,
                                                  destination: destination, carryDirty: true)
                if created.path != destination {
                    // A branch já está aberta em outro lugar: o git não deixa
                    // abrir de novo, e o link é o que põe ela aqui mesmo assim.
                    try FileManager.default.createSymbolicLink(atPath: destination,
                                                               withDestinationPath: created.path)
                    Log.write("multi-projeto: \(link.name) já estava aberta em \(created.path) — ligada")
                }
                if !created.reused { pending.append((repoRoot, created.path)) }
            } catch {
                Log.write("multi-projeto: worktree de \(member.name) falhou — \(error)")
                failures.append("\(member.name): \(error)")
            }
        }
        guard failures.count < members.count else {
            MultiProjectLinks.pruneRoot(URL(fileURLWithPath: root))
            return (nil, root, failures)
        }

        let nodes = origin.map { Self.repointed($0.nodes, originRoot: $0.url.path, cwds: [:]) }
            ?? template.flatMap { WorkbenchTemplateStore.template(named: $0)?.instantiate() } ?? []
        var config = WorkbenchConfig(
            name: WorkbenchStore.availableName(basedOn: Worktree.sanitize(branch),
                                             taken: configs.map(\.name)),
            path: (root as NSString).abbreviatingWithTildeInPath,
            nodes: nodes,
            template: origin?.template ?? template,
            project: project.id)
        config.edges = origin?.edges
        config.rules = origin?.rules
        config.view = origin?.view
        config.mosaic = origin?.mosaic

        configs.append(config)
        reconcileWorkspaces()
        // Ela já nasce com projeto: a conciliação não muda nada e não redesenha.
        reloadSidebar()
        schedulePersist()
        activate(configs.count - 1)
        Log.write("multi-projeto: bancada \"\(config.name)\" em \(root) — "
                  + "\(members.count - failures.count)/\(members.count) worktrees")
        copyUnversioned(pending, into: configs.count - 1)
        return (configs.count - 1, root, failures)
    }

    /// Duplica a bancada numa worktree nova, com os mesmos nós.
    ///
    /// Partir da bancada em vez do `+` é o que dispensa escolher template: o que
    /// se quer é "outra igual a esta, em outra branch".
    private func duplicateWorkbenchAsWorktree(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let origin = configs[index]
        if let project = origin.project.flatMap({ project(withID: $0) }), project.isMulti {
            createMultiWorktree(project, inheriting: origin)
            return
        }

        let status: Worktree.Status
        do {
            status = try Worktree.status(of: origin.url.path)
        } catch {
            presentError("\"\(origin.name)\" não é um repositório git", error)
            return
        }

        // Do checkout principal, mesmo que esta bancada já seja uma worktree:
        // partir da worktree ligada aninharia uma dentro da outra.
        let repoRoot = Worktree.mainRepo(of: origin.url.path) ?? status.repoRoot
        let suggested = Worktree.availableBranch(basedOn: status.branch, in: repoRoot)
        guard let form = askWorktreeForm(status: status,
                                         repoRoot: repoRoot,
                                         suggestedBranch: suggested,
                                         inheriting: origin) else { return }

        if let error = duplicate(index, repoRoot: repoRoot, status: status, form: form) {
            presentError("Não consegui criar a worktree", error)
        }
    }

    /// A duplicação em si, sem diálogo.
    ///
    /// Separada porque é o que o socket precisa alcançar: um `NSAlert` não é
    /// dirigível de fora, e sem isto o fluxo inteiro — worktree da bancada, worktree
    /// de cada terminal, reapontamento dos `cwd` — só poderia ser verificado a
    /// olho. Devolve o erro em vez de apresentá-lo: quem chamou sabe se há usuário
    /// olhando.
    @discardableResult
    private func duplicate(_ index: Int, repoRoot: String, status: Worktree.Status,
                           form: WorktreeForm) -> Error? {
        let origin = configs[index]
        let created: Worktree.Created
        do {
            created = try Worktree.create(
                from: repoRoot,
                branch: form.branch,
                destination: Worktree.suggestedPath(repoRoot: repoRoot, branch: form.branch),
                carryDirty: true)
        } catch {
            return error
        }

        // As worktrees dos terminais que você marcou, cada uma no repositório
        // dela. Rodam depois da worktree da bancada porque a falha de uma vizinha
        // não pode impedir a principal de existir.
        var extraWorktrees: [(repo: String, path: String)] = []
        let nodeCwds = NodeWorktreePlanner.materialize(form.nodes) { repo, path in
            extraWorktrees.append((repo, path))
        }

        let nodes = Self.repointed(origin.nodes, originRoot: origin.url.path, cwds: nodeCwds)
        let worktreePath = (created.path as NSString).abbreviatingWithTildeInPath

        let alvo: Int
        switch form.target {
        case .newWorkbench:
            // As ligações vêm junto: elas são parte da montagem, tanto quanto os
            // nós. A aresta guarda id de nó, e a duplicação preserva os ids, então
            // a rede da worktree nasce igual à da origem — quem podia acionar
            // quem continua podendo, no checkout novo.
            // O modo e as proporções vêm junto pelo mesmo motivo que as arestas:
            // é montagem, não estado de conversa.
            let config = WorkbenchConfig(
                name: WorkbenchStore.availableName(basedOn: Worktree.sanitize(created.branch),
                                                 taken: configs.map(\.name)),
                path: worktreePath,
                nodes: nodes,
                template: origin.template,
                // A worktree é do mesmo projeto que a origem: saiu dela.
                project: origin.project,
                edges: origin.edges,
                maxVisits: origin.maxVisits,
                view: origin.view,
                mosaic: origin.mosaic)
            configs.append(config)
            alvo = configs.count - 1
            reloadSidebar()
            activate(alvo)
            Log.write("bancada \"\(origin.name)\" duplicada em \"\(config.name)\" "
                      + "(\(nodes.count) nós, worktree \(created.path))")

        case .moveCurrent:
            configs[index].path = worktreePath
            configs[index].nodes = nodes
            alvo = index

            // O canvas inteiro é remontado: um pty não muda de diretório depois
            // de aberto, e reconstruir reaproveita o mesmo caminho de sempre em
            // vez de um segundo, quase igual, só para esta situação.
            if let shell = shell(at: index), let id = workbenchID(at: index) {
                shell.nodes.forEach { $0.prepareForRemoval() }
                shells[id] = nil
                if index == activeIndex { root.show(NSView()) }
            }
            activeID = nil
            reloadSidebar()
            activate(index)
            Log.write("bancada \"\(origin.name)\" movida para a worktree \(created.path) "
                      + "— \(nodes.count) nós reiniciados lá")
        }

        schedulePersist()

        // Worktree reaproveitada fica de fora da cópia: ela já tem `.env` e
        // dependências, e passar por cima estragaria o que se pediu para reusar.
        copyUnversioned((created.reused ? [] : [(repoRoot, created.path)]) + extraWorktrees,
                        into: alvo)
        return nil
    }

    /// Copia o que o git não versiona para cada worktree criada, uma depois da
    /// outra — em fila para a faixa poder dizer qual repo está sendo copiado.
    /// Com clone do APFS cada uma leva um ou dois segundos, e esperar entre elas
    /// só deixava a mensagem mais tempo na tela.
    private func copyUnversioned(_ pending: [(repo: String, path: String)], into index: Int) {
        guard let first = pending.first else { shell(at: index)?.showBanner(nil); return }
        let rest = Array(pending.dropFirst())
        let repo = (first.repo as NSString).lastPathComponent

        shell(at: index)?.showBanner("Copiando o que o git não versiona em \(repo) "
                                  + "(.env, node_modules, build…)"
                                  + (rest.isEmpty ? "" : " — e mais \(rest.count)"))

        Worktree.copyUnversioned(from: first.repo, to: first.path) { [weak self] summary in
            guard let self else { return }
            self.shell(at: index)?.showBanner("\(repo): \(summary)")
            guard !rest.isEmpty else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.shell(at: index)?.showBanner(nil)
                }
                return
            }
            self.copyUnversioned(rest, into: index)
        }
    }

    /// Prepara os nós da origem para nascerem na worktree: cada um apontando para
    /// onde deve, e sem a conversa de quem serviu de molde.
    ///
    /// Três destinos, e a regra é sempre "para onde este terminal deve abrir":
    ///
    /// - **dentro do repositório da origem** → relativo. É o que faz o nó valer em
    ///   qualquer checkout, e é o motivo de o `cwd` relativo existir
    /// - **worktree própria criada** → absoluto, apontando para ela
    /// - **fora do repositório, sem worktree** → absoluto, apontando para o lugar
    ///   original. Repo vizinho não tem equivalente dentro da worktree da bancada, e
    ///   jogar o terminal na raiz dela o transforma em cópia do terminal ao lado
    ///
    /// A versão anterior só olhava `cwd` começando com `/` ou `~`, e por isso
    /// `../nexus-backend` atravessava a duplicação **literal**: na origem `..` era
    /// a pasta de projetos, e na worktree passou a ser `worktrees/<repo>/`, que
    /// não tem backend nenhum. O terminal abria na raiz da worktree em silêncio, e
    /// o agente do backend trabalhava no frontend.
    private static func repointed(_ nodes: [NodeConfig], originRoot: String,
                                  cwds: [String: String]) -> [NodeConfig] {
        var result = nodes.map(\.withoutConversation)
        let root = URL(fileURLWithPath: originRoot)

        for i in result.indices {
            if let novo = cwds[result[i].id] {
                result[i].cwd = novo
                continue
            }
            guard let cwd = result[i].cwd else { continue }

            let resolved = WorkbenchConfig.resolve(cwd: cwd, against: root)
            if resolved == originRoot {
                result[i].cwd = nil
            } else if resolved.hasPrefix(originRoot + "/") {
                result[i].cwd = String(resolved.dropFirst(originRoot.count + 1))
            } else {
                result[i].cwd = NodeWorktreePlanner.short(resolved)
                Log.write("duplicar: nó \"\(result[i].id)\" abre fora do repositório "
                          + "(\(cwd)) — segue apontando para \(resolved)")
            }
        }
        return result
    }

    /// O que fazer com a worktree recém-criada.
    private enum WorktreeDestination {
        /// Bancada nova na lista; a de origem continua intacta e rodando.
        case newWorkbench
        /// A bancada atual passa a apontar para a worktree. Os terminais são
        /// reiniciados lá — não há como trocar o diretório de um pty em curso.
        case moveCurrent
    }

    private struct WorktreeForm {
        let branch: String
        let template: String?
        let target: WorktreeDestination
        /// O que cada terminal faz. Vazio quando não há bancada de origem.
        let nodes: [NodeWorktree]
    }

    private func askWorktreeForm(status: Worktree.Status,
                                 repoRoot: String,
                                 suggestedBranch: String,
                                 inheriting origin: WorkbenchConfig? = nil) -> WorktreeForm? {
        let alert = NSAlert()
        alert.messageText = "Worktree de \((repoRoot as NSString).lastPathComponent)"
        alert.informativeText = worktreeSummary(status: status)
        // "Abrir" e não "Criar": a branch pode já existir, e aí não se cria nada.
        alert.addButton(withTitle: "Abrir")
        alert.addButton(withTitle: "Cancelar")

        // Duplicando há duas saídas; a partir do `+`, sem bancada de origem, só
        // faz sentido abrir uma nova.
        let offersMove = origin != nil
        let width: CGFloat = 460
        let container = FormView(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        // De cima para baixo: a lista de terminais tem tamanho variável, e contar y
        // a partir do rodapé em cada linha é como se erra por um pixel a cada
        // mudança de layout.
        var y: CGFloat = 0

        func label(_ text: String) {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 10, weight: .semibold)
            field.textColor = .secondaryLabelColor
            field.frame = NSRect(x: 0, y: y, width: width, height: 13)
            container.addSubview(field)
            y += 17
        }

        func hint(_ text: String, indent: CGFloat = 18, lines: Int = 1) {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 10)
            field.textColor = .secondaryLabelColor
            field.maximumNumberOfLines = lines
            field.frame = NSRect(x: indent, y: y, width: width - indent,
                                 height: CGFloat(lines) * 13)
            container.addSubview(field)
            y += CGFloat(lines) * 13 + 5
        }

        // Radio e não popup: as duas saídas são diferentes o bastante para
        // precisarem estar visíveis lado a lado — uma reinicia processos, a outra
        // não.
        let newWorkbenchRadio = HandButton(radioButtonWithTitle:
            "Abrir uma bancada nova na worktree", target: nil, action: nil)
        let moveRadio = HandButton(radioButtonWithTitle:
            "Mudar esta bancada para a worktree", target: nil, action: nil)

        // Precisa continuar vivo enquanto o modal roda: é ele quem responde pelos
        // cliques dos radios.
        let radios = RadioGroup([newWorkbenchRadio, moveRadio])

        if offersMove {
            label("O QUE FAZER")
            newWorkbenchRadio.frame = NSRect(x: 0, y: y, width: width, height: 18)
            newWorkbenchRadio.state = .on
            container.addSubview(newWorkbenchRadio)
            y += 20
            hint("Nada aqui é reiniciado; você troca entre as duas na barra.")

            moveRadio.frame = NSRect(x: 0, y: y, width: width, height: 18)
            container.addSubview(moveRadio)
            y += 20
            hint("Os terminais reiniciam na pasta nova — o que estiver rodando neles para.")
            y += 6
        }

        label("BRANCH DA BANCADA")
        let branchField = NSTextField(frame: NSRect(x: 0, y: y, width: width, height: 22))
        branchField.stringValue = suggestedBranch
        container.addSubview(branchField)
        y += 25

        // O que vai acontecer com o nome que está escrito agora: criar branch,
        // abrir na que já existe, seguir uma remota, ou usar a worktree que já a
        // tem aberta. Sem esta linha as quatro são visualmente idênticas, e a
        // diferença entre elas é o que o botão faz. Ver ADR-018.
        let verdict = NSTextField(labelWithString: "")
        verdict.font = .systemFont(ofSize: 10)
        verdict.maximumNumberOfLines = 3
        verdict.frame = NSRect(x: 0, y: y, width: width, height: 39)
        container.addSubview(verdict)
        y += 43

        // Onde a worktree nasce, para conferir — não para editar. A pasta é derivada
        // da branch pela mesma convenção de sempre, e apontá-la para outro lugar
        // não resolvia problema nenhum: era escolha a mais num formulário que já
        // pede as que importam.
        let pasta = NSTextField(labelWithString: "")
        pasta.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pasta.textColor = .secondaryLabelColor
        pasta.lineBreakMode = .byTruncatingMiddle
        pasta.frame = NSRect(x: 0, y: y, width: width, height: 14)
        container.addSubview(pasta)
        y += 22

        // Lido uma vez, e não por tecla: `git worktree list` + `branch` +
        // `for-each-ref` a cada caractere seriam três processos por tecla na
        // thread que está segurando o modal.
        let branches = Worktree.index(of: repoRoot)

        func refreshVerdict() {
            let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let plan = branches.plan(for: branch)
            verdict.stringValue = plan.summary(comingFrom: status.branch,
                                               dirty: status.hasDirtyTracked)
            verdict.textColor = plan.isFresh ? .secondaryLabelColor : .systemOrange

            if case .alreadyCheckedOut(let existing) = plan {
                pasta.stringValue = NodeWorktreePlanner.short(existing)
                // Reaproveitar worktree torna fácil cair na pasta de uma bancada
                // que já está aberta — dois code-servers vigiando os mesmos
                // arquivos, e dois agentes editando sem saber um do outro. Não é
                // proibido; é o tipo de coisa que tem de ser dita antes.
                if let aberta = configs.first(where: { $0.url.path == existing }) {
                    verdict.stringValue += " Cuidado: essa pasta já é a bancada \"\(aberta.name)\"."
                }
            } else {
                pasta.stringValue = branch.isEmpty ? ""
                    : NodeWorktreePlanner.short(Worktree.suggestedPath(repoRoot: repoRoot,
                                                                      branch: branch))
            }
        }
        refreshVerdict()

        // Uma linha por terminal, com o repositório de cada um. Existe porque uma
        // frente de trabalho raramente é um repositório só, e porque foi
        // justamente essa informação que faltou quando as pastas embaralharam: dá
        // para ver, antes de criar, onde cada card vai abrir.
        var rows: [NodeWorktreeRow] = []
        if let origin {
            let plans = NodeWorktreePlanner.inspect(origin, workbenchRoot: origin.url.path,
                                                    branch: suggestedBranch)
            label("TERMINAIS")
            hint("Todos vão. Na mesma branch da bancada, junto com ela; com outra branch, "
                 + "em worktree própria do repositório dele. Em branco, fica onde está.",
                 indent: 0, lines: 2)

            // Um índice por repositório, e não por linha: vários terminais no mesmo
            // repo dariam três processos de git cada um, na thread do modal.
            var indexes: [String: Worktree.BranchIndex] = [:]
            for repo in Set(plans.compactMap(\.repoRoot)) {
                indexes[repo] = repo == repoRoot ? branches : Worktree.index(of: repo)
            }

            let listHeight = min(CGFloat(plans.count), 4.5) * NodeWorktreeRow.height
            let list = FormView(frame: NSRect(x: 0, y: 0, width: width - 2,
                                              height: CGFloat(plans.count) * NodeWorktreeRow.height))
            for (index, plan) in plans.enumerated() {
                let row = NodeWorktreeRow(plan: plan, width: width - 2,
                                          workbenchBranch: suggestedBranch,
                                          branches: plan.repoRoot.flatMap { indexes[$0] })
                row.frame.origin.y = CGFloat(index) * NodeWorktreeRow.height
                list.addSubview(row)
                rows.append(row)
            }

            let scroll = NSScrollView(frame: NSRect(x: 0, y: y, width: width, height: listHeight))
            scroll.documentView = list
            scroll.hasVerticalScroller = plans.count > 4
            scroll.drawsBackground = false
            container.addSubview(scroll)
            y += listHeight + 4
        }

        // Renomear a branch reflete no veredito, na pasta e nas linhas dos
        // terminais, desde que você não as tenha editado à mão.
        let branchObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: branchField, queue: .main) { _ in
                refreshVerdict()
                let branch = branchField.stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                rows.forEach { $0.suggest(branch: branch) }
            }
        defer { NotificationCenter.default.removeObserver(branchObserver) }

        // Duplicando, os nós vêm da bancada de origem e não há template a escolher
        // — mostrar um seletor aqui só ofereceria uma decisão já tomada.
        let picker = HandPopUpButton(frame: NSRect(x: 0, y: y, width: width, height: 22))
        let vazio = "Começar vazia"
        if origin == nil {
            picker.addItem(withTitle: vazio)
            let templates = WorkbenchTemplateStore.names
            if !templates.isEmpty {
                picker.menu?.addItem(.separator())
                picker.addItems(withTitles: templates)
            }
            container.addSubview(picker)
            y += 22
        }

        container.setFrameSize(NSSize(width: width, height: y))
        alert.accessoryView = container
        alert.window.initialFirstResponder = branchField

        // `NSButton.target` não retém: sem prender a vida do grupo ao modal, o
        // ARC pode liberá-lo assim que sai do último uso — e os radios voltam a
        // não responder.
        let response = withExtendedLifetime(radios) { alert.runModal() }
        guard response == .alertFirstButtonReturn else { return nil }

        let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return nil }

        if origin != nil {
            return WorktreeForm(branch: branch, template: nil,
                                target: moveRadio.state == .on ? .moveCurrent : .newWorkbench,
                                nodes: rows.map(\.resolved))
        }
        let chosen = picker.titleOfSelectedItem
        return WorktreeForm(branch: branch,
                            template: chosen == vazio ? nil : chosen,
                            target: .newWorkbench, nodes: [])
    }

    /// Diz exatamente o que vai junto. "Leva tudo" sem detalhar é o tipo de
    /// promessa que só se descobre quebrada depois.
    ///
    /// De onde a worktree sai e o que acontece com as mudanças não commitadas
    /// NÃO estão aqui: dependem da branch que você digitar, e ficam na linha que
    /// acompanha o campo dela. Repetir aqui seria contradizê-la na metade dos
    /// casos.
    private func worktreeSummary(status: Worktree.Status) -> String {
        var linhas: [String] = []
        if !status.untracked.isEmpty {
            linhas.append("\(status.untracked.count) arquivo(s) novo(s) vão junto.")
        }
        // "Quando ela nasce" porque a worktree pode ser uma que já existe, e ali
        // nada é copiado: sobrescrever o .env de uma pasta com trabalho dentro
        // seria estragar o que se pediu para reaproveitar.
        linhas.append("Quando a worktree nasce, o que o .gitignore esconde (.env, node_modules, "
                      + "build…) é copiado depois, por "
                      + "\(Flavor.current.config("worktree-copy.sh").path).")
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
    /// bancada"), e separar em dois passos só adiciona cliques.
    private func askWorkbenchNameAndTemplate(suggested: String) -> (String, String?)? {
        let alert = NSAlert()
        alert.messageText = "Nova bancada"
        alert.informativeText = "O nome é a primeira parte do endereço de dispatch."
        alert.addButton(withTitle: "Criar")
        alert.addButton(withTitle: "Cancelar")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 54))

        let field = NSTextField(frame: NSRect(x: 0, y: 30, width: 280, height: 24))
        field.stringValue = suggested
        field.placeholderString = "nome da bancada"
        container.addSubview(field)

        let picker = HandPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let vazio = "Começar vazia"
        picker.addItem(withTitle: vazio)
        let templates = WorkbenchTemplateStore.names
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
    private func renameWorkbench(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let current = configs[index].name

        let alert = NSAlert()
        alert.messageText = "Renomear bancada"
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
        let name = WorkbenchStore.availableName(basedOn: typed, taken: taken)

        configs[index].name = name
        shell(at: index)?.nodes.forEach { $0.workbenchRenamed(to: name) }
        reloadSidebar()
        Log.write("bancada \"\(current)\" renomeada para \"\(name)\"")
        schedulePersist()
    }

    private func confirmRemoveWorkbench(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let config = configs[index]
        let live = shell(at: index) != nil
        // TODAS as worktrees da bancada, e não só a pasta dela: desde o worktree por
        // terminal (ADR-017), uma bancada pode ter aberto worktree em três
        // repositórios diferentes. Apagar só a da bancada deixava as outras no disco
        // e registradas no git, sem nada na tela que lembrasse delas.
        let involved = worktrees(of: config)
        let deletable = involved.filter { $0.usedBy == nil }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remover a bancada \"\(config.name)\"?"
        alert.informativeText = live
            ? "Os terminais abertos são encerrados."
            : "A bancada sai da lista."
        alert.addButton(withTitle: "Remover")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true

        var checkbox: NSButton?
        if !deletable.isEmpty {
            let box = HandButton(
                checkboxWithTitle: deletable.count == 1
                    ? "Também apagar a worktree do disco"
                    : "Também apagar as \(deletable.count) worktrees do disco",
                target: nil, action: nil)
            box.state = .off

            var linhas = involved.map { wt -> String in
                let quem = wt.owners.joined(separator: ", ")
                guard let usedBy = wt.usedBy else {
                    return "\(wt.repo) · \(wt.branch ?? "?") · \(quem)"
                }
                return "\(wt.repo) · \(wt.branch ?? "?") · MANTIDA, é a bancada \"\(usedBy)\""
            }
            linhas.append("Desmarcado, as pastas ficam onde estão e você pode reabri-las.")

            let hint = NSTextField(labelWithString: linhas.joined(separator: "\n"))
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = .secondaryLabelColor
            hint.maximumNumberOfLines = linhas.count

            let altura = CGFloat(linhas.count) * 14 + 4
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: altura + 22))
            box.frame = NSRect(x: 0, y: altura, width: 420, height: 18)
            hint.frame = NSRect(x: 18, y: 0, width: 402, height: altura)
            container.addSubview(box)
            container.addSubview(hint)
            alert.accessoryView = container
            checkbox = box
        } else if involved.isEmpty {
            alert.informativeText += " Nenhuma pasta é tocada."
        } else {
            // Tudo o que ela usa é pasta de outra bancada: apagar levaria trabalho
            // de quem não foi consultado.
            alert.informativeText += " As worktrees dela são de outras bancadas e ficam."
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard checkbox?.state == .on else {
            removeWorkbench(index)
            return
        }
        guard confirmWorktreeLosses(deletable) else { return }

        // Apagar antes de tirar a bancada da lista: se o git recusar, você fica com
        // a bancada e com a pasta, em vez de perder a bancada e ficar com a pasta.
        var falhas: [String] = []
        var removidas: [String] = []
        var sobras: [String] = []
        for wt in deletable {
            do {
                try Worktree.remove(wt.path)
                removidas.append("\(wt.repo)/\(wt.branch ?? "?")")
            } catch Worktree.Failure.leftovers(let path, let reason) {
                // O git já desfez o registro: a worktree acabou, e o que sobrou é
                // pasta. Segurar a bancada por causa dela seria segurar por um
                // problema que a própria remoção resolve — quem está escrevendo lá
                // dentro é o dev server e o agente DESTA bancada (as órfãs no disco
                // eram só `.vite` e `.omc`), e eles morrem junto com ela. A faxina
                // fica para depois disso (ADR-060).
                Log.write("worktree: \(path) — \(reason); a pasta fica para a faxina "
                          + "depois que os processos da bancada morrerem")
                removidas.append("\(wt.repo)/\(wt.branch ?? "?")")
                sobras.append(path)
            } catch {
                // No log também: o alerta some com um OK, e é justamente a
                // mensagem do git que diz por que a pasta resistiu.
                Log.write("worktree: falha ao apagar \(wt.path) — \(error)")
                falhas.append("\(wt.repo) · \(wt.branch ?? "?") — \(error)")
            }
        }

        guard falhas.isEmpty else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "A bancada não foi removida"
            alert.informativeText = (removidas.isEmpty
                ? "" : "Já apagadas: \(removidas.joined(separator: ", ")).\n\n")
                + "Não consegui apagar:\n" + falhas.joined(separator: "\n")
            alert.runModal()
            return
        }
        let roots = multiRoots(config)
        removeWorkbench(index)
        sweepLeftovers(sobras, roots: roots)
    }

    /// A segunda passada nas pastas que o git deixou para trás.
    ///
    /// Depois de a bancada sair: `prepareForRemoval` acabou de mandar SIGTERM, e
    /// quem ignorou leva SIGKILL meio segundo depois. Antes disso o dev server
    /// ainda estava recriando `.vite` mais rápido do que qualquer um apaga — é
    /// por isso que a faxina não roda junto com o `worktree remove`.
    private func sweepLeftovers(_ paths: [String], roots: [URL] = []) {
        roots.forEach { MultiProjectLinks.pruneRoot($0) }
        guard !paths.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for path in paths {
                do {
                    try Worktree.finishRemoval(of: path, registered: false)
                    Log.write("worktree: \(path) apagada na segunda passada")
                } catch {
                    Log.write("worktree: \(path) resistiu — \(error)")
                }
            }
            roots.forEach { MultiProjectLinks.pruneRoot($0) }
        }
    }

    private func isMultiProject(_ config: WorkbenchConfig) -> Bool {
        config.project.flatMap { project(withID: $0) }?.isMulti ?? false
    }

    /// A pasta-mãe de uma bancada multi-projeto em worktree, para sair junto
    /// com as worktrees de dentro. A do checkout principal é a pasta de links
    /// do projeto, e fica.
    private func multiRoots(_ config: WorkbenchConfig) -> [URL] {
        guard isMultiProject(config),
              let project = config.project.flatMap({ project(withID: $0) }),
              !project.owns(path: config.url.path) else { return [] }
        return [config.url]
    }

    /// PNG do card de um nó, direto do AppKit.
    ///
    /// `cacheDisplay` desenha a árvore de views num bitmap sem depender da tela —
    /// funciona com a janela atrás de outra, o que o `screencapture` não faz. O
    /// corpo de um `WKWebView` sai em branco por esse caminho (ele pinta fora da
    /// árvore), e para o conteúdo do editor existe o `/shot` normal.
    private func cardSnapshot(target: String, file: URL) -> String {
        // `window` fotografa a janela inteira — barra, sidebar e conteúdo. É o que
        // permite conferir de fora uma mudança de barra, que não tem card nenhum.
        let alvo: NSView?
        if target == "window" {
            alvo = window.contentView
        } else if target == "sidebar" {
            // Só a barra: no `window` o vidro por baixo sai branco no bitmap e
            // esconde as linhas, que é justamente o que se quer conferir.
            alvo = root.sidebar
        } else {
            let parts = target.split(separator: "/", maxSplits: 1).map(String.init)
            alvo = parts.count == 2
                ? configs.firstIndex(where: { $0.name == parts[0] })
                    .flatMap { shell(at: $0)?.nodes.first { $0.nodeID == parts[1] } }
                : nil
        }
        guard let node = alvo else { return "erro: nó desconhecido '\(target)'" }

        guard let rep = node.bitmapImageRepForCachingDisplay(in: node.bounds) else {
            return "erro: não consegui alocar o bitmap"
        }
        node.cacheDisplay(in: node.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            return "erro: falha ao converter em PNG"
        }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: file)
        } catch {
            return "erro: \(error)"
        }
        return file.path
    }

    /// Remoção sem diálogo, para o socket. Mesmas regras do formulário: só apaga
    /// worktree ligada, e nunca a que é pasta de outra bancada.
    private func removeWorkbench(named name: String, purge: Bool) -> [String: Any] {
        guard let index = configs.firstIndex(where: { $0.name == name })
        else { return ["ok": false, "error": "bancada desconhecida '\(name)'"] }

        let involved = worktrees(of: configs[index])
        var removidas: [String] = []
        var falhas: [String] = []
        var sobras: [String] = []

        if purge {
            for wt in involved where wt.usedBy == nil {
                do {
                    try Worktree.remove(wt.path)
                    removidas.append(wt.path)
                } catch Worktree.Failure.leftovers(let path, let reason) {
                    Log.write("worktree: \(path) — \(reason); faxina depois dos processos")
                    removidas.append(wt.path)
                    sobras.append(path)
                } catch {
                    Log.write("worktree: falha ao apagar \(wt.path) — \(error)")
                    falhas.append("\(wt.path): \(error)")
                }
            }
            guard falhas.isEmpty else {
                return ["ok": false, "error": "worktree não removida",
                        "removed": removidas, "failed": falhas]
            }
        }

        let roots = purge ? multiRoots(configs[index]) : []
        removeWorkbench(index)
        sweepLeftovers(sobras, roots: roots)
        return ["ok": true, "workbench": name, "removed": removidas,
                "sweeping": sobras,
                "kept": involved.filter { $0.usedBy != nil }
                    .map { ["path": $0.path, "usedBy": $0.usedBy ?? ""] },
                "worktrees": involved.map { ["path": $0.path, "repo": $0.repo,
                                             "branch": $0.branch ?? "",
                                             "owners": $0.owners] }]
    }

    /// Uma worktree que esta bancada usa.
    private struct WorkbenchWorktree {
        let path: String
        let repo: String
        let branch: String?
        /// Quem dentro da bancada abre nela: "bancada", ou os ids dos nós.
        let owners: [String]
        /// Outra bancada que abre esta MESMA pasta. Apagar levaria o trabalho dela,
        /// e ela continuaria na lista apontando para o vazio.
        let usedBy: String?
    }

    /// Toda worktree ligada que a bancada usa: a pasta dela e a de cada nó que abre
    /// fora dela.
    ///
    /// Nó dentro da pasta da bancada não entra: é a mesma worktree, e apagá-la duas
    /// vezes daria erro na segunda. Só worktree LIGADA — oferecer apagar o checkout
    /// principal seria oferecer apagar o repositório.
    private func worktrees(of config: WorkbenchConfig) -> [WorkbenchWorktree] {
        var owners: [String: [String]] = [:]
        let raiz = config.url.path

        if config.exists, Worktree.isLinkedWorktree(raiz) { owners[raiz] = ["bancada"] }

        // Bancada de multi-projeto em worktree: a raiz não é repositório, e cada
        // subpasta é uma worktree. Link não entra — é a pasta de links do
        // checkout principal, ou uma worktree de outro lugar reaproveitada, e
        // nenhuma das duas é desta bancada para apagar (ADR-065).
        if isMultiProject(config), !Worktree.isLinkedWorktree(raiz) {
            for child in MultiProjectLinks.realSubfolders(of: config.url)
            where Worktree.isLinkedWorktree(child) {
                owners[child] = ["bancada"]
            }
        }

        for node in config.nodes where node.type != .web {
            let path = config.resolvedDirectory(for: node)
            guard path != raiz, !path.hasPrefix(raiz + "/"),
                  FileManager.default.fileExists(atPath: path),
                  Worktree.isLinkedWorktree(path)
            else { continue }
            owners[path, default: []].append(node.id)
        }

        return owners.keys.sorted().map { path in
            WorkbenchWorktree(
                path: path,
                repo: ((Worktree.mainRepo(of: path) ?? path) as NSString).lastPathComponent,
                branch: Worktree.branchOf(path),
                owners: owners[path] ?? [],
                usedBy: configs.first { $0.name != config.name && $0.url.path == path }?.name)
        }
    }

    /// Segundo passo, só quando há trabalho a perder. `worktree remove` precisa de
    /// `--force` aqui — a worktree nasce suja de propósito — e forçar sem mostrar
    /// o que morre seria apagar às escuras.
    ///
    /// Uma seção por worktree: com três repositórios envolvidos, somar os números
    /// num total só não diria em qual deles está o trabalho que você não quer
    /// perder.
    private func confirmWorktreeLosses(_ worktrees: [WorkbenchWorktree]) -> Bool {
        var linhas: [String] = []

        for wt in worktrees {
            guard let losses = try? Worktree.losses(in: wt.path), !losses.isEmpty else { continue }
            if !linhas.isEmpty { linhas.append("") }
            linhas.append("\(wt.repo) · \(wt.branch ?? "?")")

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
                              + "sobrevivem na branch \(wt.branch ?? "?"), que não é apagada.")
            }
        }

        guard !linhas.isEmpty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Isto apaga trabalho não commitado"
        alert.informativeText = linhas.joined(separator: "\n")
        alert.addButton(withTitle: "Apagar mesmo assim")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func removeWorkbench(_ index: Int) {
        let name = configs[index].name

        // Solta os processos antes de perder a referência à bancada na tela.
        if let shell = shell(at: index) {
            shell.nodes.forEach { $0.prepareForRemoval() }
            if index == activeIndex { root.show(NSView()) }
        }

        // Shell e controller são chaveados por id: remover do meio desloca as
        // posições, e nenhum dos dois se importa. Antes isto era um bloco de
        // reindexação seguido de religar todas as closures.
        let removed = configs[index].id
        configs.remove(at: index)
        shells[removed] = nil
        edgeControllers[removed] = nil
        openTabs.removeAll { $0 == removed }

        activeID = nil
        reloadSidebar()
        Log.write("bancada \"\(name)\" removida")
        schedulePersist()

        if !configs.isEmpty { activate(min(index, configs.count - 1)) }
    }

    // MARK: - Reposicionar na árvore (ADR-051)

    func moveWorkspace(_ id: String, to position: Int) -> Bool {
        guard let moved = WorkspaceMove.workspace(id, to: position, in: workspaces) else { return false }
        workspaces = moved
        WorkspaceStore.save(workspaces)
        reloadSidebar()
        return true
    }

    func moveProject(_ id: String, toWorkspace target: String, at position: Int,
                     stored: Bool? = nil) -> Bool {
        guard let moved = WorkspaceMove.project(id, toWorkspace: target, at: position,
                                                stored: stored, in: workspaces) else { return false }
        workspaces = moved
        WorkspaceStore.save(workspaces)
        reloadSidebar()
        return true
    }

    /// Arrastar bancada na barra muda a POSIÇÃO dela. Os shells não se mexem:
    /// são por id (ver `WorkbenchLookup`). O que ainda anda por posição é
    /// `activeIndex`, e o mapa do movimento diz para onde ele foi.
    func moveWorkbench(_ index: Int, toProject project: String, at position: Int) -> Bool {
        guard let moved = WorkspaceMove.workbench(index, toProject: project, at: position,
                                                  in: configs) else { return false }
        configs = moved.list
        // `activeID` não precisa de correção nenhuma: o id não se move com a lista.
        reloadSidebar()
        schedulePersist()
        return true
    }

    /// Guardar o projeto na gaveta do workspace (ou tirá-lo de lá) pelo menu:
    /// vai para o fim do lado de destino, que é onde a mão o deixaria.
    private func storeProject(_ id: String, in workspace: String, stored: Bool) {
        _ = moveProject(id, toWorkspace: workspace, at: Int.max, stored: stored)
        // Guardar com a gaveta fechada faria o projeto sumir sem explicação.
        if stored, let w = workspaces.firstIndex(where: { $0.id == workspace }),
           !workspaces[w].isStoredOpen {
            workspaces[w].storedOpen = true
            WorkspaceStore.save(workspaces)
            reloadSidebar()
        }
    }

    private func toggleDrawer(_ workspace: String) {
        guard let w = workspaces.firstIndex(where: { $0.id == workspace }) else { return }
        workspaces[w].storedOpen = workspaces[w].isStoredOpen ? nil : true
        WorkspaceStore.save(workspaces)
        reloadSidebar()
    }

    private func markLiveWorkbenches() {
        root.sidebar.markLive(indices: liveIndices)
    }

    // MARK: - Workspaces e projetos (ADR-043)

    private func reloadSidebar() {
        root.sidebar.reload(workspaces: workspaces, configs: configs)
        root.sidebar.select(activeIndex)
        markLiveWorkbenches()
    }

    private func project(withID id: String) -> ProjectConfig? {
        for space in workspaces { if let p = space.project(withID: id) { return p } }
        return nil
    }

    /// Toda bancada ganha projeto; o que mudou vai para o disco na hora. Roda na
    /// carga e a cada bancada criada por pasta livre. O `mainRepo` é git de
    /// verdade: bancada em worktree cai no projeto do checkout principal.
    private func reconcileWorkspaces() {
        let result = WorkspaceStore.reconcile(workspaces: workspaces, workbenches: configs,
                                              mainRepo: { Worktree.mainRepo(of: $0) })
        result.notes.forEach { Log.write("workspaces: \($0)") }
        guard result.changed else { return }
        workspaces = result.workspaces
        configs = result.workbenches
        WorkspaceStore.save(workspaces)
        schedulePersist()
        if root != nil { reloadSidebar() }
    }

    /// Ativar uma bancada escondida por grupo recolhido — pelo socket, ou pela
    /// remoção da vizinha — abre o caminho até ela, senão a seleção some.
    private func revealInSidebar(_ index: Int) {
        let tree = WorkspaceTree(workspaces: workspaces, workbenches: configs)
        guard let (wsID, pid) = tree.ancestors(of: index),
              let w = workspaces.firstIndex(where: { $0.id == wsID }) else { return }
        var changed = false
        if workspaces[w].isCollapsed { workspaces[w].collapsed = nil; changed = true }
        if let p = workspaces[w].projects.firstIndex(where: { $0.id == pid }),
           workspaces[w].projects[p].isCollapsed {
            workspaces[w].projects[p].collapsed = nil
            changed = true
        }
        guard changed else { return }
        WorkspaceStore.save(workspaces)
        reloadSidebar()
    }

    private func toggleGroup(_ item: SidebarItem) {
        switch item {
        case .workspace(let id):
            guard let w = workspaces.firstIndex(where: { $0.id == id }) else { return }
            workspaces[w].collapsed = workspaces[w].isCollapsed ? nil : true
        case .project(let wsID, let id):
            guard let w = workspaces.firstIndex(where: { $0.id == wsID }),
                  let p = workspaces[w].projects.firstIndex(where: { $0.id == id }) else { return }
            workspaces[w].projects[p].collapsed = workspaces[w].projects[p].isCollapsed ? nil : true
        case .workbench, .orphans:
            return
        }
        WorkspaceStore.save(workspaces)
        reloadSidebar()
    }

    private func createWorkspace() {
        guard let form = WorkspaceForm.ask() else { return }
        var space = WorkspaceConfig(name: form.name)
        space.projects = WorkspaceEdit.apply(
            to: [], folders: form.folders, multis: form.multis,
            linkPath: Self.multiProjectPath, hasWorkbenches: { _ in false }).projects
        if let source = form.iconSource {
            do { try WorkspaceStore.installIcon(from: source, into: &space) }
            catch { presentError("Não consegui copiar a imagem", error) }
        }
        workspaces.append(space)
        WorkspaceStore.save(workspaces)
        MultiProjectLinks.syncAll([space])
        Log.write("workspace \"\(space.name)\" criado com \(space.projects.count) projeto(s)")
        // Bancada que já apontava para uma dessas pastas continua no projeto
        // antigo: pertencimento é por id, e trocar de teto é decisão sua.
        reloadSidebar()
    }

    private func editWorkspace(_ id: String) {
        guard let w = workspaces.firstIndex(where: { $0.id == id }) else { return }
        guard let form = WorkspaceForm.ask(existing: workspaces[w]) else { return }
        var space = workspaces[w]
        space.name = form.name

        let tree = WorkspaceTree(workspaces: workspaces, workbenches: configs)
        let outcome = WorkspaceEdit.apply(
            to: space.projects, folders: form.folders, multis: form.multis,
            linkPath: Self.multiProjectPath,
            hasWorkbenches: { !tree.indices(inProject: $0).isEmpty })
        space.projects = outcome.projects
        let refused = outcome.refused

        if form.clearIcon { WorkspaceStore.removeIcon(of: &space) }
        if let source = form.iconSource {
            do { try WorkspaceStore.installIcon(from: source, into: &space) }
            catch { presentError("Não consegui copiar a imagem", error) }
        }
        workspaces[w] = space
        WorkspaceStore.save(workspaces)
        MultiProjectLinks.syncAll([space])
        Log.write("workspace \"\(space.name)\" editado — \(space.projects.count) projeto(s)")
        reloadSidebar()

        if !refused.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Projeto com bancadas fica"
            alert.informativeText = "Remova antes as bancadas de: \(refused.joined(separator: ", "))."
            alert.runModal()
        }
    }

    private static func multiProjectPath(_ id: String) -> String {
        (Flavor.current.multiProjectDirectory(id).path as NSString).abbreviatingWithTildeInPath
    }

    private func confirmRemoveWorkspace(_ id: String) {
        guard let w = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let tree = WorkspaceTree(workspaces: workspaces, workbenches: configs)
        let members = tree.indices(inWorkspace: id)
        let alert = NSAlert()
        if !members.isEmpty {
            alert.messageText = "\"\(workspaces[w].name)\" ainda tem \(members.count) bancada(s)"
            alert.informativeText = "Remova as bancadas antes de remover o workspace."
            alert.runModal()
            return
        }
        alert.messageText = "Remover o workspace \"\(workspaces[w].name)\"?"
        alert.informativeText = "Só a organização some; nenhuma pasta é tocada."
        alert.addButton(withTitle: "Remover")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var space = workspaces.remove(at: w)
        WorkspaceStore.removeIcon(of: &space)
        try? FileManager.default.removeItem(at: Flavor.current.workspaceDirectory(space.id))
        WorkspaceStore.save(workspaces)
        Log.write("workspace \"\(space.name)\" removido")
        reloadSidebar()
    }

    private func confirmRemoveProject(_ workspaceID: String, _ projectID: String) {
        guard let w = workspaces.firstIndex(where: { $0.id == workspaceID }),
              let p = workspaces[w].projects.firstIndex(where: { $0.id == projectID }) else { return }
        let project = workspaces[w].projects[p]
        let tree = WorkspaceTree(workspaces: workspaces, workbenches: configs)
        let members = tree.indices(inProject: projectID)
        let alert = NSAlert()
        if !members.isEmpty {
            alert.messageText = "\"\(project.name)\" ainda tem \(members.count) bancada(s)"
            alert.informativeText = "Remova as bancadas antes de tirar o projeto do workspace."
            alert.runModal()
            return
        }
        alert.messageText = "Tirar \"\(project.name)\" de \"\(workspaces[w].name)\"?"
        alert.informativeText = "A pasta \(project.path) não é tocada."
        alert.addButton(withTitle: "Tirar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        workspaces[w].projects.remove(at: p)
        WorkspaceStore.save(workspaces)
        Log.write("projeto \"\(project.name)\" tirado do workspace \"\(workspaces[w].name)\"")
        reloadSidebar()
    }

    /// A árvore, para verificar por fora.
    private func workspacesSnapshot() -> [String: Any] {
        let tree = WorkspaceTree(workspaces: workspaces, workbenches: configs)
        return [
            "workspaces": workspaces.map { space in
                ["id": space.id, "name": space.name, "icon": space.icon ?? "",
                 "collapsed": space.isCollapsed,
                 "projects": space.projects.map { project in
                     ["id": project.id, "name": project.name, "path": project.path,
                      "collapsed": project.isCollapsed,
                      "workbenches": tree.indices(inProject: project.id).map { configs[$0].name }]
                 }] as [String: Any]
            },
            "orphans": tree.orphans.map { configs[$0].name },
        ]
    }

    // MARK: - Templates

    /// Salva o canvas atual como preset. O que vira template é o `WorkbenchConfig`
    /// já sincronizado, então o layout gravado é o que está na tela.
    private func saveCurrentAsTemplate() {
        guard activeIndex >= 0, activeIndex < configs.count else { return }
        syncFrames(index: activeIndex)

        let workbench = configs[activeIndex]
        guard !workbench.nodes.isEmpty else {
            let empty = NSAlert()
            empty.messageText = "Canvas vazio"
            empty.informativeText = "Monte os nós que você quer no preset e salve de novo."
            empty.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Salvar como template"
        alert.informativeText = Self.templateSummary(of: workbench)
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "nome do template"
        // O nome da bancada, e não o do template de origem: este botão cria um
        // preset novo. Atualizar o de origem é o botão ao lado.
        field.stringValue = workbench.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if WorkbenchTemplateStore.template(named: name) != nil {
            let overwrite = NSAlert()
            overwrite.alertStyle = .warning
            overwrite.messageText = "Já existe um template \"\(name)\""
            overwrite.informativeText = "Substituir pelo canvas atual?"
            overwrite.addButton(withTitle: "Substituir")
            overwrite.addButton(withTitle: "Cancelar")
            guard overwrite.runModal() == .alertFirstButtonReturn else { return }
        }

        WorkbenchTemplateStore.put(WorkbenchTemplateStore.capture(from: workbench), named: name)
        configs[activeIndex].template = name
        // A bancada passa a ter origem: o botão de atualizar aparece agora, sem
        // esperar o próximo arranque.
        shell(at: activeIndex)?.canvas.originTemplate = name
        schedulePersist()
    }

    /// Regrava o template de que esta bancada nasceu, com o canvas de agora.
    ///
    /// Botão separado do "salvar como", e não o mesmo com o nome pré-preenchido:
    /// são intenções diferentes. Uma cria um preset novo e pede nome; a outra
    /// atualiza um que já existe e já tem nome — pedir de novo só cria a chance
    /// de errar uma letra e nascer um template gêmeo.
    ///
    /// Editar o template não mexe em quem já nasceu dele: os valores foram
    /// copiados na criação, e as bancadas existentes seguem como estão.
    private func updateOriginTemplate(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let workbench = configs[index]
        guard let name = workbench.template else { return }

        guard !workbench.nodes.isEmpty else {
            let empty = NSAlert()
            empty.messageText = "Canvas vazio"
            empty.informativeText = "Um template sem nós não abre nada. "
                + "Monte o canvas e atualize de novo."
            empty.runModal()
            return
        }

        // O template pode ter sido apagado desde que esta bancada nasceu: aí não
        // há o que atualizar, e virar um "salvar como" silencioso seria pior.
        guard WorkbenchTemplateStore.template(named: name) != nil else {
            let sumiu = NSAlert()
            sumiu.messageText = "O template \"\(name)\" não existe mais"
            sumiu.informativeText = "Use \"salvar como template\" para criá-lo de novo."
            sumiu.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Atualizar o template \"\(name)\"?"
        alert.informativeText = Self.templateSummary(of: workbench)
            + "\n\nAs bancadas que já nasceram deste template não mudam."
        alert.addButton(withTitle: "Atualizar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        WorkbenchTemplateStore.put(WorkbenchTemplateStore.capture(from: workbench), named: name)
        Log.write("template \"\(name)\" atualizado a partir da bancada \"\(workbench.name)\"")
    }

    /// Diz o que está sendo salvo, em uma linha: sem isso o diálogo pede um nome
    /// para algo que o usuário não vê.
    private static func templateSummary(of workbench: WorkbenchConfig) -> String {
        var counts: [NodeKind: Int] = [:]
        for node in workbench.nodes { counts[node.type, default: 0] += 1 }

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
            + "\(workbench.path) como pasta inicial."
    }

    /// Layout de quem ainda não tem frame gravado: editor à esquerda, o resto
    /// empilhado à direita. Um nó só passa por aqui uma vez — na primeira vez o
    /// resultado é escrito no workbenches.json e a partir daí manda o arquivo.
    private func defaultFrames(for config: WorkbenchConfig) -> [String: NSRect] {
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
                                in config: WorkbenchConfig,
                                agents: [String: AgentProfile]) -> String? {
        guard node.type == .agent else { return nil }
        return """
            Este terminal é um nó do Egeon Deck e tem vizinhos endereçáveis. \
            Use o comando `egeon`:

              egeon peers                     quem você pode acionar agora
              egeon status                    quem VOCÊ é: endereço, papel, bancada
              egeon peek <endereço> [linhas]  o que ele mostra agora, sem interromper
              egeon send <endereço> <<'MB'    manda o texto para ele
              (o que você quer dizer)
              MB
              egeon trace <<'MB'              registra na trilha da bancada
              pedido: … — entrega: …
              MB

            Mensagem que chega marcada com `[ED] mensagem de <alguém>` veio de um \
            terminal que parou e espera o seu resultado — ele não vê a sua tela. \
            Termine respondendo a ele com `egeon send`, uma ou duas linhas: o que \
            você entregou, ou por que não deu. E se você parar para perguntar algo \
            ao usuário no meio, avise o remetente ANTES de parar: quem para calado \
            deixa o outro esperando sem saber de nada.

            Lista vazia significa que ninguém está ligado a você neste momento; \
            ela muda enquanto você trabalha, então consulte na hora em vez de \
            confiar na memória. Quando o pedido for para outro agente, olhe os \
            vizinhos ANTES de abrir um subagente do seu próprio CLI: o vizinho \
            está aberto na tela do usuário, o subagente morre no fim do seu \
            turno. Acionar não é obrigatório, e responder a uma \
            mensagem também não. Endereço fora da lista é recusado, e uma cadeia \
            longa demais de agentes falando entre si também — quando isso \
            acontecer, volte a falar com o usuário em vez de insistir.

            A trilha é a memória da bancada, e sobrevive à conversa: ao fim de \
            TODO turno, antes do marcador final, rode `egeon trace` com uma ou \
            duas linhas — o que foi pedido e o que você entregou (ou onde parou). \
            Quem escreveu, CLI, modelo e conversa são carimbados pelo app; não \
            os repita.
            """
    }

    private static func launchPlan(for node: NodeConfig,
                                   profile: AgentProfile?,
                                   catalog: String?,
                                   rules: String?) -> (command: String,
                                                       promptToInject: String?,
                                                       hooked: Bool) {
        let base = node.cmd
            ?? profile.map { $0.command.joined(separator: " ") }
            ?? "exec /bin/zsh -l"

        guard node.type == .agent, let profile else { return (base, nil, false) }

        // Modelo e esforço são flags do binário do perfil: com `cmd` trocado por
        // outro programa, anexar `--model` mataria o terminal no arranque.
        let modelFlags = profile.runsOwnBinary(base)
            ? (profile.modelArguments(node.model) ?? [])
                + profile.effortLaunch(effort: node.effort, ultracode: node.ultracode == true).arguments
            : []
        let modelSuffix = modelFlags.isEmpty ? ""
            : " " + modelFlags.map(AppEnvironment.shellQuote).joined(separator: " ")

        guard let text = profile.systemPromptText(role: node.effectivePrompt, catalog: catalog,
                                                  rules: rules)
        else { return (base + modelSuffix, nil, false) }

        if let arguments = profile.systemPromptArguments(for: text), profile.runsOwnBinary(base) {
            var extras = modelFlags + arguments
            // O gancho de relato entra junto: é o que faz o app saber quando VOCÊ
            // troca de conversa dentro da TUI, e é por ele que chegam o fim de
            // turno e o pedido de permissão (ADR-024).
            let report = profile.reportArguments(hookFile: ClaudeHooks.settingsFile.path)
            if let report { extras += report }
            let flags = " " + extras.map(AppEnvironment.shellQuote).joined(separator: " ")
            return (conversationCommand(base: base, flags: flags, node: node, profile: profile),
                    nil, report != nil)
        }

        // CLI sem flag de system prompt (ou `cmd` trocado por outro programa):
        // resta injetar como primeira mensagem. Vale a pena junto de um papel ou
        // de regras, que já iam ser injetados de qualquer jeito; só pelo
        // protocolo, não — seria gastar um turno em toda bancada para um
        // marcador que se dilui depois de vinte mensagens. Aí o terminal fica
        // só com o silêncio.
        let hasRole = !(node.effectivePrompt ?? "").isEmpty || !(rules ?? "").isEmpty
        guard hasRole else {
            if profile.attentionConfig.activeMarker != nil {
                Log.write("agente \(profile.displayName): sem flag de system prompt, "
                          + "o protocolo de marcador não sobe — a detecção fica só no "
                          + "silêncio", key: "marker.\(profile.displayName)")
            }
            return (base + modelSuffix, nil, false)
        }
        return (base + modelSuffix, text, false)
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
    private static func conversationCommand(base: String, flags: String,
                                       node: NodeConfig, profile: AgentProfile) -> String {
        guard profile.keepsConversation, let id = node.conversationId,
              let resume = profile.conversationArguments(profile.resume, id: id),
              let fresh = profile.conversationArguments(profile.newSession, id: id) else {
            return base + flags
        }
        func line(_ arguments: [String]) -> String {
            base + " " + arguments.map(AppEnvironment.shellQuote).joined(separator: " ") + flags
        }
        // `conversationStarted` diz se já houve uma primeira subida: sem isso a linha
        // de estreia mostraria "No conversation found" antes de criar.
        return node.hasStartedConversation ? "\(line(resume)) || \(line(fresh))" : line(fresh)
    }

    /// Garante que um nó de agente tenha id de bancada próprio antes de subir.
    ///
    /// Ponto único: os cinco lugares que criam nó passam por aqui, então gerar o
    /// id em outro lugar não faz sentido.
    private func prepared(_ node: NodeConfig, index: Int) -> NodeConfig {
        guard node.type == .agent,
              let profile = node.agent.flatMap({ agents[$0] }), profile.keepsConversation,
              let position = configs[index].nodes.firstIndex(where: { $0.id == node.id })
        else { return node }

        if configs[index].nodes[position].conversationId == nil {
            configs[index].nodes[position].conversationId = UUID().uuidString
            schedulePersist()
            Log.write("bancada \(configs[index].name): nó \"\(node.id)\" ganhou conversa "
                      + "\(configs[index].nodes[position].conversationId ?? "?")")
        }
        return configs[index].nodes[position]
    }

    /// O CLI relatou qual conversa está aberta neste terminal.
    ///
    /// Chamado a cada prompt do agente, então só grava quando o valor muda de
    /// fato — senão seria uma reescrita do workbenches.json por mensagem sua.
    private func recordConversation(target: String, id: String, transcript: String?) {
        let parts = target.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let index = configs.firstIndex(where: { $0.name == parts[0] }),
              let position = configs[index].nodes.firstIndex(where: { $0.id == parts[1] })
        else { return }

        var changed = false
        // O transcript é conferido mesmo com a conversa igual: depois de um
        // rebuild o `conversationId` volta do arquivo e o caminho não, e sair cedo
        // aqui deixaria a conversa sem transcript até você trocar de conversa.
        if let transcript, !transcript.isEmpty,
           configs[index].nodes[position].transcript != transcript {
            configs[index].nodes[position].transcript = transcript
            changed = true
        }
        if configs[index].nodes[position].conversationId != id {
            let anterior = configs[index].nodes[position].conversationId ?? "nenhuma"
            configs[index].nodes[position].conversationId = id
            configs[index].nodes[position].conversationStarted = true
            changed = true
            Log.write("conversa[\(target)]: \(anterior) → \(id)")
        }
        guard changed else { return }
        schedulePersist()
    }

    /// Qual bancada é dona de uma pasta.
    ///
    /// Primeiro pelas pastas que os nós de editor de fato abriram, que é resposta
    /// exata. Só depois pelo caminho da bancada, e aí o mais específico ganha:
    /// duas bancadas podem apontar para o mesmo repositório em worktrees
    /// diferentes, e a worktree é sempre o caminho mais longo — comparar pela
    /// primeira que casa daria a resposta do checkout principal.
    private func workbenchOwning(folder raw: String) -> String? {
        let folder = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            .standardized.path
        for config in configs {
            for node in config.nodes where node.type == .editor {
                if config.directory(for: node) == folder { return config.name }
            }
        }
        return configs
            .filter { folder == $0.url.path || folder.hasPrefix($0.url.path + "/") }
            .max { $0.url.path.count < $1.url.path.count }?
            .name
    }

    private func makeNode(_ raw: NodeConfig, in config: WorkbenchConfig, frame: NSRect) -> NodeView {
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
                self?.updateWebNode(workbench: config.name, id: node.id,
                                    url: web.currentURL, profile: web.profileName)
            }
            return web

        case .shell, .agent:
            let profile = node.agent.flatMap { agents[$0] }
            if node.type == .agent && profile == nil {
                Log.write("bancada \(config.name): perfil de agente "
                          + "'\(node.agent ?? "?")' não existe em agents.json")
            }
            let launch = Self.launchPlan(
                for: node, profile: profile,
                catalog: Self.catalog(for: node, in: config, agents: agents),
                rules: AgentRules.block(workbench: config.rules, node: node.effectiveRules))

            let terminal = TerminalNode(frame: frame, address: address, title: title,
                                        cwd: config.directory(for: node),
                                        command: launch.command, profile: profile,
                                        config: node.config,
                                        model: node.model,
                                        effort: node.effort,
                                        ultracode: node.ultracode == true,
                                        catalog: profile.flatMap(ClaudeModelCatalog.current(for:)),
                                        extraEnvironment: profile.map {
                                            $0.effortLaunch(effort: node.effort,
                                                            ultracode: node.ultracode == true).environment
                                        } ?? [:],
                                        prompt: launch.promptToInject,
                                        hooked: launch.hooked)
            let launched = Date()
            terminal.modelResolver = { [weak self] in
                self?.literalModel(workbench: config.name, nodeID: node.id, since: launched)
            }
            if index >= 0, node.conversationId != nil, !node.hasStartedConversation,
               let position = configs[index].nodes.firstIndex(where: { $0.id == node.id }) {
                configs[index].nodes[position].conversationStarted = true
                schedulePersist()
            }
            return terminal
        }
    }

    private func build(_ index: Int) -> WorkbenchShell {
        let shell = WorkbenchShell(frame: root.contentFrame, mode: configs[index].viewMode)
        shells[configs[index].id] = shell
        wire(shell, id: configs[index].id)

        guard configs[index].exists else {
            shell.showBanner("Caminho não existe: \(configs[index].path) — edite \(Flavor.current.config("workbenches.json").path)")
            Log.write("bancada \(configs[index].name): caminho inexistente \(configs[index].path)")
            return shell
        }

        // Pasta de nó que não resolve é dita na hora de montar, e não descoberta
        // por um `pwd` três horas depois: o terminal abre na raiz da bancada, fica
        // com a cara do terminal certo, e o agente trabalha no lugar errado.
        let unresolved = configs[index].unresolvedDirectories
        if !unresolved.isEmpty {
            let lista = unresolved.map { "\($0.id) → \($0.tried)" }.joined(separator: ", ")
            shell.showBanner("Pasta inexistente, abrindo na raiz da bancada: \(lista)")
            Log.write("bancada \(configs[index].name): \(unresolved.count) nó(s) com cwd que não "
                      + "resolve — \(lista)")
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
                Log.write("bancada \(configs[index].name): nó \"\(node.id)\" estava fora do "
                          + "documento em (\(Int(frame.minX)),\(Int(frame.minY))) — resgatado")
                frame.origin.x = max(0, frame.minX)
                frame.origin.y = max(0, frame.minY)
            }

            configs[index].nodes[i].setFrame(frame)
            shell.attach(makeNode(node, in: configs[index], frame: frame))
        }
        schedulePersist()

        // Abrir enquadrando os nós, não em (0,0): a bancada gravada pode estar
        // toda longe do canto, e cair no vazio é ter de procurar os cards.
        DispatchQueue.main.async {
            shell.layoutSubtreeIfNeeded()
            shell.canvas.fitAll()
        }
        return shell
    }

    // MARK: - Barra de ações

    /// Liga um shell recém-montado ao app.
    ///
    /// Tudo aqui resolve a POSIÇÃO a partir do id na hora da chamada. Antes o
    /// índice era capturado por valor, e por isso remover ou arrastar uma
    /// bancada obrigava a religar todos os shells — um passo fácil de esquecer,
    /// e cujo sintoma é um botão de fechar que apaga o nó da bancada vizinha.
    private func wire(_ shell: WorkbenchShell, id: String) {
        // Fechar e configurar nó chegam pelo shell: quem os disparou pode ser o
        // canvas ou o mosaico, e daqui não faz diferença qual.
        shell.onRequestClose = { [weak self] node in
            guard let self, let index = self.index(ofID: id) else { return }
            self.confirmRemoval(of: node, index: index)
        }
        shell.onRequestEditNode = { [weak self] node in
            guard let self, let index = self.index(ofID: id) else { return }
            self.editNode(node, index: index)
        }
        shell.onRequestNodeWorktree = { [weak self] node in
            guard let self, let index = self.index(ofID: id) else { return }
            self.nodeWorktree(node, index: index)
        }
        shell.onRequestNodeModel = { [weak self] node, choice in
            guard let self, let index = self.index(ofID: id) else { return }
            self.changeModel(of: node, to: choice, index: index)
        }
        shell.onModeChanged = { [weak self] mode in
            guard let self, let index = self.index(ofID: id) else { return }
            self.recordViewMode(mode, index: index)
            // Só a bancada na tela manda na barra: as outras trocam de modo pelo
            // socket sem estar visíveis.
            //
            // Ao lado em tudo que não é canvas: a barra flutua porque o grid corre
            // por baixo dela e é isso que a faz parecer suspensa. O mosaico tem
            // conteúdo opaco de largura cheia, e ali flutuar é cobrir conteúdo.
            if index == self.activeIndex { self.root.setMosaic(mode != .canvas) }
        }
        shell.onMosaicLayoutChanged = { [weak self] layout in
            guard let self, let index = self.index(ofID: id) else { return }
            self.recordMosaicLayout(layout, index: index)
        }
        shell.tabs.onPick = { [weak self] picked in
            guard let self, let index = self.index(ofID: picked) else { return }
            self.activate(index)
        }
        shell.tabs.onClose = { [weak self] in self?.closeTab($0) }
        shell.tabs.onReorder = { [weak self] order in self?.reorderTabs(order) }
        guard let index = index(ofID: id) else { return }
        shell.mosaicLayout = configs[index].mosaic
        shell.setWorkbench(name: configs[index].name, path: configs[index].path)

        wireChat(shell.chat, id: id)

        let canvas = shell.canvas
        // Lido na hora do enquadrar, não guardado: a barra lateral recolhe e abre.
        canvas.visibleInsets = { [weak self] in
            NSEdgeInsets(top: 0, left: self?.root.floatingSidebarInset ?? 0, bottom: 0, right: 0)
        }
        canvas.onPlace = { [weak self] tool, rect in
            guard let self, let index = self.index(ofID: id) else { return }
            self.place(tool, rect: rect, index: index)
        }
        canvas.onLayoutChanged = { [weak self] in
            guard let self, let index = self.index(ofID: id) else { return }
            self.syncFrames(index: index)
            self.schedulePersist()
        }
        canvas.onSaveTemplate = { [weak self] in self?.saveCurrentAsTemplate() }
        canvas.onUpdateTemplate = { [weak self] in
            guard let self, let index = self.index(ofID: id) else { return }
            self.updateOriginTemplate(index)
        }
        canvas.originTemplate = configs[index].template
        canvas.onNewWorktree = { [weak self] in
            guard let self, let index = self.index(ofID: id) else { return }
            self.duplicateWorkbenchAsWorktree(index)
        }
        canvas.nodeTemplateNames = { NodeTemplateStore.names }
        canvas.onConfigureTerminal = { [weak self] in
            guard let self, let index = self.index(ofID: id) else { return }
            self.configureNewTerminal(index: index)
        }
        edgeController(for: index)?.wire()
    }

    /// O controller de aresta da bancada. As closures resolvem pelo **id** na
    /// hora da chamada: assim ele continua correto depois de a bancada mudar de
    /// posição na barra, que era o que obrigava a religar tudo ao arrastar.
    private func edgeController(for index: Int) -> EdgeController? {
        guard let id = workbenchID(at: index) else { return nil }
        if let existing = edgeControllers[id] { return existing }
        let controller = EdgeController(
            canvas: { [weak self] in self?.shells[id]?.canvas },
            config: { [weak self] in
                guard let self, let i = WorkbenchLookup.index(ofID: id, in: self.configs)
                else { return nil }
                return self.configs[i]
            },
            change: { [weak self] mutate in
                guard let self, let i = WorkbenchLookup.index(ofID: id, in: self.configs) else { return }
                mutate(&self.configs[i])
            },
            persist: { [weak self] in self?.schedulePersist() }
        )
        edgeControllers[id] = controller
        return controller
    }

    // MARK: - Modo chat

    /// Fechaduras de leitura e envio; nenhuma referência a `NodeView` — em chat
    /// os cards estão cobertos, e o que a tela desenha é estado remontado a
    /// cada leitura.
    private func wireChat(_ chat: ChatContainer, id: String) {
        chat.participants = { [weak self] in
            guard let self, let config = self.config(ofID: id) else { return [] }
            return ChatParticipant.from(nodes: config.nodes, workbench: config.name) {
                Dispatcher.shared.target($0)?.activity
            }
        }
        chat.historyFile = { [weak self] in
            guard let self, self.config(ofID: id) != nil else { return nil }
            return ChatHistory.shared.current(forWorkbench: id)
        }
        chat.liveSource = { [weak self] participant in
            guard let self, let config = self.config(ofID: id),
                  let node = config.nodes.first(where: { $0.id == participant.id }),
                  let path = node.transcript else { return nil }
            return (URL(fileURLWithPath: path),
                    Dispatcher.shared.target(participant.address)?.turnStartedAt)
        }
        chat.send = { [weak self] text, participant in
            guard let self, self.config(ofID: id) != nil else {
                return "bancada sumiu"
            }
            var request = DispatchRequest(target: participant.address)
            request.text = text
            do {
                // `from: nil` de propósito: quem manda é VOCÊ, e as guardas de
                // cadeia só valem entre agentes.
                _ = try Dispatcher.shared.dispatch(request, from: nil)
                return nil
            } catch {
                return "\(error)"
            }
        }
    }

    // MARK: - Limpar a bancada

    /// Pergunta antes: o `/clear` zera o contexto de cada agente, e não tem
    /// volta pela TUI.
    private func confirmClearWorkbench(_ index: Int) {
        guard index >= 0, index < configs.count else { return }
        let config = configs[index]
        let agents = config.nodes.filter { $0.type == .agent }.count
        let alert = NSAlert()
        alert.messageText = "Limpar a bancada \"\(config.name)\"?"
        alert.informativeText = "Roda o comando de limpar em \(agents) agente\(agents == 1 ? "" : "s") "
            + "— eles esquecem a conversa atual — e arquiva o chat e a trilha da bancada em "
            + "chat-archive/ e trace-archive/. Nada é apagado do disco."
        alert.addButton(withTitle: "Limpar")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearWorkbench(index) { result in
            Log.write("bancada \"\(config.name)\" limpa pelo botão: \(result)")
        }
    }

    /// O `clear` do perfil vai pela fila do Dispatcher, como um prompt seu:
    /// terminal ocupado recebe quando ficar livre, e a TUI não descarta o
    /// texto no meio de um redraw. Agente cujo CLI não declara `clear` é
    /// pulado e listado — não morto.
    ///
    /// Tem duração, e por isso devolve pelo `completion`: arquivar o chat só
    /// depois de os agentes assentarem é o que impede o fim do turno velho de
    /// cair na conversa nova (ADR-059). Enquanto isso a bancada fica com a
    /// cortina de "um instante" — nada aceita clique.
    private func clearWorkbench(_ index: Int, completion: (([String: Any]) -> Void)? = nil) {
        guard index >= 0, index < configs.count else {
            completion?(["ok": false, "error": "bancada sumiu"]); return
        }
        let config = configs[index]
        guard cleaners[config.id] == nil else {
            completion?(["ok": false, "error": "limpeza já em curso nesta bancada"]); return
        }
        let profiles = agents
        let targets = config.nodes.filter { $0.type == .agent }.map { node in
            WorkbenchCleaner.Agent(id: node.id, address: config.address(of: node),
                                   command: node.agent.flatMap { profiles[$0]?.clear })
        }
        let cleaner = WorkbenchCleaner(
            agents: targets,
            dispatch: { agent in
                guard let command = agent.command,
                      Dispatcher.shared.target(agent.address) != nil else { return false }
                var request = DispatchRequest(target: agent.address)
                request.text = command
                do {
                    _ = try Dispatcher.shared.dispatch(request, from: nil)
                    return true
                } catch {
                    Log.write("limpar[\(agent.address)]: \(error)")
                    return false
                }
            },
            isBusy: { agent in
                guard let target = Dispatcher.shared.target(agent.address) else { return false }
                return WorkbenchCleaner.isBusy(activity: target.activity, pending: target.pending)
            },
            archive: { (ChatHistory.shared.archive(workbench: config.id),
                        TraceLog.shared.archive(workbench: config.id)) },
            onPhase: { [weak self] phase in
                self?.shell(at: index)?.showBusy(phase.label)
            },
            onFinish: { [weak self] result in
                guard let self else { return }
                self.cleaners[config.id] = nil
                // O arquivo saiu do disco; o eco local e o turno ao vivo ainda
                // estavam na memória do chat, e sem isto voltariam a desenhar
                // numa thread vazia.
                self.shell(at: index)?.chat.clearedHistory()
                Log.write("bancada \"\(config.name)\" limpa: clear em "
                          + "[\(result.cleared.joined(separator: ", "))]"
                          + (result.skipped.isEmpty ? "" : ", pulados [\(result.skipped.joined(separator: ", "))]")
                          + (result.chat.map { ", chat arquivado em \($0.lastPathComponent)" } ?? ", chat já vazio")
                          + (result.trace.map { ", trilha arquivada em \($0.lastPathComponent)" } ?? ", trilha vazia"))
                var payload = result.payload
                payload["workbench"] = config.name
                completion?(payload)
            })
        cleaners[config.id] = cleaner
        cleaner.run()
    }

    /// Limpezas em curso, por id de bancada — o timer do cleaner é dele, mas
    /// alguém precisa segurá-lo de pé até o fim.
    private var cleaners: [String: WorkbenchCleaner] = [:]

    // MARK: - Visualização

    private func recordViewMode(_ mode: ViewMode, index: Int) {
        guard index >= 0, index < configs.count else { return }
        configs[index].view = mode
        schedulePersist()
        Log.write("bancada \(configs[index].name): visualização \(mode.rawValue)")
    }

    private func recordMosaicLayout(_ layout: MosaicLayout, index: Int) {
        guard index >= 0, index < configs.count, configs[index].mosaic != layout else { return }
        configs[index].mosaic = layout
        // De volta para o shell também: ele repassa a proporção na hora de montar
        // o mosaico, e sem isto ida e volta ao canvas ressuscitaria a do arranque
        // — o arrasto só sobreviveria depois de fechar o app.
        shell(at: index)?.mosaicLayout = layout
        schedulePersist()
    }

    /// Recolher a barra de bancadas ao trilho, ou abrir de volta.
    @objc func toggleSidebarCollapsed() { root.toggleCollapsed() }

    @objc func showCanvasView() { shell(at: activeIndex)?.show(.canvas) }
    @objc func showMosaicView() { shell(at: activeIndex)?.show(.mosaic) }
    @objc func showChatView() { shell(at: activeIndex)?.show(.chat) }

    // MARK: - Ligações entre terminais

    /// Liga dois terminais. Nasce nos DOIS sentidos — o botão de direção na linha
    /// tira o que você não quiser.
    ///
    /// Bidirecional por padrão é escolha de fluxo, e ela amplia autorização: quem
    /// você acionou pode acionar de volta sem você desenhar nada. Fica assim porque
    /// a montagem que se usa é o par conversando, e desenhar a volta à mão toda vez
    /// era o passo que se esquecia — o limite continua sendo o `maxSends` da linha,
    /// que passa a contar ida e volta desde o começo. Ver ADR-028.
    /// Teto de revisitas da bancada — a rede, não o botão do dia a dia.
    private func editVisitLimit(_ index: Int) {
        guard index >= 0, index < configs.count else { return }

        let alert = NSAlert()
        alert.messageText = "Limite de conversa — \(configs[index].name)"
        alert.informativeText = "Quantas vezes um mesmo terminal pode entrar numa cadeia de "
            + "mensagens entre agentes antes de o Egeon Deck cortar.\n\n"
            + "Isto é a rede de segurança da bancada inteira: é o único limite que segura um "
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
        Log.write("bancada \(configs[index].name): teto de visitas = \(configs[index].visitLimit)")
    }

    /// As regras da bancada: valem para todo agente que abre aqui (ADR-056).
    ///
    /// Salvar reinicia os agentes da bancada — o system prompt só é lido no
    /// arranque, e regra que não sobe não é regra. A conversa fica: o id é
    /// nosso e o CLI a retoma, como na troca de modelo.
    private func editWorkbenchRules(_ index: Int) {
        guard index >= 0, index < configs.count else { return }

        let alert = NSAlert()
        alert.messageText = "Regras — \(configs[index].name)"
        alert.informativeText = "Como se trabalha nesta bancada. Vale para todo agente que "
            + "abre aqui, somado às regras de cada terminal, e entra no system prompt depois "
            + "do papel — quando um pedido conflita com uma regra, vale a regra.\n\n"
            + "Uma por linha, curtas, dizendo o que FAZER (\"peça antes de commitar\" adere "
            + "muito melhor que \"não commite\") e o porquê quando não for óbvio. Poucas: "
            + "regra demais dilui todas."
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextView()
        field.string = configs[index].rules ?? ""
        field.font = .systemFont(ofSize: 11)
        field.isRichText = false
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 150)
        field.autoresizingMask = [.width]
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = field
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let rules: String? = typed.isEmpty ? nil : typed
        guard rules != configs[index].rules else { return }

        configs[index].rules = rules
        schedulePersist()
        Log.write("bancada \(configs[index].name): regras "
                  + (rules == nil ? "removidas" : "atualizadas") + " — reiniciando os agentes")
        restartAgents(in: index)
    }

    /// Reergue os agentes de uma bancada no lugar em que estão, com o system
    /// prompt refeito. Só os agentes: shell, editor e navegador não leem regra.
    private func restartAgents(in index: Int) {
        guard index >= 0, index < configs.count, let shell = shell(at: index) else { return }
        for node in shell.nodes {
            guard let config = configs[index].nodes.first(where: { $0.id == node.nodeID }),
                  config.type == .agent else { continue }
            let frame = shell.canvasFrame(of: config.id) ?? node.frame
            shell.detach(node)
            shell.attach(makeNode(config, in: configs[index], frame: frame))
        }
    }

    /// Remover é irreversível dentro do app — o nó sai do canvas e do
    /// workbenches.json — então passa por confirmação, com o aviso que o próprio
    /// tipo de nó dá sobre o que se perde.
    private func confirmRemoval(of node: NodeView, index: Int) {
        guard index >= 0, index < configs.count, let shell = shell(at: index) else { return }

        let name = node.nodeID.isEmpty ? "este nó" : "\"\(node.nodeID)\""
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remover \(name) do bancada \(configs[index].name)?"
        alert.informativeText = node.removalWarning
        alert.addButton(withTitle: "Remover")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons.first?.hasDestructiveAction = true

        // Folha na janela em vez de modal solto: o canvas fica visível atrás, e
        // dá pra conferir qual nó está sendo apagado.
        guard let window else {
            if alert.runModal() == .alertFirstButtonReturn { remove(node, index: index, from: shell) }
            return
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.remove(node, index: index, from: shell)
        }
    }

    private func remove(_ node: NodeView, index: Int, from shell: WorkbenchShell) {
        let id = node.nodeID
        shell.detach(node)
        if !id.isEmpty {
            configs[index].nodes.removeAll { $0.id == id }
            // Aresta apontando para nó que não existe mais viraria alvo morto no
            // catálogo do agente: ele leria um endereço e o dispatch recusaria.
            let orphans = configs[index].edgeList.filter { $0.from == id || $0.to == id }
            if !orphans.isEmpty {
                configs[index].edges = configs[index].edgeList.filter {
                    $0.from != id && $0.to != id
                }
                shell.canvas.edges = configs[index].edgeList
                Log.write("bancada \(configs[index].name): \(orphans.count) ligação(ões) "
                          + "removida(s) junto com \"\(id)\"")
            }
            Log.write("bancada \(configs[index].name): nó \"\(id)\" removido")
        }
        schedulePersist()
    }

    /// Cria um nó onde a ferramenta foi solta e grava no workbenches.json.
    private func place(_ tool: CanvasTool, rect: NSRect, index: Int) {
        guard let kind = tool.nodeKind, index >= 0, index < configs.count,
              let shell = shell(at: index) else { return }

        if kind == .shell {
            // Componente escolhido no menu pula o formulário: ele já traz tipo,
            // agente, comando, pasta e papel — perguntar de novo seria repetir
            // uma decisão já tomada.
            if let name = shell.canvas.pendingComponent,
               let component = NodeTemplateStore.component(named: name) {
                place(component: component, rect: rect, index: index)
                return
            }

            // Sem componente, o terminal é configurado antes de existir. O
            // retângulo que você acabou de marcar é preservado, então o formulário
            // não custa a posição nem o tamanho.
            let dialog = NodeTemplateDialog(
                title: "Novo terminal",
                confirmLabel: "Criar",
                agents: agents,
                initial: NodeTemplate(name: "", kind: .agent, agent: "claude"),
                root: configs[index].url,
                folderSuggestions: folderSuggestions(for: index),
                suggestedConfigs: workspace(of: index)?.lastConfigs ?? [:])
            guard let result = dialog.run() else { return }
            rememberConfig(result.component, index: index)
            if result.saveAsNodeTemplate { NodeTemplateStore.put(result.component) }
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
        shell.attach(makeNode(node, in: configs[index], frame: rect))
        Log.write("bancada \(configs[index].name): nó \(kind.rawValue) \"\(node.id)\" criado")
        schedulePersist()
    }

    // MARK: - Componentes

    private func workspace(of index: Int) -> WorkspaceConfig? {
        guard let pid = configs[index].project else { return nil }
        return workspaces.first { $0.project(withID: pid) != nil }
    }

    /// A configuração escolhida no formulário vira a sugestão do workspace para
    /// aquele CLI — ao criar e ao editar, porque as duas são escolha sua.
    private func rememberConfig(_ component: NodeTemplate, index: Int) {
        guard component.kind == .agent, let agent = component.agent,
              let pid = configs[index].project,
              let w = workspaces.firstIndex(where: { $0.project(withID: pid) != nil }) else { return }
        let config = component.resolved(for: agent).config
        guard workspaces[w].lastConfigs?[agent] != config else { return }
        workspaces[w].remember(config: config, for: agent)
        WorkspaceStore.save(workspaces)
    }

    private func folderSuggestions(for index: Int) -> [String] {
        FolderSuggestions.list(repoChildren: FolderSuggestions.repoChildren(of: configs[index].url))
    }

    /// Abre o formulário e cria o terminal no primeiro lugar livre do canvas.
    private func configureNewTerminal(index: Int) {
        guard index >= 0, index < configs.count, let canvas = shell(at: index)?.canvas else { return }

        let dialog = NodeTemplateDialog(
            title: "Novo terminal",
            confirmLabel: "Criar",
            agents: agents,
            initial: NodeTemplate(name: "", kind: .agent, agent: "claude"),
            root: configs[index].url,
            folderSuggestions: folderSuggestions(for: index),
            suggestedConfigs: workspace(of: index)?.lastConfigs ?? [:])
        guard let result = dialog.run() else { return }
        rememberConfig(result.component, index: index)

        if result.saveAsNodeTemplate { NodeTemplateStore.put(result.component) }

        let rect = canvas.spawnRect(size: CanvasTool.terminal.defaultNodeSize)
        place(component: result.component, rect: rect, index: index)
    }

    /// Materializa um componente como nó. O id vem do nome, então o endereço de
    /// dispatch fica legível: `deck/revisor`.
    private func place(component: NodeTemplate, rect: NSRect, index: Int) {
        guard index >= 0, index < configs.count, let shell = shell(at: index) else { return }

        let id = nextID(prefix: NodeTemplateStore.identifier(from: component.name),
                        in: configs[index])
        var node = NodeTemplateStore.instantiate(component, id: id)
        node.setFrame(rect)

        configs[index].nodes.append(node)
        shell.attach(makeNode(node, in: configs[index], frame: rect))
        Log.write("bancada \(configs[index].name): \(node.type.rawValue) \"\(id)\" criado"
                  + (component.prompt == nil ? "" : " com papel"))
        schedulePersist()
    }

    /// Configura um nó já na tela.
    ///
    /// Nome, comando, agente e pasta definem como o processo foi lançado, então
    /// mudá-los exige um processo novo — não há como reconfigurar um pty em
    /// andamento. O diálogo avisa antes.
    private func editNode(_ node: NodeView, index: Int) {
        guard index >= 0, index < configs.count, let shell = shell(at: index),
              let position = configs[index].nodes.firstIndex(where: { $0.id == node.nodeID })
        else { return }

        let current = configs[index].nodes[position]
        let dialog = NodeTemplateDialog(
            title: "Configurar \(current.id)",
            confirmLabel: "Aplicar",
            agents: agents,
            initial: NodeTemplateStore.capture(from: current, name: current.component ?? current.id),
            root: configs[index].url,
            folderSuggestions: folderSuggestions(for: index))
        guard let result = dialog.run() else { return }
        // Só se mudou: mexer no nome de um terminal no padrão não é escolher o
        // padrão para o workspace.
        if result.component.resolved(for: result.component.agent).config != current.config
            || result.component.agent != current.agent {
            rememberConfig(result.component, index: index)
        }

        if result.saveAsNodeTemplate { NodeTemplateStore.put(result.component) }

        let component = result.component
        let renamed = NodeTemplateStore.identifier(from: component.name)
        let newID = renamed == current.id
            ? current.id
            : nextID(prefix: renamed, in: configs[index])

        // Em modo mosaico o frame da view é o do painel, e gravá-lo destruiria a
        // posição que o nó tem no canvas. Quem sabe qual é ela é o shell.
        let canvasFrame = shell.canvasFrame(of: current.id) ?? node.frame
        var updated = NodeTemplateStore.instantiate(component, id: newID)
        updated.setFrame(canvasFrame)

        let sameProcess = updated.type == current.type
            && updated.agent == current.agent
            && updated.model == current.model
            && updated.effort == current.effort
            && updated.cmd == current.cmd
            && updated.config == current.config
            && updated.cwd == current.cwd
            // O EFETIVO, não o geral: mudar só a exceção do CLI em uso muda o
            // system prompt, e ele só é lido no arranque.
            && updated.effectivePrompt == current.effectivePrompt
            && updated.effectiveRules == current.effectiveRules

        configs[index].nodes[position] = updated

        if sameProcess && newID == current.id {
            schedulePersist()
            return
        }

        // Troca o nó por um novo: o antigo é encerrado explicitamente para o pty
        // não ficar órfão.
        shell.detach(node)
        shell.attach(makeNode(updated, in: configs[index], frame: canvasFrame))
        Log.write("bancada \(configs[index].name): nó \"\(current.id)\" reconfigurado"
                  + (newID == current.id ? "" : " e renomeado para \"\(newID)\""))
        schedulePersist()
    }

    /// Cache do modelo literal por transcript: (mtime, modelo). O arquivo só é
    /// relido quando muda.
    private var literalModelCache: [String: (mtime: Date, since: Date?, model: String?)] = [:]

    /// O modelo que está de fato respondendo neste nó: última linha de assistant
    /// do transcript; antes do primeiro turno, o `model` do settings.json da
    /// configuração em uso. Nil quando nenhum dos dois sabe.
    ///
    /// `since` é o arranque deste processo: resposta de antes dele foi de outro
    /// modelo, se você trocou. E o settings.json só responde quando o nó está no
    /// padrão — com modelo escolhido, ele diz o que o CLI usaria sem a flag.
    private func literalModel(workbench: String, nodeID: String, since: Date? = nil) -> String? {
        guard let config = configs.first(where: { $0.name == workbench }),
              let node = config.nodes.first(where: { $0.id == nodeID }) else { return nil }
        if let path = node.transcript, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]
                         as? Date) ?? .distantPast
            if let cached = literalModelCache[path], cached.mtime == mtime, cached.since == since,
               let model = cached.model {
                return model
            }
            let model = ClaudeTranscript.lastModel(at: url, since: since)
            literalModelCache[path] = (mtime, since, model)
            if let model { return model }
        }
        guard node.model == nil else { return nil }
        return node.agent.flatMap { agents[$0] }?.defaultModelName(config: node.config)
    }

    /// Troca o modelo ou o esforço de um terminal com IA, pelo seletor do
    /// cabeçalho.
    ///
    /// O processo reinicia — não há como trocar o modelo de um pty em curso — mas
    /// a conversa FICA: o id é nosso, e o CLI a retoma com o modelo novo. É o
    /// contrário da worktree, onde a conversa é da pasta antiga e vai embora.
    private func changeModel(of node: NodeView, to choice: ModelChoice, index: Int) {
        guard index >= 0, index < configs.count, let shell = shell(at: index),
              let position = configs[index].nodes.firstIndex(where: { $0.id == node.nodeID })
        else { return }
        let current = configs[index].nodes[position]
        var updated = choice.applied(to: current)
        // Modelo novo que não tem o nível em vigor: o CLI rebaixaria calado, e o
        // slider mostraria um nível que não existe. Volta ao auto, e diz.
        if case .model = choice, let effort = updated.effort,
           let profile = updated.agent.flatMap({ agents[$0] }),
           let model = ClaudeModelCatalog.current(for: profile)?.model(for: updated.model),
           !model.efforts.contains(effort) {
            updated.effort = nil
            Log.write("bancada \(configs[index].name): \(model.label) não tem esforço \(effort) — "
                      + "nó \"\(current.id)\" volta ao auto")
        }
        guard updated.model != current.model || updated.effort != current.effort
                || updated.ultracode != current.ultracode else { return }

        configs[index].nodes[position] = updated

        let frame = shell.canvasFrame(of: current.id) ?? node.frame
        shell.detach(node)
        shell.attach(makeNode(updated, in: configs[index], frame: frame))
        let what: String
        switch choice {
        case .model(let model):
            what = "modelo \(model ?? "padrão") (antes \(current.model ?? "padrão"))"
        case .effort(let effort):
            what = "esforço \(effort ?? "padrão") (antes \(current.effort ?? "padrão"))"
        case .ultracode(let on):
            what = "ultracode \(on ? "ligado" : "desligado")"
        }
        Log.write("bancada \(configs[index].name): nó \"\(current.id)\" reiniciado com \(what)")
        schedulePersist()
    }

    /// Leva UM terminal para uma worktree nova do repositório em que ele abre.
    ///
    /// Existe porque uma frente de trabalho raramente é um repositório só: com o
    /// frontend na bancada e o backend num repo vizinho, a branch nova precisa dos
    /// dois — e duplicar a bancada inteira para levar um card é caro demais.
    ///
    /// O card é reapontado, não clonado: id, papel, arestas e posição continuam os
    /// mesmos. O processo reinicia porque não há como trocar o diretório de um pty
    /// em curso, e a conversa é zerada porque ela é da pasta antiga.
    private func nodeWorktree(_ node: NodeView, index: Int) {
        guard index >= 0, index < configs.count,
              let position = configs[index].nodes.firstIndex(where: { $0.id == node.nodeID })
        else { return }

        let config = configs[index]
        let current = config.directory(for: config.nodes[position])

        let status: Worktree.Status
        // Do checkout principal: partir de uma worktree ligada aninharia worktree
        // dentro de worktree.
        guard let repoRoot = Worktree.mainRepo(of: current),
              let read = try? Worktree.status(of: repoRoot) else {
            presentError("\"\(node.nodeID)\" não abre num repositório git",
                         Worktree.Failure.notARepo(current))
            return
        }
        status = read

        let suggested = Worktree.availableBranch(basedOn: status.branch, in: repoRoot)
        guard let form = NodeWorktreePlanner.ask(nodeID: node.nodeID,
                                                 repoRoot: repoRoot,
                                                 currentPath: current,
                                                 status: status,
                                                 suggestedBranch: suggested) else { return }

        if case .failure(let error) = repoint(
            nodeID: node.nodeID, index: index, repoRoot: repoRoot, branch: form.branch,
            destination: Worktree.suggestedPath(repoRoot: repoRoot, branch: form.branch)) {
            presentError("Não consegui abrir a worktree", error)
        }
    }

    /// Abre a worktree e reaponta o nó, sem diálogo. Ver `duplicate` — mesmo
    /// motivo de existir.
    ///
    /// Devolve o que aconteceu, e não só se deu certo: com branch que já existe o
    /// nó pode ter ido para uma worktree que o app não escolheu, e quem chamou
    /// pelo socket precisa poder verificar onde o terminal foi parar.
    @discardableResult
    private func repoint(nodeID: String, index: Int, repoRoot: String,
                         branch: String,
                         destination: String) -> Result<Worktree.Created, Error> {
        guard index >= 0, index < configs.count, let shell = shell(at: index),
              let position = configs[index].nodes.firstIndex(where: { $0.id == nodeID }),
              let node = shell.nodes.first(where: { $0.nodeID == nodeID })
        else { return .failure(Worktree.Failure.notARepo(nodeID)) }

        let created: Worktree.Created
        do {
            created = try Worktree.create(from: repoRoot, branch: branch,
                                          destination: destination, carryDirty: true)
        } catch {
            return .failure(error)
        }

        // Sem a conversa: ela é da pasta antiga, e retomá-la aqui traria o agente
        // no meio de um assunto que era de outro checkout.
        var updated = configs[index].nodes[position].withoutConversation
        updated.cwd = NodeWorktreePlanner.short(created.path)
        configs[index].nodes[position] = updated

        let frame = shell.canvasFrame(of: nodeID) ?? node.frame
        shell.detach(node)
        shell.attach(makeNode(updated, in: configs[index], frame: frame))
        schedulePersist()

        Log.write("worktree por terminal: \"\(nodeID)\" de \(configs[index].name) "
                  + "passou a abrir em \(created.path) (branch \(created.branch))"
                  + (created.reused ? " — worktree que já existia" : ""))

        copyUnversioned(created.reused ? [] : [(repoRoot, created.path)], into: index)
        return .success(created)
    }

    /// Worktree pelo socket, sem diálogo. `ws` duplica a bancada levando os
    /// terminais de repo vizinho junto; `ws/id` leva só aquele terminal.
    ///
    /// Existe para o fluxo poder ser verificado de fora: ele cria worktree em
    /// repositório de verdade e reaponta o `cwd` de cada nó, e "compilou" não diz
    /// nada sobre um terminal ter aberto na pasta certa.
    ///
    /// `nodes` customiza a branch por terminal — `back:fix/api,sub:spike` —, que é
    /// a mesma coisa que se digita nas linhas do formulário. Sem ela, todos herdam a
    /// branch da bancada, que é o padrão do formulário. Branch vazia (`back:`) é o
    /// "não me leve": o terminal fica no repositório original.
    private func makeWorktree(target: String, branch: String,
                              nodeBranches: [String: String] = [:]) -> [String: Any] {
        let parts = target.split(separator: "/", maxSplits: 1).map(String.init)
        guard let workbenchName = parts.first,
              let index = configs.firstIndex(where: { $0.name == workbenchName })
        else { return ["ok": false, "error": "bancada desconhecida '\(target)'"] }

        let nodeID = parts.count == 2 ? parts[1] : nil
        let origin = configs[index]

        // Nó: o repositório é o da pasta em que ele abre, que pode ser vizinho.
        // Sempre pelo checkout principal — partir de uma worktree ligada aninharia
        // worktree dentro de worktree.
        if let nodeID {
            guard let node = origin.nodes.first(where: { $0.id == nodeID })
            else { return ["ok": false, "error": "nó desconhecido '\(nodeID)'"] }
            let current = origin.directory(for: node)
            guard let repoRoot = Worktree.mainRepo(of: current),
                  let status = try? Worktree.status(of: repoRoot)
            else { return ["ok": false, "error": "\(current) não é repositório git"] }

            // O nome pedido vai como veio: se a branch já existe, é nela que o
            // terminal abre. Só o nome vazio é sugerido pelo app. Ver ADR-018.
            let name = branch.isEmpty
                ? Worktree.availableBranch(basedOn: status.branch, in: repoRoot)
                : branch
            let destination = Worktree.suggestedPath(repoRoot: repoRoot, branch: name)
            switch repoint(nodeID: nodeID, index: index, repoRoot: repoRoot,
                           branch: name, destination: destination) {
            case .failure(let error):
                return ["ok": false, "error": "\(error)"]
            case .success(let created):
                return ["ok": true, "node": nodeID, "repo": repoRoot,
                        "branch": name, "path": created.path,
                        "reused": created.reused]
            }
        }

        if let project = origin.project.flatMap({ project(withID: $0) }), project.isMulti {
            guard !branch.isEmpty else { return ["ok": false, "error": "multi-projeto pede branch"] }
            // Em multi-projeto o `&nodes=` fala de repositório: `nexus-backend:fix/api`
            // é a linha daquele repo no formulário.
            let repoBranches = nodeBranches
            let members = workspaces.first { $0.project(withID: project.id) != nil }?
                .members(of: project) ?? []
            let opened = openMultiWorktree(project, members: members, branch: branch,
                                           overrides: repoBranches, template: nil,
                                           inheriting: origin)
            return ["ok": opened.index != nil, "path": opened.root, "failed": opened.failures,
                    "workbench": opened.index.map { configs[$0].name } ?? ""]
        }

        guard let repoRoot = Worktree.mainRepo(of: origin.url.path),
              let status = try? Worktree.status(of: origin.url.path)
        else { return ["ok": false, "error": "\(origin.path) não é repositório git"] }

        let name = branch.isEmpty
            ? Worktree.availableBranch(basedOn: status.branch, in: repoRoot)
            : branch
        // Cada terminal herda a branch da bancada, e `nodes` sobrescreve quem foi
        // pedido — é o mesmo que digitar na linha dele. A decisão de quem ganha
        // worktree própria sai daí, e não de uma marcação separada.
        let plans = NodeWorktreePlanner.inspect(origin, workbenchRoot: origin.url.path,
                                                branch: name)
            .map { plan -> NodeWorktree in
                var copy = plan
                if let custom = nodeBranches[plan.nodeID] {
                    copy.branch = custom
                    copy.touched = true
                }
                return copy.decided(workbenchBranch: name)
            }
        let form = WorktreeForm(branch: name, template: nil,
                                target: .newWorkbench, nodes: plans)
        if let error = duplicate(index, repoRoot: repoRoot, status: status, form: form) {
            return ["ok": false, "error": "\(error)"]
        }
        // A pasta vem da bancada que acabou de nascer, e não do caminho sugerido:
        // com branch que já existe a worktree pode ser outra, e é justamente isso
        // que quem chamou precisa poder conferir.
        return ["ok": true, "workbench": workbenchName, "branch": name,
                "workbench": configs.last?.name ?? "",
                "path": configs.last?.url.path
                    ?? Worktree.suggestedPath(repoRoot: repoRoot, branch: name),
                "nodes": plans.filter(\.enabled).map { ["id": $0.nodeID,
                                                        "repo": $0.repoName] }]
    }

    /// `sh`, `sh-2`, `sh-3`… O id entra no endereço de dispatch, então precisa
    /// ser único dentro da bancada.
    private func nextID(prefix: String, in config: WorkbenchConfig) -> String {
        let taken = Set(config.nodes.map(\.id))
        if !taken.contains(prefix) { return prefix }
        var n = 2
        while taken.contains("\(prefix)-\(n)") { n += 1 }
        return "\(prefix)-\(n)"
    }

    // MARK: - Persistência

    /// Lê de volta o que está na tela. A view é a verdade sobre posição: o
    /// usuário acabou de arrastar.
    ///
    /// Só em modo canvas. No mosaico o frame do card é o do painel do split view,
    /// e gravá-lo aqui achataria a montagem do canvas inteira — na volta, todo nó
    /// nasceria do tamanho da coluna em que estava.
    private func syncFrames(index: Int) {
        guard index >= 0, index < configs.count, let shell = shell(at: index),
              shell.mode == .canvas else { return }
        var byID: [String: NSRect] = [:]
        for node in shell.nodes where !node.nodeID.isEmpty { byID[node.nodeID] = node.frame }
        for i in configs[index].nodes.indices {
            if let rect = byID[configs[index].nodes[i].id] {
                configs[index].nodes[i].setFrame(rect)
            }
        }
    }

    private func updateWebNode(workbench: String, id: String, url: String, profile: String) {
        guard let index = configs.firstIndex(where: { $0.name == workbench }),
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
            self.recordTabOrder()
            WorkbenchStore.save(self.configs)
        }
    }

    // MARK: - Geometria (para dirigir e verificar gestos de fora)

    /// Onde cada nó está na tela, em coordenadas com origem no topo — as do
    /// CGEvent. Estimar isso a partir de uma captura de tela erra, sobretudo com
    /// zoom aplicado: 26pt de cabeçalho viram 11pt a 43%.
    private func canvasGeometry() -> [String: Any] {
        guard let shell = shell(at: activeIndex), let window else { return [:] }
        let canvas = shell.canvas
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
        for node in shell.nodes {
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

        // `mode` na frente porque muda o sentido do resto: em mosaico o `docFrame`
        // é o do painel, `grabPoint` não arrasta nada e não há zoom.
        return [
            "workbench": activeIndex < configs.count ? configs[activeIndex].name : "?",
            "mode": shell.mode.rawValue,
            "magnification": shell.mode == .canvas
                ? Double((canvas.scroll.magnification * 1000).rounded()) / 1000 : 1,
            "docSize": ["w": Int(canvas.doc.frame.width), "h": Int(canvas.doc.frame.height)],
            "scrollOrigin": ["x": Int(canvas.scroll.contentView.bounds.origin.x),
                             "y": Int(canvas.scroll.contentView.bounds.origin.y)],
            "canvasOnScreen": toTopLeft(onScreen(shell.visibleContent,
                                                 shell.visibleContent.bounds)),
            "nodes": nodes
        ]
    }

    // MARK: - Menu

    /// ⌘] e ⌘[ percorrem a FAIXA, não a lista inteira: com dezenas de bancadas
    /// no catálogo, "próxima" só é útil entre as que você abriu.
    @objc func nextWorkbench() { stepTab(1) }
    @objc func previousWorkbench() { stepTab(-1) }

    private func stepTab(_ delta: Int) {
        let list = openTabs.isEmpty ? configs.map(\.id) : openTabs
        guard !list.isEmpty else { return }
        let current = activeID.flatMap { list.firstIndex(of: $0) } ?? 0
        let next = list[((current + delta) % list.count + list.count) % list.count]
        if let index = index(ofID: next) { activate(index) }
    }

    /// ⌘1…⌘9 vão direto à aba daquela posição, como em qualquer editor.
    @objc func pickTabByNumber(_ sender: NSMenuItem) {
        let n = sender.tag - 1
        guard n >= 0, n < openTabs.count, let index = index(ofID: openTabs[n]) else { return }
        activate(index)
    }

    /// ⌘W fecha a aba da frente. Fechar não encerra: os terminais continuam.
    @objc func closeActiveTab() {
        guard let id = activeID else { return }
        closeTab(id)
    }

    private var activeCanvas: CanvasContainer? { shell(at: activeIndex)?.canvas }

    @objc func zoomIn() { activeCanvas?.stepZoom(1) }
    @objc func zoomOut() { activeCanvas?.stepZoom(-1) }
    @objc func zoomReset() { activeCanvas?.zoom(to: 1) }

    /// Um key equivalent de menu é consultado antes do responder chain, então um
    /// item habilitado engole a tecla mesmo com o cursor dentro do editor.
    /// Desabilitar devolve a tecla a quem tem o foco — ⌘1…⌘4 focam grupos de
    /// editor no workbench, e ⌘=/⌘− dão zoom no código.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Os itens de visualização carregam o estado: a marca diz em que modo a
        // bancada ativa está, sem precisar olhar a barra.
        if menuItem.action == #selector(toggleSidebarCollapsed) {
            menuItem.state = root.isCollapsed ? .on : .off
            // ⌘/ é "comentar linha" no workbench, e key equivalent de menu é
            // consultado ANTES do responder chain: habilitado com o cursor dentro
            // do editor, a tecla deixaria de comentar. No terminal ela não tem
            // dono, e ali a barra continua respondendo.
            return !(shell(at: activeIndex)?.focusIsInsideEditor ?? false)
        }

        // ⌘1…⌘9: a aba tem de existir, senão a tecla vira um beep.
        if menuItem.action == #selector(pickTabByNumber(_:)) {
            let n = menuItem.tag - 1
            guard n >= 0, n < openTabs.count else { return false }
            menuItem.title = config(ofID: openTabs[n])?.name ?? "Aba \(menuItem.tag)"
            menuItem.isHidden = false
            return true
        }
        if menuItem.action == #selector(closeActiveTab) { return activeID != nil }
        if menuItem.action == #selector(nextWorkbench)
            || menuItem.action == #selector(previousWorkbench) {
            guard openTabs.count > 1 || configs.count > 1 else { return false }
            // Com o cursor dentro de uma caixa de texto, ⌘← e ⌘→ são dela: no
            // composer do chat elas levam ao início e ao fim da linha, e o menu
            // é consultado antes do responder chain.
            let seta = menuItem.keyEquivalent == "\u{2190}" || menuItem.keyEquivalent == "\u{2192}"
            guard seta else { return true }
            return !(shell(at: activeIndex)?.focusIsInTextInput ?? false)
        }

        let modeItems: [Selector: ViewMode] = [
            #selector(showCanvasView): .canvas,
            #selector(showMosaicView): .mosaic,
            #selector(showChatView): .chat
        ]
        if let action = menuItem.action, let wants = modeItems[action] {
            guard let mode = shell(at: activeIndex)?.mode else { return false }
            menuItem.state = mode == wants ? .on : .off
            return true
        }

        let canvasOnly: Set<Selector> = [
            #selector(pickCursorTool), #selector(pickTerminalTool),
            #selector(pickEditorTool), #selector(pickWebTool),
            #selector(zoomIn), #selector(zoomOut), #selector(zoomReset)
        ]
        guard let action = menuItem.action, canvasOnly.contains(action) else { return true }
        guard let shell = shell(at: activeIndex) else { return false }
        // Ferramenta e zoom só existem no canvas; fora dele o item some do caminho e
        // a tecla volta para quem tem o foco.
        return shell.mode == .canvas && !shell.canvas.focusIsInsideNode
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
        // ⌘→ / ⌘← são o atalho natural para "a aba do lado", e ⌘] / ⌘[ ficam como
        // segunda via: nas setas o AppKit consulta o menu antes do responder
        // chain, e dentro de uma caixa de texto elas são início e fim da linha —
        // `validateMenuItem` devolve a tecla nesse caso.
        appMenu.addItem(withTitle: "Aba à direita", action: #selector(nextWorkbench),
                        keyEquivalent: "\u{2192}")
        appMenu.addItem(withTitle: "Aba à esquerda", action: #selector(previousWorkbench),
                        keyEquivalent: "\u{2190}")
        appMenu.addItem(withTitle: "Próxima bancada", action: #selector(nextWorkbench),
                        keyEquivalent: "]").isHidden = true
        appMenu.addItem(withTitle: "Bancada anterior", action: #selector(previousWorkbench),
                        keyEquivalent: "[").isHidden = true
        // Fechar a aba, e não a janela: a bancada continua rodando e volta pela
        // barra lateral. É por isso que ⌘W não pode ser o do sistema aqui.
        appMenu.addItem(withTitle: "Fechar a aba", action: #selector(closeActiveTab),
                        keyEquivalent: "w")
        for n in 1...9 {
            let item = appMenu.addItem(withTitle: "Aba \(n)", action: #selector(pickTabByNumber(_:)),
                                       keyEquivalent: "\(n)")
            item.tag = n
            item.isHidden = true
            item.isAlternate = false
        }
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
        // ⌥⌘1/⌥⌘2 e não ⌘1/⌘2: estes últimos já são as ferramentas, e o workbench
        // do code-server usa ⌘1…⌘4 para focar grupos de editor.
        canvasMenu.addItem(withTitle: "Ver no canvas", action: #selector(showCanvasView),
                           keyEquivalent: "1").keyEquivalentModifierMask = [.command, .option]
        canvasMenu.addItem(withTitle: "Ver em mosaico", action: #selector(showMosaicView),
                           keyEquivalent: "2").keyEquivalentModifierMask = [.command, .option]
        canvasMenu.addItem(withTitle: "Ver como chat", action: #selector(showChatView),
                           keyEquivalent: "3").keyEquivalentModifierMask = [.command, .option]
        canvasMenu.addItem(withTitle: "Recolher a barra de bancadas",
                           action: #selector(toggleSidebarCollapsed), keyEquivalent: "/")
        canvasMenu.addItem(.separator())
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

/// Container de formulário que cresce de cima para baixo.
///
/// A lista de terminais do formulário de worktree tem tamanho variável, e contar
/// y a partir do rodapé em cada linha é como se erra por um pixel a cada mudança
/// de layout — foi assim que o segundo radio já caiu em cima do rótulo abaixo.
final class FormView: NSView {
    override var isFlipped: Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

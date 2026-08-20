import AppKit

/// Diálogo de configuração de um terminal — o mesmo para criar e para editar.
///
/// Um formulário só, e não dois parecidos, porque as perguntas são idênticas:
/// que papel é este, o que roda, em que pasta, com qual instrução.
final class ComponentDialog {

    struct Result {
        let component: Component
        /// Marcado "salvar como componente": o preset vai para components.json.
        let saveAsComponent: Bool
    }

    private let agents: [String: AgentProfile]
    private let title: String
    private let confirmLabel: String
    private let initial: Component

    /// Raiz da bancada, quando o formulário é de um nó dela.
    ///
    /// Serve ao botão de escolher pasta: é o que permite gravar RELATIVO quando a
    /// escolha está dentro da bancada. Sem raiz — formulário de componente solto —
    /// só existe caminho absoluto a gravar.
    private let root: URL?

    /// Ordem estável para o popup de CLI.
    private var agentKeys: [String] { agents.keys.sorted() }

    /// Valor de configuração de cada item do popup, na mesma ordem. `nil` é o
    /// padrão da CLI — não escrever nada no ambiente.
    private var configValues: [String?] = []

    /// Escolha vigente, para restaurá-la quando você abre o seletor de pasta e
    /// desiste — nesse instante o item selecionado é o "Escolher pasta…".
    private var lastConfig: String?

    init(title: String, confirmLabel: String,
         agents: [String: AgentProfile], initial: Component, root: URL? = nil) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.agents = agents
        self.initial = initial
        self.root = root
    }

    // MARK: - Campos

    private let nameField = NSTextField()
    private let kindPicker = NSPopUpButton()
    private let agentPicker = NSPopUpButton()
    private let cmdField = NSTextField()
    private let cwdField = NSTextField()
    private let cwdBrowse = NSButton(title: "Escolher…", target: nil, action: nil)
    private let promptField = NSTextView()
    private let saveBox = NSButton(checkboxWithTitle: "Salvar como componente reutilizável",
                                   target: nil, action: nil)
    private let promptLabel = NSTextField(labelWithString: "PAPEL (mensagem enviada ao subir)")
    private let agentLabel = NSTextField(labelWithString: "CLI")
    private let configPicker = NSPopUpButton()
    private let configLabel = NSTextField(labelWithString: "CONFIGURAÇÃO")
    private var promptScroll: NSScrollView?

    private let tabs = NSTabView()

    private static let shellOption = "Shell"
    private static let agentOption = "Agente (IA)"
    private static let browseConfigOption = "Escolher pasta…"
    /// Altura do formulário. Numa view não-flipped o y cresce para cima, então
    /// os campos do topo são posicionados a partir daqui.
    private static let formHeight: CGFloat = 382

    /// Preenche o formulário a partir de um componente salvo e leva para a aba de
    /// detalhes. Os campos seguem editáveis: o preset é ponto de partida, não
    /// camisa de força.
    private func apply(_ component: Component) {
        nameField.stringValue = component.name
        kindPicker.selectItem(withTitle: component.kind == .agent ? Self.agentOption
                                                                  : Self.shellOption)
        if let agent = component.agent, let index = agentKeys.firstIndex(of: agent) {
            agentPicker.selectItem(at: index)
        }
        reloadConfigPicker(select: component.config)
        cmdField.stringValue = component.cmd ?? ""
        cwdField.stringValue = component.cwd ?? ""
        promptField.string = component.prompt ?? ""
        updateAgentFields()

        // Escolher um preset não é o fim da tarefa: quase sempre você quer
        // ajustar o nome ou a pasta antes de criar.
        tabs.selectTabViewItem(at: 0)
    }

    func run() -> Result? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "O nome vira o id do nó e aparece no endereço de dispatch."
        alert.addButton(withTitle: confirmLabel)
        alert.addButton(withTitle: "Cancelar")

        alert.accessoryView = buildForm()
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let isAgent = kindPicker.titleOfSelectedItem == Self.agentOption

        // Nome em branco vira um padrão em vez de cancelar: confirmar e não ver
        // nada acontecer é o pior desfecho possível para um formulário.
        var name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = isAgent ? (selectedAgentKey ?? "agente") : "sh"
        }
        let cmd = cmdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwd = cwdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = promptField.string.trimmingCharacters(in: .whitespacesAndNewlines)

        let component = Component(
            name: name,
            kind: isAgent ? .agent : .shell,
            agent: isAgent ? selectedAgentKey : nil,
            cmd: cmd.isEmpty ? nil : cmd,
            config: isAgent ? selectedConfig : nil,
            cwd: cwd.isEmpty ? nil : Self.normalizedFolder(cwd),
            prompt: (isAgent && !prompt.isEmpty) ? prompt : nil)

        return Result(component: component, saveAsComponent: saveBox.state == .on)
    }

    /// Duas abas: montar do zero, ou partir de um componente salvo.
    ///
    /// Os presets ficam numa aba própria, com cards, e não num menu — antes eles
    /// viviam atrás de uma pressão longa no botão da barra, o que fazia salvar
    /// funcionar e ninguém achar o resultado.
    private func buildForm() -> NSView {
        let size = NSSize(width: 452, height: Self.formHeight + 66)
        tabs.frame = NSRect(origin: .zero, size: size)

        let details = NSTabViewItem(identifier: "detalhes")
        details.label = "Criar do zero"
        details.view = buildDetailsTab()
        tabs.addTabViewItem(details)

        let presets = NSTabViewItem(identifier: "presets")
        presets.label = "Começar de outro"
        presets.view = buildPresetsTab()
        tabs.addTabViewItem(presets)

        return tabs
    }

    private func buildDetailsTab() -> NSView {
        let width: CGFloat = 420
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: Self.formHeight))

        func caption(_ text: String, y: CGFloat) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 10, weight: .semibold)
            field.textColor = .secondaryLabelColor
            field.frame = NSRect(x: 0, y: y, width: width, height: 13)
            return field
        }

        container.addSubview(caption("NOME", y: 366))
        nameField.frame = NSRect(x: 0, y: 340, width: width, height: 22)
        nameField.stringValue = initial.name
        nameField.placeholderString = "revisor, front end, build…"
        container.addSubview(nameField)

        container.addSubview(caption("TIPO", y: 320))
        kindPicker.frame = NSRect(x: 0, y: 294, width: 180, height: 22)
        kindPicker.addItems(withTitles: [Self.shellOption, Self.agentOption])
        kindPicker.selectItem(withTitle: initial.kind == .agent ? Self.agentOption : Self.shellOption)
        kindPicker.target = self
        kindPicker.action = #selector(kindChanged)
        container.addSubview(kindPicker)

        agentLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        agentLabel.textColor = .secondaryLabelColor
        agentLabel.frame = NSRect(x: 200, y: 320, width: 220, height: 13)
        container.addSubview(agentLabel)

        agentPicker.frame = NSRect(x: 200, y: 294, width: 220, height: 22)
        agentPicker.addItems(withTitles: agentKeys.map { agents[$0]?.displayName ?? $0 })
        if let agent = initial.agent, let index = agentKeys.firstIndex(of: agent) {
            agentPicker.selectItem(at: index)
        }
        agentPicker.target = self
        agentPicker.action = #selector(agentChanged)
        container.addSubview(agentPicker)

        configLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        configLabel.textColor = .secondaryLabelColor
        configLabel.frame = NSRect(x: 0, y: 274, width: width, height: 13)
        container.addSubview(configLabel)

        configPicker.frame = NSRect(x: 0, y: 248, width: width, height: 22)
        configPicker.target = self
        configPicker.action = #selector(configChanged)
        container.addSubview(configPicker)
        reloadConfigPicker(select: initial.config)

        container.addSubview(caption("COMANDO — vazio usa o padrão do CLI", y: 228))
        cmdField.frame = NSRect(x: 0, y: 202, width: width, height: 22)
        cmdField.stringValue = initial.cmd ?? ""
        cmdField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        // Duas instalações do mesmo CLI se distinguem aqui.
        cmdField.placeholderString = "ex: claude --model opus"
        container.addSubview(cmdField)

        container.addSubview(caption("PASTA — relativa à raiz da bancada", y: 182))
        cwdField.frame = NSRect(x: 0, y: 156, width: width - 96, height: 22)
        cwdField.stringValue = initial.cwd ?? ""
        cwdField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cwdField.placeholderString = "ex: deck-backend — vazio usa a raiz"
        container.addSubview(cwdField)

        // O campo continua editável ao lado do botão: digitar é o jeito de escrever
        // um caminho que ainda não existe em disco, e o painel não escolhe pasta
        // inexistente.
        cwdBrowse.frame = NSRect(x: width - 90, y: 154, width: 90, height: 26)
        cwdBrowse.bezelStyle = .rounded
        cwdBrowse.controlSize = .small
        cwdBrowse.font = .systemFont(ofSize: 11)
        cwdBrowse.target = self
        cwdBrowse.action = #selector(browseFolder)
        container.addSubview(cwdBrowse)

        promptLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.frame = NSRect(x: 0, y: 136, width: width, height: 13)
        container.addSubview(promptLabel)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 34, width: width, height: 96))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        promptField.frame = NSRect(x: 0, y: 0, width: width, height: 96)
        promptField.font = .systemFont(ofSize: 11)
        promptField.string = initial.prompt ?? ""
        promptField.isRichText = false
        promptField.autoresizingMask = [.width]
        scroll.documentView = promptField
        container.addSubview(scroll)
        promptScroll = scroll

        saveBox.frame = NSRect(x: 0, y: 4, width: width, height: 18)
        saveBox.state = .off
        container.addSubview(saveBox)

        updateAgentFields()
        return container
    }

    /// Grid de cards, um por componente salvo. Clicar preenche a outra aba.
    private func buildPresetsTab() -> NSView {
        let width: CGFloat = 420
        let height = Self.formHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let saved = ComponentStore.names.compactMap { ComponentStore.component(named: $0) }

        guard !saved.isEmpty else {
            let vazio = NSTextField(labelWithString:
                "Nenhum componente salvo ainda.\n\nMonte um terminal na aba \"Criar do zero\" e "
                + "marque \"Salvar como componente reutilizável\" — ele aparece aqui da próxima vez.")
            vazio.font = .systemFont(ofSize: 12)
            vazio.textColor = .secondaryLabelColor
            vazio.maximumNumberOfLines = 0
            vazio.alignment = .center
            vazio.frame = NSRect(x: 30, y: height / 2 - 40, width: width - 60, height: 80)
            container.addSubview(vazio)
            return container
        }

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let columns = 3
        let cardSize = NSSize(width: 132, height: 96)
        let gap: CGFloat = 12
        let rows = Int(ceil(Double(saved.count) / Double(columns)))
        let contentHeight = max(height, CGFloat(rows) * (cardSize.height + gap) + gap)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: contentHeight))

        for (index, component) in saved.enumerated() {
            let card = ComponentCard(component: component,
                                     subtitle: component.displayAgent(using: agents) ?? "Shell")
            card.onClick = { [weak self] in self?.apply(component) }

            let column = index % columns
            let row = index / columns
            card.frame = NSRect(
                x: gap + CGFloat(column) * (cardSize.width + gap),
                // De cima para baixo: uma view não-flipped desenharia a primeira
                // linha no rodapé.
                y: contentHeight - gap - CGFloat(row + 1) * cardSize.height
                   - CGFloat(row) * gap,
                width: cardSize.width, height: cardSize.height)
            content.addSubview(card)
        }

        scroll.documentView = content
        container.addSubview(scroll)
        return container
    }

    @objc private func kindChanged() { updateAgentFields() }

    // MARK: - Configuração da CLI

    /// Remonta o popup de configuração com o que existe no disco agora.
    ///
    /// Descoberto, e não digitado, porque a ferramenta é emprestada: quem abrir
    /// numa máquina que não é a sua vê as configurações DELE na lista, sem saber
    /// que existe uma variável de ambiente por trás.
    private func reloadConfigPicker(select value: String?) {
        configPicker.removeAllItems()
        configValues = []

        guard let profile = selectedAgentKey.flatMap({ agents[$0] }),
              let variable = profile.configEnv else {
            configLabel.stringValue = "CONFIGURAÇÃO"
            configPicker.addItem(withTitle: "padrão da CLI")
            configValues = [nil]
            updateAgentFields()
            return
        }

        configLabel.stringValue = "CONFIGURAÇÃO — \(variable)"

        configPicker.addItem(withTitle: "padrão da CLI")
        configValues.append(nil)

        for url in profile.discoveredConfigs {
            configPicker.addItem(withTitle: Self.short(url.path))
            configValues.append(url.path)
        }

        // O valor gravado no nó pode não existir aqui: componente que veio de
        // outra máquina, ou pasta renomeada. Some da lista descoberta, e sem
        // este item a escolha viraria "padrão da CLI" em silêncio.
        if let value, !configValues.contains(where: { $0 == value }) {
            configPicker.addItem(withTitle: "\(Self.short(value)) (não existe aqui)")
            configValues.append(value)
        }

        configPicker.menu?.addItem(.separator())
        configPicker.addItem(withTitle: Self.browseConfigOption)

        if let value, let index = configValues.firstIndex(where: { $0 == value }) {
            configPicker.selectItem(at: index)
            lastConfig = value
        } else {
            configPicker.selectItem(at: 0)
            lastConfig = nil
        }
        updateAgentFields()
    }

    /// A CLI selecionada, ou nil quando o formulário está em modo shell.
    private var selectedAgentKey: String? {
        agentKeys[safe: agentPicker.indexOfSelectedItem]
    }

    /// A configuração selecionada. Nil é o padrão da CLI.
    private var selectedConfig: String? {
        configValues[safe: configPicker.indexOfSelectedItem] ?? nil
    }

    @objc private func agentChanged() {
        // Trocar de CLI troca o conjunto de configurações: as do Claude Code não
        // dizem nada ao Codex. A escolha anterior é oferecida de volta só se a
        // CLI nova a conhecer.
        reloadConfigPicker(select: selectedConfig)
    }

    @objc private func configChanged() {
        guard configValues[safe: configPicker.indexOfSelectedItem] == nil,
              configPicker.titleOfSelectedItem == Self.browseConfigOption
        else {
            lastConfig = selectedConfig
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Pasta de configuração do CLI"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())

        // Desistir do painel volta para o que estava escolhido: sair sem querer
        // não pode trocar a configuração do terminal em silêncio.
        guard panel.runModal() == .OK, let url = panel.url else {
            reloadConfigPicker(select: lastConfig)
            return
        }
        lastConfig = url.path
        reloadConfigPicker(select: url.path)
    }

    @objc private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Pasta onde este terminal abre"
        panel.prompt = "Usar esta pasta"
        panel.directoryURL = browseStart()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        cwdField.stringValue = Self.stored(folder: url, root: root)
    }

    /// Onde o painel abre: a pasta que o campo já aponta, e a raiz da bancada
    /// quando ele está vazio.
    ///
    /// Resolve pela MESMA regra do runtime (`WorkbenchConfig.resolve`), senão o
    /// painel abriria num lugar e o terminal em outro. Caminho que não existe cai
    /// na raiz: painel apontado para pasta inexistente abre no último lugar que o
    /// sistema lembra, que não tem relação com esta bancada.
    private func browseStart() -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let typed = cwdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return root ?? home }

        let resolved = root.map { WorkbenchConfig.resolve(cwd: typed, against: $0) }
            ?? (typed as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: resolved) else { return root ?? home }
        return URL(fileURLWithPath: resolved)
    }

    /// O que o botão de escolher pasta grava.
    ///
    /// Dentro da raiz da bancada, RELATIVO — é o que faz o nó valer em qualquer
    /// checkout, e é dele que a duplicação em worktree depende. A própria raiz
    /// grava vazio, que é como se diz "a raiz" no resto do app. Fora dela,
    /// absoluto encurtado para `~`: repo vizinho não tem equivalente dentro da
    /// worktree.
    ///
    /// Nunca `..`, mesmo escolhendo uma pasta acima da raiz. O mesmo texto
    /// significa pastas diferentes em checkouts diferentes, e foi assim que os
    /// terminais de uma bancada inteira acabaram na mesma pasta (ADR-017).
    static func stored(folder url: URL, root: URL?) -> String {
        let path = url.standardized.path
        guard let root = root?.standardized.path else { return short(path) }
        if path == root { return "" }
        if path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return short(path)
    }

    /// `/Users/você/.claude-trabalho` → `~/.claude-trabalho`.
    private static func short(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Shell não tem CLI nem papel — deixar os campos ativos convidaria a
    /// preencher algo que seria ignorado em silêncio.
    private func updateAgentFields() {
        let isAgent = kindPicker.titleOfSelectedItem == Self.agentOption
        agentPicker.isEnabled = isAgent
        promptField.isEditable = isAgent
        agentLabel.textColor = isAgent ? .secondaryLabelColor : .tertiaryLabelColor
        promptLabel.textColor = isAgent ? .secondaryLabelColor : .tertiaryLabelColor
        promptScroll?.alphaValue = isAgent ? 1 : 0.4

        // CLI que não declara `configEnv` não tem configuração para escolher — o
        // popup fica visível, e desabilitado, para não fazer a linha inteira
        // aparecer e sumir a cada troca de CLI.
        let hasConfig = isAgent && selectedAgentKey.flatMap { agents[$0]?.configEnv } != nil
        configPicker.isEnabled = hasConfig
        configLabel.textColor = hasConfig ? .secondaryLabelColor : .tertiaryLabelColor
    }

    /// O que o campo de pasta grava.
    ///
    /// Relativo continua relativo — é o que faz o preset valer em qualquer
    /// checkout, e é dele que a duplicação em worktree depende. Absoluto continua
    /// absoluto, encurtado para `~`: é o jeito de apontar para um repositório
    /// vizinho, que não tem equivalente dentro da worktree.
    ///
    /// A versão anterior **decapitava a barra** de um caminho absoluto —
    /// `~/Documents/x` virava `Users/você/Documents/x` — e o resultado nunca
    /// resolvia contra a raiz da bancada: o terminal abria na raiz, calado. Era o
    /// mesmo silêncio que fez `../nexus-backend` embaralhar as pastas.
    private static func normalizedFolder(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix("/") || path.hasPrefix("~") else { return path }
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.hasPrefix(home) ? "~" + expanded.dropFirst(home.count) : expanded
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Exclusividade entre radios, feita à mão.
///
/// O AppKit só agrupa radios que compartilham target e action. Criados com
/// `target: nil, action: nil` — que é o que se escreve quando não há ação a
/// executar — eles viram checkboxes redondos independentes e aceitam ficar os
/// dois marcados ao mesmo tempo.
///
/// Quem usa precisa segurar a instância enquanto o diálogo vive: ela é o target
/// dos botões, e se sumir eles param de responder.
final class RadioGroup: NSObject {
    private let buttons: [NSButton]
    /// Chamado depois da troca, para quem precisa reagir à escolha.
    var onChange: ((NSButton) -> Void)?

    init(_ buttons: [NSButton]) {
        self.buttons = buttons
        super.init()
        for button in buttons {
            button.target = self
            button.action = #selector(pick(_:))
        }
    }

    @objc private func pick(_ sender: NSButton) {
        for button in buttons { button.state = (button === sender) ? .on : .off }
        onChange?(sender)
    }
}

/// Card de um componente salvo: ícone, nome e o que ele roda.
///
/// Um botão desenhado à mão em vez de linha de lista porque a escolha é visual —
/// você reconhece "revisor" pelo formato antes de ler o nome.
final class ComponentCard: NSView {
    var onClick: (() -> Void)?

    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var hovering = false { didSet { restyle() } }
    private var trackingArea: NSTrackingArea?

    init(component: Component, subtitle: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        let symbols = component.kind == .agent
            ? ["sparkles", "brain", "wand.and.stars"]
            : ["apple.terminal", "terminal", "chevron.left.forwardslash.chevron.right"]
        icon.image = symbols.lazy
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            .first
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        nameLabel.stringValue = component.name
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        detailLabel.stringValue = subtitle
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)

        toolTip = component.prompt.map { "Papel: \($0)" } ?? component.name
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: (bounds.width - 26) / 2, y: 16, width: 26, height: 26)
        nameLabel.frame = NSRect(x: 6, y: 50, width: bounds.width - 12, height: 16)
        detailLabel.frame = NSRect(x: 6, y: 68, width: bounds.width - 12, height: 14)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func restyle() {
        layer?.backgroundColor = hovering
            ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            : NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = hovering
            ? NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
            : NSColor.separatorColor.cgColor
        icon.contentTintColor = hovering ? .controlAccentColor : .secondaryLabelColor
    }
}

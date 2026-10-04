import AppKit

/// Diálogo de configuração de um terminal — o mesmo para criar e para editar.
///
/// Um formulário só, e não dois parecidos, porque as perguntas são idênticas:
/// que papel é este, o que roda, em que pasta, com qual instrução.
///
/// O tipo é uma aba, e os campos seguem ela: shell é nome, comando e pasta;
/// agente é CLI, modelo e esforço, configuração, pasta, papel e regras — nessa
/// ordem, que é a de "com o quê sobe" até "como trabalha". Campo que o CLI não
/// tem não aparece: desabilitado, ele convidava a preencher o que seria
/// ignorado.
final class NodeTemplateDialog {

    struct Result {
        let component: NodeTemplate
        /// Marcado "salvar como componente": o preset vai para components.json.
        let saveAsNodeTemplate: Bool
    }

    private let agents: [String: AgentProfile]
    private let title: String
    private let confirmLabel: String
    private let initial: NodeTemplate

    /// Raiz da bancada, quando o formulário é de um nó dela.
    ///
    /// Serve ao + da pasta: é o que permite gravar RELATIVO quando a escolha
    /// está dentro da bancada. Sem raiz — formulário de componente solto — só
    /// existe caminho absoluto a gravar.
    private let root: URL?
    /// As subpastas da bancada que a lista de pasta oferece (`FolderSuggestions`).
    private let folderSuggestions: [String]
    /// A configuração que cada CLI sugere quando o terminal ainda não tem uma:
    /// a última escolhida no workspace. Vazio ao editar — ali vale a do nó.
    private let suggestedConfigs: [String: String]

    /// Ordem estável para os radios de CLI.
    private var agentKeys: [String] { agents.keys.sorted() }

    init(title: String, confirmLabel: String,
         agents: [String: AgentProfile], initial: NodeTemplate, root: URL? = nil,
         folderSuggestions: [String] = [], suggestedConfigs: [String: String] = [:]) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.agents = agents
        self.initial = initial
        self.root = root
        self.folderSuggestions = folderSuggestions
        self.suggestedConfigs = suggestedConfigs
    }

    /// A configuração que entra na tela para um CLI: a dele, ou a sugerida.
    private func config(for cli: String?, own: String?) -> String? {
        own ?? cli.flatMap { suggestedConfigs[$0] }
    }

    // MARK: - Campos

    private let kindTabs = NSSegmentedControl(labels: ["Shell", "Agente"],
                                              trackingMode: .selectOne, target: nil, action: nil)
    private let nameField = NSTextField()
    private let cmdField = NSTextField()
    private var agentRadios: [NSButton] = []
    private var agentGroup: RadioGroup?
    private let modelPicker = HandPopUpButton()
    private let effortPicker = HandPopUpButton()
    /// Popup, sem digitação: as descobertas no disco na lista, e o + do título
    /// para a que não está — caminho digitado à mão era erro de digitação
    /// virando configuração que não existe.
    private let configField = HandPopUpButton()
    private let configBrowse = NodeTemplateDialog.plusButton("Outra configuração")
    /// Valor de cada item da lista de configuração, na mesma ordem. `nil` é o
    /// padrão da CLI — não escrever nada no ambiente.
    private var configItems: [(title: String, value: String?)] = []
    private let folderScroll = NSScrollView()
    private let folderList = FlippedView()
    private let folderAdd = NodeTemplateDialog.plusButton("Outra pasta")
    private var folderOptions: [String] = []
    private var folderRadios: [NSButton] = []
    private var folderGroup: RadioGroup?
    private var selectedFolder = ""
    private let promptField = NSTextView()
    private let rulesField = NSTextView()
    private let promptScroll = NSScrollView()
    private let rulesScroll = NSScrollView()
    private let saveBox = HandButton(checkboxWithTitle: "Salvar como componente reutilizável",
                                     target: nil, action: nil)
    /// Pode montar e reconfigurar a bancada pelo `egeon` (ADR-066). Ao lado do
    /// "salvar": é decisão sobre o terminal, não sobre um campo dele.
    private let maestroBox = HandButton(checkboxWithTitle: "Maestro — monta a bancada",
                                        target: nil, action: nil)

    private let nameCaption = caption("NOME")
    private let cmdCaption = caption("COMANDO — vazio abre o zsh")
    private let agentCaption = caption("CLI")
    private let modelCaption = caption("MODELO")
    private let effortCaption = caption("ESFORÇO")
    private let configCaption = caption("CONFIGURAÇÃO")
    private let folderCaption = caption("PASTA — relativa à raiz da bancada")
    private let promptCaption = caption("PAPEL — quem este terminal é")
    private let rulesCaption = caption("REGRAS — somam às da bancada")

    /// O componente em edição, com o que CADA CLI tem. O formulário mostra um
    /// por vez: sem guardar o resto, salvar com o Claude Code na tela apagaria
    /// o que o Codex tinha de próprio (ADR-057).
    private var loaded: NodeTemplate?
    /// Qual CLI está na tela agora. Trocar guarda o que você digitou no CLI que
    /// sai, antes de mostrar o que entra.
    private var shownAgent: String?

    private let tabs = NSTabView()
    /// Segura o target dos controles enquanto o modal roda.
    private var actions: DialogActions?

    private static let defaultModelOption = "padrão do CLI"
    private static let defaultConfigOption = "padrão da CLI"
    private static let formWidth: CGFloat = 720
    /// Mais alto que isto, o `NSAlert` troca para o layout com o ícone ao lado
    /// (é como ele cabe numa tela baixa), e o formulário vai parar encostado na
    /// borda direita da janela. Espaço a mais vem da largura.
    private static let formHeight: CGFloat = 510
    /// Folga entre os campos e a moldura da aba.
    private static let inset: CGFloat = 12
    /// Do título ao campo, e de um campo ao título do próximo.
    private static let labelGap: CGFloat = 19
    private static let gap: CGFloat = 14

    /// O "escolher outro" do formulário: um + ao lado do título do campo, igual
    /// em todos.
    private static func plusButton(_ tip: String) -> HandButton {
        let button = HandButton(
            image: NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: tip)
                ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.contentTintColor = .controlAccentColor
        button.toolTip = tip
        return button
    }

    private static func caption(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 10, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    private var isAgent: Bool { kindTabs.selectedSegment == 1 }

    /// Preenche o formulário a partir de um componente salvo e leva para a aba de
    /// detalhes. Os campos seguem editáveis: o preset é ponto de partida, não
    /// camisa de força.
    private func apply(_ component: NodeTemplate) {
        nameField.stringValue = component.name
        kindTabs.selectedSegment = component.kind == .agent ? 1 : 0
        maestroBox.state = component.maestro == true ? .on : .off
        selectAgent(component.agent)
        let resolved = component.resolved(for: component.agent)
        reloadConfig(select: resolved.config)
        reloadModelPicker(select: resolved.model)
        reloadEffortPicker(select: resolved.effort)
        cmdField.stringValue = component.command ?? ""
        reloadFolders(select: component.cwd ?? "")
        // O preset traz o que ele tem para cada CLI junto: escolher um componente
        // e trocar de CLI depois devolve o que aquele CLI tinha lá.
        loaded = component
        showTexts(of: component.agent)
        relayout()

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

        // Nome em branco vira um padrão em vez de cancelar: confirmar e não ver
        // nada acontecer é o pior desfecho possível para um formulário.
        var name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = isAgent ? (selectedAgentKey ?? "agente") : "sh"
        }

        // O que está na tela é do CLI que está na tela: a mesma regra da troca
        // de CLI, aplicada de novo na saída (ADR-057).
        rememberShown()
        var base = loaded ?? initial
        base.name = name
        base.kind = isAgent ? .agent : .shell
        base.agent = isAgent ? selectedAgentKey : nil
        base.cwd = selectedFolder.isEmpty ? nil : Self.normalizedFolder(selectedFolder)
        base.maestro = isAgent && maestroBox.state == .on ? true : nil
        if isAgent {
            base.command = nil
        } else {
            // Shell não tem CLI, papel nem regra — e não pode carregar o mapa
            // de um agente que ele deixou de ser.
            base.command = trimmed(cmdField.stringValue)
            base.prompt = nil
            base.rules = nil
            base.byAgent = nil
        }
        return Result(component: base, saveAsNodeTemplate: saveBox.state == .on)
    }

    /// Duas abas: montar do zero, ou partir de um componente salvo.
    ///
    /// Os presets ficam numa aba própria, com cards, e não num menu — antes eles
    /// viviam atrás de uma pressão longa no botão da barra, o que fazia salvar
    /// funcionar e ninguém achar o resultado.
    private func buildForm() -> NSView {
        let size = NSSize(width: Self.formWidth + 32, height: Self.formHeight + 66)
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
        let width = Self.formWidth
        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: Self.formHeight))
        let actions = DialogActions(self)
        self.actions = actions

        kindTabs.selectedSegment = initial.kind == .agent ? 1 : 0
        kindTabs.segmentDistribution = .fillEqually
        kindTabs.target = actions
        kindTabs.action = #selector(DialogActions.kindChanged)

        nameField.stringValue = initial.name
        nameField.placeholderString = "revisor, front end, build…"

        cmdField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cmdField.placeholderString = "ex: npm run dev"
        cmdField.stringValue = initial.command ?? ""

        // Radio e não popup: são poucos, e ver os três lado a lado é saber de
        // cara quais CLIs existem nesta máquina.
        agentRadios = agentKeys.map { key in
            HandButton(radioButtonWithTitle: agents[key]?.displayName ?? key, target: nil, action: nil)
        }
        let group = RadioGroup(agentRadios)
        group.onChange = { [weak self] _ in self?.agentChanged() }
        agentGroup = group
        selectAgent(initial.agent)

        configBrowse.target = actions
        configBrowse.action = #selector(DialogActions.browseConfig)

        folderAdd.target = actions
        folderAdd.action = #selector(DialogActions.addFolder)
        folderScroll.documentView = folderList
        folderScroll.hasVerticalScroller = true
        folderScroll.autohidesScrollers = true
        folderScroll.borderType = .bezelBorder
        folderScroll.drawsBackground = false

        for (field, scroll) in [(promptField, promptScroll), (rulesField, rulesScroll)] {
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            field.font = .systemFont(ofSize: 11)
            field.isRichText = false
            field.autoresizingMask = [.width]
            scroll.documentView = field
        }
        saveBox.state = .off
        maestroBox.state = initial.maestro == true ? .on : .off
        maestroBox.toolTip = "Este terminal ganha `egeon bench`, `models`, `plan` e `apply`: "
            + "cria terminais, escolhe modelo, esforço, papel e regras de cada um, e liga as "
            + "arestas. Reinicia o agente."

        let views: [NSView] = [kindTabs, nameCaption, nameField, cmdCaption, cmdField,
                               agentCaption, modelCaption, modelPicker, effortCaption, effortPicker,
                               configCaption, configField, configBrowse,
                               folderCaption, folderAdd, folderScroll,
                               promptCaption, promptScroll, rulesCaption, rulesScroll, saveBox,
                               maestroBox]
        views.forEach(container.addSubview)
        agentRadios.forEach(container.addSubview)

        let resolved = initial.resolved(for: initial.agent)
        reloadConfig(select: config(for: initial.agent, own: resolved.config))
        reloadModelPicker(select: resolved.model)
        reloadEffortPicker(select: resolved.effort)
        reloadFolders(select: initial.cwd ?? "")
        loaded = loaded ?? initial
        showTexts(of: initial.agent)
        relayout()
        return container
    }

    /// Posiciona de cima para baixo o que o tipo e o CLI pedem, e esconde o
    /// resto. Uma passada só, chamada a cada troca: calcular y por campo em
    /// cada mudança é como se erra por um pixel.
    fileprivate func relayout() {
        let width = Self.formWidth - 2 * Self.inset
        let profile = isAgent ? selectedAgentKey.flatMap { agents[$0] } : nil
        let hasModels = profile?.offersModels ?? false
        let hasEfforts = profile?.offersEfforts ?? false
        let hasConfig = profile?.configEnv != nil
        var y: CGFloat = 0

        func place(_ view: NSView, _ height: CGFloat, x: CGFloat = 0, w: CGFloat? = nil) {
            view.isHidden = false
            view.frame = NSRect(x: Self.inset + x, y: y, width: w ?? width - x, height: height)
        }
        func hide(_ views: NSView...) { views.forEach { $0.isHidden = true } }
        func titled(_ label: NSTextField, plus: NSButton) {
            place(label, 13, w: width - 24)
            place(plus, 16, x: width - 16, w: 16)
            plus.frame.origin.y -= 2
            y += Self.labelGap
        }
        func captioned(_ label: NSTextField, then: () -> Void) {
            place(label, 13)
            y += Self.labelGap
            then()
        }

        y = 8
        place(kindTabs, 24)
        y += 24 + Self.gap
        captioned(nameCaption) { place(nameField, 22); y += 22 + Self.gap }

        if isAgent {
            hide(cmdCaption, cmdField)
            captioned(agentCaption) {
                let each = width / CGFloat(max(agentRadios.count, 1))
                for (i, radio) in agentRadios.enumerated() {
                    place(radio, 18, x: CGFloat(i) * each, w: each)
                }
                y += 18 + Self.gap
            }
            if hasModels || hasEfforts {
                let half = (width - 10) / 2
                if hasModels {
                    place(modelCaption, 13, w: half)
                    modelPicker.isHidden = false
                    modelPicker.frame = NSRect(x: Self.inset, y: y + Self.labelGap, width: half, height: 22)
                } else { hide(modelCaption, modelPicker) }
                if hasEfforts {
                    let x = hasModels ? half + 10 : 0
                    place(effortCaption, 13, x: x, w: half)
                    effortPicker.isHidden = false
                    effortPicker.frame = NSRect(x: Self.inset + x, y: y + Self.labelGap,
                                                width: half, height: 22)
                } else { hide(effortCaption, effortPicker) }
                y += Self.labelGap + 22 + Self.gap
            } else {
                hide(modelCaption, modelPicker, effortCaption, effortPicker)
            }
            if hasConfig {
                configCaption.stringValue = "CONFIGURAÇÃO — \(profile?.configEnv ?? "")"
                titled(configCaption, plus: configBrowse)
                place(configField, 24)
                configField.frame.origin.y -= 1
                y += 24 + Self.gap
            } else {
                hide(configCaption, configField, configBrowse)
            }
        } else {
            agentRadios.forEach { $0.isHidden = true }
            hide(agentCaption, modelCaption, modelPicker, effortCaption, effortPicker,
                 configCaption, configField, configBrowse)
            captioned(cmdCaption) { place(cmdField, 22); y += 22 + Self.gap }
        }

        titled(folderCaption, plus: folderAdd)
        let listHeight = min(CGFloat(max(folderOptions.count, 1)) * 20 + 8, 88)
        place(folderScroll, listHeight)
        layoutFolderList()
        y += listHeight + Self.gap

        let bottom = Self.formHeight - 28
        if isAgent {
            // Lado a lado, papel à esquerda: é a ordem em que os dois entram no
            // system prompt — e é ela que faz a regra valer sobre o papel
            // (ADR-056). Um embaixo do outro não cabe: acima de ~510 de altura o
            // `NSAlert` põe o ícone de lado para caber na tela.
            let half = (width - Self.gap) / 2
            let textHeight = max(40, bottom - Self.gap / 2 - y - Self.labelGap)
            place(promptCaption, 13, w: half)
            place(rulesCaption, 13, x: half + Self.gap, w: half)
            y += Self.labelGap
            place(promptScroll, textHeight, w: half)
            place(rulesScroll, textHeight, x: half + Self.gap, w: half)
        } else {
            hide(promptCaption, promptScroll, rulesCaption, rulesScroll)
        }

        saveBox.isHidden = false
        if isAgent {
            let half = (width - Self.gap) / 2
            saveBox.frame = NSRect(x: Self.inset, y: bottom, width: half, height: 18)
            maestroBox.isHidden = false
            maestroBox.frame = NSRect(x: Self.inset + half + Self.gap, y: bottom, width: half, height: 18)
        } else {
            saveBox.frame = NSRect(x: Self.inset, y: bottom, width: width, height: 18)
            maestroBox.isHidden = true
        }
    }

    /// Grid de cards, um por componente salvo. Clicar preenche a outra aba.
    private func buildPresetsTab() -> NSView {
        let width = Self.formWidth
        let height = Self.formHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let saved = NodeTemplateStore.names.compactMap { NodeTemplateStore.component(named: $0) }

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
            let card = NodeTemplateCard(component: component,
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

    // MARK: - CLI

    /// A CLI marcada. Nil só quando não há perfil nenhum.
    private var selectedAgentKey: String? {
        agentRadios.firstIndex { $0.state == .on }.flatMap { agentKeys[safe: $0] }
    }

    private func selectAgent(_ key: String?) {
        let index = key.flatMap { agentKeys.firstIndex(of: $0) } ?? 0
        for (i, radio) in agentRadios.enumerated() { radio.state = i == index ? .on : .off }
    }

    fileprivate func agentChanged() {
        rememberShown()
        // Trocar de CLI troca o conjunto de configurações: as do Claude Code não
        // dizem nada ao Codex. A escolha anterior é oferecida de volta só se a
        // CLI nova a conhecer.
        let entering = loaded?.overrides(for: selectedAgentKey) ?? NodeTemplate.Overrides()
        reloadConfig(select: config(for: selectedAgentKey, own: entering.config))
        reloadModelPicker(select: entering.model)
        reloadEffortPicker(select: entering.effort)
        showTexts(of: selectedAgentKey)
        relayout()
    }

    fileprivate func kindChanged() { relayout() }

    // MARK: - Configuração da CLI

    /// Remonta a lista de configuração com o que existe no disco agora.
    ///
    /// Descoberto, e não digitado, porque a ferramenta é emprestada: quem abrir
    /// numa máquina que não é a sua vê as configurações DELE na lista, sem saber
    /// que existe uma variável de ambiente por trás.
    private func reloadConfig(select value: String?) {
        let profile = selectedAgentKey.flatMap { agents[$0] }
        configItems = Self.configItems(default: profile?.defaultConfigPath,
                                       discovered: (profile?.discoveredConfigs ?? []).map(\.path),
                                       current: value)
        configField.removeAllItems()
        configField.addItems(withTitles: configItems.map(\.title))
        let chosen = value == profile?.defaultConfigPath ? nil : value
        configField.selectItem(at: configItems.firstIndex { $0.value == chosen } ?? 0)
    }

    /// Os itens do popup de configuração.
    ///
    /// O primeiro é o padrão, mostrado pelo caminho que o CLI usa sem a
    /// variável (`~/.claude`), e gravado vazio — é a mesma pasta, e não
    /// escrever nada no ambiente deixa o CLI decidir. Por isso ela não se
    /// repete entre as descobertas.
    ///
    /// O valor gravado no nó pode não existir aqui: componente que veio de outra
    /// máquina, ou pasta renomeada. Some da lista descoberta, e sem este item a
    /// escolha viraria o padrão em silêncio.
    static func configItems(default path: String?, discovered: [String],
                            current: String?) -> [(title: String, value: String?)] {
        var items: [(title: String, value: String?)] =
            [(path.map(short) ?? defaultConfigOption, nil)]
        items += discovered.filter { $0 != path }.map { (short($0), $0) }
        if let current, current != path, !items.contains(where: { $0.value == current }) {
            items.append((short(current), current))
        }
        return items
    }

    /// A configuração no popup. Nil é o padrão da CLI.
    private var selectedConfig: String? {
        configItems[safe: configField.indexOfSelectedItem]?.value ?? nil
    }

    fileprivate func browseConfig() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Pasta de configuração do CLI"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        // Desistir do painel deixa a caixa como estava: sair sem querer não pode
        // trocar a configuração do terminal em silêncio.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        reloadConfig(select: url.path)
    }

    // MARK: - Modelo e esforço

    /// Nil é o padrão do CLI — o primeiro item.
    private var selectedModel: String? {
        modelPicker.selectedItem?.representedObject as? String
    }

    /// A lista vem do perfil: trocar de CLI troca os modelos. A escolha anterior
    /// só volta se o CLI novo a conhecer — `opus` não diz nada ao Codex, e o app
    /// anexaria `--model opus` a um binário que não tem esse modelo. Modelo
    /// escrito à mão no `components.json` continua valendo: só é descartado
    /// quando o CLI declara uma lista e o valor não está nela.
    ///
    /// Com catálogo (Claude Code), os modelos vêm com nome de gente — "Opus 5.5"
    /// grava `claude-opus-5-5` — e os apelidos seguem depois, para quem quer
    /// sempre o mais recente.
    private func reloadModelPicker(select value: String?) {
        modelPicker.removeAllItems()
        let menu = modelPicker.menu!
        func add(_ title: String, _ id: String?) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = id
            menu.addItem(item)
        }
        add(Self.defaultModelOption, nil)
        let profile = selectedAgentKey.flatMap { agents[$0] }
        let catalog = profile.flatMap(ClaudeModelCatalog.current(for:))
        let aliases = profile?.models ?? []
        var ids = aliases
        if let catalog {
            for model in catalog.featured + catalog.older { add(model.label, model.id) }
            ids += catalog.models.map(\.id)
        }
        for alias in aliases { add(alias, alias) }
        if let value, !value.isEmpty, !ids.contains(value), aliases.isEmpty, catalog == nil {
            add(value, value)
            ids.append(value)
        }
        let index = menu.items.firstIndex { ($0.representedObject as? String) == value }
        modelPicker.selectItem(at: value == nil ? 0 : index ?? 0)
    }

    /// Nil é o padrão do CLI — o primeiro item.
    private var selectedEffort: String? {
        let index = effortPicker.indexOfSelectedItem
        guard index > 0, let title = effortPicker.titleOfSelectedItem else { return nil }
        return title
    }

    /// A mesma regra do `reloadModelPicker`: a lista é do perfil, e um nível
    /// que o CLI novo não declara não é levado junto.
    private func reloadEffortPicker(select value: String?) {
        effortPicker.removeAllItems()
        effortPicker.addItem(withTitle: Self.defaultModelOption)
        let known = selectedAgentKey.flatMap { agents[$0]?.efforts } ?? []
        var options = known
        if let value, !value.isEmpty, !options.contains(value), known.isEmpty {
            options.append(value)
        }
        effortPicker.addItems(withTitles: options)
        if let value, let index = options.firstIndex(of: value) {
            effortPicker.selectItem(at: index + 1)
        } else {
            effortPicker.selectItem(at: 0)
        }
    }

    // MARK: - Papel e regras

    /// Papel e regras do CLI que entra: os dele quando você escreveu algo
    /// diferente ali, os gerais quando não. Papel e regras são gerais — trocar
    /// de CLI não esvazia os campos.
    private func showTexts(of cli: String?) {
        let base = loaded ?? initial
        let own = base.overrides(for: cli)
        promptField.string = own.prompt ?? base.prompt ?? ""
        rulesField.string = own.rules ?? base.rules ?? ""
        shownAgent = cli
    }

    /// Guarda o que está na tela no CLI que estava selecionado — a regra mora
    /// no `NodeTemplate`; aqui só se colhem os campos. O comando do CLI não
    /// está mais na tela: vai o que ele já tinha, para não ser apagado.
    private func rememberShown() {
        guard let cli = shownAgent else { return }
        let base = loaded ?? initial
        loaded = base.remembering(
            cli: cli, cmd: base.overrides(for: cli).cmd, config: selectedConfig,
            model: selectedModel, effort: selectedEffort, prompt: trimmed(promptField.string),
            rules: trimmed(rulesField.string))
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - Pasta

    /// A raiz na lista. Grava vazio, que é como o resto do app diz "a raiz".
    static let rootOption = "root"

    static func shown(cwd: String?) -> String {
        let value = cwd ?? ""
        return value.isEmpty ? rootOption : value
    }

    /// As opções da lista de pasta: a raiz, as subpastas da bancada, e a pasta
    /// atual do nó quando ela não é nenhuma dessas — sem ela, editar um nó
    /// customizado mostraria uma escolha que não é a dele.
    static func folderOptions(current: String, suggestions: [String]) -> [String] {
        var out = [""] + suggestions.filter { !$0.isEmpty }
        if !out.contains(current) { out.append(current) }
        return out
    }

    private func reloadFolders(select value: String) {
        // O que o + já tinha acrescentado continua na lista.
        let base = Self.folderOptions(current: value, suggestions: folderSuggestions)
        folderOptions = base + folderOptions.filter { !base.contains($0) }
        selectedFolder = value
        folderRadios.forEach { $0.removeFromSuperview() }
        folderRadios = folderOptions.map { option in
            let radio = HandButton(radioButtonWithTitle: Self.shown(cwd: option), target: nil, action: nil)
            radio.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            radio.lineBreakMode = .byTruncatingMiddle
            radio.state = option == value ? .on : .off
            folderList.addSubview(radio)
            return radio
        }
        let group = RadioGroup(folderRadios)
        group.onChange = { [weak self] sender in
            guard let self, let i = self.folderRadios.firstIndex(where: { $0 === sender }) else { return }
            self.selectedFolder = self.folderOptions[i]
        }
        folderGroup = group
    }

    private func layoutFolderList() {
        let inner = folderScroll.contentSize.width
        folderList.frame = NSRect(x: 0, y: 0, width: inner,
                                  height: max(CGFloat(folderRadios.count) * 20 + 4,
                                              folderScroll.contentSize.height))
        for (i, radio) in folderRadios.enumerated() {
            radio.frame = NSRect(x: 6, y: 2 + CGFloat(i) * 20, width: inner - 12, height: 18)
        }
    }

    /// O + da pasta: qualquer lugar, gravado relativo quando cai dentro da
    /// bancada.
    fileprivate func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Pasta onde este terminal abre"
        panel.prompt = "Usar esta pasta"
        panel.directoryURL = browseStart()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let value = Self.stored(folder: url, root: root)
        if !folderOptions.contains(value) { folderOptions.append(value) }
        reloadFolders(select: value)
        relayout()
        folderList.scrollToVisible(folderRadios.last?.frame ?? .zero)
    }

    /// Onde o painel abre: a pasta escolhida, e a raiz da bancada quando é ela.
    ///
    /// Resolve pela MESMA regra do runtime (`WorkbenchConfig.resolve`), senão o
    /// painel abriria num lugar e o terminal em outro. Caminho que não existe cai
    /// na raiz: painel apontado para pasta inexistente abre no último lugar que o
    /// sistema lembra, que não tem relação com esta bancada.
    private func browseStart() -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard !selectedFolder.isEmpty else { return root ?? home }
        let resolved = root.map { WorkbenchConfig.resolve(cwd: selectedFolder, against: $0) }
            ?? (selectedFolder as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: resolved) else { return root ?? home }
        return URL(fileURLWithPath: resolved)
    }

    /// O que o + da pasta grava.
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

    /// O que a pasta grava.
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

/// Target dos controles do diálogo. O diálogo é classe Swift pura, sem
/// `NSObject`; o seletor precisa de alguém que o Objective-C enxergue.
private final class DialogActions: NSObject {
    private weak var dialog: NodeTemplateDialog?
    init(_ dialog: NodeTemplateDialog) { self.dialog = dialog }
    @objc func kindChanged() { dialog?.kindChanged() }
    @objc func browseConfig() { dialog?.browseConfig() }
    @objc func addFolder() { dialog?.addFolder() }
}

/// De cima para baixo, como se lê.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
final class NodeTemplateCard: NSView {
    var onClick: (() -> Void)?

    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var hovering = false { didSet { restyle() } }
    private var trackingArea: NSTrackingArea?

    init(component: NodeTemplate, subtitle: String) {
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

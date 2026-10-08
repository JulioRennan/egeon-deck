import AppKit

final class SidebarRow: NSView {
    let index: Int
    /// Nome da bancada. É a chave do resumo de atividade do Dispatcher —
    /// o índice da linha não serve, porque o endereço de dispatch é por nome.
    let name: String
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    /// Pastilha com a inicial da bancada, só no trilho recolhido. Nome inteiro não
    /// cabe em 52pt, e uma coluna de bolinhas iguais não diz QUAL bancada é.
    private let tile = NSView()
    private let initial = NSTextField(labelWithString: "")

    var onClick: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?
    var onDuplicateAsWorktree: ((Int) -> Void)?
    var onRemove: ((Int) -> Void)?
    var onEditVisitLimit: ((Int) -> Void)?
    var onEditRules: ((Int) -> Void)?
    /// "Limpar a bancada": `clear` em todo agente e o chat arquivado (ADR-037).
    var onClear: ((Int) -> Void)?

    var isSelected = false { didSet { needsDisplay = true; restyle() } }
    /// Bancada já materializada (terminais rodando, editor carregado).
    var isLive = false { didSet { restyle() } }
    /// Apagando as worktrees da bancada em segundo plano: o badge vira
    /// "removendo…" e o nome apaga, até ela sair da lista (ou a remoção falhar).
    var isRemoving = false {
        didSet {
            guard isRemoving != oldValue else { return }
            lastBadge = ""
            restyle()
        }
    }

    /// Alguma coisa nesta bancada está te esperando. Guardado porque no trilho
    /// quem grita isso é o ARO da pastilha, e `restyle` não vê o resumo.
    private var wantsAttention = false
    /// A borda que gira quando a bancada precisa de você: na linha inteira com a
    /// barra aberta, na pastilha no trilho.
    private lazy var rowRing = AttentionRing(host: self, cornerRadius: 7)
    private lazy var tileRing = AttentionRing(host: tile, cornerRadius: 7, lineWidth: 2)

    /// Trilho recolhido: só a pastilha da inicial e o badge, sem nome nem caminho.
    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            nameLabel.isHidden = isCompact
            pathLabel.isHidden = isCompact
            tile.isHidden = !isCompact
            initial.isHidden = !isCompact
            dot.isHidden = isCompact
            // A assinatura do badge não muda de modo, mas a fonte e o alinhamento
            // dele mudam: sem zerar o cache, o rótulo fica com a métrica do modo
            // anterior até a próxima troca de contagem.
            lastBadge = ""
            restyle()
            needsLayout = true
        }
    }

    init(index: Int, config: WorkbenchConfig) {
        self.index = index
        self.name = config.name
        super.init(frame: .zero)
        wantsLayer = true

        nameLabel.stringValue = config.name
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail

        pathLabel.stringValue = config.exists
            ? (config.path as NSString).abbreviatingWithTildeInPath
            : "caminho não existe — \(config.path)"
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = config.exists
            ? NSColor(calibratedWhite: 1, alpha: 0.5)
            : NSColor.systemRed.withAlphaComponent(0.85)
        pathLabel.lineBreakMode = .byTruncatingMiddle

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3

        // Monoespaçado porque o conteúdo é spinner: com fonte proporcional cada
        // quadro do braille tem uma largura, e o rótulo treme a cada troca.
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        statusLabel.alignment = .right

        tile.wantsLayer = true
        tile.layer?.cornerRadius = 7
        tile.isHidden = true

        initial.stringValue = String(config.name.prefix(1)).uppercased()
        initial.font = .systemFont(ofSize: 13, weight: .semibold)
        initial.alignment = .center
        initial.isHidden = true

        addSubview(dot)
        addSubview(tile)
        addSubview(initial)
        addSubview(nameLabel)
        addSubview(pathLabel)
        addSubview(statusLabel)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Largura que o badge de fato ocupa, medida do conteúdo.
    ///
    /// Reservar o pior caso — `⠙9 ●9 ●9`, três avisos com contagem — custaria
    /// 66pt em TODA linha, e a barra tem 264: um terço do nome da bancada pago
    /// para um caso que quase nunca acontece. O comum é uma bolinha só.
    private var badgeWidth: CGFloat = 0

    override func layout() {
        super.layout()
        rowRing.layout()
        if isCompact {
            let side: CGFloat = 26
            tile.frame = NSRect(x: ((bounds.width - side) / 2).rounded(), y: 2,
                                width: side, height: side)
            tileRing.layout()
            initial.frame = NSRect(x: tile.frame.minX, y: tile.frame.minY + 5,
                                   width: side, height: 16)
            // Badge embaixo da pastilha, em fonte miúda: no trilho os três avisos
            // continuam convivendo (ADR-024) porque é o único lugar onde uma
            // bancada inativa se anuncia — o que a largura não dá é o nome.
            statusLabel.frame = NSRect(x: 0, y: 30, width: bounds.width, height: 12)
            return
        }

        // Mesma coluna de texto que o cabeçalho do projeto (`SidebarGroupRow`):
        // dentro do tile, a bancada tem de ler como item da mesma lista.
        dot.frame = NSRect(x: 15, y: bounds.midY - 3, width: 6, height: 6)
        let textWidth = bounds.width - 44 - badgeWidth
        nameLabel.frame = NSRect(x: 32, y: 7, width: textWidth, height: 17)
        pathLabel.frame = NSRect(x: 32, y: 24, width: textWidth, height: 13)
        // 4 da borda da linha, que é onde o `+` do cabeçalho termina: encostado
        // no limite útil da direita e alinhado com o que já estava lá.
        statusLabel.frame = NSRect(x: bounds.width - badgeWidth - 4,
                                   y: bounds.midY - 9,
                                   width: badgeWidth, height: 18)
    }

    /// A bancada que precisa de você quase nunca é a que está na tela: o canvas
    /// das outras sai da hierarquia de views e não desenha nada. Esta linha é a
    /// única pista que elas têm.
    ///
    /// Os três avisos convivem, e é o caso normal de uma bancada com vários nós:
    /// um agente rodando, outro te perguntando algo, um terceiro que já acabou.
    /// Escolher um para mostrar escondia os outros dois — e como a laranja
    /// ganhava sempre, o escondido era justamente o que dizia se ainda há
    /// trabalho em curso.
    func show(_ summary: ActivitySummary) {
        // Isto roda a cada quadro do spinner, em toda linha da barra. A
        // assinatura carrega as três contagens e não o texto: com a MESMA
        // bolinha em dois estados, `●` sozinho é ambíguo — laranja e verde
        // escreveriam igual, e a linha ficaria presa na cor anterior.
        let signature = (isRemoving ? "removendo/" : "")
            + "\(summary.starting)/\(summary.working)/\(summary.background)/"
            + "\(summary.attention)/\(summary.done)/"
            + (summary.working > 0 || summary.starting > 0 || isRemoving ? String(Spinner.current) : "")
            + (summary.background > 0 ? String(Spinner.hourglass) : "")
        guard signature != lastBadge else { return }
        lastBadge = signature

        // No trilho o badge é miúdo e centrado sob a pastilha; expandido é 12pt
        // encostado na direita. Escolhido aqui, e não no rótulo, porque
        // `attributedStringValue` ignora fonte e alinhamento da view.
        let font: NSFont = isCompact
            ? .monospacedSystemFont(ofSize: 10, weight: .semibold)
            : .monospacedSystemFont(ofSize: 12, weight: .medium)
        let paragraph = isCompact ? Self.centered : Self.rightAligned

        let badge = NSMutableAttributedString()
        func add(_ glyph: String, _ count: Int, _ color: NSColor) {
            guard count > 0 else { return }
            // Sem espaço entre os grupos no trilho: os três com contagem passam
            // de 48pt de largura, e o que sobra do rótulo é cortado no meio.
            if badge.length > 0, !isCompact { badge.append(NSAttributedString(string: " ")) }
            // Fonte e alinhamento vêm junto porque `attributedStringValue`
            // ignora os do rótulo: sem a fonte o spinner volta a tremer em fonte
            // proporcional, e sem o parágrafo o badge encosta na ESQUERDA da
            // caixa — que é longe da borda do tile, justamente onde ele não
            // serve.
            badge.append(NSAttributedString(string: count > 1 ? "\(glyph)\(count)" : glyph,
                                            attributes: [.foregroundColor: color,
                                                         .font: font,
                                                         .paragraphStyle: paragraph]))
        }

        // Ordem fixa, na sequência do ciclo: rodando, parou te perguntando,
        // parou pronto. Ordenar por urgência faria a bolinha trocar de lugar
        // conforme a bancada anda, e badge que se move é badge que se procura em
        // vez de se reconhecer.
        // Mais claro no trilho: ali o spinner tem 10pt e concorre com o card que
        // passa por trás do vidro.
        if isRemoving {
            // Ganha de tudo: o que os terminais estão fazendo deixa de importar
            // para uma bancada que está de saída.
            badge.append(NSAttributedString(
                string: isCompact ? String(Spinner.current) : "\(Spinner.current) removendo…",
                attributes: [.foregroundColor: NSColor.systemRed.withAlphaComponent(0.8),
                             .font: isCompact ? font
                                 : NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                             .paragraphStyle: paragraph]))
        } else if summary.isPreparing, !isCompact {
            // Bancada recém-aberta, terminais ainda subindo: dizer por extenso
            // vale mais que um spinner, que aqui leria como "trabalhando".
            badge.append(NSAttributedString(
                string: "\(Spinner.current) preparando…",
                attributes: [.foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.35),
                             .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                             .paragraphStyle: paragraph]))
        } else {
            // No trilho, ou com trabalho de verdade ao lado, o "subindo" é um
            // spinner mais apagado que o de trabalho — presente, não urgente.
            add(String(Spinner.current), summary.starting,
                NSColor(calibratedWhite: 1, alpha: isCompact ? 0.4 : 0.25))
            add(String(Spinner.current), summary.working,
                NSColor(calibratedWhite: 1, alpha: isCompact ? 0.75 : 0.45))
            add(String(Spinner.hourglass), summary.background,
                NSColor(calibratedWhite: 1, alpha: isCompact ? 0.75 : 0.45))
            add("●", summary.attention, .systemOrange)
            add("●", summary.done, .systemGreen)
        }

        statusLabel.attributedStringValue = badge

        // No trilho, 10pt de glifo é pouco para o aviso que INTERROMPE: o aro da
        // pastilha vira laranja, que se reconhece sem ler.
        if wantsAttention != (summary.attention > 0) {
            wantsAttention = summary.attention > 0
            restyle()
        }

        // O nome da bancada fica com o que sobra, então a caixa acompanha o
        // conteúdo em vez de reservar o pior caso.
        // O NSTextField desenha com ~2pt de inset de cada lado; com folga de 2 a
        // bolinha alinhada à direita vazava pela borda e saía cortada pela metade.
        let width = badge.length == 0 ? 0 : ceil(badge.size().width) + 8
        if width != badgeWidth {
            badgeWidth = width
            needsLayout = true
        }
    }

    /// Última combinação desenhada, para não remontar o rótulo à toa.
    private var lastBadge = ""

    private static let rightAligned: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }()

    private static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    /// Contraste sobre vidro, não sobre chapa: os alfas subiram porque atrás da
    /// barra agora passa o canvas — grid claro, terminal branco — e o que era
    /// legível em cima de 0.09 opaco virava lodo.
    private func restyle() {
        // No trilho quem carrega a seleção é a pastilha: realçar a linha inteira
        // pinta uma faixa de 52pt de ponta a ponta, que lê como divisor.
        layer?.backgroundColor = (isSelected && !isCompact)
            ? NSColor(calibratedWhite: 1, alpha: 0.14).cgColor
            : NSColor.clear.cgColor
        layer?.cornerRadius = 7
        nameLabel.textColor = isRemoving
            ? NSColor(calibratedWhite: 1, alpha: 0.35)
            : isSelected ? .white : NSColor(calibratedWhite: 1, alpha: 0.72)

        tile.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            : NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
        // Aro por prioridade: o laranja de "te espera" vence o verde de "está de
        // pé", porque um pede coisa e o outro só informa — e o laranja é a borda
        // que gira, por cima do aro parado.
        tile.layer?.borderWidth = (isLive && !wantsAttention) ? 2 : 0
        tile.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.75).cgColor
        rowRing.isOn = wantsAttention && !isCompact
        tileRing.isOn = wantsAttention && isCompact
        initial.textColor = isSelected ? .white : NSColor(calibratedWhite: 1, alpha: 0.7)

        dot.layer?.backgroundColor = (isLive ? NSColor.systemGreen : NSColor(calibratedWhite: 1, alpha: 0.22)).cgColor
    }

    override func resetCursorRects() { HandCursor.fill(self) }

    /// Arrastar reposiciona (ADR-051); o clique só vale se você não arrastou.
    var onDrag: ((SidebarDrag) -> Void)?

    override func mouseDown(with event: NSEvent) {
        SidebarDrag.track(event, in: self, item: .workbench(index: index),
                          drag: onDrag) { [weak self] in
            guard let self else { return }
            self.onClick?(self.index)
        }
    }

    /// Renomear e remover ficam no menu de contexto: são raros o bastante para
    /// não merecerem botão fixo, e um botão de remover por linha convida ao
    /// acidente.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Renomear…", action: #selector(renameFromMenu), keyEquivalent: "")
        // Duplicar mora aqui, e não no +, porque a bancada já diz qual é o
        // repositório e quais nós replicar — no + você teria de informar os dois.
        menu.addItem(withTitle: "Duplicar em nova worktree…",
                     action: #selector(duplicateFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Regras da bancada…",
                     action: #selector(rulesFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Limite de conversa entre agentes…",
                     action: #selector(visitLimitFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        // Varrer para baixo do tapete: os agentes esquecem a conversa e o chat
        // vai para o arquivo. Mora aqui, com as outras ações da bancada, e não
        // na barra — é ação rara, e botão fixo convidava ao acidente.
        let clear = NSMenuItem(title: "Limpar a bancada…", action: #selector(clearFromMenu),
                               keyEquivalent: "")
        clear.image = ToolbarButton.symbol(["paintbrush.pointed", "paintbrush"])
        menu.addItem(clear)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remover bancada…", action: #selector(removeFromMenu), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func renameFromMenu() { onRename?(index) }
    @objc private func duplicateFromMenu() { onDuplicateAsWorktree?(index) }
    @objc private func removeFromMenu() { onRemove?(index) }
    @objc private func visitLimitFromMenu() { onEditVisitLimit?(index) }
    @objc private func rulesFromMenu() { onEditRules?(index) }
    @objc private func clearFromMenu() { onClear?(index) }
}

/// Cabeçalho de workspace ou de projeto na árvore da barra (ADR-043).
///
/// Clique recolhe ou abre; o menu de contexto carrega as ações do nível. O
/// badge só aparece recolhido: aberto, cada bancada fala por si.
///
/// Projeto e bancada têm a MESMA altura e a mesma anatomia — ícone à esquerda,
/// nome em cima, caminho embaixo — para o card ler como uma lista de coisas do
/// mesmo tipo, e não como cabeçalho mais rodapé.
final class SidebarGroupRow: NSView {
    let item: SidebarItem
    private let badge: WorkspaceBadge?
    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    /// Quantos itens moram aqui — projetos no workspace, bancadas no projeto.
    /// A pastilha monta no canto do ícone, como um selo: ao lado do nome ela
    /// comia o título, que é o que se lê para achar a coisa.
    private let countLabel = CountSeal()
    /// Criar bancada direto do projeto, sem passar pelo botão direito.
    private var addButton: ToolbarButton?
    private var lastBadge = ""

    var onToggle: ((SidebarItem) -> Void)?
    var onCreateWorkbench: ((_ projectID: String) -> Void)?
    var onCreateWorkbenchFromWorktree: ((_ projectID: String) -> Void)?
    var onEditWorkspace: ((_ workspaceID: String) -> Void)?
    var onRemoveWorkspace: ((_ workspaceID: String) -> Void)?
    var onRemoveProject: ((_ workspaceID: String, _ projectID: String) -> Void)?

    private(set) var isCollapsed = false
    /// Quantos itens o nível tem; zero não mostra pastilha — vazio já se vê.
    private var count = 0
    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            nameLabel.isHidden = isCompact
            pathLabel.isHidden = isCompact
            chevron.isHidden = isCompact
            addButton?.isHidden = isCompact
            icon.isHidden = isCompact || badge != nil
            lastBadge = ""
            needsLayout = true
        }
    }

    /// Uma altura só para tudo que é linha: cabeçalho de workspace, de projeto
    /// e a bancada. É o que faz a árvore parecer feita de peças iguais.
    static let height: CGFloat = 44
    static let badgeSide: CGFloat = 28

    var isWorkspace: Bool { if case .workspace = item { return true } else { return false } }

    init(workspace: WorkspaceConfig, workbenches: Int) {
        item = .workspace(id: workspace.id)
        badge = WorkspaceBadge(side: Self.badgeSide)
        isCollapsed = workspace.isCollapsed
        super.init(frame: .zero)
        badge?.show(workspace)
        nameLabel.stringValue = workspace.name
        nameLabel.font = .systemFont(ofSize: 13, weight: .bold)
        nameLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        count = workspace.projects.count
        // A contagem de projetos subiu para a pastilha; o subtítulo passa a
        // dizer o que ela não diz — quanto trabalho há embaixo, somado.
        pathLabel.stringValue = workbenches == 1 ? "1 bancada" : "\(workbenches) bancadas"
        pathLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.42)
        setup()
    }

    /// Projeto guardado: o menu oferece o caminho de volta, e vice-versa.
    private var isStoredProject = false
    /// Só cria em worktree: o + vai direto ao formulário, sem menu.
    private var requiresWorktree = false

    /// `joins` são os nomes dos projetos que um multi-projeto junta: é o que o
    /// subtítulo dele mostra no lugar da pasta de links, que não diz nada.
    init(workspaceID: String, project: ProjectConfig, workbenches: Int, joins: [String] = []) {
        item = .project(workspaceID: workspaceID, id: project.id)
        badge = nil
        isCollapsed = project.isCollapsed
        super.init(frame: .zero)
        nameLabel.stringValue = project.name
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.8)
        pathLabel.stringValue = project.isMulti
            ? (joins.isEmpty ? "nenhuma pasta" : joins.joined(separator: " + "))
            : project.exists
            ? (project.path as NSString).abbreviatingWithTildeInPath
            : "caminho não existe — \(project.path)"
        pathLabel.textColor = project.exists
            ? NSColor(calibratedWhite: 1, alpha: 0.42)
            : NSColor.systemRed.withAlphaComponent(0.85)
        count = workbenches
        isStoredProject = project.isStored
        requiresWorktree = project.requiresWorktree
        icon.image = ToolbarButton.symbol(project.isStored
            ? ["archivebox.fill", "archivebox", "folder"]
            : project.isMulti ? ["square.stack.3d.up.fill", "folder.fill"] : ["folder.fill", "folder"])
        icon.contentTintColor = NSColor(calibratedWhite: 1, alpha: project.isStored ? 0.32 : 0.5)
        let add = ToolbarButton(symbols: ["plus"],
                                tooltip: project.requiresWorktree ? "Nova bancada em worktree"
                                                                  : "Nova bancada neste projeto",
                                size: 20)
        add.onClick = { [weak self] in self?.showCreateMenu() }
        addButton = add
        setup()
    }

    init(orphans: Int) {
        item = .orphans
        badge = nil
        super.init(frame: .zero)
        nameLabel.stringValue = "Sem projeto"
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = NSColor.systemOrange.withAlphaComponent(0.9)
        pathLabel.stringValue = "\(orphans) bancada(s) com projeto que não existe"
        pathLabel.textColor = NSColor.systemOrange.withAlphaComponent(0.6)
        icon.image = ToolbarButton.symbol(["questionmark.folder", "folder"])
        icon.contentTintColor = NSColor.systemOrange.withAlphaComponent(0.7)
        chevron.isHidden = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        if let badge { addSubview(badge) } else { addSubview(icon) }
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(pathLabel)
        chevron.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.4)
        chevron.imageScaling = .scaleProportionallyDown
        refreshChevron()
        addSubview(chevron)
        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        statusLabel.alignment = .right
        addSubview(statusLabel)
        countLabel.value = count
        countLabel.isHidden = count == 0
        addSubview(countLabel)
        if let addButton { addSubview(addButton) }
    }

    private func refreshChevron() {
        chevron.image = ToolbarButton.symbol([isCollapsed ? "chevron.right" : "chevron.down"])
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        if isCompact {
            if let badge {
                let side = Self.badgeSide
                badge.frame = NSRect(x: ((bounds.width - side) / 2).rounded(), y: midY - side / 2,
                                     width: side, height: side)
            }
            statusLabel.frame = .zero
            countLabel.isHidden = true
            return
        }
        countLabel.isHidden = count == 0
        var x: CGFloat = 10
        if let badge {
            let side = Self.badgeSide
            badge.frame = NSRect(x: x, y: midY - side / 2, width: side, height: side)
            x += side + 10
        } else {
            icon.frame = NSRect(x: x + 2, y: midY - 8, width: 16, height: 16)
            x += 28
        }
        var right = bounds.width - 10
        if !chevron.isHidden {
            chevron.frame = NSRect(x: right - 12, y: midY - 6, width: 12, height: 12)
            right -= 18
        }
        if let addButton {
            addButton.frame = NSRect(x: right - 20, y: midY - 10, width: 20, height: 20)
            right -= 24
        }
        let badgeWidth: CGFloat = statusLabel.attributedStringValue.length == 0
            ? 0 : ceil(statusLabel.attributedStringValue.size().width) + 8
        statusLabel.frame = NSRect(x: right - badgeWidth, y: midY - 8, width: badgeWidth, height: 16)
        right -= badgeWidth
        // A pastilha anda com o nome: encostada nele, e o nome encolhe antes
        // dela — a contagem é curta e não pode ser o que some.
        // O selo monta no canto do ícone; o título fica com a linha inteira.
        if !countLabel.isHidden {
            let anchor = badge?.frame ?? icon.frame
            let size = countLabel.size
            countLabel.frame = NSRect(x: anchor.maxX - size.width + 6,
                                      y: anchor.maxY - size.height + 6,
                                      width: size.width, height: size.height)
        }
        let available = max(0, right - x - 4)
        nameLabel.frame = NSRect(x: x, y: 7, width: available, height: 17)
        pathLabel.frame = NSRect(x: x, y: 24, width: available, height: 13)
    }

    /// Resumo do que está embaixo, só quando recolhido: aberto, quem avisa são
    /// as linhas das bancadas.
    func show(_ summary: ActivitySummary) {
        let visible = isCollapsed || isCompact
        let signature = visible
            ? "\(summary.working + summary.starting)/\(summary.background)/"
                + "\(summary.attention)/\(summary.done)/"
                + (summary.working + summary.starting > 0 ? String(Spinner.current) : "")
                + (summary.background > 0 ? String(Spinner.hourglass) : "")
            : ""
        guard signature != lastBadge else { return }
        lastBadge = signature
        badge?.wantsAttention = visible && summary.attention > 0

        let text = NSMutableAttributedString()
        func add(_ glyph: String, _ count: Int, _ color: NSColor) {
            guard count > 0 else { return }
            if text.length > 0 { text.append(NSAttributedString(string: " ")) }
            text.append(NSAttributedString(
                string: count > 1 ? "\(glyph)\(count)" : glyph,
                attributes: [.foregroundColor: color,
                             .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]))
        }
        if visible, !isCompact {
            add(String(Spinner.current), summary.working + summary.starting,
                NSColor(calibratedWhite: 1, alpha: 0.45))
            add(String(Spinner.hourglass), summary.background,
                NSColor(calibratedWhite: 1, alpha: 0.45))
            add("●", summary.attention, .systemOrange)
            add("●", summary.done, .systemGreen)
        }
        statusLabel.attributedStringValue = text
        needsLayout = true
    }

    override func resetCursorRects() {
        // A pilha de órfãs é rótulo, não linha: não abre nem fecha.
        if case .orphans = item { return }
        HandCursor.fill(self)
    }

    var onDrag: ((SidebarDrag) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if case .orphans = item { return }
        SidebarDrag.track(event, in: self, item: item, drag: onDrag) { [weak self] in
            guard let self else { return }
            self.onToggle?(self.item)
        }
    }

    private func showCreateMenu() {
        guard case .project = item, let addButton else { return }
        guard !requiresWorktree else { return createWorkbenchFromWorktree() }
        let menu = NSMenu()
        menu.addItem(withTitle: "Nova bancada…", action: #selector(createWorkbench), keyEquivalent: "")
        menu.addItem(withTitle: "Nova bancada em worktree…",
                     action: #selector(createWorkbenchFromWorktree), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: addButton.frame.minX, y: addButton.frame.maxY + 4), in: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        switch item {
        case .workspace:
            menu.addItem(withTitle: "Editar workspace…", action: #selector(editWorkspace),
                         keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Remover workspace…", action: #selector(removeWorkspace),
                         keyEquivalent: "")
        case .project:
            if !requiresWorktree {
                menu.addItem(withTitle: "Nova bancada…", action: #selector(createWorkbench),
                             keyEquivalent: "")
            }
            menu.addItem(withTitle: "Nova bancada em worktree…",
                         action: #selector(createWorkbenchFromWorktree), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: isStoredProject ? "Tirar da gaveta" : "Guardar na gaveta",
                         action: #selector(toggleStored), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Tirar projeto do workspace…", action: #selector(removeProject),
                         keyEquivalent: "")
        case .workbench, .orphans:
            return nil
        }
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func editWorkspace() {
        if case .workspace(let id) = item { onEditWorkspace?(id) }
    }
    @objc private func removeWorkspace() {
        if case .workspace(let id) = item { onRemoveWorkspace?(id) }
    }
    @objc private func createWorkbench() {
        if case .project(_, let id) = item { onCreateWorkbench?(id) }
    }
    @objc private func createWorkbenchFromWorktree() {
        if case .project(_, let id) = item { onCreateWorkbenchFromWorktree?(id) }
    }
    /// Guardar e desguardar pelo menu — o arrasto faz o mesmo, mas menu é o
    /// que se acha sem adivinhar.
    var onToggleStored: ((_ workspaceID: String, _ projectID: String, _ stored: Bool) -> Void)?

    @objc private func toggleStored() {
        guard case .project(let workspaceID, let id) = item else { return }
        onToggleStored?(workspaceID, id, !isStoredProject)
    }

    @objc private func removeProject() {
        if case .project(let ws, let id) = item { onRemoveProject?(ws, id) }
    }
}

/// O card de um workspace, e dentro dele o tile de cada projeto — o
/// `ExpansionTile` aninhado: cabeçalho em cima, filhos por dentro do mesmo
/// contorno, para o que é de um workspace parecer de fato separado do que é
/// do outro.
final class SidebarCard: NSView {
    init(radius: CGFloat, fill: CGFloat, stroke: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: fill).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: stroke).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
}

/// Documento da rolagem: virado, como o resto da barra.
final class SidebarList: NSView {
    override var isFlipped: Bool { true }
}

final class Sidebar: NSView {
    /// Cabeçalho curto porque a barra agora flutua: os botões da janela ficam
    /// FORA dela, e não há mais o que desviar aqui dentro.
    static let headerHeight: CGFloat = 34
    /// Nome, caminho e até três indicadores com contagem cabem sem cortar.
    static let expandedWidth: CGFloat = 292
    /// Largura do trilho recolhido: cabe a pastilha de 26pt com folga, e é o que
    /// o conteúdo reserva de gutter — o que se abre além disso flutua por cima.
    static let railWidth: CGFloat = 52
    private static let rowHeight = SidebarGroupRow.height
    /// Folga entre cards e entre peças dentro de um card.
    private static let cardGap: CGFloat = 8
    private static let cardInset: CGFloat = 6
    private static let rowGap: CGFloat = 2
    /// O fio do projeto e o respiro que ele ocupa (1pt de linha + folga).
    private static let dividerGap: CGFloat = 7

    /// Trilho recolhido. Propagado às linhas, que trocam nome por pastilha; os
    /// projetos e os cards somem — no trilho a hierarquia é workspace → bancada.
    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            rows.forEach { $0.isCompact = isCompact }
            groups.forEach { $0.isCompact = isCompact }
            title.isHidden = isCompact
            emptyLabel.isHidden = isCompact || !rows.isEmpty
            // O + sai do trilho: criar abre um menu, e menu saindo de uma faixa
            // de 52pt cai por cima dos cards. Você abre a barra e cria.
            addButton.isHidden = isCompact
            collapseButton.setSymbols(
                isCompact ? ["sidebar.trailing", "chevron.right"]
                          : ["sidebar.leading", "chevron.left"],
                tooltip: isCompact ? "Abrir a barra (⌘/)" : "Recolher a barra (⌘/)")
            needsLayout = true
        }
    }

    /// A árvore montada: card por workspace, tile por projeto, linhas dentro.
    struct ProjectTile {
        let tile: SidebarCard
        let header: SidebarGroupRow
        /// Fio entre o cabeçalho do projeto e as bancadas dele: sem ele, nome
        /// do projeto e nome da bancada viram uma lista só.
        let divider: NSView
        let rows: [SidebarRow]
        /// `nil` no tile dos órfãos: ele não é projeto, e nada cai nele.
        var projectID: String?
    }
    struct WorkspaceCard {
        let card: SidebarCard
        let header: SidebarGroupRow
        /// Os projetos em uso; os guardados ficam na gaveta.
        let projects: [ProjectTile]
        let drawer: DrawerRow
        let stored: [ProjectTile]
        let workspaceID: String

        /// Tudo que a queda pode acertar, dos dois lados da gaveta.
        var allProjects: [ProjectTile] { projects + stored }
    }
    var cards: [WorkspaceCard] = []
    private var orphanTile: ProjectTile?
    /// A linha arrastada agora, e a guia que mostra onde ela cai.
    var dragged: SidebarItem?
    let dropLine: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        view.layer?.cornerRadius = 1
        return view
    }()

    private var rows: [SidebarRow] = []
    private var groups: [SidebarGroupRow] = []
    private var tree = WorkspaceTree(workspaces: [], workbenches: [])
    private let scroll = NSScrollView()
    private let list = SidebarList()
    private let title = NSTextField(labelWithString: "WORKSPACES")
    private let addButton = ToolbarButton(symbols: ["plus"], tooltip: "Novo workspace ou bancada", size: 22)
    private let collapseButton = ToolbarButton(symbols: ["sidebar.leading", "chevron.left"],
                                               tooltip: "Recolher a barra (⌘/)", size: 22)
    private let emptyLabel = NSTextField(labelWithString: "")

    var onSelect: ((Int) -> Void)?
    var onToggleCollapse: (() -> Void)?
    /// Bancada por pasta livre, sem projeto escolhido: o app acha o projeto.
    var onCreate: (() -> Void)?
    var onCreateFromWorktree: (() -> Void)?
    /// Bancada dentro de um projeto: a pasta já está decidida.
    var onCreateInProject: ((_ projectID: String) -> Void)?
    var onCreateFromWorktreeInProject: ((_ projectID: String) -> Void)?
    var onCreateWorkspace: (() -> Void)?
    var onEditWorkspace: ((_ workspaceID: String) -> Void)?
    var onRemoveWorkspace: ((_ workspaceID: String) -> Void)?
    var onRemoveProject: ((_ workspaceID: String, _ projectID: String) -> Void)?
    /// Guardar o projeto na gaveta do workspace, ou tirá-lo de lá (ADR-052).
    var onToggleStored: ((_ workspaceID: String, _ projectID: String, _ stored: Bool) -> Void)?
    /// Abrir ou fechar a gaveta de um workspace.
    var onToggleDrawer: ((_ workspaceID: String) -> Void)?
    var onToggleGroup: ((SidebarItem) -> Void)?
    /// Reposicionar arrastando (ADR-051): item, pai de destino e posição.
    var onMoveWorkspace: ((_ id: String, _ position: Int) -> Void)?
    var onMoveProject: ((_ id: String, _ workspaceID: String, _ position: Int,
                         _ stored: Bool) -> Void)?
    var onMoveWorkbench: ((_ index: Int, _ projectID: String, _ position: Int) -> Void)?
    var onRename: ((Int) -> Void)?
    var onDuplicateAsWorktree: ((Int) -> Void)?
    var onRemove: ((Int) -> Void)?
    var onEditVisitLimit: ((Int) -> Void)?
    var onEditRules: ((Int) -> Void)?
    /// "Limpar a bancada": `clear` em todo agente e o chat arquivado (ADR-037).
    var onClear: ((Int) -> Void)?

    init(workspaces: [WorkspaceConfig], configs: [WorkbenchConfig]) {
        super.init(frame: .zero)
        wantsLayer = true
        // Sem fundo próprio: quem pinta é o `GlassPanel` que a envolve. Chapa
        // opaca aqui apagaria o vidro por dentro.
        layer?.backgroundColor = NSColor.clear.cgColor

        title.font = .systemFont(ofSize: 10, weight: .bold)
        title.textColor = NSColor(calibratedWhite: 1, alpha: 0.42)
        addSubview(title)

        // Menu, e não ação direta: as rotas terminam no mesmo lugar (algo novo na
        // árvore), então pertencem ao mesmo botão.
        addButton.onClick = { [weak self] in self?.showCreateMenu() }
        addSubview(addButton)

        collapseButton.onClick = { [weak self] in self?.onToggleCollapse?() }
        addSubview(collapseButton)

        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.45)
        emptyLabel.stringValue = "Nenhuma bancada.\nUse + para criar,\nvazia ou de um template."
        emptyLabel.maximumNumberOfLines = 0

        // Rolagem porque a árvore cresce: três workspaces com dois projetos cada
        // já passam da altura de uma janela pequena.
        scroll.documentView = list
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed
        scroll.horizontalScrollElasticity = .none
        addSubview(scroll)
        list.addSubview(emptyLabel)

        reload(workspaces: workspaces, configs: configs)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Recria as linhas. Bancadas, projetos e workspaces mudam em tempo de
    /// execução, então a barra não pode ser montada só uma vez no init.
    func reload(workspaces: [WorkspaceConfig], configs: [WorkbenchConfig]) {
        list.subviews.filter { $0 !== emptyLabel }.forEach { $0.removeFromSuperview() }
        rows = []
        groups = []
        cards = []
        orphanTile = nil
        tree = WorkspaceTree(workspaces: workspaces, workbenches: configs)

        func row(_ index: Int) -> SidebarRow {
            let row = SidebarRow(index: index, config: configs[index])
            row.onClick = { [weak self] in self?.onSelect?($0) }
            row.onDrag = { [weak self] in self?.handle($0) }
            row.onRename = { [weak self] in self?.onRename?($0) }
            row.onDuplicateAsWorktree = { [weak self] in self?.onDuplicateAsWorktree?($0) }
            row.onRemove = { [weak self] in self?.onRemove?($0) }
            row.onEditVisitLimit = { [weak self] in self?.onEditVisitLimit?($0) }
            row.onEditRules = { [weak self] in self?.onEditRules?($0) }
            row.onClear = { [weak self] in self?.onClear?($0) }
            rows.append(row)
            return row
        }

        // O card entra na hierarquia ANTES do que vai dentro: é fundo, e um
        // fundo por cima engoliria os cliques das linhas.
        for space in workspaces {
            let card = SidebarCard(radius: 12, fill: 0.045, stroke: 0.09)
            list.addSubview(card)
            let header = SidebarGroupRow(workspace: space,
                                         workbenches: tree.indices(inWorkspace: space.id).count)
            wire(header)
            groups.append(header)
            list.addSubview(header)
            func tile(for project: ProjectConfig) -> ProjectTile {
                let tile = SidebarCard(radius: 9, fill: 0.04, stroke: 0.06)
                list.addSubview(tile)
                let members = tree.indices(inProject: project.id)
                let head = SidebarGroupRow(workspaceID: space.id, project: project,
                                           workbenches: members.count,
                                           joins: space.members(of: project).map(\.name))
                wire(head)
                groups.append(head)
                list.addSubview(head)
                let line = Self.makeDivider()
                list.addSubview(line)
                let rowsOfProject = members.map(row)
                rowsOfProject.forEach { list.addSubview($0) }
                return ProjectTile(tile: tile, header: head, divider: line,
                                   rows: rowsOfProject, projectID: project.id)
            }

            let active = space.activeProjects.map(tile)
            let stored = space.storedProjects
            // A gaveta aparece SEMPRE, mesmo vazia: é o alvo para onde se
            // arrasta o primeiro projeto, e sem ela guardar não teria onde
            // começar.
            let drawer = DrawerRow(count: stored.count, open: space.isStoredOpen)
            drawer.onClick = { [weak self] in self?.onToggleDrawer?(space.id) }
            list.addSubview(drawer)
            // Os tiles guardados nascem montados mesmo com a gaveta fechada: é
            // o layout que os esconde, e assim abrir não remonta a barra.
            let storedTiles = stored.map(tile)
            cards.append(WorkspaceCard(card: card, header: header, projects: active,
                                       drawer: drawer, stored: storedTiles,
                                       workspaceID: space.id))
        }

        let lost = tree.orphans
        if !lost.isEmpty {
            let tile = SidebarCard(radius: 12, fill: 0.03, stroke: 0.08)
            tile.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.35).cgColor
            list.addSubview(tile)
            let head = SidebarGroupRow(orphans: lost.count)
            groups.append(head)
            list.addSubview(head)
            let members = lost.map(row)
            members.forEach { list.addSubview($0) }
            let line = Self.makeDivider()
            list.addSubview(line)
            orphanTile = ProjectTile(tile: tile, header: head, divider: line, rows: members,
                                     projectID: nil)
        }

        rows.forEach { $0.isCompact = isCompact }
        groups.forEach { $0.isCompact = isCompact }
        emptyLabel.isHidden = isCompact || !configs.isEmpty
        needsLayout = true
    }

    private static func makeDivider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
        return line
    }

    private func wire(_ group: SidebarGroupRow) {
        group.onToggle = { [weak self] in self?.onToggleGroup?($0) }
        group.onDrag = { [weak self] in self?.handle($0) }
        group.onCreateWorkbench = { [weak self] in self?.onCreateInProject?($0) }
        group.onCreateWorkbenchFromWorktree = { [weak self] in self?.onCreateFromWorktreeInProject?($0) }
        group.onEditWorkspace = { [weak self] in self?.onEditWorkspace?($0) }
        group.onRemoveWorkspace = { [weak self] in self?.onRemoveWorkspace?($0) }
        group.onRemoveProject = { [weak self] in self?.onRemoveProject?($0, $1) }
        group.onToggleStored = { [weak self] in self?.onToggleStored?($0, $1, $2) }
    }

    override func layout() {
        super.layout()
        if isCompact {
            collapseButton.frame = NSRect(x: ((bounds.width - 22) / 2).rounded(), y: 8,
                                          width: 22, height: 22)
        } else {
            title.frame = NSRect(x: 16, y: 12, width: bounds.width - 84, height: 14)
            addButton.frame = NSRect(x: bounds.width - 60, y: 8, width: 22, height: 22)
            collapseButton.frame = NSRect(x: bounds.width - 32, y: 8, width: 22, height: 22)
        }
        scroll.frame = NSRect(x: 0, y: Self.headerHeight, width: bounds.width,
                              height: max(0, bounds.height - Self.headerHeight))
        emptyLabel.frame = NSRect(x: 16, y: 8, width: bounds.width - 32, height: 56)

        let y = isCompact ? layoutRail() : layoutCards()
        list.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(y + 8, scroll.bounds.height))
    }

    /// Expandido: card por workspace, tile por projeto, linhas dentro do tile.
    private func layoutCards() -> CGFloat {
        let inset = Self.cardInset
        let outer: CGFloat = 8
        var y: CGFloat = 2

        func hide(_ tile: ProjectTile) {
            tile.tile.isHidden = true
            tile.header.isHidden = true
            tile.divider.isHidden = true
            tile.rows.forEach { $0.isHidden = true }
        }

        func layoutTile(_ tile: ProjectTile, x: CGFloat, width: CGFloat, y: inout CGFloat,
                        expanded: Bool) {
            tile.tile.isHidden = false
            let top = y
            tile.header.isHidden = false
            tile.header.frame = NSRect(x: x, y: y, width: width, height: Self.rowHeight)
            y += Self.rowHeight
            tile.divider.isHidden = !expanded || tile.rows.isEmpty
            if !tile.divider.isHidden {
                tile.divider.frame = NSRect(x: x + inset, y: y, width: width - inset * 2, height: 1)
                y += Self.dividerGap
            }
            if expanded {
                for row in tile.rows {
                    row.isHidden = false
                    row.frame = NSRect(x: x + inset, y: y, width: width - inset * 2,
                                       height: Self.rowHeight)
                    y += Self.rowHeight + Self.rowGap
                }
                if !tile.rows.isEmpty { y += inset - Self.rowGap }
            } else {
                tile.rows.forEach { $0.isHidden = true }
            }
            tile.tile.frame = NSRect(x: x, y: top, width: width, height: y - top)
        }

        for card in cards {
            let top = y
            let width = bounds.width - outer * 2
            card.card.isHidden = false
            card.header.frame = NSRect(x: outer, y: y, width: width, height: Self.rowHeight)
            y += Self.rowHeight
            if card.header.isCollapsed {
                card.drawer.isHidden = true
                for tile in card.allProjects { hide(tile) }
            } else {
                for tile in card.projects {
                    layoutTile(tile, x: outer + inset, width: width - inset * 2, y: &y,
                               expanded: !tile.header.isCollapsed)
                    y += Self.cardGap - 2
                }
                if !card.projects.isEmpty { y += inset - (Self.cardGap - 2) }
                let drawer = card.drawer
                drawer.isHidden = false
                drawer.frame = NSRect(x: outer + inset, y: y, width: width - inset * 2,
                                      height: DrawerRow.height)
                y += DrawerRow.height
                if drawer.isOpen, !card.stored.isEmpty {
                    y += 2
                    for tile in card.stored {
                        layoutTile(tile, x: outer + inset, width: width - inset * 2, y: &y,
                                   expanded: !tile.header.isCollapsed)
                        y += Self.cardGap - 2
                    }
                    y += inset - (Self.cardGap - 2)
                } else {
                    for tile in card.stored { hide(tile) }
                    y += inset
                }
            }
            card.card.frame = NSRect(x: outer, y: top, width: width, height: y - top)
            y += Self.cardGap
        }

        if let orphanTile {
            layoutTile(orphanTile, x: outer, width: bounds.width - outer * 2, y: &y, expanded: true)
            y += Self.cardGap
        }
        return y
    }

    /// Trilho: a pastilha do workspace e, sob ela, as pastilhas das bancadas.
    /// Projeto e cards não aparecem — 52pt não têm onde pôr hierarquia.
    private func layoutRail() -> CGFloat {
        var y: CGFloat = 0
        let width = bounds.width - 4
        func rail(_ tiles: [ProjectTile], collapsed: Bool) {
            for tile in tiles {
                tile.tile.isHidden = true
                tile.header.isHidden = true
                tile.divider.isHidden = true
                for row in tile.rows {
                    row.isHidden = collapsed
                    guard !collapsed else { continue }
                    row.frame = NSRect(x: 2, y: y, width: width, height: Self.rowHeight)
                    y += Self.rowHeight + Self.rowGap
                }
            }
        }
        for card in cards {
            card.card.isHidden = true
            card.drawer.isHidden = true
            card.header.frame = NSRect(x: 2, y: y, width: width, height: Self.rowHeight)
            y += Self.rowHeight
            rail(card.allProjects, collapsed: card.header.isCollapsed)
            y += 6
        }
        if let orphanTile { rail([orphanTile], collapsed: false) }
        return y
    }

    private func showCreateMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Novo workspace…", action: #selector(createWorkspace), keyEquivalent: "")
        menu.addItem(.separator())
        // Por pasta livre: o app acha o projeto pela pasta — ou cria um. Continua
        // aqui porque é o atalho de quem ainda não desenhou workspace nenhum.
        menu.addItem(withTitle: "Nova bancada…", action: #selector(createPlain), keyEquivalent: "")
        menu.addItem(withTitle: "Nova bancada a partir de worktree…",
                     action: #selector(createFromWorktree), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: addButton.frame.minX, y: addButton.frame.maxY + 4),
                   in: self)
    }

    @objc private func createWorkspace() { onCreateWorkspace?() }
    @objc private func createPlain() { onCreate?() }
    @objc private func createFromWorktree() { onCreateFromWorktree?() }

    func select(_ index: Int) {
        for row in rows { row.isSelected = (row.index == index) }
    }

    /// Chamado pelo laço da UI com o resumo de TODAS as bancadas vivas, não só a
    /// que está na tela. Os grupos somam o que têm embaixo.
    func showActivity(_ summaries: [String: ActivitySummary]) {
        for row in rows { row.show(summaries[row.name] ?? ActivitySummary()) }
        for group in groups {
            let members: [Int]
            switch group.item {
            case .workspace(let id): members = tree.indices(inWorkspace: id)
            case .project(_, let id): members = tree.indices(inProject: id)
            case .orphans: members = tree.orphans
            case .workbench: members = []
            }
            var total = ActivitySummary()
            for index in members where index < tree.workbenches.count {
                guard let s = summaries[tree.workbenches[index].name] else { continue }
                total.starting += s.starting
                total.working += s.working
                total.background += s.background
                total.attention += s.attention
                total.done += s.done
            }
            group.show(total)
        }
    }

    func markLive(_ index: Int) {
        rows.first { $0.index == index }?.isLive = true
    }

    func markLive(indices: Set<Int>) {
        for row in rows { row.isLive = indices.contains(row.index) }
    }

    func markRemoving(indices: Set<Int>) {
        for row in rows { row.isRemoving = indices.contains(row.index) }
    }
}

// MARK: - Arrastar para reposicionar (ADR-051)

/// Um passo do arrasto de uma linha da barra. O laço é da linha; quem decide
/// onde aquilo cai é a `Sidebar`, que é a única que conhece a árvore inteira.
struct SidebarDrag {
    enum Phase { case began, moved, ended, cancelled }
    let phase: Phase
    let item: SidebarItem
    /// Onde o mouse está, em coordenadas da janela.
    let point: NSPoint

    /// Mantido como nome público daqui; o valor é o do `PressDrag`.
    static var threshold: CGFloat { PressDrag.threshold }

    /// O laço é o `PressDrag`, dividido com a faixa de abas; aqui só se traduz a
    /// carga para o que a barra lateral entende.
    static func track(_ event: NSEvent, in view: NSView, item: SidebarItem,
                      drag: ((SidebarDrag) -> Void)?, click: @escaping () -> Void) {
        PressDrag.track(event, in: view, payload: item, drag: drag.map { report in
            { (step: PressDrag.Step<SidebarItem>) in
                let phase: Phase
                switch step.phase {
                case .began:     phase = .began
                case .moved:     phase = .moved
                case .ended:     phase = .ended
                case .cancelled: phase = .cancelled
                }
                report(SidebarDrag(phase: phase, item: step.payload, point: step.point))
            }
        }, click: click)
    }
}

extension Sidebar {
    /// Onde uma linha arrastada cai: sempre "dentro de um pai, nesta posição".
    enum Drop: Equatable {
        case workspace(position: Int)
        /// `stored` diz de que lado da gaveta o projeto cai (ADR-052).
        case project(workspaceID: String, position: Int, stored: Bool)
        case workbench(projectID: String, position: Int)
    }

    /// O alvo para um ponto em coordenadas da lista. Quem arrasta decide o
    /// tipo: bancada só cai em projeto, projeto só em workspace, e workspace
    /// entre workspaces — a árvore não muda de forma no arrasto.
    func drop(for item: SidebarItem, at point: NSPoint) -> Drop? {
        switch item {
        case .workbench(let index):
            guard let tile = tileHit(point) else { return nil }
            let rows = tile.tile.rows.filter { !$0.isHidden }
            var position = rows.filter { point.y > $0.frame.midY }.count
            // Tirar a própria linha da conta: sem isso, arrastar para baixo
            // dentro do mesmo projeto para uma posição antes da desejada.
            if let mine = rows.firstIndex(where: { $0.index == index }),
               position > mine { position -= 1 }
            return .workbench(projectID: tile.projectID, position: position)
        case .project(_, let id):
            guard let card = cardHit(point) else { return nil }
            // Abaixo da tampa da gaveta é dentro dela — é assim que se guarda
            // um projeto: arrastando para lá.
            let stored = point.y > card.card.drawer.frame.midY
            let side = stored ? card.card.stored : card.card.projects
            let tiles = side.filter { !$0.tile.isHidden }
            var position = tiles.filter { point.y > $0.tile.frame.midY }.count
            if let mine = tiles.firstIndex(where: { $0.projectID == id }), position > mine {
                position -= 1
            }
            return .project(workspaceID: card.workspaceID, position: position, stored: stored)
        case .workspace(let id):
            let visible = cards.filter { !$0.card.isHidden }
            var position = visible.filter { point.y > $0.card.frame.midY }.count
            if let mine = visible.firstIndex(where: { $0.workspaceID == id }), position > mine {
                position -= 1
            }
            return .workspace(position: position)
        case .orphans:
            return nil
        }
    }

    private func tileHit(_ point: NSPoint) -> (projectID: String, tile: ProjectTile)? {
        for card in cards where !card.card.isHidden {
            for tile in card.allProjects where !tile.tile.isHidden {
                if tile.tile.frame.insetBy(dx: 0, dy: -Self.cardGap / 2).contains(point),
                   let id = tile.projectID {
                    return (id, tile)
                }
            }
        }
        return nil
    }

    private func cardHit(_ point: NSPoint) -> (workspaceID: String, card: WorkspaceCard)? {
        for card in cards where !card.card.isHidden {
            if card.card.frame.insetBy(dx: 0, dy: -Self.cardGap / 2).contains(point) {
                return (card.workspaceID, card)
            }
        }
        return nil
    }

    /// O laço do arrasto, vindo de qualquer linha.
    func handle(_ drag: SidebarDrag) {
        let point = list.convert(drag.point, from: nil)
        switch drag.phase {
        case .began:
            dragged = drag.item
            list.addSubview(dropLine)
            viewFor(drag.item)?.alphaValue = 0.5
        case .moved:
            guard dragged != nil else { return }
            showDropLine(for: drag.item, at: point)
        case .cancelled:
            viewFor(drag.item)?.alphaValue = 1
            dragged = nil
            dropLine.removeFromSuperview()
        case .ended:
            viewFor(drag.item)?.alphaValue = 1
            dragged = nil
            dropLine.removeFromSuperview()
            guard let target = drop(for: drag.item, at: point) else { return }
            switch (drag.item, target) {
            case (.workspace(let id), .workspace(let position)):
                onMoveWorkspace?(id, position)
            case (.project(_, let id), .project(let workspaceID, let position, let stored)):
                onMoveProject?(id, workspaceID, position, stored)
            case (.workbench(let index), .workbench(let projectID, let position)):
                onMoveWorkbench?(index, projectID, position)
            default:
                break
            }
        }
    }

    /// A view da linha que está sendo arrastada, para desbotá-la.
    private func viewFor(_ item: SidebarItem) -> NSView? {
        switch item {
        case .workbench(let index):
            return cards.flatMap { $0.projects }.flatMap { $0.rows }.first { $0.index == index }
        case .project(let workspaceID, let id):
            return cards.first { $0.workspaceID == workspaceID }?
                .allProjects.first { $0.projectID == id }?.header
        case .workspace(let id):
            return cards.first { $0.workspaceID == id }?.header
        case .orphans:
            return nil
        }
    }

    /// A linha que mostra onde vai cair.
    private func showDropLine(for item: SidebarItem, at point: NSPoint) {
        guard let target = drop(for: item, at: point), let frame = lineFrame(for: target) else {
            dropLine.isHidden = true
            return
        }
        dropLine.isHidden = false
        dropLine.frame = frame
    }

    private func lineFrame(for target: Drop) -> NSRect? {
        func between(_ frames: [NSRect], _ position: Int, x: CGFloat, width: CGFloat) -> NSRect? {
            guard !frames.isEmpty || position == 0 else { return nil }
            let y: CGFloat
            if frames.isEmpty { return nil }
            else if position >= frames.count { y = frames[frames.count - 1].maxY }
            else { y = frames[position].minY }
            return NSRect(x: x, y: y - 1, width: width, height: 2)
        }
        switch target {
        case .workspace(let position):
            let frames = cards.filter { !$0.card.isHidden }.map { $0.card.frame }
            return between(frames, position, x: 8, width: bounds.width - 16)
        case .project(let workspaceID, let position, let stored):
            guard let card = cards.first(where: { $0.workspaceID == workspaceID }) else { return nil }
            let side = stored ? card.stored : card.projects
            let tiles = side.filter { !$0.tile.isHidden }.map { $0.tile.frame }
            let x = card.card.frame.minX + Self.cardInset
            let width = card.card.frame.width - Self.cardInset * 2
            guard let frame = between(tiles, position, x: x, width: width) else {
                // Gaveta fechada ou vazia: a guia encosta na tampa dela.
                return NSRect(x: x, y: card.drawer.frame.maxY - 1, width: width, height: 2)
            }
            return frame
        case .workbench(let projectID, let position):
            guard let tile = cards.flatMap({ $0.projects }).first(where: { $0.projectID == projectID })
            else { return nil }
            let rows = tile.rows.filter { !$0.isHidden }.map { $0.frame }
            guard let frame = between(rows, position, x: tile.tile.frame.minX + Self.cardInset,
                                      width: tile.tile.frame.width - Self.cardInset * 2)
            else {
                // Projeto vazio: a linha vai logo abaixo do cabeçalho dele.
                let header = tile.header.frame
                return NSRect(x: header.minX + Self.cardInset, y: header.maxY - 1,
                              width: header.width - Self.cardInset * 2, height: 2)
            }
            return frame
        }
    }
}

// MARK: - Selo de contagem

/// O número de itens de um nível, montado no canto do ícone.
///
/// View desenhada, e não `NSTextField` com fundo: o rótulo centra o texto na
/// caixa dele, que não é a caixa do glifo — o dígito ficava visivelmente fora
/// do centro do círculo. Aqui o número é centrado pela **altura da caixa alta**
/// (`capHeight`), que é o que o olho lê como centro num círculo pequeno.
final class CountSeal: NSView {
    var value = 0 {
        didSet {
            guard value != oldValue else { return }
            needsDisplay = true
            needsLayout = true
        }
    }

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
    private static let fill = NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1)
    private static let ring = NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1)
    private static let ink = NSColor(calibratedWhite: 1, alpha: 0.78)
    private static let minSide: CGFloat = 16

    override var isFlipped: Bool { true }

    private var text: NSAttributedString {
        NSAttributedString(string: "\(value)", attributes: [.font: Self.font,
                                                            .foregroundColor: Self.ink])
    }

    /// Redondo enquanto couber; vira cápsula quando o número é largo.
    var size: NSSize {
        let width = ceil(text.size().width) + 10
        return NSSize(width: max(Self.minSide, width), height: Self.minSide)
    }

    override var intrinsicContentSize: NSSize { size }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let radius = rect.height / 2
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        Self.fill.setFill()
        path.fill()
        Self.ring.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let string = text
        let measured = string.size()
        // Centro ótico: o glifo do dígito ocupa do baseline ao `capHeight`, e é
        // esse bloco que precisa ficar no meio — não a linha inteira, que traz
        // ascender e descender vazios junto.
        let baseline = (bounds.height + Self.font.capHeight) / 2
        let origin = NSPoint(x: (bounds.width - measured.width) / 2,
                             y: baseline - Self.font.ascender)
        string.draw(at: origin)
    }
}

// MARK: - A gaveta dos guardados

/// A linha que abre e fecha os projetos guardados de um workspace (ADR-052).
///
/// Discreta de propósito: ela é a tampa de uma gaveta, não um projeto — quem
/// tem cinco repositórios e trabalha em um não quer os outros quatro
/// disputando atenção com o que está aberto.
final class DrawerRow: NSView {
    static let height: CGFloat = 26

    private(set) var isOpen: Bool
    private let count: Int
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    var onClick: (() -> Void)?

    init(count: Int, open: Bool) {
        self.count = count
        self.isOpen = open
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        label.font = .systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = NSColor(calibratedWhite: 1, alpha: 0.38)
        switch count {
        case 0:  label.stringValue = "gaveta vazia"
        case 1:  label.stringValue = "1 guardado"
        default: label.stringValue = "\(count) guardados"
        }
        addSubview(label)
        chevron.image = ToolbarButton.symbol([open ? "chevron.down" : "chevron.right"])
        chevron.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.3)
        chevron.imageScaling = .scaleProportionallyDown
        // Vazia não abre nada; ela fica ali como alvo de queda.
        chevron.isHidden = count == 0
        addSubview(chevron)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard count > 0 else { return }
        onClick?()
    }

    override func resetCursorRects() { HandCursor.fill(self, when: count > 0) }

    override func layout() {
        super.layout()
        chevron.frame = NSRect(x: 10, y: bounds.midY - 5, width: 10, height: 10)
        let x: CGFloat = count == 0 ? 12 : 26
        label.frame = NSRect(x: x, y: bounds.midY - 7, width: bounds.width - x - 10, height: 14)
    }
}

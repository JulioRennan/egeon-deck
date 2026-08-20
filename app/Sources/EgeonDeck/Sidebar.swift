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

    var isSelected = false { didSet { needsDisplay = true; restyle() } }
    /// Bancada já materializada (terminais rodando, editor carregado).
    var isLive = false { didSet { restyle() } }

    /// Alguma coisa nesta bancada está te esperando. Guardado porque no trilho
    /// quem grita isso é o ARO da pastilha, e `restyle` não vê o resumo.
    private var wantsAttention = false

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
    /// 66pt em TODA linha, e a barra tem 220: um terço do nome da bancada pago
    /// para um caso que quase nunca acontece. O comum é uma bolinha só.
    private var badgeWidth: CGFloat = 0

    override func layout() {
        super.layout()
        if isCompact {
            let side: CGFloat = 26
            tile.frame = NSRect(x: ((bounds.width - side) / 2).rounded(), y: 2,
                                width: side, height: side)
            initial.frame = NSRect(x: tile.frame.minX, y: tile.frame.minY + 5,
                                   width: side, height: 16)
            // Badge embaixo da pastilha, em fonte miúda: no trilho os três avisos
            // continuam convivendo (ADR-024) porque é o único lugar onde uma
            // bancada inativa se anuncia — o que a largura não dá é o nome.
            statusLabel.frame = NSRect(x: 0, y: 30, width: bounds.width, height: 12)
            return
        }

        dot.frame = NSRect(x: 12, y: bounds.midY - 3, width: 6, height: 6)
        let textWidth = bounds.width - 40 - badgeWidth
        nameLabel.frame = NSRect(x: 28, y: 8, width: textWidth, height: 17)
        pathLabel.frame = NSRect(x: 28, y: 26, width: textWidth, height: 13)
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
        let signature = "\(summary.working)/\(summary.attention)/\(summary.done)/"
            + (summary.working > 0 ? String(Spinner.current) : "")
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
        add(String(Spinner.current), summary.working,
            NSColor(calibratedWhite: 1, alpha: isCompact ? 0.75 : 0.45))
        add("●", summary.attention, .systemOrange)
        add("●", summary.done, .systemGreen)

        statusLabel.attributedStringValue = badge

        // No trilho, 10pt de glifo é pouco para o aviso que INTERROMPE: o aro da
        // pastilha vira laranja, que se reconhece sem ler.
        if wantsAttention != (summary.attention > 0) {
            wantsAttention = summary.attention > 0
            restyle()
        }

        // O nome da bancada fica com o que sobra, então a caixa acompanha o
        // conteúdo em vez de reservar o pior caso.
        let width = badge.length == 0 ? 0 : ceil(badge.size().width) + 2
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
        layer?.cornerRadius = 8
        nameLabel.textColor = isSelected ? .white : NSColor(calibratedWhite: 1, alpha: 0.72)

        tile.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            : NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
        // Aro por prioridade: laranja de "te espera" vence o verde de "está de
        // pé", porque um pede coisa e o outro só informa.
        tile.layer?.borderWidth = (wantsAttention || isLive) ? 2 : 0
        tile.layer?.borderColor = wantsAttention
            ? NSColor.systemOrange.cgColor
            : NSColor.systemGreen.withAlphaComponent(0.75).cgColor
        initial.textColor = isSelected ? .white : NSColor(calibratedWhite: 1, alpha: 0.7)

        dot.layer?.backgroundColor = (isLive ? NSColor.systemGreen : NSColor(calibratedWhite: 1, alpha: 0.22)).cgColor
    }

    override func mouseDown(with event: NSEvent) { onClick?(index) }

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
        menu.addItem(withTitle: "Limite de conversa entre agentes…",
                     action: #selector(visitLimitFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remover bancada…", action: #selector(removeFromMenu), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func renameFromMenu() { onRename?(index) }
    @objc private func duplicateFromMenu() { onDuplicateAsWorktree?(index) }
    @objc private func removeFromMenu() { onRemove?(index) }
    @objc private func visitLimitFromMenu() { onEditVisitLimit?(index) }
}

final class Sidebar: NSView {
    /// Cabeçalho curto porque a barra agora flutua: os botões da janela ficam
    /// FORA dela, e não há mais o que desviar aqui dentro.
    static let headerHeight: CGFloat = 34
    static let expandedWidth: CGFloat = 232
    /// Largura do trilho recolhido: cabe a pastilha de 26pt com folga, e é o que
    /// o conteúdo reserva de gutter — o que se abre além disso flutua por cima.
    static let railWidth: CGFloat = 52
    private static let rowHeight: CGFloat = 46
    private static let rowGap: CGFloat = 4

    /// Trilho recolhido. Propagado às linhas, que trocam nome por pastilha.
    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            rows.forEach { $0.isCompact = isCompact }
            title.isHidden = isCompact
            emptyLabel.isHidden = isCompact || !rows.isEmpty
            // O + sai do trilho: criar bancada abre um menu, e menu saindo de uma
            // faixa de 52pt cai por cima dos cards. Você abre a barra e cria.
            addButton.isHidden = isCompact
            collapseButton.setSymbols(
                isCompact ? ["sidebar.trailing", "chevron.right"]
                          : ["sidebar.leading", "chevron.left"],
                tooltip: isCompact ? "Abrir a barra (⌘/)" : "Recolher a barra (⌘/)")
            needsLayout = true
        }
    }

    private var rows: [SidebarRow] = []
    private let title = NSTextField(labelWithString: "BANCADAS")
    private let addButton = ToolbarButton(symbols: ["plus"], tooltip: "Nova bancada", size: 22)
    /// Recolher e abrir. Existe além do ⌘/ porque atalho não se descobre olhando
    /// a tela, e uma barra que recolhe sem dizer como voltar é uma barra que
    /// alguém vai achar que quebrou.
    private let collapseButton = ToolbarButton(symbols: ["sidebar.leading", "chevron.left"],
                                               tooltip: "Recolher a barra (⌘/)", size: 22)
    private let emptyLabel = NSTextField(labelWithString: "")

    var onSelect: ((Int) -> Void)?
    var onToggleCollapse: (() -> Void)?
    var onCreate: (() -> Void)?
    var onCreateFromWorktree: (() -> Void)?
    var onRename: ((Int) -> Void)?
    var onDuplicateAsWorktree: ((Int) -> Void)?
    var onRemove: ((Int) -> Void)?
    var onEditVisitLimit: ((Int) -> Void)?

    init(configs: [WorkbenchConfig]) {
        super.init(frame: .zero)
        wantsLayer = true
        // Sem fundo próprio: quem pinta é o `GlassPanel` que a envolve. Chapa
        // opaca aqui apagaria o vidro por dentro.
        layer?.backgroundColor = NSColor.clear.cgColor

        title.font = .systemFont(ofSize: 10, weight: .bold)
        title.textColor = NSColor(calibratedWhite: 1, alpha: 0.42)
        addSubview(title)

        // Menu, e não ação direta: as duas rotas terminam no mesmo lugar (uma
        // bancada nova na lista), então elas pertencem ao mesmo botão.
        addButton.onClick = { [weak self] in self?.showCreateMenu() }
        addSubview(addButton)

        collapseButton.onClick = { [weak self] in self?.onToggleCollapse?() }
        addSubview(collapseButton)

        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.45)
        emptyLabel.stringValue = "Nenhuma bancada.\nUse + para criar,\nvazia ou de um template."
        emptyLabel.maximumNumberOfLines = 0
        addSubview(emptyLabel)

        reload(configs)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Recria as linhas. Bancadas são criadas e removidas em tempo de execução,
    /// então a barra não pode ser montada só uma vez no init.
    func reload(_ configs: [WorkbenchConfig]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = configs.enumerated().map { index, config in
            let row = SidebarRow(index: index, config: config)
            row.onClick = { [weak self] in self?.onSelect?($0) }
            row.onRename = { [weak self] in self?.onRename?($0) }
            row.onDuplicateAsWorktree = { [weak self] in self?.onDuplicateAsWorktree?($0) }
            row.onRemove = { [weak self] in self?.onRemove?($0) }
            row.onEditVisitLimit = { [weak self] in self?.onEditVisitLimit?($0) }
            row.isCompact = isCompact
            addSubview(row)
            return row
        }
        emptyLabel.isHidden = isCompact || !configs.isEmpty
        needsLayout = true
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
        emptyLabel.frame = NSRect(x: 16, y: Self.headerHeight + 8,
                                  width: bounds.width - 32, height: 56)

        let inset: CGFloat = isCompact ? 2 : 8
        var y = Self.headerHeight
        for row in rows {
            row.frame = NSRect(x: inset, y: y,
                               width: bounds.width - inset * 2, height: Self.rowHeight)
            y += Self.rowHeight + Self.rowGap
        }
    }

    private func showCreateMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Nova bancada…", action: #selector(createPlain), keyEquivalent: "")
        menu.addItem(withTitle: "Nova bancada a partir de worktree…",
                     action: #selector(createFromWorktree), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: addButton.frame.minX, y: addButton.frame.maxY + 4),
                   in: self)
    }

    @objc private func createPlain() { onCreate?() }
    @objc private func createFromWorktree() { onCreateFromWorktree?() }

    func select(_ index: Int) {
        for row in rows { row.isSelected = (row.index == index) }
    }

    /// Chamado pelo laço da UI com o resumo de TODAS as bancadas vivas, não só a
    /// que está na tela.
    func showActivity(_ summaries: [String: ActivitySummary]) {
        for row in rows { row.show(summaries[row.name] ?? ActivitySummary()) }
    }

    func markLive(_ index: Int) {
        rows.first { $0.index == index }?.isLive = true
    }

    func markLive(indices: Set<Int>) {
        for row in rows { row.isLive = indices.contains(row.index) }
    }
}

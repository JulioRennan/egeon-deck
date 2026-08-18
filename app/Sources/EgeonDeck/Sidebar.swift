import AppKit

final class SidebarRow: NSView {
    let index: Int
    /// Nome da sessão. É a chave do resumo de atividade do Dispatcher —
    /// o índice da linha não serve, porque o endereço de dispatch é por nome.
    let name: String
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let statusLabel = NSTextField(labelWithString: "")

    var onClick: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?
    var onDuplicateAsWorktree: ((Int) -> Void)?
    var onRemove: ((Int) -> Void)?
    var onEditVisitLimit: ((Int) -> Void)?

    var isSelected = false { didSet { needsDisplay = true; restyle() } }
    /// Sessão já materializada (terminais rodando, editor carregado).
    var isLive = false { didSet { restyle() } }

    init(index: Int, config: SessionConfig) {
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
            ? NSColor(calibratedWhite: 1, alpha: 0.35)
            : NSColor.systemRed.withAlphaComponent(0.8)
        pathLabel.lineBreakMode = .byTruncatingMiddle

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3

        // Monoespaçado porque o conteúdo é spinner: com fonte proporcional cada
        // quadro do braille tem uma largura, e o rótulo treme a cada troca.
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        statusLabel.alignment = .right

        addSubview(dot)
        addSubview(nameLabel)
        addSubview(pathLabel)
        addSubview(statusLabel)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Cabe `⠙9 ●9 ●9`: os três avisos convivem, e o pior caso é a sessão que
    /// tem nó em cada estado.
    private static let statusWidth: CGFloat = 66

    override func layout() {
        super.layout()
        dot.frame = NSRect(x: 12, y: bounds.midY - 3, width: 6, height: 6)
        let textWidth = bounds.width - 40 - Self.statusWidth
        nameLabel.frame = NSRect(x: 28, y: 8, width: textWidth, height: 17)
        pathLabel.frame = NSRect(x: 28, y: 26, width: textWidth, height: 13)
        // 4 da borda da linha, que é onde o `+` do cabeçalho termina: encostado
        // no limite útil da direita e alinhado com o que já estava lá.
        statusLabel.frame = NSRect(x: bounds.width - Self.statusWidth - 4,
                                   y: bounds.midY - 9,
                                   width: Self.statusWidth, height: 18)
    }

    /// A sessão que precisa de você quase nunca é a que está na tela: o canvas
    /// das outras sai da hierarquia de views e não desenha nada. Esta linha é a
    /// única pista que elas têm.
    ///
    /// Os três avisos convivem, e é o caso normal de uma sessão com vários nós:
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

        let badge = NSMutableAttributedString()
        func add(_ glyph: String, _ count: Int, _ color: NSColor) {
            guard count > 0 else { return }
            if badge.length > 0 { badge.append(NSAttributedString(string: " ")) }
            // Fonte e alinhamento vêm junto porque `attributedStringValue`
            // ignora os do rótulo: sem a fonte o spinner volta a tremer em fonte
            // proporcional, e sem o parágrafo o badge encosta na ESQUERDA da
            // caixa — que é longe da borda do tile, justamente onde ele não
            // serve.
            badge.append(NSAttributedString(string: count > 1 ? "\(glyph)\(count)" : glyph,
                                            attributes: [.foregroundColor: color,
                                                         .font: statusLabel.font as Any,
                                                         .paragraphStyle: Self.rightAligned]))
        }

        // Ordem fixa, na sequência do ciclo: rodando, parou te perguntando,
        // parou pronto. Ordenar por urgência faria a bolinha trocar de lugar
        // conforme a sessão anda, e badge que se move é badge que se procura em
        // vez de se reconhecer.
        add(String(Spinner.current), summary.working, NSColor(calibratedWhite: 1, alpha: 0.45))
        add("●", summary.attention, .systemOrange)
        add("●", summary.done, .systemGreen)

        statusLabel.attributedStringValue = badge
    }

    /// Última combinação desenhada, para não remontar o rótulo à toa.
    private var lastBadge = ""

    private static let rightAligned: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }()

    private func restyle() {
        layer?.backgroundColor = isSelected
            ? NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
            : NSColor.clear.cgColor
        layer?.cornerRadius = 8
        nameLabel.textColor = isSelected ? .white : NSColor(calibratedWhite: 1, alpha: 0.6)
        dot.layer?.backgroundColor = (isLive ? NSColor.systemGreen : NSColor(calibratedWhite: 1, alpha: 0.18)).cgColor
    }

    override func mouseDown(with event: NSEvent) { onClick?(index) }

    /// Renomear e remover ficam no menu de contexto: são raros o bastante para
    /// não merecerem botão fixo, e um botão de remover por linha convida ao
    /// acidente.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Renomear…", action: #selector(renameFromMenu), keyEquivalent: "")
        // Duplicar mora aqui, e não no +, porque a sessão já diz qual é o
        // repositório e quais nós replicar — no + você teria de informar os dois.
        menu.addItem(withTitle: "Duplicar em nova worktree…",
                     action: #selector(duplicateFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Limite de conversa entre agentes…",
                     action: #selector(visitLimitFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remover sessão…", action: #selector(removeFromMenu), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func renameFromMenu() { onRename?(index) }
    @objc private func duplicateFromMenu() { onDuplicateAsWorktree?(index) }
    @objc private func removeFromMenu() { onRemove?(index) }
    @objc private func visitLimitFromMenu() { onEditVisitLimit?(index) }
}

final class Sidebar: NSView {
    static let headerHeight: CGFloat = 66
    private static let rowHeight: CGFloat = 46
    private static let rowGap: CGFloat = 4

    private var rows: [SidebarRow] = []
    private let title = NSTextField(labelWithString: "SESSÕES")
    private let addButton = ToolbarButton(symbols: ["plus"], tooltip: "Nova sessão", size: 22)
    private let emptyLabel = NSTextField(labelWithString: "")

    var onSelect: ((Int) -> Void)?
    var onCreate: (() -> Void)?
    var onCreateFromWorktree: (() -> Void)?
    var onRename: ((Int) -> Void)?
    var onDuplicateAsWorktree: ((Int) -> Void)?
    var onRemove: ((Int) -> Void)?
    var onEditVisitLimit: ((Int) -> Void)?

    init(configs: [SessionConfig]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor

        title.font = .systemFont(ofSize: 10, weight: .bold)
        title.textColor = NSColor(calibratedWhite: 1, alpha: 0.28)
        addSubview(title)

        // Menu, e não ação direta: as duas rotas terminam no mesmo lugar (uma
        // sessão nova na lista), então elas pertencem ao mesmo botão.
        addButton.onClick = { [weak self] in self?.showCreateMenu() }
        addSubview(addButton)

        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.3)
        emptyLabel.stringValue = "Nenhuma sessão.\nUse + para criar,\nvazia ou de um template."
        emptyLabel.maximumNumberOfLines = 0
        addSubview(emptyLabel)

        reload(configs)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Recria as linhas. Sessões são criadas e removidas em tempo de execução,
    /// então a barra não pode ser montada só uma vez no init.
    func reload(_ configs: [SessionConfig]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = configs.enumerated().map { index, config in
            let row = SidebarRow(index: index, config: config)
            row.onClick = { [weak self] in self?.onSelect?($0) }
            row.onRename = { [weak self] in self?.onRename?($0) }
            row.onDuplicateAsWorktree = { [weak self] in self?.onDuplicateAsWorktree?($0) }
            row.onRemove = { [weak self] in self?.onRemove?($0) }
            row.onEditVisitLimit = { [weak self] in self?.onEditVisitLimit?($0) }
            addSubview(row)
            return row
        }
        emptyLabel.isHidden = !configs.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 20, y: 38, width: bounds.width - 60, height: 14)
        addButton.frame = NSRect(x: bounds.width - 34, y: 33, width: 22, height: 22)
        emptyLabel.frame = NSRect(x: 20, y: Self.headerHeight + 8,
                                  width: bounds.width - 40, height: 56)

        var y = Self.headerHeight
        for row in rows {
            row.frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: Self.rowHeight)
            y += Self.rowHeight + Self.rowGap
        }
    }

    private func showCreateMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Nova sessão…", action: #selector(createPlain), keyEquivalent: "")
        menu.addItem(withTitle: "Nova sessão a partir de worktree…",
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

    /// Chamado pelo laço da UI com o resumo de TODAS as sessões vivas, não só a
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

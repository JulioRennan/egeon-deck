import AppKit

// MARK: - A tabela da thread

/// Dirige o `NSTableView` da thread: uma linha por bloco, altura do cache,
/// view reusada por tipo, e diff por id entre uma montagem e outra — a linha
/// que entrou é inserida, a que mudou é recarregada, o resto fica (ADR-042).
/// Não mede nada: recebe blocos e medidas prontos do `ChatContainer`.
final class ChatThreadController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let scrollView = NSScrollView()
    let tableView = NSTableView()
    private(set) var blocks: [ChatBlock] = []
    private var rows: [String: ChatRowMetrics] = [:]
    /// As medidas por bolha da última montagem — o `known` da próxima.
    private(set) var bubbleMetrics: [String: ChatBlockLayout.BubbleMetrics] = [:]
    /// Clique numa linha: a chave da mensagem-alvo (citação ou prompt respondido).
    var onClick: ((ChatBlock) -> Void)?
    var onScroll: (() -> Void)?
    /// Quantas vezes a tabela mudou de fato — para o teste.
    private(set) var applies = 0
    /// Quantas views de linha nasceram — para o teste provar que só o visível
    /// existe e que a rolagem reusa.
    private(set) var rowsCreated = 0
    private var flashKey: String?

    override init() {
        super.init()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("block"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.usesAutomaticRowHeights = false
        tableView.rowHeight = 40
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.wantsLayer = true
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                               name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() { onScroll?() }

    /// A largura para a qual as linhas devem ser medidas.
    var width: CGFloat { scrollView.contentSize.width }

    // MARK: Aplicar uma montagem

    /// Troca a lista de blocos. Devolve se algo mudou na tela e se a mudança
    /// foi estrutural (linha nova ou removida) — quem chama decide a rolagem.
    @discardableResult
    func apply(_ next: [ChatBlock], metrics: [String: ChatBlockLayout.BubbleMetrics])
        -> (changed: Bool, structural: Bool) {
        var nextRows: [String: ChatRowMetrics] = [:]
        for bubble in metrics.values { nextRows.merge(bubble.rows) { _, new in new } }

        let oldIds = blocks.map(\.id)
        let newIds = next.map(\.id)
        let oldSet = Set(oldIds), newSet = Set(newIds)
        let removed = IndexSet(oldIds.indices.filter { !newSet.contains(oldIds[$0]) })
        let inserted = IndexSet(newIds.indices.filter { !oldSet.contains(newIds[$0]) })
        let oldByKey = Dictionary(zip(oldIds, blocks), uniquingKeysWith: { a, _ in a })
        var changed = IndexSet()
        for (index, block) in next.enumerated() where oldSet.contains(block.id) {
            if oldByKey[block.id] != block || rows[block.id] != nextRows[block.id] { changed.insert(index) }
        }
        guard !removed.isEmpty || !inserted.isEmpty || !changed.isEmpty else { return (false, false) }
        applies += 1

        // Quem está lendo no meio não pode ser empurrado por linha que entrou
        // ou cresceu acima: guarda a primeira linha visível e onde ela estava,
        // e a devolve ao mesmo lugar depois. No fim, quem chama decide.
        let anchor = isAtBottom ? nil : firstVisibleAnchor()

        let previous = blocks
        blocks = next
        rows = nextRows
        bubbleMetrics = metrics

        // Os ids comuns têm de estar na mesma ordem para inserir/remover por
        // índice valer; a resposta ao vivo muda de hora e pode trocar de
        // lugar — aí é recarga inteira, que na tabela só refaz o visível.
        let commonOld = oldIds.filter { newSet.contains($0) }
        let commonNew = newIds.filter { oldSet.contains($0) }
        let structural: Bool
        if commonOld != commonNew || previous.isEmpty {
            tableView.reloadData()
            structural = true
        } else {
            tableView.beginUpdates()
            tableView.removeRows(at: removed, withAnimation: [])
            tableView.insertRows(at: inserted, withAnimation: [])
            tableView.endUpdates()
            if !changed.isEmpty {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    tableView.noteHeightOfRows(withIndexesChanged: changed)
                }
                tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
            }
            structural = !removed.isEmpty || !inserted.isEmpty
        }
        if let anchor { restore(anchor) }
        return (true, structural)
    }

    // MARK: Âncora de leitura

    private struct Anchor {
        let id: String
        /// Distância do topo da linha ao topo da viewport.
        let offset: CGFloat
    }

    private func firstVisibleAnchor() -> Anchor? {
        let visible = scrollView.contentView.documentVisibleRect
        let range = tableView.rows(in: visible)
        guard range.length > 0, range.location < blocks.count else { return nil }
        let row = range.location
        return Anchor(id: blocks[row].id, offset: visible.minY - tableView.rect(ofRow: row).minY)
    }

    private func restore(_ anchor: Anchor) {
        guard let row = blocks.firstIndex(where: { $0.id == anchor.id }) else { return }
        tableView.layoutSubtreeIfNeeded()
        let y = tableView.rect(ofRow: row).minY + anchor.offset
        scroll(to: max(0, min(y, bottomY)), animated: false)
    }

    // MARK: NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { blocks.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < blocks.count else { return 40 }
        return rows[blocks[row].id]?.height ?? 40
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < blocks.count else { return nil }
        let block = blocks[row]
        let identifier: NSUserInterfaceItemIdentifier
        switch block.kind {
        case .prompt:            identifier = ChatPromptRow.identifier
        case .header, .typing:   identifier = ChatHeaderRow.identifier
        case .prose, .code, .step: identifier = ChatTextRow.identifier
        case .diff:              identifier = ChatDiffRow.identifier
        case .status:            identifier = ChatStatusRow.identifier
        }
        let view = (tableView.makeView(withIdentifier: identifier, owner: nil) as? ChatRowView)
            ?? makeRow(identifier)
        view.configure(block, metrics: rows[block.id] ?? ChatRowMetrics(height: 40, bubbleWidth: 200))
        view.flashing = flashKey == block.messageKey
        view.onClick = { [weak self] in self?.onClick?(block) }
        return view
    }

    private func makeRow(_ identifier: NSUserInterfaceItemIdentifier) -> ChatRowView {
        rowsCreated += 1
        let view: ChatRowView
        switch identifier {
        case ChatPromptRow.identifier: view = ChatPromptRow()
        case ChatHeaderRow.identifier: view = ChatHeaderRow()
        case ChatDiffRow.identifier:   view = ChatDiffRow()
        case ChatStatusRow.identifier: view = ChatStatusRow()
        default:                       view = ChatTextRow()
        }
        view.identifier = identifier
        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    // MARK: Rolagem

    var isAtBottom: Bool {
        let visible = scrollView.contentView.documentVisibleRect
        return visible.maxY >= tableView.bounds.height - 40
    }

    /// Perto do começo do que está carregado: hora de trazer mais histórico.
    var isNearTop: Bool { scrollView.contentView.documentVisibleRect.minY < 300 }

    private var bottomY: CGFloat { max(0, tableView.bounds.height - scrollView.contentSize.height) }

    func scrollToBottom(animated: Bool) { scroll(to: bottomY, animated: animated) }
    func scrollToTop(animated: Bool) { scroll(to: 0, animated: animated) }

    /// Rolagem com movimento, como no WhatsApp: pular seco perde a noção de
    /// para onde se foi. Seca para acompanhar a bolha ao vivo e a caixa
    /// empurrando a thread — animar a cada linha gravada é tremor.
    func scroll(to y: CGFloat, animated: Bool) {
        let clip = scrollView.contentView
        guard animated else {
            clip.setBoundsOrigin(NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            onScroll?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.scrollView.reflectScrolledClipView(clip)
            self.onScroll?()
        }
    }

    /// Rola até a mensagem e a acende um instante.
    func scrollTo(messageKey: String) {
        guard let row = blocks.firstIndex(where: { $0.messageKey == messageKey }) else { return }
        scroll(to: max(0, tableView.rect(ofRow: row).minY - 24), animated: true)
        flashKey = messageKey
        redrawVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.flashKey = nil
            self?.redrawVisible()
        }
    }

    private func redrawVisible() {
        for view in visibleRows() { view.flashing = flashKey == view.block?.messageKey }
    }

    private func visibleRows() -> [ChatRowView] {
        let range = tableView.rows(in: tableView.visibleRect)
        return (range.location..<(range.location + range.length)).compactMap {
            tableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? ChatRowView
        }
    }

    /// Só as linhas de status têm o que animar.
    func tick() {
        for view in visibleRows() {
            (view as? ChatStatusRow)?.tick()
            (view as? ChatHeaderRow)?.tick()
        }
    }
}

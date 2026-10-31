import AppKit

// MARK: - Nó de fila

/// A fila de prompts como lista de tarefas: uma linha por tarefa, e o clique
/// abre ali mesmo o cartão com o título, as notas e os prints — como no
/// Things. Você anota tudo de uma vez e manda uma por uma ao agente ligado por
/// aresta, à mão ou sozinha a cada fim de turno dele.
final class QueueNode: NodeView {
    let controller: QueueController
    private(set) var address: String

    private let content = FlippedView()
    private let bar = NSView()
    private let targetPicker = HandPopUpButton(frame: .zero, pullsDown: false)
    private let targetLabel = NSTextField(labelWithString: "para")
    private let nextButton = ToolbarButton(symbols: ["paperplane.fill", "paperplane"],
                                           tooltip: "Enviar a próxima pendente", size: 30)
    private let clearButton = ToolbarButton(symbols: ["checkmark.circle", "checkmark"],
                                            tooltip: "Tirar da lista o que já foi", size: 30)
    private let autoBox = HandButton(checkboxWithTitle: "Automático", target: nil, action: nil)
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let listScroll = NSScrollView()
    private let list = QueueListView()
    private let newRow = QueueNewRow()
    private let port = NodePortButton()

    private var rows: [String: QueueRow] = [:]
    /// A tarefa aberta — uma por vez, como no Things.
    private var expanded: String?
    /// A tarefa sendo arrastada, a altura do cursor na lista e onde ela cai.
    private var dragging: (id: String, y: CGFloat, target: Int)?

    private static let barHeight: CGFloat = 46

    init(frame: NSRect, address: String, title: String, controller: QueueController) {
        self.address = address
        self.controller = controller
        let id = String(address.split(separator: "/").last ?? "")
        super.init(frame: frame, title: "☰ " + id, accent: .systemTeal, nodeID: id)
        titleLabel.toolTip = address
        registerForDraggedTypes([.fileURL, .png, .tiff])

        body.addSubview(content)
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor
        content.addSubview(bar)

        targetLabel.font = .systemFont(ofSize: 13, weight: .medium)
        targetLabel.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        bar.addSubview(targetLabel)
        targetPicker.font = .systemFont(ofSize: 13)
        targetPicker.bezelStyle = .inline
        targetPicker.target = self
        targetPicker.action = #selector(targetPicked)
        bar.addSubview(targetPicker)

        autoBox.font = .systemFont(ofSize: 13)
        autoBox.target = self
        autoBox.action = #selector(autoToggled)
        autoBox.toolTip = "Manda a próxima sozinha quando o agente termina o turno; espera enquanto ele pergunta algo a você"
        bar.addSubview(autoBox)

        nextButton.onClick = { [weak self] in self?.report(self?.controller.sendNext()) }
        clearButton.onClick = { [weak self] in self?.controller.clearDone() }
        bar.addSubview(nextButton)
        bar.addSubview(clearButton)

        notice.font = .systemFont(ofSize: 13)
        notice.textColor = .systemOrange
        notice.isHidden = true
        content.addSubview(notice)

        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.documentView = list
        content.addSubview(listScroll)
        list.onClickEmpty = { [weak self] in self?.collapse() }

        newRow.onCreate = { [weak self] title in self?.create(title: title) }
        list.addSubview(newRow)

        addSubview(port)
        port.onDrag = { [weak self] point in
            guard let self else { return }
            self.onPortDrag?(self, point)
        }
        port.onRelease = { [weak self] point in
            guard let self else { return }
            self.onPortRelease?(self, point)
        }

        controller.onChange = { [weak self] in self?.reload() }
        controller.start()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var removalWarning: String {
        "As tarefas da fila e os prints anotados nelas são apagados junto."
    }

    override func prepareForRemoval() {
        controller.stop()
        controller.store.removeAll()
    }

    override func workbenchRenamed(to workbench: String) {
        address = "\(workbench)/\(nodeID)"
        titleLabel.toolTip = address
    }

    // MARK: Estado na tela

    /// Refaz a barra e acerta as linhas pelo id — sem recriar quem já existe:
    /// a tarefa aberta tem campo com o cursor dentro, e recriar a linha a cada
    /// tecla (a fila grava e avisa a cada uma) tiraria o teclado de você.
    func reload() {
        let targets = controller.targets
        targetPicker.removeAllItems()
        if targets.isEmpty {
            targetPicker.addItem(withTitle: "ninguém ligado")
            targetPicker.isEnabled = false
        } else {
            targetPicker.addItems(withTitles: targets.map(\.label))
            targetPicker.isEnabled = targets.count > 1
            if let destination = controller.destination,
               let index = targets.firstIndex(where: { $0.id == destination }) {
                targetPicker.selectItem(at: index)
            }
        }
        autoBox.state = controller.queue.auto ? .on : .off

        let pending = controller.queue.pendingCount
        subtitle = pending == 0 ? "nada pendente" : "\(pending) pendente\(pending == 1 ? "" : "s")"
        if let blocker = controller.blocker { show(notice: blocker) }
        else if notice.stringValue.hasPrefix("Ligue a fila") { show(notice: nil) }

        let items = controller.queue.items
        let alive = Set(items.map(\.id))
        for (id, row) in rows where !alive.contains(id) {
            row.removeFromSuperview()
            rows[id] = nil
        }
        if let expanded, !alive.contains(expanded) { self.expanded = nil }
        for item in items {
            if let row = rows[item.id] {
                row.update(item)
            } else {
                let row = makeRow(item)
                rows[item.id] = row
                list.addSubview(row)
            }
        }
        needsLayout = true
    }

    private func makeRow(_ item: QueueItem) -> QueueRow {
        let row = QueueRow(item: item, store: controller.store)
        let id = item.id
        row.onExpand = { [weak self] in self?.expand(id) }
        row.onToggleDone = { [weak self] in self?.controller.toggleDone(id) }
        row.onSend = { [weak self] in self?.report(self?.controller.send(id)) }
        row.onReopen = { [weak self] in self?.controller.reopen(id) }
        row.onRemove = { [weak self] in self?.controller.remove(id) }
        row.onMove = { [weak self] offset in self?.controller.move(id, by: offset) }
        row.onEdit = { [weak self] title, notes in self?.controller.update(id, title: title, notes: notes) }
        row.onAttach = { [weak self] pasted in self?.attach(pasted, to: id) }
        row.onDetach = { [weak self] image in self?.controller.detach(image, from: id) }
        row.onReply = { [weak self] text in self?.report(self?.controller.reply(id, text: text)) }
        row.onCommitTitle = { [weak self] in self?.create(title: "", after: id) }
        row.onCollapse = { [weak self] in self?.collapse() }
        row.onResize = { [weak self] in self?.needsLayout = true }
        row.onDragMove = { [weak self] y in self?.dragMoved(id, to: y) }
        row.onDragEnd = { [weak self] in self?.dragEnded() }
        return row
    }

    // MARK: Reordenar

    /// As linhas que não estão sendo arrastadas, na ordem, com a altura de
    /// cada uma — é sobre elas que se decide onde a arrastada cai.
    private func restingRows(width: CGFloat, excluding id: String) -> [(id: String, height: CGFloat)] {
        controller.queue.items.compactMap { item in
            guard item.id != id, let row = rows[item.id] else { return nil }
            return (item.id, row.height(for: width) + (row.isExpanded ? 12 : 0))
        }
    }

    private func dragMoved(_ id: String, to y: CGFloat) {
        guard let row = rows[id] else { return }
        if dragging == nil {
            // Na frente das outras enquanto anda.
            list.addSubview(row, positioned: .above, relativeTo: nil)
            row.alphaValue = 0.85
        }
        var top: CGFloat = Self.listTop
        var target = 0
        for resting in restingRows(width: row.frame.width, excluding: id) {
            if y < top + resting.height / 2 { break }
            top += resting.height
            target += 1
        }
        dragging = (id, y, target)
        needsLayout = true
    }

    private func dragEnded() {
        guard let drag = dragging else { return }
        dragging = nil
        rows[drag.id]?.alphaValue = 1
        controller.move(drag.id, to: drag.target)
        needsLayout = true
    }

    /// Abre a tarefa por fora — a rota `/queue?open=` faz o clique.
    func open(_ id: String) { expand(id) }

    private func expand(_ id: String) {
        guard expanded != id else { return }
        let previous = expanded
        expanded = id
        if let previous { rows[previous]?.setExpanded(false); controller.dropIfEmpty(previous) }
        rows[id]?.setExpanded(true)
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let row = rows[id] {
            list.scrollToVisible(row.frame)
            row.focusTitle()
        }
    }

    private func collapse() {
        guard let id = expanded else { return }
        expanded = nil
        rows[id]?.setExpanded(false)
        controller.dropIfEmpty(id)
        window?.makeFirstResponder(newRow.field)
        needsLayout = true
    }

    /// Enter na linha de baixo põe a tarefa na lista e deixa a linha pronta
    /// para a próxima — anotar dez seguidas é digitar e dar Enter dez vezes.
    /// Enter no título de uma tarefa aberta abre uma nova logo abaixo dela.
    private func create(title: String, after: String? = nil) {
        let item = controller.add(title: title, after: after)
        if after != nil || title.isEmpty { expand(item.id) }
    }

    private func attach(_ pasted: QueueStore.Pasted, to id: String) {
        controller.attach(Self.save(pasted, in: controller.store), to: id)
    }

    private static func save(_ pasted: QueueStore.Pasted, in store: QueueStore) -> [String] {
        switch pasted {
        case .files(let urls): return urls.compactMap(store.importImage(at:))
        case .png(let data): return store.saveImage(png: data).map { [$0] } ?? []
        }
    }

    private func show(notice text: String?) {
        notice.stringValue = text ?? ""
        notice.isHidden = text == nil
        needsLayout = true
    }

    private func report(_ error: String?) {
        show(notice: error)
        guard let error else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.notice.stringValue == error else { return }
            self.show(notice: self.controller.blocker)
        }
    }

    @objc private func targetPicked() {
        let targets = controller.targets
        let index = targetPicker.indexOfSelectedItem
        guard index >= 0, index < targets.count else { return }
        controller.setTarget(targets[index].id)
    }

    @objc private func autoToggled() { controller.setAuto(autoBox.state == .on) }

    // MARK: Arrastar imagem

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        QueueStore.images(in: sender.draggingPasteboard) == nil ? [] : .copy
    }

    /// Na tarefa aberta, o print entra nela; sem nenhuma aberta, vira tarefa
    /// nova já aberta, para você dar o título.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pasted = QueueStore.images(in: sender.draggingPasteboard) else { return false }
        let id = expanded ?? controller.add(title: "").id
        attach(pasted, to: id)
        expand(id)
        return true
    }

    // MARK: Layout

    private static let listTop: CGFloat = 8

    override func layout() {
        super.layout()
        content.frame = body.bounds
        let width = content.bounds.width
        bar.frame = NSRect(x: 0, y: 0, width: width, height: Self.barHeight)

        targetLabel.frame = NSRect(x: 12, y: 14, width: 34, height: 18)
        let rightWidth: CGFloat = 30 * 2 + 4 + 118
        let pickerWidth = max(90, min(240, width - 48 - rightWidth - 20))
        targetPicker.frame = NSRect(x: 46, y: 10, width: pickerWidth, height: 26)
        var x = width - 8
        for button in [clearButton, nextButton] {
            x -= 30
            button.frame = NSRect(x: x, y: 8, width: 30, height: 30)
            x -= 2
        }
        autoBox.frame = NSRect(x: x - 118, y: 13, width: 114, height: 20)

        var y = Self.barHeight + 4
        if !notice.isHidden {
            let height = ceil(notice.attributedStringValue.boundingRect(
                with: NSSize(width: width - 24, height: 200), options: .usesLineFragmentOrigin).height)
            notice.frame = NSRect(x: 12, y: y + 2, width: width - 24, height: height)
            y += height + 6
        }
        listScroll.frame = NSRect(x: 0, y: y, width: width, height: max(0, content.bounds.height - y))

        let rowWidth = listScroll.contentSize.width - 12
        var rowY: CGFloat = Self.listTop
        var slot = 0
        for item in controller.queue.items {
            guard let row = rows[item.id] else { continue }
            let height = row.height(for: rowWidth)
            if let drag = dragging, drag.id == item.id {
                // Segue o cursor; o lugar dela na lista é o vão aberto abaixo.
                row.frame = NSRect(x: 6, y: drag.y - height / 2, width: rowWidth, height: height)
                continue
            }
            if let drag = dragging, drag.target == slot, let dragged = rows[drag.id] {
                rowY += dragged.height(for: rowWidth)
            }
            slot += 1
            // Aberta ganha ar em volta: é um cartão, não mais uma linha.
            if row.isExpanded { rowY += 4 }
            row.frame = NSRect(x: 6, y: rowY, width: rowWidth, height: height)
            rowY += height + (row.isExpanded ? 8 : 0)
        }
        if let drag = dragging, drag.target >= slot, let dragged = rows[drag.id] {
            rowY += dragged.height(for: rowWidth)
        }
        newRow.frame = NSRect(x: 6, y: rowY, width: rowWidth, height: QueueRow.collapsedHeight)
        rowY += QueueRow.collapsedHeight + 12
        list.frame = NSRect(x: 0, y: 0, width: listScroll.contentSize.width,
                            height: max(rowY, listScroll.contentSize.height))

        let size = NodePortButton.size
        port.frame = NSRect(x: bounds.maxX - size - 1, y: bounds.midY - size / 2, width: size, height: size)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// O fundo da lista: clique fora das tarefas recolhe a aberta.
private final class QueueListView: NSView {
    var onClickEmpty: (() -> Void)?
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { onClickEmpty?() }
}

// MARK: - Bolinha de estado

/// O checkbox da tarefa: ○ pendente, ◐ com o agente, ✓ feita. Clicar marca e
/// desmarca à mão.
private final class StatusDot: NSView {
    var onClick: (() -> Void)?
    var status: QueueItem.Status = .pending { didSet { needsDisplay = true } }
    /// O agente perguntou: a bolinha vira um "?" laranja até você responder.
    var awaiting = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func resetCursorRects() { HandCursor.fill(self) }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        if awaiting {
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5)).fill()
            let mark = NSAttributedString(string: "?", attributes: [
                .font: NSFont.systemFont(ofSize: bounds.height * 0.62, weight: .heavy),
                .foregroundColor: NSColor.black.withAlphaComponent(0.85)])
            let size = mark.size()
            mark.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
            return
        }
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 2.5, dy: 2.5))
        circle.lineWidth = 1.6
        switch status {
        case .pending:
            NSColor(calibratedWhite: 0.5, alpha: 1).setStroke()
            circle.stroke()
        case .sent:
            NSColor.systemOrange.setStroke()
            circle.stroke()
            let half = NSBezierPath()
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius = bounds.width / 2 - 2.5
            half.move(to: center)
            half.appendArc(withCenter: center, radius: radius, startAngle: 270, endAngle: 90, clockwise: false)
            half.close()
            NSColor.systemOrange.setFill()
            half.fill()
        case .done:
            NSColor.systemTeal.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
            let check = NSBezierPath()
            let w = bounds.width
            check.move(to: NSPoint(x: bounds.minX + w * 0.28, y: bounds.midY))
            check.line(to: NSPoint(x: bounds.midX - w * 0.05, y: bounds.maxY - w * 0.28))
            check.line(to: NSPoint(x: bounds.maxX - w * 0.25, y: bounds.minY + w * 0.27))
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.black.withAlphaComponent(0.85).setStroke()
            check.stroke()
        }
    }
}

// MARK: - Tarefa

/// Uma tarefa: recolhida é a bolinha e o título; aberta é um cartão com o
/// título editável, as notas, os prints e o enviar.
private final class QueueRow: NSView, NSTextFieldDelegate {
    var onExpand: (() -> Void)?
    var onToggleDone: (() -> Void)?
    var onSend: (() -> Void)?
    var onReopen: (() -> Void)?
    var onRemove: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var onEdit: ((String, String) -> Void)?
    var onAttach: ((QueueStore.Pasted) -> Void)?
    var onDetach: ((String) -> Void)?
    /// Você escreveu na thread da tarefa.
    var onReply: ((String) -> Void)?
    /// Enter no título: a próxima tarefa nasce logo abaixo.
    var onCommitTitle: (() -> Void)?
    var onCollapse: (() -> Void)?
    /// A altura mudou (as notas cresceram) — o nó refaz o layout.
    var onResize: (() -> Void)?
    /// Arrastando a linha recolhida: a altura do cursor na lista.
    var onDragMove: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    static let collapsedHeight: CGFloat = 40

    private(set) var isExpanded = false
    private var item: QueueItem
    private let store: QueueStore

    private let dot = StatusDot()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let titleField = NSTextField()
    private let notes = QueueNotesView()
    private let notesPlaceholder = NSTextField(labelWithString: "Notas — onde acontece, passos, o esperado.  ⌘V cola print")
    /// Cada print e a proporção dele — a miniatura mantém o formato da tela.
    private var thumbs: [(view: NSView, aspect: CGFloat)] = []
    private let meta = NSTextField(labelWithString: "")
    private let thread = ThreadView()
    private let replyField = NSTextField()
    private let sendButton = HandButton(title: "Enviar", target: nil, action: nil)
    private let removeButton = ToolbarButton(symbols: ["trash", "xmark"], tooltip: "Apagar a tarefa", size: 28)
    private var press: NSPoint?
    private var dragged = false

    private static let titleFont = NSFont.systemFont(ofSize: 15)
    private static let notesFont = NSFont.systemFont(ofSize: 14)
    /// Altura do print aberto: grande o bastante para ler a tela que ele
    /// mostra, sem abrir o arquivo.
    private static let thumbHeight: CGFloat = 200
    /// Três linhas: o espaço de escrever existe antes de haver o que escrever,
    /// e o clique nele é edição, não "clique fora".
    private static let notesMinHeight: CGFloat = 58

    init(item: QueueItem, store: QueueStore) {
        self.item = item
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        dot.onClick = { [weak self] in self?.onToggleDone?() }
        addSubview(dot)

        titleLabel.font = Self.titleFont
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        badge.font = .systemFont(ofSize: 12)
        badge.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        badge.alignment = .right
        addSubview(badge)

        titleField.font = .systemFont(ofSize: 16, weight: .semibold)
        titleField.textColor = NSColor(calibratedWhite: 0.95, alpha: 1)
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.placeholderString = "Nova tarefa"
        titleField.lineBreakMode = .byTruncatingTail
        titleField.usesSingleLineMode = true
        titleField.cell?.isScrollable = true
        titleField.delegate = self
        addSubview(titleField)

        notes.font = Self.notesFont
        notes.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        notes.insertionPointColor = .white
        notes.drawsBackground = false
        notes.isRichText = false
        notes.importsGraphics = false
        notes.allowsUndo = true
        notes.textContainerInset = .zero
        notes.textContainer?.lineFragmentPadding = 0
        notes.isVerticallyResizable = false
        notes.onChange = { [weak self] in self?.notesChanged() }
        notes.onPasteImages = { [weak self] pasted in self?.onAttach?(pasted) }
        notes.onEscape = { [weak self] in self?.onCollapse?() }
        addSubview(notes)

        notesPlaceholder.font = Self.notesFont
        notesPlaceholder.textColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        addSubview(notesPlaceholder)

        meta.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        meta.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        meta.lineBreakMode = .byTruncatingTail
        addSubview(meta)

        sendButton.bezelStyle = .rounded
        sendButton.controlSize = .regular
        sendButton.font = .systemFont(ofSize: 13)
        sendButton.image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)
        sendButton.imagePosition = .imageLeading
        sendButton.target = self
        sendButton.action = #selector(sendClicked)
        addSubview(sendButton)
        removeButton.onClick = { [weak self] in self?.onRemove?() }
        addSubview(removeButton)

        addSubview(thread)
        replyField.font = .systemFont(ofSize: 14)
        replyField.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        replyField.isBordered = false
        replyField.drawsBackground = true
        replyField.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        replyField.focusRingType = .none
        replyField.usesSingleLineMode = true
        replyField.cell?.isScrollable = true
        replyField.wantsLayer = true
        replyField.layer?.cornerRadius = 6
        replyField.delegate = self
        addSubview(replyField)

        titleField.nextKeyView = notes
        apply(item, texts: true)
        setExpanded(false)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    // MARK: Dados

    func update(_ item: QueueItem) {
        let imagesChanged = item.images != self.item.images
        // Com o cursor dentro, o texto na tela é a verdade — é dele que a fila
        // acabou de ser gravada.
        apply(item, texts: !isEditing)
        if imagesChanged { rebuildThumbs() }
    }

    private var isEditing: Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder === notes || (responder as? NSText)?.delegate === titleField
    }

    private func apply(_ item: QueueItem, texts: Bool) {
        self.item = item
        dot.status = item.status
        dot.awaiting = item.awaiting
        let done = item.status == .done
        titleLabel.stringValue = item.title.isEmpty ? (item.notes.isEmpty ? "Sem título" : item.notes) : item.title
        titleLabel.textColor = item.title.isEmpty
            ? NSColor(calibratedWhite: 0.45, alpha: 1)
            : NSColor(calibratedWhite: done ? 0.5 : 0.92, alpha: 1)
        var marks: [String] = []
        if item.awaiting { marks.append("? pergunta") }
        if !item.thread.isEmpty { marks.append("💬 \(item.thread.count)") }
        if !item.images.isEmpty { marks.append("▣ \(item.images.count)") }
        if !item.notes.isEmpty, !item.title.isEmpty { marks.append("≡") }
        if item.status == .sent, let to = item.sentTo { marks.append("→ \(to)") }
        badge.stringValue = marks.joined(separator: "  ")
        badge.textColor = item.awaiting ? .systemOrange : NSColor(calibratedWhite: 0.45, alpha: 1)
        let placeholder = item.awaiting ? "Responder a pergunta…"
            : item.sentTo.map { "Responder ao \($0)…" } ?? "Comentar — vai junto quando enviar"
        replyField.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: item.awaiting ? NSColor.systemOrange.withAlphaComponent(0.8)
                                            : NSColor(calibratedWhite: 0.4, alpha: 1),
            .font: NSFont.systemFont(ofSize: 14)])
        if thread.messages != item.thread {
            thread.set(item.thread)
            thread.isHidden = !isExpanded || item.thread.isEmpty
            onResize?()
        }
        meta.stringValue = Self.meta(for: item)
        meta.isHidden = !isExpanded || meta.stringValue.isEmpty
        sendButton.title = item.status == .pending ? "Enviar" : "Enviar de novo"
        if texts {
            titleField.stringValue = item.title
            if notes.string != item.notes { notes.string = item.notes }
        }
        notesPlaceholder.isHidden = !notes.string.isEmpty || !isExpanded
        if thumbs.count != item.images.count { rebuildThumbs() }
        needsLayout = true
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func meta(for item: QueueItem) -> String {
        let sent = "enviada \(item.sentAt.map(clock.string) ?? "") → \(item.sentTo ?? "?")"
        switch item.status {
        case .pending: return ""
        case .sent: return sent + " · em andamento"
        case .done: return item.sentAt == nil
            ? "feita à mão" + (item.doneAt.map { " · \(clock.string(from: $0))" } ?? "")
            : sent + (item.doneAt.map { " · feita \(clock.string(from: $0))" } ?? "")
        }
    }

    private func rebuildThumbs() {
        thumbs.forEach { $0.view.removeFromSuperview() }
        thumbs = item.images.map { name in
            let image = NSImage(contentsOf: store.url(of: name))
            let size = image?.size ?? .zero
            let holder = ThumbHolder()
            let thumb = HandImageView()
            thumb.image = image
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.borderWidth = 1
            thumb.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor
            thumb.toolTip = "Abrir o print"
            thumb.identifier = NSUserInterfaceItemIdentifier(name)
            thumb.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openThumb(_:))))
            holder.image = thumb
            holder.addSubview(thumb)
            let drop = ThumbRemoveButton()
            drop.toolTip = "Tirar este print"
            drop.onClick = { [weak self] in self?.onDetach?(name) }
            holder.remove = drop
            holder.addSubview(drop)
            addSubview(holder)
            return (holder, size.height > 0 ? size.width / size.height : 1)
        }
        layoutThumbs()
        onResize?()
    }

    /// Os prints em fluxo: cada um na altura padrão e na largura da proporção
    /// dele, quebrando linha quando não cabe. Relativo ao topo da área.
    private func thumbFrames(width: CGFloat) -> [NSRect] {
        var frames: [NSRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        for thumb in thumbs {
            let w = min(width, Self.thumbHeight * thumb.aspect)
            let h = w / max(thumb.aspect, 0.01)
            if x > 0, x + w > width {
                x = 0
                y = (frames.map(\.maxY).max() ?? 0) + 10
            }
            frames.append(NSRect(x: x, y: y, width: w, height: h))
            x += w + 10
        }
        return frames
    }

    // MARK: Abrir e recolher

    func setExpanded(_ open: Bool) {
        isExpanded = open
        layer?.backgroundColor = open ? NSColor(calibratedWhite: 1, alpha: 0.06).cgColor : nil
        layer?.borderWidth = open ? 1 : 0
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.1).cgColor
        titleLabel.isHidden = open
        badge.isHidden = open
        for view in [titleField, notes, sendButton, removeButton, replyField] as [NSView] { view.isHidden = !open }
        thread.isHidden = !open || thread.messages.isEmpty
        notesPlaceholder.isHidden = !open || !notes.string.isEmpty
        meta.isHidden = !open || meta.stringValue.isEmpty
        thumbs.forEach { $0.view.isHidden = !open }
        if !open, isEditing { window?.makeFirstResponder(nil) }
        window?.invalidateCursorRects(for: self)
        needsLayout = true
    }

    func focusTitle() {
        window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectedRange = NSRange(location: titleField.stringValue.utf16.count, length: 0)
    }

    /// Recolhida: clique abre, arrasto reordena — os dois começam no mesmo
    /// mouseDown, e quem decide é o quanto o cursor andou. Aberta: o clique em
    /// qualquer parte do cartão é escrever, nunca fechar — o vazio dele leva o
    /// cursor para o fim das notas.
    override func mouseDown(with event: NSEvent) {
        guard !isExpanded else {
            window?.makeFirstResponder(notes)
            notes.setSelectedRange(NSRange(location: (notes.string as NSString).length, length: 0))
            return
        }
        press = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isExpanded, let press, let list = superview else { return }
        let point = event.locationInWindow
        if !dragged, hypot(point.x - press.x, point.y - press.y) < 4 { return }
        dragged = true
        list.autoscroll(with: event)
        onDragMove?(list.convert(point, from: nil).y)
    }

    override func mouseUp(with event: NSEvent) {
        defer { press = nil; dragged = false }
        guard !isExpanded, press != nil else { return }
        if dragged { onDragEnd?() } else { onExpand?() }
    }

    override func resetCursorRects() {
        if !isExpanded { HandCursor.fill(self) }
    }

    // MARK: Edição

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === titleField else { return }
        onEdit?(titleField.stringValue, notes.string)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === replyField {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let text = replyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    replyField.stringValue = ""
                    onReply?(text)
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCollapse?()
                return true
            default:
                return false
            }
        }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onCommitTitle?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCollapse?()
            return true
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)):
            window?.makeFirstResponder(notes)
            return true
        default:
            return false
        }
    }

    private func notesChanged() {
        notesPlaceholder.isHidden = !notes.string.isEmpty
        onEdit?(titleField.stringValue, notes.string)
        needsLayout = true
        onResize?()
    }

    @objc private func sendClicked() { onSend?() }

    @objc private func openThumb(_ gesture: NSClickGestureRecognizer) {
        guard let name = gesture.view?.identifier?.rawValue else { return }
        NSWorkspace.shared.open(store.url(of: name))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ handler: @escaping () -> Void) {
            menu.addItem(ClosureMenuItem(title: title, handler: handler))
        }
        if item.status == .pending { add("Enviar agora") { [weak self] in self?.onSend?() } }
        else { add("Voltar para pendente") { [weak self] in self?.onReopen?() } }
        menu.addItem(.separator())
        add("Mover para cima") { [weak self] in self?.onMove?(-1) }
        add("Mover para baixo") { [weak self] in self?.onMove?(1) }
        menu.addItem(.separator())
        add("Apagar") { [weak self] in self?.onRemove?() }
        return menu
    }

    // MARK: Medidas

    private func notesHeight(for width: CGFloat) -> CGFloat {
        guard let layout = notes.layoutManager, let container = notes.textContainer else { return Self.notesMinHeight }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return max(Self.notesMinHeight, ceil(layout.usedRect(for: container).height) + 4)
    }

    func height(for width: CGFloat) -> CGFloat {
        guard isExpanded else { return Self.collapsedHeight }
        var height: CGFloat = 8 + 28 + 8 + notesHeight(for: Self.inner(width))
        if let bottom = thumbFrames(width: Self.inner(width)).map(\.maxY).max() { height += 12 + bottom }
        if !thread.messages.isEmpty { height += 14 + thread.height(for: Self.inner(width)) }
        return height + 12 + 32 + 10 + 30 + 10
    }

    private static let textX: CGFloat = 42

    private static func inner(_ width: CGFloat) -> CGFloat { width - textX - 14 }

    override func layout() {
        super.layout()
        dot.frame = NSRect(x: 11, y: 10, width: 20, height: 20)
        let badgeWidth: CGFloat = isExpanded ? 0 : min(140, ceil(badge.intrinsicContentSize.width))
        badge.frame = NSRect(x: bounds.width - badgeWidth - 12, y: 12, width: badgeWidth, height: 16)
        titleLabel.frame = NSRect(x: Self.textX, y: 10, width: bounds.width - Self.textX - badgeWidth - 22, height: 20)

        let inner = Self.inner(bounds.width)
        titleField.frame = NSRect(x: Self.textX - 2, y: 7, width: inner + 4, height: 26)
        notes.frame = NSRect(x: Self.textX, y: 44, width: inner, height: notesHeight(for: inner))
        notesPlaceholder.frame = NSRect(x: Self.textX, y: 44, width: inner, height: 19)
        layoutThumbs()
        let thumbsBottom = thumbs.filter { !$0.view.isHidden }.map(\.view.frame.maxY).max() ?? notes.frame.maxY
        var y = thumbsBottom + 14
        if !thread.messages.isEmpty {
            let height = thread.height(for: inner)
            thread.frame = NSRect(x: Self.textX, y: y, width: inner, height: height)
            y += height + 12
        }
        replyField.frame = NSRect(x: Self.textX, y: y, width: inner, height: 30)

        let footer = bounds.height - 42
        sendButton.sizeToFit()
        sendButton.frame = NSRect(x: bounds.width - sendButton.frame.width - 12, y: footer + 2,
                                  width: sendButton.frame.width, height: 30)
        removeButton.frame = NSRect(x: sendButton.frame.minX - 36, y: footer + 3, width: 28, height: 28)
        meta.frame = NSRect(x: Self.textX, y: footer + 10, width: max(0, removeButton.frame.minX - Self.textX - 8),
                            height: 15)
    }

    private func layoutThumbs() {
        let top = notes.frame.maxY + 12
        for (thumb, frame) in zip(thumbs, thumbFrames(width: Self.inner(bounds.width))) {
            thumb.view.frame = frame.offsetBy(dx: Self.textX, dy: top)
            thumb.view.isHidden = !isExpanded
        }
    }
}

/// A thread da tarefa: o que o agente perguntou, comentou ou marcou, e o que
/// você respondeu — em ordem, com um fio à esquerda ligando tudo.
private final class ThreadView: NSView {
    private(set) var messages: [QueueMessage] = []
    private var blocks: [(head: NSTextField, body: NSTextField)] = []

    private static let bodyFont = NSFont.systemFont(ofSize: 13.5)
    private static let headHeight: CGFloat = 17
    private static let gap: CGFloat = 10
    private static let indent: CGFloat = 12

    override var isFlipped: Bool { true }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func set(_ messages: [QueueMessage]) {
        self.messages = messages
        blocks.forEach { $0.head.removeFromSuperview(); $0.body.removeFromSuperview() }
        blocks = messages.map { message in
            let (label, color): (String, NSColor) = switch message.kind {
            case .question: ("\(message.author ?? "agente") perguntou", .systemOrange)
            case .note: ("\(message.author ?? "agente") comentou", .systemTeal)
            case .done: ("\(message.author ?? "agente") marcou como feita", .systemGreen)
            case .reply: ("você", NSColor(calibratedWhite: 0.7, alpha: 1))
            }
            let head = NSTextField(labelWithString: "\(label) · \(Self.clock.string(from: message.at))")
            head.font = .systemFont(ofSize: 11.5, weight: .semibold)
            head.textColor = color
            let body = NSTextField(wrappingLabelWithString: message.text)
            body.font = Self.bodyFont
            body.textColor = NSColor(calibratedWhite: 0.88, alpha: 1)
            body.isSelectable = true
            body.isHidden = message.text.isEmpty
            addSubview(head)
            addSubview(body)
            return (head, body)
        }
        needsLayout = true
        needsDisplay = true
    }

    private static func bodyHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: bodyFont]).height) + 2
    }

    func height(for width: CGFloat) -> CGFloat {
        let inner = width - Self.indent
        return messages.enumerated().reduce(0) { total, entry in
            total + (entry.offset == 0 ? 0 : Self.gap) + Self.headHeight + Self.bodyHeight(entry.element.text, width: inner)
        }
    }

    override func layout() {
        super.layout()
        let inner = bounds.width - Self.indent
        var y: CGFloat = 0
        for (message, block) in zip(messages, blocks) {
            block.head.frame = NSRect(x: Self.indent, y: y, width: inner, height: Self.headHeight)
            y += Self.headHeight
            let height = Self.bodyHeight(message.text, width: inner)
            block.body.frame = NSRect(x: Self.indent, y: y, width: inner, height: height)
            y += height + Self.gap
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
        NSRect(x: 2, y: 2, width: 2, height: max(0, bounds.height - 4)).fill()
    }
}

/// O print com o X por cima, no canto.
private final class ThumbHolder: NSView {
    var image: NSView?
    var remove: NSView?
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        image?.frame = bounds
        let size = ThumbRemoveButton.size
        remove?.frame = NSRect(x: bounds.width - size - 6, y: 6, width: size, height: size)
    }
}

/// O X de tirar o print: círculo escuro com X branco, que aparece sobre
/// qualquer tela — o `xmark.circle.fill` do sistema sumia em print claro.
private final class ThumbRemoveButton: NSView {
    static let size: CGFloat = 26
    var onClick: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override func resetCursorRects() { HandCursor.fill(self) }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        (hovering ? NSColor.systemRed : NSColor.black.withAlphaComponent(0.72)).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        NSColor(calibratedWhite: 1, alpha: 0.35).setStroke()
        let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 1
        ring.stroke()
        let inset = bounds.insetBy(dx: bounds.width * 0.33, dy: bounds.height * 0.33)
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: inset.minX, y: inset.minY))
        cross.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        cross.move(to: NSPoint(x: inset.maxX, y: inset.minY))
        cross.line(to: NSPoint(x: inset.minX, y: inset.maxY))
        cross.lineWidth = 2.2
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }
}

/// O corpo da tarefa: texto puro, e print colado vira anexo dela em vez de um
/// borrão de RTF no meio das notas.
private final class QueueNotesView: NSTextView {
    var onChange: (() -> Void)?
    var onPasteImages: ((QueueStore.Pasted) -> Void)?
    var onEscape: (() -> Void)?

    override func paste(_ sender: Any?) {
        if let pasted = QueueStore.images(in: .general) { onPasteImages?(pasted) }
        else { pasteAsPlainText(sender) }
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?()
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        QueueStore.images(in: sender.draggingPasteboard) == nil ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pasted = QueueStore.images(in: sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        onPasteImages?(pasted)
        return true
    }
}

// MARK: - Nova tarefa

/// A última linha, sempre lá: escreve e dá Enter, e a tarefa entra na lista.
private final class QueueNewRow: NSView, NSTextFieldDelegate {
    var onCreate: ((String) -> Void)?
    let field = NSTextField()
    private let dot = StatusDot()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        dot.alphaValue = 0.45
        addSubview(dot)
        field.font = NSFont.systemFont(ofSize: 15)
        field.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderAttributedString = NSAttributedString(
            string: "Nova tarefa…",
            attributes: [.foregroundColor: NSColor(calibratedWhite: 0.4, alpha: 1), .font: NSFont.systemFont(ofSize: 15)])
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        addSubview(field)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(field) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let title = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return true }
        field.stringValue = ""
        onCreate?(title)
        return true
    }

    override func layout() {
        super.layout()
        dot.frame = NSRect(x: 11, y: 10, width: 20, height: 20)
        field.frame = NSRect(x: 40, y: 10, width: bounds.width - 48, height: 21)
    }
}

/// Item de menu com a ação num bloco — o menu de contexto da linha é montado
/// na hora, e alvo/seletor por item seria uma classe por ação.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

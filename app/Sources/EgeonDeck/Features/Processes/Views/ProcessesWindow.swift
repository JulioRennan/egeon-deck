import AppKit

/// A janela "Processos" (ADR-083): o que o Egeon lançou, por nó, com os órfãos
/// no topo e em laranja — é por eles que a janela existe.
final class ProcessesWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = ProcessesWindow()

    private enum Column: String, CaseIterable {
        case node, state, pid, age, command

        var title: String {
            switch self {
            case .node: return "Nó"
            case .state: return "Estado"
            case .pid: return "PID"
            case .age: return "Idade"
            case .command: return "Comando"
            }
        }

        var width: CGFloat {
            switch self {
            case .node: return 220
            case .state: return 70
            case .pid: return 64
            case .age: return 80
            case .command: return 420
            }
        }
    }

    private let table = NSTableView()
    private let summary = NSTextField(labelWithString: "")
    private let filter = NSSegmentedControl(labels: ["Todos", "Órfãos"], trackingMode: .selectOne,
                                            target: nil, action: nil)
    private let killOrphans = PointerButton(title: "Encerrar órfãos", target: nil, action: nil)
    private let killSelected = PointerButton(title: "Encerrar selecionados", target: nil, action: nil)
    private var all: [EgeonProcess] = []
    private var rows: [EgeonProcess] = []
    private var timer: Timer?
    private var scanning = false

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 480),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: true)
        window.title = "Processos do \(Flavor.current.displayName)"
        window.minSize = NSSize(width: 560, height: 260)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("processes")
        super.init(window: window)
        window.delegate = self
        build(in: window)
        NotificationCenter.default.addObserver(forName: OrphanReaper.didReap, object: nil, queue: .main) {
            [weak self] _ in self?.refresh()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refresh()
        // Enquanto está à vista: processo nasce e morre sem avisar ninguém.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    private func build(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        summary.font = .systemFont(ofSize: 12, weight: .medium)
        summary.textColor = .secondaryLabelColor
        filter.selectedSegment = 0
        filter.target = self
        filter.action = #selector(filterChanged)
        killOrphans.target = self
        killOrphans.action = #selector(killOrphansClicked)
        killSelected.target = self
        killSelected.action = #selector(killSelectedClicked)

        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 40
            table.addTableColumn(tableColumn)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .fullWidth
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.sizeLastColumnToFit()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let bar = NSStackView(views: [filter, summary, NSView(), killSelected, killOrphans])
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        for view in [bar, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        restyle()
    }

    private func refresh() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = ProcessScanner.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                self.show(found)
            }
        }
    }

    private func show(_ found: [EgeonProcess]) {
        let selected = Set(table.selectedRowIndexes.map { rows[$0].pid })
        all = ProcessList.ordered(found)
        rows = filter.selectedSegment == 1 ? all.filter(\.orphan) : all
        table.reloadData()
        table.selectRowIndexes(IndexSet(rows.indices.filter { selected.contains(rows[$0].pid) }),
                               byExtendingSelection: false)
        restyle()
    }

    private func restyle() {
        let orphans = all.filter(\.orphan).count
        summary.stringValue = "\(all.count - orphans) no app · \(orphans) órfão\(orphans == 1 ? "" : "s")"
        let reaper = OrphanReaper.shared
        if !reaper.policy.enabled {
            summary.stringValue += " · limpeza automática desligada"
        } else if let last = reaper.last {
            let time = DateFormatter.localizedString(from: last.date, dateStyle: .none, timeStyle: .short)
            summary.stringValue += " · última limpeza \(time): \(last.count) encerrado\(last.count == 1 ? "" : "s")"
        } else {
            summary.stringValue += " · limpeza a cada \(Int(reaper.policy.intervalMinutes)) min"
        }
        killOrphans.isEnabled = orphans > 0
        killSelected.isEnabled = !table.selectedRowIndexes.isEmpty
    }

    @objc private func filterChanged() { show(all) }

    @objc private func killOrphansClicked() {
        let count = all.filter(\.orphan).count
        confirm("Encerrar \(count) processo\(count == 1 ? "" : "s") órfão\(count == 1 ? "" : "s")?") {
            ProcessScanner.terminate(nil)
        }
    }

    @objc private func killSelectedClicked() {
        let pids = Set(table.selectedRowIndexes.map { rows[$0].pid })
        let live = rows.filter { pids.contains($0.pid) && !$0.orphan }.count
        // Processo no app é de um terminal aberto: avisar, porque pode ser o
        // próprio agente.
        let extra = live > 0 ? " \(live) ainda são de terminal aberto." : ""
        confirm("Encerrar \(pids.count) processo\(pids.count == 1 ? "" : "s")?" + extra) {
            ProcessScanner.terminate(pids)
        }
    }

    private func confirm(_ message: String, _ action: @escaping () -> [EgeonProcess]) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Recebem SIGTERM — o mesmo que fechar o terminal deles."
        alert.addButton(withTitle: "Encerrar")
        alert.addButton(withTitle: "Cancelar")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                _ = action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refresh() }
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableViewSelectionDidChange(_ notification: Notification) { restyle() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, let column = Column(rawValue: id.rawValue) else { return nil }
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField ?? {
            let field = NSTextField(labelWithString: "")
            field.identifier = id
            field.lineBreakMode = column == .command ? .byTruncatingMiddle : .byTruncatingTail
            return field
        }()
        let process = rows[row]
        cell.textColor = .labelColor
        cell.font = .systemFont(ofSize: 12)
        switch column {
        case .node:
            cell.stringValue = process.node ?? "app"
        case .state:
            cell.stringValue = process.orphan ? "órfão" : "no app"
            cell.textColor = process.orphan ? .systemOrange : .secondaryLabelColor
        case .pid:
            cell.stringValue = "\(process.pid)"
            cell.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        case .age:
            cell.stringValue = ProcessList.age(Date().timeIntervalSince(process.started))
            cell.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        case .command:
            cell.stringValue = process.command
            cell.textColor = .secondaryLabelColor
            cell.toolTip = process.command
        }
        return cell
    }
}

/// Botão com a mão: aqui se clica (ADR-048).
private final class PointerButton: NSButton {
    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
    }

    override func resetCursorRects() {
        if isEnabled { HandCursor.fill(self) }
    }
}

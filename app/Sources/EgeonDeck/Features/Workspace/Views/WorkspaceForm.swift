import AppKit

/// Nome, imagem e pastas — o formulário de criar e de editar workspace.
///
/// As pastas entram aqui, e não uma a uma depois, porque é assim que se
/// define um workspace: "estes repositórios são deste assunto". Cada pasta vira
/// um projeto; a que já era projeto continua com o id dela.
///
/// Embaixo, os multi-projetos: um nome e algumas das pastas de cima, juntas
/// numa pasta só para a bancada (ADR-065). As pastas continuam sendo projetos
/// sozinhas — bancada só do backend e bancada do conjunto convivem.
final class WorkspaceForm: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Result {
        var name: String
        var folders: [String]
        var multis: [MultiProjectDraft]
        /// Imagem nova escolhida, para copiar para a pasta do workspace.
        var iconSource: URL?
        /// Você pediu para tirar a imagem que havia.
        var clearIcon: Bool
    }

    private let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    private let badge = WorkspaceBadge(side: 44)
    private let table = NSTableView()
    private let multiTable = NSTableView()
    private var folders: [String]
    private var multis: [MultiProjectDraft]
    private var iconSource: URL?
    private var clearIcon = false
    private let hadIcon: Bool

    private init(existing: WorkspaceConfig?) {
        folders = existing?.projects.filter { !$0.isMulti }.map(\.path) ?? []
        multis = existing.map(MultiProject.drafts) ?? []
        hadIcon = existing?.icon != nil
        super.init()
        nameField.stringValue = existing?.name ?? ""
        nameField.placeholderString = "nome do workspace"
        if let existing { badge.show(existing) } else { badge.preview(nil, initial: "?") }
    }

    static func ask(existing: WorkspaceConfig? = nil) -> Result? {
        let form = WorkspaceForm(existing: existing)
        return form.run(editing: existing != nil)
    }

    private func run(editing: Bool) -> Result? {
        let alert = NSAlert()
        alert.messageText = editing ? "Editar workspace" : "Novo workspace"
        alert.informativeText = "Cada pasta vira um projeto; um multi-projeto junta algumas delas "
            + "numa pasta só. As bancadas se organizam por projeto."
        alert.addButton(withTitle: editing ? "Salvar" : "Criar")
        alert.addButton(withTitle: "Cancelar")

        let width: CGFloat = 320
        // O que já existia sobe inteiro `lift`: os multi-projetos entram por baixo.
        let lift: CGFloat = 136
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 246 + lift))

        badge.frame = NSRect(x: 0, y: 200 + lift, width: 44, height: 44)
        container.addSubview(badge)

        nameField.frame = NSRect(x: 54, y: 210 + lift, width: width - 54, height: 24)
        container.addSubview(nameField)

        let pick = HandButton(title: "Imagem…", target: self, action: #selector(pickImage))
        pick.bezelStyle = .rounded
        pick.controlSize = .small
        pick.frame = NSRect(x: 54, y: 184 + lift, width: 84, height: 22)
        container.addSubview(pick)

        let none = HandButton(title: "Sem imagem", target: self, action: #selector(dropImage))
        none.bezelStyle = .rounded
        none.controlSize = .small
        none.frame = NSRect(x: 142, y: 184 + lift, width: 96, height: 22)
        container.addSubview(none)

        let label = NSTextField(labelWithString: "Pastas (projetos)")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.frame = NSRect(x: 0, y: 160 + lift, width: width, height: 16)
        container.addSubview(label)

        let column = NSTableColumn(identifier: .init("path"))
        column.width = width - 20
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 18
        table.allowsMultipleSelection = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 30 + lift, width: width, height: 126))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        container.addSubview(scroll)

        let add = HandButton(title: "Adicionar pastas…", target: self, action: #selector(addFolders))
        add.bezelStyle = .rounded
        add.controlSize = .small
        add.frame = NSRect(x: 0, y: lift, width: 130, height: 22)
        container.addSubview(add)

        let remove = HandButton(title: "Tirar selecionadas", target: self, action: #selector(removeSelected))
        remove.bezelStyle = .rounded
        remove.controlSize = .small
        remove.frame = NSRect(x: 134, y: lift, width: 130, height: 22)
        container.addSubview(remove)

        let multiLabel = NSTextField(labelWithString: "Multi-projetos")
        multiLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        multiLabel.frame = NSRect(x: 0, y: 112, width: width, height: 16)
        container.addSubview(multiLabel)

        let multiColumn = NSTableColumn(identifier: .init("multi"))
        multiColumn.width = width - 20
        multiTable.addTableColumn(multiColumn)
        multiTable.headerView = nil
        multiTable.dataSource = self
        multiTable.delegate = self
        multiTable.rowHeight = 18
        multiTable.target = self
        multiTable.doubleAction = #selector(editMulti)
        let multiScroll = NSScrollView(frame: NSRect(x: 0, y: 30, width: width, height: 78))
        multiScroll.documentView = multiTable
        multiScroll.hasVerticalScroller = true
        multiScroll.borderType = .bezelBorder
        container.addSubview(multiScroll)

        let addMulti = HandButton(title: "Novo multi-projeto…", target: self, action: #selector(newMulti))
        addMulti.bezelStyle = .rounded
        addMulti.controlSize = .small
        addMulti.frame = NSRect(x: 0, y: 0, width: 140, height: 22)
        container.addSubview(addMulti)

        let editButton = HandButton(title: "Editar…", target: self, action: #selector(editMulti))
        editButton.bezelStyle = .rounded
        editButton.controlSize = .small
        editButton.frame = NSRect(x: 144, y: 0, width: 70, height: 22)
        container.addSubview(editButton)

        let removeMulti = HandButton(title: "Tirar", target: self, action: #selector(removeSelectedMulti))
        removeMulti.bezelStyle = .rounded
        removeMulti.controlSize = .small
        removeMulti.frame = NSRect(x: 218, y: 0, width: 60, height: 22)
        container.addSubview(removeMulti)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        return Result(name: typed, folders: folders, multis: multis, iconSource: iconSource,
                      clearIcon: clearIcon && iconSource == nil)
    }

    @objc private func pickImage() {
        let panel = NSOpenPanel()
        panel.title = "Imagem do workspace"
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        iconSource = url
        clearIcon = false
        badge.preview(NSImage(contentsOf: url), initial: initial)
    }

    @objc private func dropImage() {
        iconSource = nil
        clearIcon = hadIcon
        badge.preview(nil, initial: initial)
    }

    private var initial: String {
        String(nameField.stringValue.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    @objc private func addFolders() {
        let panel = NSOpenPanel()
        panel.title = "Pastas do workspace"
        panel.message = "Escolha uma ou mais pastas — cada uma vira um projeto."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Adicionar"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = (ProjectConfig.normalize(url.path) as NSString).abbreviatingWithTildeInPath
            guard !folders.contains(where: { ProjectConfig.normalize($0) == ProjectConfig.normalize(path) })
            else { continue }
            folders.append(path)
        }
        table.reloadData()
    }

    @objc private func removeSelected() {
        let rows = table.selectedRowIndexes
        guard !rows.isEmpty else { return }
        let gone = rows.map { folders[$0] }
        folders = folders.enumerated().filter { !rows.contains($0.offset) }.map(\.element)
        // A pasta que saiu sai também dos conjuntos: multi-projeto aponta para
        // projeto deste workspace, e ela deixou de ser.
        for i in multis.indices {
            multis[i].folders.removeAll { folder in
                gone.contains { ProjectConfig.normalize($0) == ProjectConfig.normalize(folder) }
            }
        }
        table.reloadData()
        multiTable.reloadData()
    }

    @objc private func newMulti() {
        guard let draft = MultiProjectEditor.ask(MultiProjectDraft(name: "", folders: []),
                                                 folders: folders) else { return }
        multis.append(draft)
        multiTable.reloadData()
    }

    @objc private func editMulti() {
        let row = multiTable.selectedRow >= 0 ? multiTable.selectedRow : multiTable.clickedRow
        guard row >= 0, row < multis.count,
              let draft = MultiProjectEditor.ask(multis[row], folders: folders) else { return }
        multis[row] = draft
        multiTable.reloadData()
    }

    @objc private func removeSelectedMulti() {
        let row = multiTable.selectedRow
        guard row >= 0, row < multis.count else { return }
        multis.remove(at: row)
        multiTable.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === multiTable ? multis.count : folders.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = tableView === multiTable
            ? "\(multis[row].name) — \(multis[row].summary.isEmpty ? "nenhuma pasta" : multis[row].summary)"
            : folders[row]
        let cell = NSTextField(labelWithString: text)
        cell.font = .systemFont(ofSize: 11)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }
}

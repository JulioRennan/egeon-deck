import AppKit

/// Nome, imagem e pastas — o formulário de criar e de editar workspace.
///
/// As pastas entram aqui, e não uma a uma depois, porque é assim que se
/// define um workspace: "estes repositórios são deste assunto". Cada pasta vira
/// um projeto; a que já era projeto continua com o id dela.
final class WorkspaceForm: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Result {
        var name: String
        var folders: [String]
        /// Imagem nova escolhida, para copiar para a pasta do workspace.
        var iconSource: URL?
        /// Você pediu para tirar a imagem que havia.
        var clearIcon: Bool
    }

    private let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    private let badge = WorkspaceBadge(side: 44)
    private let table = NSTableView()
    private var folders: [String]
    private var iconSource: URL?
    private var clearIcon = false
    private let hadIcon: Bool

    private init(existing: WorkspaceConfig?) {
        folders = existing?.projects.map(\.path) ?? []
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
        alert.informativeText = "Cada pasta vira um projeto; as bancadas se organizam por projeto."
        alert.addButton(withTitle: editing ? "Salvar" : "Criar")
        alert.addButton(withTitle: "Cancelar")

        let width: CGFloat = 320
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 246))

        badge.frame = NSRect(x: 0, y: 200, width: 44, height: 44)
        container.addSubview(badge)

        nameField.frame = NSRect(x: 54, y: 210, width: width - 54, height: 24)
        container.addSubview(nameField)

        let pick = HandButton(title: "Imagem…", target: self, action: #selector(pickImage))
        pick.bezelStyle = .rounded
        pick.controlSize = .small
        pick.frame = NSRect(x: 54, y: 184, width: 84, height: 22)
        container.addSubview(pick)

        let none = HandButton(title: "Sem imagem", target: self, action: #selector(dropImage))
        none.bezelStyle = .rounded
        none.controlSize = .small
        none.frame = NSRect(x: 142, y: 184, width: 96, height: 22)
        container.addSubview(none)

        let label = NSTextField(labelWithString: "Pastas (projetos)")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.frame = NSRect(x: 0, y: 160, width: width, height: 16)
        container.addSubview(label)

        let column = NSTableColumn(identifier: .init("path"))
        column.width = width - 20
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 18
        table.allowsMultipleSelection = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 30, width: width, height: 126))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        container.addSubview(scroll)

        let add = HandButton(title: "Adicionar pastas…", target: self, action: #selector(addFolders))
        add.bezelStyle = .rounded
        add.controlSize = .small
        add.frame = NSRect(x: 0, y: 0, width: 130, height: 22)
        container.addSubview(add)

        let remove = HandButton(title: "Tirar selecionadas", target: self, action: #selector(removeSelected))
        remove.bezelStyle = .rounded
        remove.controlSize = .small
        remove.frame = NSRect(x: 134, y: 0, width: 130, height: 22)
        container.addSubview(remove)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        return Result(name: typed, folders: folders, iconSource: iconSource,
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
        folders = folders.enumerated().filter { !rows.contains($0.offset) }.map(\.element)
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { folders.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: folders[row])
        cell.font = .systemFont(ofSize: 11)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }
}

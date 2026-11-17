import AppKit

/// Branch da bancada e de cada repositório de um multi-projeto (ADR-065).
///
/// As linhas dos repos acompanham a branch da bancada enquanto você não mexe
/// nelas — o caso normal é a mesma branch em todos. Mexeu, a linha é sua;
/// esvaziá-la volta a acompanhar.
final class MultiWorktreeForm: NSObject, NSTextFieldDelegate {
    struct Result {
        var branch: String
        var template: String?
        /// Só os repos com branch diferente da da bancada.
        var overrides: [String: String]
    }

    private let branchField = NSTextField(frame: .zero)
    private var repoFields: [NSTextField] = []
    private var edited: Set<Int> = []

    static func ask(project: ProjectConfig, links: [String], offersTemplate: Bool) -> Result? {
        MultiWorktreeForm().run(project: project, links: links, offersTemplate: offersTemplate)
    }

    private func run(project: ProjectConfig, links: [String], offersTemplate: Bool) -> Result? {
        let alert = NSAlert()
        alert.messageText = "Worktree de \(project.name)"
        alert.informativeText = "Todos numa pasta só, com o nome da branch da bancada. "
            + "Cada repo segue essa branch, a não ser que você troque a dele. "
            + "Branch que já existe é aberta, não recriada."
        alert.addButton(withTitle: "Abrir")
        alert.addButton(withTitle: "Cancelar")

        let width: CGFloat = 380
        let row: CGFloat = 26
        let labelWidth: CGFloat = 130
        let templateHeight: CGFloat = offersTemplate ? 34 : 0
        let height = 22 + 24 + 14 + 16 + CGFloat(links.count) * row + templateHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        var y = height

        func caption(_ text: String) {
            y -= 16
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 10, weight: .semibold)
            field.textColor = .secondaryLabelColor
            field.frame = NSRect(x: 0, y: y, width: width, height: 13)
            container.addSubview(field)
        }

        caption("BRANCH DA BANCADA")
        y -= 28
        branchField.frame = NSRect(x: 0, y: y + 2, width: width, height: 24)
        branchField.placeholderString = "ex.: feat/login"
        branchField.delegate = self
        container.addSubview(branchField)

        y -= 8
        caption("POR REPOSITÓRIO")
        for link in links {
            y -= row
            let name = NSTextField(labelWithString: link)
            name.font = .systemFont(ofSize: 11)
            name.lineBreakMode = .byTruncatingMiddle
            name.frame = NSRect(x: 0, y: y + 4, width: labelWidth - 8, height: 16)
            container.addSubview(name)

            let field = NSTextField(frame: NSRect(x: labelWidth, y: y + 1, width: width - labelWidth, height: 22))
            field.font = .systemFont(ofSize: 11)
            field.placeholderString = "a mesma da bancada"
            field.delegate = self
            container.addSubview(field)
            repoFields.append(field)
        }

        let picker = HandPopUpButton(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        let vazio = "Começar vazia"
        if offersTemplate {
            picker.addItem(withTitle: vazio)
            let templates = WorkbenchTemplateStore.names
            if !templates.isEmpty {
                picker.menu?.addItem(.separator())
                picker.addItems(withTitles: templates)
            }
            container.addSubview(picker)
        }

        alert.accessoryView = container
        alert.window.initialFirstResponder = branchField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return nil }
        var overrides: [String: String] = [:]
        for (link, field) in zip(links, repoFields) {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, value != branch { overrides[link] = value }
        }
        let chosen = offersTemplate ? picker.titleOfSelectedItem : nil
        return Result(branch: branch, template: chosen == vazio ? nil : chosen, overrides: overrides)
    }

    func controlTextDidChange(_ note: Notification) {
        guard let field = note.object as? NSTextField else { return }
        if field === branchField {
            for (i, repo) in repoFields.enumerated() where !edited.contains(i) {
                repo.stringValue = branchField.stringValue
            }
        } else if let i = repoFields.firstIndex(where: { $0 === field }) {
            if field.stringValue.isEmpty { edited.remove(i) } else { edited.insert(i) }
        }
    }
}

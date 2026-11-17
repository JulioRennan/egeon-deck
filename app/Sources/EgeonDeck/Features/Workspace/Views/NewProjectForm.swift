import AppKit

/// Nome, pasta-mãe e `git init` — o formulário do "Novo projeto…" (ADR-092).
///
/// Nome inválido volta para o formulário com o que você digitou, em vez de
/// fechar e obrigar a recomeçar.
final class NewProjectForm: NSObject {
    struct Result {
        var plan: NewProject.Plan
        var git: Bool
    }

    private let workspace: WorkspaceConfig
    private let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    private let parentLabel = NSTextField(labelWithString: "")
    private let gitBox = NSButton(checkboxWithTitle: "Iniciar repositório git", target: nil, action: nil)
    private var parent: String

    private init(workspace: WorkspaceConfig) {
        self.workspace = workspace
        parent = NewProject.suggestedParent(for: workspace)
        super.init()
        nameField.placeholderString = "nome da pasta"
        gitBox.state = .on
    }

    static func ask(in workspace: WorkspaceConfig) -> Result? {
        NewProjectForm(workspace: workspace).run()
    }

    private func run() -> Result? {
        var problem: String?
        while true {
            guard let typed = present(problem: problem) else { return nil }
            switch NewProject.plan(name: typed, parent: parent, in: workspace, kind: NewProject.diskKind) {
            case .success(let plan): return Result(plan: plan, git: gitBox.state == .on)
            case .failure(let failure): problem = failure.message
            }
        }
    }

    private func present(problem: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = "Novo projeto em \"\(workspace.name)\""
        alert.informativeText = problem
            ?? "Cria a pasta e a põe no workspace. Pasta que já existe com esse nome é só adicionada."
        if problem != nil { alert.alertStyle = .warning }
        alert.addButton(withTitle: "Criar")
        alert.addButton(withTitle: "Cancelar")

        let width: CGFloat = 320
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 84))
        nameField.frame = NSRect(x: 0, y: 60, width: width, height: 24)
        container.addSubview(nameField)

        let caption = NSTextField(labelWithString: "em")
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: 0, y: 34, width: 20, height: 16)
        container.addSubview(caption)

        parentLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        parentLabel.lineBreakMode = .byTruncatingMiddle
        parentLabel.stringValue = parent
        parentLabel.frame = NSRect(x: 22, y: 34, width: width - 112, height: 16)
        container.addSubview(parentLabel)

        let choose = HandButton(title: "Escolher…", target: self, action: #selector(chooseParent))
        choose.bezelStyle = .rounded
        choose.controlSize = .small
        choose.frame = NSRect(x: width - 84, y: 30, width: 84, height: 22)
        container.addSubview(choose)

        gitBox.frame = NSRect(x: 0, y: 0, width: width, height: 20)
        container.addSubview(gitBox)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return nameField.stringValue
    }

    @objc private func chooseParent() {
        let panel = NSOpenPanel()
        panel.title = "Onde criar o projeto"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        panel.directoryURL = URL(fileURLWithPath: ProjectConfig.normalize(parent))
        guard panel.runModal() == .OK, let url = panel.url else { return }
        parent = (ProjectConfig.normalize(url.path) as NSString).abbreviatingWithTildeInPath
        parentLabel.stringValue = parent
    }
}

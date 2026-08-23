import AppKit

final class NodeWorktreeRow: NSView {
    let plan: NodeWorktree
    /// Você mexeu na branch desta linha — a sugestão da bancada não a reescreve mais.
    private(set) var touched = false

    private let branchField = NSTextField()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var observer: NSObjectProtocol?
    /// As branches do repositório DESTE terminal — cada linha pode estar em um
    /// repositório diferente, e é o que torna a resposta por linha diferente.
    private let branches: Worktree.BranchIndex?
    /// A branch da bancada, para saber se esta linha diverge dela.
    private var workbenchBranch: String

    static let height: CGFloat = 40

    init(plan: NodeWorktree, width: CGFloat, workbenchBranch: String,
         branches: Worktree.BranchIndex?) {
        self.plan = plan
        self.workbenchBranch = workbenchBranch
        self.branches = branches
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        title.stringValue = plan.nodeID
        title.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        addSubview(title)

        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        addSubview(detail)

        branchField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        branchField.stringValue = plan.branch
        branchField.placeholderString = "não levar"
        addSubview(branchField)

        // Pasta que não está em git nenhum não tem worktree para criar. A linha
        // aparece de propósito: é a chance de ver onde aquele terminal abre, que é
        // exatamente a informação que faltava quando as pastas embaralharam.
        if plan.repoRoot == nil {
            branchField.isEditable = false
            branchField.isHidden = true
            detail.stringValue = FileManager.default.fileExists(atPath: plan.currentPath)
                ? "\(NodeWorktreePlanner.short(plan.currentPath)) · não é repositório git"
                : "\(NodeWorktreePlanner.short(plan.currentPath)) · esta pasta não existe"
            detail.textColor = FileManager.default.fileExists(atPath: plan.currentPath)
                ? .secondaryLabelColor : .systemOrange
        } else {
            describePlan()
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: branchField,
            queue: .main) { [weak self] _ in
                self?.touched = true
                self?.describePlan()
            }
    }

    /// O que vai acontecer com a branch escrita nesta linha: ir junto com a bancada,
    /// abrir worktree própria — criando a branch, entrando na que já existe, ou
    /// usando a worktree que já a tem aberta (ADR-018) — ou ficar onde está.
    private func describePlan() {
        guard let branches else { return }
        let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !branch.isEmpty else {
            detail.stringValue = "\(plan.repoName) · fica no repositório original"
            detail.textColor = .systemOrange
            return
        }
        guard resolved.enabled else {
            detail.stringValue = "\(plan.repoName) · vai junto com a bancada"
            detail.textColor = .secondaryLabelColor
            return
        }

        let verdict = branches.plan(for: branch)
        detail.stringValue = "\(plan.repoName) · worktree própria · \(verdict.short)"
        detail.textColor = verdict.isFresh ? .secondaryLabelColor : .systemOrange
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let branchWidth: CGFloat = 170
        let textWidth = max(0, bounds.width - branchWidth - 10)
        title.frame = NSRect(x: 0, y: 4, width: textWidth, height: 14)
        detail.frame = NSRect(x: 0, y: 20, width: textWidth, height: 13)
        branchField.frame = NSRect(x: bounds.width - branchWidth, y: 9,
                                   width: branchWidth, height: 22)
    }

    /// A branch da bancada mudou. Reescreve só quem você não customizou.
    func suggest(branch: String) {
        workbenchBranch = branch
        guard !touched, !branchField.isHidden else {
            // Linha customizada não muda de texto, mas muda de significado: a
            // branch dela pode ter deixado de divergir da bancada.
            describePlan()
            return
        }
        branchField.stringValue = branch
        // Escrever no campo por código não dispara `textDidChange`.
        describePlan()
    }

    /// O plano desta linha depois do que você escreveu.
    var resolved: NodeWorktree {
        var copy = plan
        copy.branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.touched = touched
        return copy.decided(workbenchBranch: workbenchBranch)
    }
}

import AppKit

/// O que acontece com a pasta de um terminal quando a sessão vira worktree.
///
/// Existe porque uma frente de trabalho raramente é um repositório só: o card do
/// frontend abre no repo da sessão, e o do backend abre num repo vizinho. Uma
/// branch nova precisa dos DOIS em worktree, senão o agente do backend continua
/// commitando no checkout principal enquanto o do frontend trabalha na branch
/// nova.
struct NodeWorktree {
    let nodeID: String
    /// Onde este nó abre hoje, já resolvido.
    let currentPath: String
    /// Raiz do repositório em que `currentPath` cai. Nulo quando não é git.
    let repoRoot: String?

    /// A pasta está dentro da pasta da sessão?
    ///
    /// Quem está dentro não escolhe nada: o `cwd` relativo já o leva para a pasta
    /// equivalente da worktree, e é justamente isso que o `cwd` relativo existe
    /// para fazer.
    ///
    /// Por contenção de caminho, e não por identidade de repositório: é essa a
    /// regra que `repointed` de fato aplica, e duas worktrees do MESMO repo são
    /// pastas diferentes — dizer "segue a sessão" ali esconderia a escolha.
    let followsSession: Bool

    /// Criar worktree própria para este terminal?
    var enabled: Bool
    /// Branch da worktree deste terminal. Nasce igual à da sessão.
    var branch: String
    /// Você editou a branch deste terminal à mão?
    ///
    /// Governa o re-sugerir: mudar a branch da sessão reescreve as linhas que você
    /// não tocou, e deixa em paz as que você customizou.
    var touched = false

    var repoName: String { ((repoRoot ?? currentPath) as NSString).lastPathComponent }

    /// Onde a worktree deste terminal nasce. Mesma convenção da sessão.
    var destination: String? {
        guard let repoRoot, enabled else { return nil }
        return Worktree.suggestedPath(repoRoot: repoRoot, branch: branch)
    }
}

enum NodeWorktreePlanner {
    /// Levanta o estado de cada nó que tem pasta.
    ///
    /// Nó `web` fica fora: ele não abre pasta nenhuma. Editor entra junto dos
    /// terminais — ele também resolve `cwd`, e um editor apontado para o repo
    /// vizinho tem o mesmo problema.
    static func inspect(_ config: SessionConfig,
                        sessionRoot: String,
                        branch: String) -> [NodeWorktree] {
        config.nodes.compactMap { node in
            guard node.type != .web else { return nil }

            let path = config.resolvedDirectory(for: node)
            let inside = path == sessionRoot || path.hasPrefix(sessionRoot + "/")
            // Pasta que não existe não tem repositório para inspecionar, e chamar
            // o git nela só produziria erro. O nó aparece na lista de qualquer
            // jeito: é a chance de você ver que ele está quebrado.
            //
            // Pelo checkout PRINCIPAL: um terminal que já está numa worktree, se
            // partisse dela, aninharia worktree dentro de worktree.
            let root = FileManager.default.fileExists(atPath: path)
                ? Worktree.mainRepo(of: path)
                : nil

            return NodeWorktree(
                nodeID: node.id,
                currentPath: path,
                repoRoot: root,
                followsSession: inside,
                // Repo vizinho vem marcado: é o caso em que a worktree é quase
                // sempre o que se quer, e desmarcar é um clique.
                enabled: !inside && root != nil,
                branch: branch)
        }
    }

    /// Cria as worktrees dos terminais e devolve, por nó, o `cwd` novo.
    ///
    /// Nós que caem no mesmo `destination` — mesmo repo e mesma branch —
    /// compartilham uma worktree, e o git só é chamado uma vez. Nomes diferentes no
    /// mesmo repo viram worktrees diferentes, que é o que a customização por
    /// terminal significa.
    ///
    /// O que falha não derruba o resto: o terminal fica apontando para o
    /// repositório original, que é onde ele estava, e o erro vai para o log.
    static func materialize(_ plans: [NodeWorktree],
                            onCreate: (String, String) -> Void) -> [String: String] {
        var created: [String: String] = [:]   // destino → caminho pronto
        var cwdByNode: [String: String] = [:]

        for plan in plans {
            guard plan.enabled, let repoRoot = plan.repoRoot,
                  let destination = plan.destination else { continue }

            if let ready = created[destination] {
                cwdByNode[plan.nodeID] = short(ready)
                Log.write("worktree por terminal: \"\(plan.nodeID)\" divide "
                          + "\(destination) com outro terminal")
                continue
            }

            do {
                // O nome que você escreveu, sem sufixo somado por baixo: se a
                // branch já existe, é nela que o terminal abre. Ver ADR-018.
                let result = try Worktree.create(from: repoRoot, branch: plan.branch,
                                                 destination: destination, carryDirty: true)
                created[destination] = result.path
                cwdByNode[plan.nodeID] = short(result.path)
                // Worktree reaproveitada tem trabalho dentro. Copiar `.env` e
                // `node_modules` por cima do que já está lá é sobrescrever
                // configuração de alguém que não pediu nada.
                if !result.reused { onCreate(repoRoot, result.path) }
                Log.write("worktree por terminal: \"\(plan.nodeID)\" → \(result.path)"
                          + (result.reused ? " (worktree que já existia)" : ""))
            } catch {
                Log.write("worktree por terminal: \"\(plan.nodeID)\" falhou em "
                          + "\(plan.repoName) — \(error). Segue apontando para \(repoRoot)")
                cwdByNode[plan.nodeID] = short(repoRoot)
            }
        }
        return cwdByNode
    }

    /// `/Users/você/x` → `~/x`. O que vai para o `sessions.json` é feito para ser
    /// lido e editado à mão.
    static func short(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Worktree de um terminal só

    struct SingleForm {
        let branch: String
        let destination: String
    }

    /// Pergunta a branch e a pasta da worktree de UM terminal.
    ///
    /// Existe à parte do formulário da sessão porque é outro momento: a sessão já
    /// está montada, e o que você quer é levar um card — o do backend, quase
    /// sempre — para uma branch nova sem mexer no resto.
    static func ask(nodeID: String, repoRoot: String, currentPath: String,
                    status: Worktree.Status, suggestedBranch: String) -> SingleForm? {
        let repo = (repoRoot as NSString).lastPathComponent

        let alert = NSAlert()
        alert.messageText = "Worktree para \"\(nodeID)\""
        alert.informativeText = "O terminal passa a abrir na worktree de \(repo), "
            + "e sai de \(short(currentPath)).\n\n"
            + "O processo reinicia — não há como trocar o diretório de um pty em curso — e a "
            + "conversa do agente começa do zero. Id, papel, arestas e posição no canvas "
            + "continuam os mesmos."
        alert.addButton(withTitle: "Abrir")
        alert.addButton(withTitle: "Cancelar")

        let width: CGFloat = 420
        let container = FormView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        var y: CGFloat = 0

        func label(_ text: String) {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 10, weight: .semibold)
            field.textColor = .secondaryLabelColor
            field.frame = NSRect(x: 0, y: y, width: width, height: 13)
            container.addSubview(field)
            y += 17
        }

        label("BRANCH")
        let branchField = NSTextField(frame: NSRect(x: 0, y: y, width: width, height: 22))
        branchField.stringValue = suggestedBranch
        container.addSubview(branchField)
        y += 25

        // O que vai acontecer com o nome que está escrito agora. Ver ADR-018: a
        // mesma caixa serve para criar branch e para ir para uma que já existe, e
        // sem esta linha as duas são visualmente idênticas.
        let verdict = NSTextField(labelWithString: "")
        verdict.font = .systemFont(ofSize: 10)
        verdict.maximumNumberOfLines = 2
        verdict.frame = NSRect(x: 0, y: y, width: width, height: 26)
        container.addSubview(verdict)
        y += 30

        label("PASTA DA WORKTREE")
        let pathField = NSTextField(frame: NSRect(x: 0, y: y, width: width, height: 22))
        pathField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        container.addSubview(pathField)
        y += 22

        var pathTouched = false
        // Lido uma vez: um `git worktree list` por tecla digitada seria três
        // processos por caractere na thread que segura o modal.
        let branches = Worktree.index(of: repoRoot)

        func refresh() {
            let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let plan = branches.plan(for: branch)
            verdict.stringValue = plan.summary(comingFrom: status.branch,
                                               dirty: status.hasDirtyTracked)
            verdict.textColor = plan.isFresh ? .secondaryLabelColor : .systemOrange

            if case .alreadyCheckedOut(let existing) = plan {
                // A pasta não é escolha: ela já existe, com trabalho dentro.
                pathField.stringValue = short(existing)
                pathField.isEditable = false
                pathField.textColor = .secondaryLabelColor
            } else {
                pathField.isEditable = true
                pathField.textColor = .labelColor
                if !pathTouched {
                    pathField.stringValue = Worktree.suggestedPath(repoRoot: repoRoot,
                                                                   branch: branch)
                }
            }
        }
        refresh()

        let pathObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: pathField, queue: .main) { _ in
                pathTouched = true
            }
        let branchObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: branchField, queue: .main) { _ in
                refresh()
            }
        defer {
            NotificationCenter.default.removeObserver(pathObserver)
            NotificationCenter.default.removeObserver(branchObserver)
        }

        container.setFrameSize(NSSize(width: width, height: y))
        alert.accessoryView = container
        alert.window.initialFirstResponder = branchField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = (pathField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !branch.isEmpty, !destination.isEmpty else { return nil }
        return SingleForm(branch: branch, destination: destination)
    }
}

// MARK: - A lista de terminais no formulário de worktree

/// Uma linha por terminal: quem é, em que repositório está, e com que branch a
/// worktree dele nasce.
final class NodeWorktreeRow: NSView {
    let plan: NodeWorktree
    /// Você mexeu na branch desta linha — a sugestão da sessão não a reescreve mais.
    private(set) var touched = false

    private let toggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let branchField = NSTextField()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var observer: NSObjectProtocol?
    /// As branches do repositório DESTE terminal — cada linha pode estar em um
    /// repositório diferente, e é o que torna a resposta por linha diferente.
    private let branches: Worktree.BranchIndex?

    static let height: CGFloat = 40

    init(plan: NodeWorktree, width: CGFloat) {
        self.plan = plan
        self.branches = (plan.followsSession || plan.repoRoot == nil)
            ? nil : plan.repoRoot.map(Worktree.index(of:))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))

        title.stringValue = plan.nodeID
        title.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        addSubview(title)

        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        addSubview(detail)

        toggle.target = self
        toggle.action = #selector(toggled)
        addSubview(toggle)

        branchField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        branchField.stringValue = plan.branch
        addSubview(branchField)

        // Quem está dentro do repo da sessão não tem escolha a fazer, e quem não
        // está em git nenhum não tem worktree para criar. Os dois aparecem na
        // lista de propósito: é a chance de ver onde cada terminal abre, que é
        // exatamente a informação que faltava quando as pastas embaralharam.
        if plan.followsSession {
            toggle.isEnabled = false
            branchField.isHidden = true
            detail.stringValue = "\(plan.repoName) · segue a worktree da sessão"
        } else if plan.repoRoot == nil {
            toggle.isEnabled = false
            branchField.isHidden = true
            detail.stringValue = FileManager.default.fileExists(atPath: plan.currentPath)
                ? "\(NodeWorktreePlanner.short(plan.currentPath)) · não é repositório git"
                : "\(NodeWorktreePlanner.short(plan.currentPath)) · esta pasta não existe"
            detail.textColor = FileManager.default.fileExists(atPath: plan.currentPath)
                ? .secondaryLabelColor : .systemOrange
        } else {
            toggle.state = plan.enabled ? .on : .off
            describePlan()
        }
        toggle.state = plan.followsSession ? .on : toggle.state

        observer = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: branchField,
            queue: .main) { [weak self] _ in
                self?.touched = true
                self?.describePlan()
            }
    }

    /// O que vai acontecer com a branch escrita nesta linha: criar, abrir na que
    /// já existe, ou usar a worktree que já a tem aberta. Ver ADR-018.
    private func describePlan() {
        guard let branches else { return }
        let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let verdict = branches.plan(for: branch)
        detail.stringValue = "\(plan.repoName) · \(verdict.short)"
        detail.textColor = verdict.isFresh ? .secondaryLabelColor : .systemOrange
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override var isFlipped: Bool { true }

    @objc private func toggled() {}

    override func layout() {
        super.layout()
        let branchWidth: CGFloat = 150
        toggle.frame = NSRect(x: 0, y: 11, width: 18, height: 18)
        let textWidth = max(0, bounds.width - 22 - branchWidth - 10)
        title.frame = NSRect(x: 22, y: 4, width: textWidth, height: 14)
        detail.frame = NSRect(x: 22, y: 20, width: textWidth, height: 13)
        branchField.frame = NSRect(x: bounds.width - branchWidth, y: 9,
                                   width: branchWidth, height: 22)
    }

    /// A branch da sessão mudou. Reescreve só quem você não customizou.
    func suggest(branch: String) {
        guard !touched, !branchField.isHidden else { return }
        branchField.stringValue = branch
        // Escrever no campo por código não dispara `textDidChange`.
        describePlan()
    }

    /// O plano desta linha depois do que você escolheu.
    var resolved: NodeWorktree {
        var copy = plan
        copy.enabled = toggle.isEnabled && toggle.state == .on && !plan.followsSession
        copy.branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.touched = touched
        return copy
    }
}

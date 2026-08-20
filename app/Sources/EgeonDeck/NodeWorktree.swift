import AppKit

/// O que acontece com a pasta de um terminal quando a bancada vira worktree.
///
/// Existe porque uma frente de trabalho raramente é um repositório só: o card do
/// frontend abre no repo da bancada, e o do backend abre num repo vizinho. Uma
/// branch nova precisa dos DOIS em worktree, senão o agente do backend continua
/// commitando no checkout principal enquanto o do frontend trabalha na branch
/// nova.
struct NodeWorktree {
    let nodeID: String
    /// Onde este nó abre hoje, já resolvido.
    let currentPath: String
    /// Raiz do repositório em que `currentPath` cai. Nulo quando não é git.
    let repoRoot: String?

    /// A pasta está dentro da pasta da bancada?
    ///
    /// Quem está dentro e fica na MESMA branch não precisa de worktree própria: o
    /// `cwd` relativo já o leva para a pasta equivalente da worktree da bancada, e é
    /// justamente isso que o `cwd` relativo existe para fazer.
    ///
    /// Por contenção de caminho, e não por identidade de repositório: é essa a
    /// regra que `repointed` de fato aplica, e duas worktrees do MESMO repo são
    /// pastas diferentes — dizer "segue a bancada" ali esconderia a escolha.
    let insideWorkbench: Bool

    /// Criar worktree própria para este terminal?
    ///
    /// Derivado da branch, não escolhido em caixinha: o que decide é o nome que
    /// você escreveu na linha. Ver `decided(workbenchBranch:)`.
    var enabled: Bool
    /// Branch deste terminal. Nasce igual à da bancada.
    ///
    /// Igual à da bancada significa "vai junto com ela". Diferente significa
    /// worktree própria, no repositório deste terminal. Vazia significa "não me
    /// leve" — o terminal fica apontando para o repositório original.
    var branch: String
    /// Você editou a branch deste terminal à mão?
    ///
    /// Governa o re-sugerir: mudar a branch da bancada reescreve as linhas que você
    /// não tocou, e deixa em paz as que você customizou.
    var touched = false

    var repoName: String { ((repoRoot ?? currentPath) as NSString).lastPathComponent }

    /// Onde a worktree deste terminal nasce. Mesma convenção da bancada.
    var destination: String? {
        guard let repoRoot, enabled else { return nil }
        return Worktree.suggestedPath(repoRoot: repoRoot, branch: branch)
    }

    /// O plano deste terminal depois de saber a branch da bancada.
    ///
    /// Uma regra só, e é a branch que a diz: repositório outro, ou branch outra,
    /// pede worktree própria. Dentro da bancada e na mesma branch, ir junto é o
    /// suficiente — criar uma segunda worktree ali seriam duas pastas para a mesma
    /// branch do mesmo repo, e o git recusa a segunda.
    func decided(workbenchBranch: String) -> NodeWorktree {
        var copy = self
        copy.enabled = repoRoot != nil && !branch.isEmpty
            && (!insideWorkbench || branch != workbenchBranch)
        return copy
    }
}

enum NodeWorktreePlanner {
    /// Levanta o estado de cada nó que tem pasta.
    ///
    /// Nó `web` fica fora: ele não abre pasta nenhuma. Editor entra junto dos
    /// terminais — ele também resolve `cwd`, e um editor apontado para o repo
    /// vizinho tem o mesmo problema.
    static func inspect(_ config: WorkbenchConfig,
                        workbenchRoot: String,
                        branch: String) -> [NodeWorktree] {
        config.nodes.compactMap { node in
            guard node.type != .web else { return nil }

            let path = config.resolvedDirectory(for: node)
            let inside = path == workbenchRoot || path.hasPrefix(workbenchRoot + "/")
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
                insideWorkbench: inside,
                // Todo terminal com repositório vai: repo vizinho ganha worktree
                // própria, e quem está dentro da bancada vai junto com ela. Nenhum
                // fica atrás por ser shell ou por ser agente.
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

    /// `/Users/você/x` → `~/x`. O que vai para o `workbenches.json` é feito para ser
    /// lido e editado à mão.
    static func short(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Worktree de um terminal só

    /// A pasta não está aqui: ela é derivada da branch, sempre pela mesma
    /// convenção (`Worktree.suggestedPath`), e branch que já está aberta em
    /// worktree usa aquela pasta. Editá-la era escolha sem consequência boa — dava
    /// para apontar a worktree para qualquer lugar do disco e ninguém precisava
    /// disso.
    struct SingleForm {
        let branch: String
    }

    /// Pergunta a branch e a pasta da worktree de UM terminal.
    ///
    /// Existe à parte do formulário da bancada porque é outro momento: a bancada já
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

        // Onde vai nascer, para conferir — não para editar.
        let pasta = NSTextField(labelWithString: "")
        pasta.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pasta.textColor = .secondaryLabelColor
        pasta.lineBreakMode = .byTruncatingMiddle
        pasta.frame = NSRect(x: 0, y: y, width: width, height: 14)
        container.addSubview(pasta)
        y += 18

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
                pasta.stringValue = short(existing)
            } else {
                pasta.stringValue = branch.isEmpty ? ""
                    : short(Worktree.suggestedPath(repoRoot: repoRoot, branch: branch))
            }
        }
        refresh()

        let branchObserver = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: branchField, queue: .main) { _ in
                refresh()
            }
        defer { NotificationCenter.default.removeObserver(branchObserver) }

        container.setFrameSize(NSSize(width: width, height: y))
        alert.accessoryView = container
        alert.window.initialFirstResponder = branchField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return nil }
        return SingleForm(branch: branch)
    }
}

// MARK: - A lista de terminais no formulário de worktree

/// Uma linha por terminal: quem é, em que repositório está, e em que branch ele
/// vai abrir.
///
/// A branch é o único controle da linha, e não havia como não ser: com uma
/// caixinha "criar worktree própria" ao lado, o mesmo estado tinha duas
/// representações — marcado com a branch da bancada não quer dizer nada, e
/// desmarcado com outra branch escrita mente sobre o que vai acontecer.
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

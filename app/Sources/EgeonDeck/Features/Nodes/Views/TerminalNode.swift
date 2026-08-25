import AppKit
import SwiftTerm

// MARK: - Nó de terminal (processo real, dentro da nossa janela)

/// Terminal com um gancho na saída. `dataReceived` é `open` no SwiftTerm e roda
/// na main queue, então dá para medir silêncio sem corrida com a injeção.
final class MBTerminalView: LocalProcessTerminalView {
    var onOutput: (() -> Void)?

    /// Se o arrasto entra como texto COLADO em vez de digitado. Não é preferência:
    /// o Claude Code só reconhece caminho de imagem no evento de paste — é ali que
    /// ele lê o arquivo e troca o caminho por `[Image #1]`, anexando a imagem de
    /// verdade em vez de deixar o agente abrir com `Read`. Digitado, o mesmo
    /// caminho fica texto cru. Segue o modo de injeção do perfil, e não um
    /// interruptor próprio, porque no zsh o marcador volta literal (ADR-007).
    var dropAsPaste = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes(TerminalDrop.types)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        TerminalDrop.accepts(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let texto = TerminalDrop.text(from: sender.draggingPasteboard) else { return false }
        // Só o caminho, e o Enter é seu: arrastar um arquivo é entregá-lo, e não
        // mandar o agente sair trabalhando com o que ele achar do assunto.
        if dropAsPaste {
            send(txt: "\u{1b}[200~" + texto + "\u{1b}[201~")
        } else {
            send(txt: texto)
        }
        // Sem isto o texto entra aqui e o teclado continua no card de onde você
        // veio — a frase que acompanha o arquivo iria para o terminal errado.
        window?.makeFirstResponder(self)
        Log.write("drop: caminho injetado no terminal: \(texto.trimmingCharacters(in: .whitespaces))")
        return true
    }
}

final class TerminalNode: NodeView {
    let term = MBTerminalView(frame: .zero)
    private(set) var address: String
    private var baseTitle: String
    /// `✦` para terminal com IA, `▸` para shell. Guardado em vez de relido do
    /// rótulo: o rótulo agora carrega estado, e ler o símbolo de volta dele
    /// quebraria assim que o sufixo mudasse.
    private let symbol: String
    private let port = NodePortButton()

    /// Você escolheu outro modelo no cabeçalho. Nil é o padrão do CLI. Quem
    /// atende reinicia o processo — não há como trocar o modelo de um pty em
    /// curso — e mantém a conversa.
    var onRequestModel: ((NodeView, String?) -> Void)?
    private var modelPicker: NSPopUpButton?
    private var modelOptions: [String] = []
    private var chosenModel: String?
    /// Quem sabe o modelo literal em uso — lê o transcript. Injetado por quem
    /// tem a configuração do nó; a view não sabe onde a conversa é gravada.
    var modelResolver: (() -> String?)?
    private var lastModelProbe = Date.distantPast
    private var literalModel: String?
    private static let defaultModelTitle = "padrão do CLI"

    /// `profile == nil` → terminal comum. Com perfil, é um "terminal com IA":
    /// mesma mecânica de pty, o que muda é saber injetar prompt e medir ociosidade.
    /// `hooked` diz se esta linha de comando leva o `--settings` com os nossos
    /// ganchos. Vem de quem montou a linha, e não de adivinhação aqui dentro:
    /// `cmd` trocado à mão pode ter trocado de programa, e aí não há gancho.
    init(frame: NSRect, address: String, title: String, cwd: String,
         command: String, profile: AgentProfile?, config: String? = nil,
         model: String? = nil, prompt: String? = nil, hooked: Bool = false) {
        self.address = address
        // Só o nome do terminal no título. O endereço inteiro cabia numa linha de
        // 11pt e não sobrava nada; agora a bancada é a mesma para todos os cards da
        // tela, então repeti-la em cada um custa espaço e não informa. O endereço
        // completo e o CLI ficam no tooltip, para quem precisa despachar.
        self.baseTitle = String(address.split(separator: "/").last ?? "")
        self.symbol = profile == nil ? "▸" : "✦"
        super.init(frame: frame,
                   title: "\(self.symbol) \(self.baseTitle)",
                   accent: profile == nil ? .systemTeal : .systemPurple,
                   nodeID: String(address.split(separator: "/").last ?? ""))
        subtitle = NodeWorktreePlanner.short(cwd)
        titleLabel.toolTip = address + (profile.map { " · \($0.displayName)" } ?? "")
        body.addSubview(term)
        if let profile, profile.offersModels { installModelPicker(profile: profile, current: model) }
        // Terminal com IA recebe o arrasto como paste; shell, como digitação.
        term.dropAsPaste = profile?.injectConfig.mode == "bracketed-paste"

        // Depois do corpo, para ficar na frente do SwiftTerm — ele consome o
        // mouse inteiro, e uma subview atrás dele nunca receberia o arrasto.
        addSubview(port)
        port.onDrag = { [weak self] point in
            guard let self else { return }
            self.onPortDrag?(self, point)
        }
        port.onRelease = { [weak self] point in
            guard let self else { return }
            self.onPortRelease?(self, point)
        }

        var environment = AppEnvironment.forChildProcess()
        environment["TERM"] = "xterm-256color"
        // O ambiente do perfil por cima do nosso, e a configuração escolhida no
        // nó por cima dele. É aqui que se decide com qual conjunto de plugins,
        // MCP e settings o CLI sobe — herdar o do app não serve: lançado pelo
        // Finder, ele não herdou o shell de ninguém.
        if let profile {
            environment.merge(profile.resolvedEnvironment) { _, novo in novo }
            if let config, let variable = profile.configEnv {
                environment[variable] = config
                Log.write("terminal[\(address)]: \(variable)=\(config)")
            }
        }
        // O gancho do CLI roda num processo filho e precisa saber de qual terminal
        // está falando. O endereço de dispatch é o identificador que o app usa em
        // todo lugar, então é ele que vai.
        //
        // Só em nó com agente: shell não tem conversa para rastrear, e a variável
        // ali seria lixo no ambiente de tudo que você rodar à mão.
        if profile != nil { environment[ClaudeHooks.targetVariable] = address }

        let env: [String] = environment.map { "\($0.key)=\($0.value)" }

        let line = "cd \(shellQuote(cwd)); clear; \(command)"
        term.startProcess(executable: "/bin/zsh", args: ["-lc", line], environment: env, execName: nil)

        Dispatcher.shared.register(Target(address: address, profile: profile,
                                           view: term, hooked: hooked))

        // O papel do terminal entra na fila em vez de ser escrito no pty agora: a
        // TUI acabou de ser lançada e ainda não tem quem leia stdin. O Dispatcher
        // já espera o `warmupMs` do perfil e o silêncio antes de entregar.
        if let prompt, !prompt.isEmpty, profile != nil {
            Dispatcher.shared.target(address)?.enqueue(prompt)
            Log.write("terminal[\(address)]: papel enfileirado (\(prompt.count) caracteres)")
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `prepareForRemoval` já desfez o registro no Dispatcher?
    ///
    /// O deinit não pode desfazer de novo. Entre remover o card e liberar a view,
    /// um nó NOVO com o MESMO endereço já pode ter se registrado — é exatamente o
    /// que acontece ao reconfigurar pelo lápis e ao reapontar para uma worktree,
    /// onde o card é trocado por outro com o mesmo id. Quem chama segura o card
    /// antigo até o fim da função, então o deinit roda DEPOIS do registro novo e
    /// apagava justamente ele: medido com `/targets` devolvendo lista vazia depois
    /// de reapontar dois terminais.
    private var unregistered = false

    deinit {
        guard !unregistered else { return }
        Dispatcher.shared.unregister(address: address)
    }

    override var supportsEditing: Bool { true }
    override var supportsWorktree: Bool { true }

    override var removalWarning: String {
        "O processo do terminal é encerrado junto — o que estiver rodando nele para."
    }

    /// A porta de aresta só existe no canvas: a ligação é desenhada arrastando de
    /// um card até outro, e no mosaico não há espaço livre onde soltar.
    override func freeformDidChange() { port.isHidden = !isFreeform }

    override func workbenchRenamed(to workbench: String) {
        let updated = "\(workbench)/\(nodeID)"
        Dispatcher.shared.rekey(from: address, to: updated)
        address = updated
        // O título é o nome do terminal e não muda com a bancada; o tooltip carrega
        // o endereço, e esse muda.
        titleLabel.toolTip = updated
        refreshBadge()
    }

    /// Sem matar o pty na mão, o processo filho sobrevive à view e fica órfão
    /// até o app sair.
    ///
    /// E o SIGTERM do `terminate()` não basta: **shell interativo ignora SIGTERM**
    /// — é o padrão do zsh com um tty. Medido depois de reapontar um terminal para
    /// outra worktree: 7 processos vivos para 6 nós, e o sobrando era um
    /// `/bin/zsh -l` filho do app, com a pasta antiga, invisível. O mesmo valia
    /// para o X do card e para o lápis de reconfigurar.
    override func prepareForRemoval() {
        Dispatcher.shared.unregister(address: address)
        unregistered = true
        guard term.process.running else { return }

        let pid = term.process.shellPid
        term.process.terminate()
        guard pid > 0 else { return }

        // Meio segundo é folga para o SIGTERM funcionar em quem o respeita — um
        // agente CLI, por exemplo, que grava a conversa ao sair.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard kill(pid, 0) == 0 else { return }

            // No GRUPO quando o shell é líder dele: o que estiver rodando dentro
            // morre junto, que é o que "remover o terminal" promete. A guarda não é
            // decoração — se o pgid não fosse o do shell, ele poderia ser o do
            // próprio app, e o SIGKILL levaria o Egeon inteiro.
            if getpgid(pid) == pid {
                killpg(pid, SIGKILL)
                Log.write("terminal: pid \(pid) ignorou SIGTERM — SIGKILL no grupo")
            } else {
                kill(pid, SIGKILL)
                Log.write("terminal: pid \(pid) ignorou SIGTERM — SIGKILL no processo")
            }
        }
    }

    override func layout() {
        super.layout()
        term.frame = body.bounds
        // Encostado na borda direita, na altura da porta de saída que a aresta
        // usa. O card tem `masksToBounds`, então ele não pode sobrar para fora.
        let size = NodePortButton.size
        port.frame = NSRect(x: bounds.maxX - size - 1, y: bounds.midY - size / 2,
                            width: size, height: size)
    }

    /// Escreve no cabeçalho o que está acontecendo: o spinner enquanto roda, o
    /// aviso quando para e espera você, e a fila pendente — prompt disparado
    /// enquanto o agente trabalha fica visível em vez de sumir até alguém
    /// desconfiar.
    ///
    /// Chamado por um timer, então tudo aqui é barato de propósito: nenhuma
    /// leitura de tela, nenhuma alocação além das strings do rótulo.
    func refreshBadge() {
        let workbench = Dispatcher.shared.target(address)
        let activity = workbench?.activity ?? .dead
        let pending = workbench?.pending ?? 0

        var parts: [String] = []
        if let label = activity.label { parts.append(label) }
        if pending > 0 { parts.append("\(pending) na fila") }

        let text = "\(symbol) \(baseTitle)"
        let status = parts.joined(separator: "  ·  ")
        // Os rótulos só são tocados quando o texto muda de fato: o spinner troca a
        // cada quadro, o resto quase nunca, e reatribuir string igual marca
        // needsDisplay à toa em todos os nós parados.
        if titleLabel.stringValue != text {
            titleLabel.stringValue = text
            // A largura do título sai do texto; sem isto, renomear o nó deixaria a
            // reserva do nome anterior.
            needsLayout = true
        }
        if statusLabel.stringValue != status {
            statusLabel.stringValue = status
            // O estado disputa a linha com o nome: quando ele esvazia, o nome
            // precisa poder crescer de volta.
            needsLayout = true
        }
        refreshModelTitle()

        titleLabel.textColor = activity.color ?? accent
        statusLabel.textColor = activity.color ?? NSColor(calibratedWhite: 0.62, alpha: 1)
        setAlert(activity.needsAttention)
    }

    /// O seletor de modelo do cabeçalho. Pull-down miúdo com o nome do modelo
    /// em curso: é o que responde "este card está rodando com o quê?" sem abrir
    /// o formulário, e é onde se troca.
    private func installModelPicker(profile: AgentProfile, current: String?) {
        // Pull-down, e não popup: o título é o modelo LITERAL em uso, e o menu
        // são os apelidos que se pode pedir. Num popup o título seria o item
        // escolhido — "sonnet", "padrão" — que é justamente o que não informa.
        let picker = NSPopUpButton(frame: .zero, pullsDown: true)
        picker.controlSize = .small
        picker.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        picker.isBordered = false
        picker.toolTip = "Modelo em uso — escolher outro reinicia o terminal, a conversa continua"
        var options = profile.models ?? []
        if let current, !current.isEmpty, !options.contains(current) { options.append(current) }
        modelOptions = options
        chosenModel = current
        picker.addItem(withTitle: "")
        picker.addItem(withTitle: Self.defaultModelTitle)
        picker.addItems(withTitles: options)
        picker.target = self
        picker.action = #selector(modelChosen(_:))
        modelPicker = picker
        headerAccessory = picker
        refreshModelTitle(force: true)
    }

    /// Título do pull-down: o nome literal quando se sabe, com o apelido pedido
    /// entre parênteses quando difere; senão o apelido; senão "padrão".
    /// Consulta o transcript no máximo a cada 2s — é leitura de arquivo, e o
    /// tick do badge é de 0,25s.
    private func refreshModelTitle(force: Bool = false) {
        guard let picker = modelPicker else { return }
        let now = Date()
        if force || now.timeIntervalSince(lastModelProbe) >= 2 {
            lastModelProbe = now
            literalModel = modelResolver?()
        }
        let title: String
        switch (literalModel, chosenModel) {
        case let (literal?, chosen?) where literal != chosen && !literal.contains(chosen):
            title = "\(literal) (\(chosen))"
        case let (literal?, _):
            title = literal
        case let (nil, chosen?):
            title = chosen
        case (nil, nil):
            title = "padrão"
        }
        // O prefixo do fornecedor é o mesmo em todo item e só come largura do
        // nome do nó ao lado; o nome inteiro fica no tooltip.
        let shown = title.hasPrefix("claude-") ? String(title.dropFirst("claude-".count)) : title
        if picker.item(at: 0)?.title != shown {
            picker.item(at: 0)?.title = shown
            picker.toolTip = "Modelo em uso: \(title) — escolher outro reinicia o terminal, a conversa continua"
            // Texto mais a seta do pull-down e o respiro da célula.
            let text = (shown as NSString).size(withAttributes: [.font: picker.font as Any]).width
            headerAccessoryWidth = ceil(text) + 26
            needsLayout = true
        }
        // Marca no menu o apelido em vigor, para o clique dizer onde se está.
        for (index, item) in picker.itemArray.enumerated() where index > 0 {
            let alias = index == 1 ? nil : modelOptions[index - 2]
            item.state = alias == chosenModel ? .on : .off
        }
    }

    @objc private func modelChosen(_ sender: NSPopUpButton) {
        // Índice 0 é o título; 1 é "padrão"; daí em diante, os apelidos.
        let index = sender.indexOfSelectedItem
        guard index >= 1 else { return }
        let chosen = index >= 2 && index - 2 < modelOptions.count ? modelOptions[index - 2] : nil
        onRequestModel?(self, chosen)
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

}

// MARK: - Nó placeholder (o que ainda não existe, dito na cara)

final class PlaceholderNode: NodeView {
    init(frame: NSRect, title: String, message: String) {
        super.init(frame: frame, title: "◻ \(title)", accent: NSColor.systemGray)
        body.wantsLayer = true
        body.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor

        let label = NSTextField(labelWithString: message)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor(calibratedWhite: 1, alpha: 0.4)
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.tag = 1
        body.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        body.viewWithTag(1)?.frame = NSRect(x: 20, y: body.bounds.midY - 40,
                                            width: body.bounds.width - 40, height: 80)
    }
}


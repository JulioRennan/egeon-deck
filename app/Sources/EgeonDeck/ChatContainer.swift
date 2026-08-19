import AppKit

/// O modo Chat: a sessão inteira como uma conversa.
///
/// Terceira forma de olhar a mesma sessão, e a única em que os cards não aparecem.
/// O motivo é o que a montagem não resolve: com cinco agentes o canvas obriga a
/// varrer cinco cards para saber o que aconteceu, e a ordem em que aconteceu não
/// está em nenhum deles. Aqui a ordem é o eixo — os transcripts dos agentes viram
/// um thread só — e o que se perde de vista, a montagem, é justamente o que já
/// está pronto e não muda mais.
///
/// Não desenha nó nenhum, mas os cards não saem da hierarquia: o `SessionShell`
/// mantém o canvas montado e põe esta view opaca por cima. Sem isso os terminais
/// nunca recebem passe de layout, o pty sobe com zero colunas e a TUI não tem onde
/// desenhar. Ver ADR-029.
final class ChatContainer: NSView {
    /// Os terminais da sessão, remontados a cada leitura.
    var nodes: (() -> [ChatNode])?
    /// Entrega o texto. Devolve o erro quando a entrega não passa.
    var send: ((_ text: String, _ target: String) -> String?)?
    /// O que o terminal está mostrando, para a gaveta de processo.
    var peek: ((_ id: String) -> [String])?
    /// Levar você ao card — usado pelo pedido de permissão, que só se responde lá.
    var onReveal: ((_ id: String) -> Void)?
    /// Você recolheu ou abriu o painel da direita.
    var onPanelToggled: ((Bool) -> Void)?

    private let thread = ChatThreadView()
    private let composer = ChatComposer()
    private let panel = ChatSidePanel()
    private let drawer = ProcessDrawer()
    private let banner = ChatStyle.label("", font: ChatStyle.meta, color: .systemOrange)

    private let content = ChatThread()
    private var timer: Timer?
    /// Processo com a gaveta aberta. Nil = fechada.
    private var openProcess: String?
    private var lastNodes: [ChatNode] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = ChatStyle.threadBackground.cgColor

        addSubview(thread)
        addSubview(composer)
        addSubview(panel)
        banner.alignment = .center
        banner.isHidden = true
        addSubview(banner)
        drawer.isHidden = true
        addSubview(drawer)

        thread.onReveal = { [weak self] id in self?.onReveal?(id) }

        composer.onSend = { [weak self] text, target in self?.deliver(text, to: target) }
        composer.statusOf = { [weak self] id in
            guard let node = self?.lastNodes.first(where: { $0.id == id }) else {
                return id == ChatComposer.everyone ? "a sessão inteira" : ""
            }
            return node.activity == .ready ? (node.role ?? "de pé") : (node.activity.label ?? "")
        }

        panel.onPickAgent = { [weak self] id in self?.composer.aim(at: id) }
        panel.onOpenProcess = { [weak self] id in self?.openDrawer(id) }
        panel.onToggleCollapse = { [weak self] in
            guard let self else { return }
            panel.setCollapsed(!panel.isCollapsed)
            onPanelToggled?(panel.isCollapsed)
            needsLayout = true
        }
        drawer.onClose = { [weak self] in self?.closeDrawer() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setPanelCollapsed(_ collapsed: Bool) {
        panel.setCollapsed(collapsed)
        needsLayout = true
    }

    // MARK: Ciclo

    /// O laço só roda com o chat na tela.
    ///
    /// Ler transcript é I/O de arquivo, e em sessão com cinco agentes são cinco
    /// arquivos. Deixar isso rodando enquanto você está no canvas é custo por nada
    /// — o thread é remontado ao entrar, e o que ele lê está gravado em disco.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    private func start() {
        guard timer == nil else { return }
        refresh()
        thread.scrollToBottom()
        // O foco vai para a caixa de escrever, e tem de ir: o canvas continua
        // montado por baixo, então sem isto o primeiro responder seria um terminal
        // coberto — você digitaria no card que não está vendo.
        composer.focus()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let nodes = self.nodes?() ?? []
        lastNodes = nodes

        let participants = nodes.filter(\.isAgent)
            .map { ChatThread.Participant(id: $0.id, transcript: $0.transcript) }
        content.forget(except: participants)
        let entries = content.entries(of: participants)

        // Só terminal DE PÉ é destino: nó com processo morto continua na lista para
        // você ver que morreu, mas mandar prompt para ele é encher fila que ninguém
        // lê — a mesma regra do `/targets`.
        // Agentes primeiro, e não na ordem do `sessions.json`: o primeiro da lista é
        // o destinatário padrão, e cair num shell faz a caixa abrir dizendo "escreva
        // pra t1" numa sessão cujo trabalho é com os agentes.
        let live = nodes.filter { $0.activity != .dead }
        var candidates = live.filter(\.isAgent).map(\.id) + live.filter { !$0.isAgent }.map(\.id)
        if live.filter(\.isAgent).count > 1 { candidates.append(ChatComposer.everyone) }
        composer.candidates = candidates

        panel.aimed = composer.target
        panel.show(nodes)
        thread.show(entries, asking: nodes.filter { $0.activity == .asking }.map(\.id))
        thread.placeholder = Self.placeholder(nodes: nodes, entries: entries)

        if let openProcess {
            let node = nodes.first { $0.id == openProcess }
            drawer.show(id: openProcess, cmd: node?.cmd ?? "",
                        lines: peek?(openProcess) ?? [])
        }
    }

    /// O que dizer quando o thread está vazio, e são três motivos diferentes.
    ///
    /// Separados porque "ninguém falou ainda" numa sessão só de shell é mentira por
    /// omissão: ali não vai aparecer conversa nunca, e ficar esperando é perder a
    /// tarde. O que falta é dito com o nome de quem falta.
    private static func placeholder(nodes: [ChatNode], entries: [ChatEntry]) -> String? {
        guard entries.isEmpty else { return nil }
        let agents = nodes.filter(\.isAgent)
        if agents.isEmpty {
            return "Esta sessão não tem nó de agente. O thread do chat sai do transcript "
                + "que o CLI grava — terminal comum não gera nenhum, então aqui não vai "
                + "aparecer conversa. Os processos continuam na lista à direita."
        }
        if agents.allSatisfy({ $0.transcript == nil }) {
            return "Os agentes estão de pé, e nenhum recebeu prompt ainda. O app descobre "
                + "onde o CLI grava a conversa no primeiro prompt — mande o primeiro por "
                + "aqui e o thread começa."
        }
        return "Ninguém falou ainda."
    }

    /// O que o painel e a caixa estão mostrando, como dados.
    ///
    /// Sai do que a última leitura de fato usou, e não de uma consulta nova: o que
    /// precisa ser conferido é a tela, e uma segunda consulta poderia concordar com
    /// o app e discordar dela.
    func snapshot() -> [[String: Any]] {
        lastNodes.map { node in
            var out: [String: Any] = [
                "id": node.id,
                "kind": node.isAgent ? "agent" : "shell",
                "activity": String(describing: node.activity),
                "cmd": node.cmd
            ]
            if !node.reaches.isEmpty { out["reaches"] = node.reaches }
            if node.id == composer.target { out["target"] = true }
            return out
        }
    }

    // MARK: Envio

    private func deliver(_ text: String, to target: String) {
        let ids: [String]
        if target == ChatComposer.everyone {
            ids = lastNodes.filter { $0.isAgent && $0.activity != .dead }.map(\.id)
        } else {
            ids = [target]
        }

        var failures: [String] = []
        for id in ids {
            if let error = send?(text, id) { failures.append("\(id): \(error)") }
        }
        if failures.isEmpty {
            show(banner: nil)
        } else {
            show(banner: failures.joined(separator: "  ·  "))
        }
        // A entrega vira mensagem no thread quando o CLI a gravar, e não agora: uma
        // linha otimista aqui apareceria antes de existir, e duplicaria quando a
        // leitura seguinte trouxesse a de verdade.
        refresh()
        thread.scrollToBottom()
    }

    private func show(banner text: String?) {
        guard let text else { banner.isHidden = true; return }
        banner.stringValue = text
        banner.isHidden = false
        Log.write("chat: entrega recusada — \(text)")
    }

    // MARK: Gaveta

    private func openDrawer(_ id: String) {
        openProcess = id
        drawer.isHidden = false
        refresh()
        needsLayout = true
    }

    private func closeDrawer() {
        openProcess = nil
        drawer.isHidden = true
        needsLayout = true
    }

    override func keyDown(with event: NSEvent) {
        // Esc fecha a gaveta. Só ela: no chat o Esc não tem outro dono, e a caixa
        // de texto não o consome.
        if event.keyCode == 53, openProcess != nil { closeDrawer(); return }
        super.keyDown(with: event)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let panelWidth = panel.isCollapsed ? ChatSidePanel.collapsedWidth : ChatSidePanel.width
        panel.frame = NSRect(x: bounds.width - panelWidth, y: 0,
                             width: panelWidth, height: bounds.height)

        let center = max(0, bounds.width - panelWidth)
        let composerHeight = ChatComposer.height
        thread.frame = NSRect(x: 0, y: 0, width: center,
                              height: max(0, bounds.height - composerHeight))
        composer.frame = NSRect(x: 0, y: thread.frame.maxY, width: center, height: composerHeight)
        banner.frame = NSRect(x: 0, y: max(0, thread.frame.maxY - 18), width: center, height: 14)

        let drawerWidth = min(ProcessDrawer.width, center * 0.9)
        drawer.frame = NSRect(x: bounds.width - panelWidth - drawerWidth, y: 0,
                              width: drawerWidth, height: bounds.height)
    }
}

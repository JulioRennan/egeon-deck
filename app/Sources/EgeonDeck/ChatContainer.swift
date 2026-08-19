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
    /// Você recolheu ou abriu o painel da direita.
    var onPanelToggled: ((Bool) -> Void)?

    private let thread = ChatThreadView()
    private let composer = ChatComposer()
    private let panel = ChatSidePanel()
    private let drawer = ProcessDrawer()
    /// Painel e gaveta entram em vidro, como as barras flutuantes do app: as três
    /// superfícies do chat falam a mesma língua da barra de sessões e da barra do
    /// canvas — mesmo raio, mesma borda, mesmo `EGEON_GLASS=0` como saída (ADR-025).
    /// A caixa de escrever traz o vidro dela por dentro, porque a lista de menção
    /// precisa nascer encostada nele.
    private lazy var panelGlass = GlassPanel(content: panel, radius: 14)
    private lazy var drawerGlass = GlassPanel(content: drawer, radius: 14)
    private let banner = ChatStyle.label("", font: ChatStyle.meta, color: .systemOrange)

    /// Folga em volta das superfícies flutuantes. O mesmo 12 do banner.
    private static let margin: CGFloat = 12

    /// Quanto da altura útil a caixa de escrever pode tomar no máximo.
    ///
    /// Pouco mais de um terço: acima disso o histórico deixa de ser histórico. É teto,
    /// não tamanho — a caixa só chega ali com um texto que de fato o preencha.
    private static let composerShare: CGFloat = 0.38
    /// Piso do teto, para janela muito baixa não deixar a caixa sem uma linha.
    private static let minComposer: CGFloat = 66

    private let content = ChatThread()
    private var timer: Timer?
    /// Processo com a gaveta aberta. Nil = fechada.
    private var openProcess: String?
    private var lastNodes: [ChatNode] = []
    /// O que você mandou e o CLI ainda não gravou no transcript.
    ///
    /// Existe pelo intervalo: a entrega passa por fila, injeção e Enter, e a mensagem
    /// só volta a existir quando o CLI a grava. Sem esta lista o thread fica parado
    /// nesse intervalo e parece ter engolido o que você escreveu.
    private var inFlight: [(entry: ChatEntry, at: Date)] = []
    /// Quanto tempo uma entrega pode ficar sem aparecer antes de ser esquecida.
    ///
    /// O Dispatcher desiste depois de três tentativas, coisa de 6s. O dobro disso com
    /// folga: mais que isso e a bolha apagada viraria mentira permanente na tela.
    private static let inFlightTimeout: TimeInterval = 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = ChatStyle.threadBackground.cgColor

        addSubview(thread)
        addSubview(composer)
        addSubview(panelGlass)
        banner.alignment = .center
        banner.isHidden = true
        addSubview(banner)
        drawerGlass.isHidden = true
        addSubview(drawerGlass)

        composer.onHeightChanged = { [weak self] in self?.needsLayout = true }

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
            .map { ChatThread.Participant(id: $0.id, agent: $0.agentKey,
                                          transcript: $0.transcript) }
        content.forget(except: participants)
        let entries = content.entries(of: participants)

        // A bolha apagada sai quando a de verdade chega — casada pelo texto, que é o
        // que atravessa o socket sem alteração num dispatch cru. Ou por tempo, se
        // nunca chegar.
        let seen = Set(entries.filter { $0.kind == .user }.map(\.text))
        let now = Date()
        inFlight.removeAll { seen.contains($0.entry.text)
            || now.timeIntervalSince($0.at) > Self.inFlightTimeout }

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
        // Trabalhando é `starting` junto: entre subir e o primeiro byte o terminal
        // também está ocupado, e é o pior momento para a tela não dizer nada.
        let working = nodes
            .filter { $0.isAgent && ($0.activity == .working || $0.activity == .starting) }
            .map { (id: $0.id, note: content.live(of: $0.id)) }
        thread.show(entries, working: working, inFlight: inFlight.map(\.entry))
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
            if let live = content.live(of: node.id) { out["live"] = live }
            return out
        }
    }

    /// Escreve na caixa e devolve a geometria que saiu disso.
    ///
    /// A resposta é o que se afirma sobre o desenho: a caixa cresceu, ela parou no
    /// teto, e o histórico encolheu na mesma medida. Ver `ChatComposer.setText`.
    func compose(_ text: String, send: Bool = false) -> [String: Any] {
        composer.setText(text)
        if send { composer.submit() }
        // O layout roda agora, e não no próximo quadro: quem chamou vai ler a
        // geometria na volta desta função.
        needsLayout = true
        layoutSubtreeIfNeeded()
        return [
            "ok": true,
            "sent": send,
            "inFlight": inFlight.count,
            "lines": text.isEmpty ? 0 : text.split(separator: "\n",
                                                   omittingEmptySubsequences: false).count,
            "composer": Int(composer.frame.height.rounded()),
            "composerTop": Int(composer.frame.minY.rounded()),
            "composerBottom": Int(composer.frame.maxY.rounded()),
            "thread": Int(thread.frame.height.rounded()),
            "ceiling": Int(composer.ceiling.rounded()),
            "capped": composer.isCapped,
            "content": Int(bounds.height.rounded())
        ]
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
        var delivered: [String] = []
        for id in ids {
            if let error = send?(text, id) {
                failures.append("\(id): \(error)")
            } else {
                delivered.append(id)
            }
        }
        if failures.isEmpty {
            show(banner: nil)
        } else {
            show(banner: failures.joined(separator: "  ·  "))
        }
        // A bolha entra APAGADA e só para quem aceitou a entrega. Ela não substitui a
        // de verdade: quando o CLI gravar, a leitura seguinte traz a definitiva e esta
        // sai, casada pelo texto. Entrar como definitiva aqui seria afirmar que
        // chegou antes de ter chegado.
        if !delivered.isEmpty {
            inFlight.append((ChatEntry(id: "flight-\(delivered.joined())-\(text.hashValue)",
                                       kind: .user, recipients: delivered,
                                       at: Date(), text: text), Date()))
        }
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
        drawerGlass.isHidden = false
        refresh()
        needsLayout = true
    }

    private func closeDrawer() {
        openProcess = nil
        drawerGlass.isHidden = true
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
        let margin = Self.margin
        let panelWidth = panel.isCollapsed ? ChatSidePanel.collapsedWidth : ChatSidePanel.width
        panelGlass.frame = NSRect(x: bounds.width - panelWidth - margin, y: margin,
                                  width: panelWidth,
                                  height: max(0, bounds.height - margin * 2))
        panel.frame = panelGlass.bounds

        // A caixa é ANCORADA embaixo e cresce para cima, e quem cede área é o
        // histórico — não o rodapé da janela, e não por sobreposição. Ela flutuava
        // sobre o thread, com a folga somada ao fim do documento: a última mensagem
        // subia, mas o meio da conversa passava por baixo do vidro, e um parágrafo
        // de cinco linhas na caixa cobria a resposta que você estava respondendo.
        // Agora o thread termina onde a caixa começa.
        //
        // A largura, ao contrário, o painel CEDE e a caixa não — ali sobreposição
        // seria mensagem coberta o tempo todo, e não só enquanto você escreve.
        let center = max(0, bounds.width - panelWidth - margin * 2)
        let column = ChatStyle.columnWidth(in: center)
        let columnX = ((center - column) / 2).rounded()

        // O teto da caixa é uma fração da altura útil: em janela baixa o teto de oito
        // linhas engoliria o histórico, e sobrar menos de metade para ler é perder o
        // motivo do modo.
        let usable = max(0, bounds.height - margin * 2)
        composer.ceiling = max(Self.minComposer, usable * Self.composerShare)
        let composerHeight = composer.height(forWidth: column)

        composer.frame = NSRect(x: columnX,
                                y: max(0, bounds.height - composerHeight - margin),
                                width: column, height: composerHeight)
        thread.frame = NSRect(x: 0, y: 0, width: center,
                              height: max(0, composer.frame.minY - margin))
        banner.frame = NSRect(x: 0, y: max(0, composer.frame.minY - 18),
                              width: center, height: 14)

        let drawerWidth = min(ProcessDrawer.width, max(0, center - margin * 2))
        drawerGlass.frame = NSRect(x: max(0, bounds.width - panelWidth - margin * 2 - drawerWidth),
                                   y: margin, width: drawerWidth,
                                   height: max(0, bounds.height - margin * 2))
        drawer.frame = drawerGlass.bounds
    }
}

import AppKit

// MARK: - O modo chat

/// A bancada como conversa: participantes à esquerda, thread no meio, composer
/// embaixo. Fechaduras de leitura, como o EdgeController: quem sabe dos nós e
/// de enviar é o dono lá fora; aqui só se desenha e se coordena.
///
/// A thread sai do histórico da bancada (`ChatHistory`, a conversa corrente),
/// relido a cada segundo só quando o arquivo mudou (ADR-037). O turno EM CURSO
/// é a exceção: enquanto o agente trabalha, a cauda do transcript dele é lida
/// a cada mudança e a bolha cresce ao vivo — prosa, passos, prosa — com o que
/// ele está fazendo agora no fim (ADR-039). No `Stop` o turno entra no
/// histórico e a bolha ao vivo dá lugar à gravada.
final class ChatContainer: NSView {
    /// Os nós da bancada como participantes, lidos na hora.
    var participants: (() -> [ChatParticipant])?
    /// Envia. Devolve mensagem de erro, ou nil se entrou na fila.
    var send: ((String, ChatParticipant) -> String?)?
    /// O card de um terminal, pelo id do nó — para mostrar o terminal de
    /// verdade no lugar da thread quando você clica num shell.
    var terminalView: ((String) -> NSView?)?
    /// Devolve o card ao canvas coberto quando o chat para de mostrá-lo.
    var releaseTerminal: ((NSView) -> Void)?
    private var shownTerminal: NSView?

    private let column = ParticipantsColumn()
    /// A thread é uma tabela: uma linha por bloco, só o visível existe (ADR-042).
    private let thread = ChatThreadController()
    private let composer = ChatComposer()
    private let popup = ChatListPopup()
    private let emptyThread = NSTextField(labelWithString:
        "Sem conversa ainda — Enter envia para o agente em foco")

    /// A conversa corrente desta bancada (`chat.jsonl`), lida na hora: "limpar
    /// a conversa" arquiva o arquivo e a thread segue o novo, vazio.
    var historyFile: (() -> URL?)?
    private var historyCache: [URL: (size: UInt64, modified: Date, records: [ChatRecord])] = [:]

    /// Onde o CLI de um agente está gravando a conversa, e quando o turno em
    /// curso começou. `nil` para quem não tem transcript (shell, CLI sem
    /// gancho): a bolha dele fica em "trabalhando…".
    var liveSource: ((ChatParticipant) -> (transcript: URL, notBefore: Date?)?)?
    private struct LiveEntry {
        var size: UInt64
        var modified: Date
        var live: ClaudeTranscript.LiveTurn?
        var readAt: Date
    }
    private var liveCache: [String: LiveEntry] = [:]
    private var liveParsing: Set<String> = []
    /// Vigia de escrita no transcript de quem trabalha: a bolha reage ao byte
    /// gravado, não ao tique de 1 s. Um por agente; cai quando ele para.
    private var liveWatchers: [String: (path: String, source: DispatchSourceFileSystemObject)] = [:]

    private var threadViewportHeight: CGFloat = 0
    /// Largura para a qual as linhas foram medidas; mudou, mede de novo.
    private var threadWidth: CGFloat = 0
    /// Quantas vezes a tabela mudou de verdade — para o teste provar que
    /// refresh sem mudança não mexe na tela.
    private(set) var threadRebuilds = 0
    private var messages: [ChatMessage] = []

    /// A setinha no canto: aparece quando você subiu para ler e some no fim.
    private let toBottom = ChevronButton()

    private func updateToBottomButton() {
        toBottom.isHidden = thread.isAtBottom || thread.blocks.isEmpty
    }

    private func scrollToBottomClicked() { thread.scrollToBottom(animated: true) }

    /// Rola por fora (`/chat?scroll=top|bottom`) — é como se confere a setinha
    /// e a animação sem mouse.
    func scroll(_ edge: String) {
        if edge == "top" { thread.scrollToTop(animated: true) } else { thread.scrollToBottom(animated: true) }
    }

    /// Clique numa linha: leva à mensagem que ela cita — ou, numa resposta
    /// sem citação, ao prompt que ela responde, como no WhatsApp.
    private func rowClicked(_ block: ChatBlock) {
        let target: String?
        if case .prompt(_, _, _, _, let quote, _, _) = block.kind {
            target = quote?.targetKey
        } else {
            target = messages.first { $0.key == block.messageKey }?.quote?.targetKey
                ?? "p|" + block.messageKey.dropFirst(2)
        }
        if let target { thread.scrollTo(messageKey: target) }
    }
    private var pending: [ChatThread.Pending] = []
    private var focusedId: String?
    private enum PopupMode { case none, switcher, mention }
    private var popupMode = PopupMode.none
    private var refreshTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Opaco de propósito: o canvas continua montado por baixo (o pty precisa
        // do passe de layout) e é esta view que o esconde.
        layer?.backgroundColor = NSColor(srgbRed: 0.043, green: 0.055, blue: 0.082,
                                         alpha: 1).cgColor

        column.onPick = { [weak self] participant in
            self?.focus(on: participant.id)
            self?.composer.focus()
        }
        addSubview(column)

        thread.onClick = { [weak self] block in self?.rowClicked(block) }
        // Saber se você está no fim é o que decide a setinha e o auto-scroll.
        thread.onScroll = { [weak self] in
            self?.updateToBottomButton()
            self?.loadMoreIfNearTop()
        }
        addSubview(thread.scrollView)

        emptyThread.font = .systemFont(ofSize: 11)
        emptyThread.textColor = NSColor(calibratedWhite: 0.35, alpha: 1)
        emptyThread.alignment = .center
        addSubview(emptyThread)

        composer.onSend = { [weak self] text in self?.sendMessage(text) }
        composer.onCycleTarget = { [weak self] in self?.cycleFocus() }
        composer.onToggleSwitcher = { [weak self] in self?.togglePopup(.switcher) }
        composer.onMentionQuery = { [weak self] query in self?.mentionChanged(query) }
        composer.popupCommand = { [weak self] selector in
            self?.handlePopupCommand(selector) ?? false
        }
        composer.onHeightChange = { [weak self] in self?.needsLayout = true }
        addSubview(composer)

        popup.isHidden = true
        addSubview(popup)

        toBottom.onClick = { [weak self] in self?.scrollToBottomClicked() }
        toBottom.isHidden = true
        addSubview(toBottom)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    // MARK: Dados

    /// Relê os nós e redesenha. Chamado ao entrar no modo e pelo timer — estado
    /// de terminal muda sem evento nosso.
    func refresh() {
        let all = participants?() ?? []
        let alive = all.filter { $0.activity != .dead }
        // Sem escolha sua, o foco é o primeiro AGENTE vivo na ordem dos nós — e
        // não o primeiro que apareceu vivo: no arranque os terminais registram
        // em ordem qualquer, e o foco ficaria preso em quem subiu antes.
        if !userChoseFocus || !alive.contains(where: { $0.id == focusedId }) {
            focusedId = (alive.first { $0.isAgent } ?? alive.first)?.id
        }
        column.update(all, focused: focusedId)
        composer.setTarget(alive.first { $0.id == focusedId })
        // Foco caiu num agente sem ser por clique (o shell morreu): thread de volta.
        if shownTerminal != nil, alive.first(where: { $0.id == focusedId })?.isAgent != false {
            leaveTerminal()
        }
        rebuildThread(all)
    }

    /// Escolhe o participante por fora (`/chat?focus=id`) — o clique na coluna
    /// não é dirigível sem Acessibilidade.
    func focusFromOutside(_ id: String) {
        guard (participants?() ?? []).contains(where: { $0.id == id }) else { return }
        focus(on: id)
    }

    private var userChoseFocus = false

    // MARK: Thread

    /// O histórico é pequeno (uns KB por turno), mas uma bancada longa tem
    /// milhares de turnos; decodificar na main a cada mudança travaria a tela.
    /// A leitura vai para uma fila de fundo, e a main só consome o cache.
    private let parseQueue = DispatchQueue(label: "egeon.chat.history", qos: .utility)
    private var parsing: Set<URL> = []

    private func turns(of participant: ChatParticipant) -> [ChatTurn] {
        Self.turns(of: participant, records: records(), live: liveTurn(of: participant)?.turn)
    }

    private static func turns(of participant: ChatParticipant, records: [ChatRecord],
                              live: ChatTurn?) -> [ChatTurn] {
        var turns = records.filter { $0.node == participant.id }.map(\.turn)
        if let live, !turns.contains(where: { $0.id == live.id }) { turns.append(live) }
        return turns
    }

    /// O turno em curso do agente, lido da cauda do transcript só quando o
    /// arquivo mudou — e só enquanto ele trabalha. Depois do `Stop` a leitura
    /// para, e o que já se tinha continua na tela até o histórico trazer o
    /// turno gravado (ou por 20 s, se o histórico nunca trouxer): sem isso a
    /// bolha sumia e voltava no intervalo entre o gancho e a gravação.
    private func liveTurn(of participant: ChatParticipant) -> ClaudeTranscript.LiveTurn? {
        guard participant.isAgent else { return nil }
        let cached = liveCache[participant.id]
        // `asking` também lê: permissão pedida no meio do turno não é fim de
        // turno, e a bolha não pode sumir enquanto você decide. Depois do
        // `Stop` o turno já está no histórico e a leitura cai sozinha.
        guard participant.activity == .working || participant.activity == .asking else {
            unwatch(participant.id)
            guard let cached, let live = cached.live else { return nil }
            let recorded = records().contains { $0.node == participant.id && $0.turn.id == live.turn.id }
            if recorded || Date().timeIntervalSince(cached.readAt) > 20 {
                liveCache[participant.id] = nil
                liveVersion += 1
                return nil
            }
            return live
        }
        guard let source = liveSource?(participant),
              let attributes = try? FileManager.default.attributesOfItem(atPath: source.transcript.path)
        else { return cached?.live }
        let size = (attributes[.size] as? UInt64) ?? 0
        let modified = (attributes[.modificationDate] as? Date) ?? .distantPast
        watch(participant.id, path: source.transcript.path)
        if let cached, cached.size == size, cached.modified == modified { return cached.live }
        // A cauda tem até 4 MB e o CLI grava várias linhas por segundo: ler a
        // cada uma saturava a fila de fundo e a main com remontagens. Umas
        // três leituras por segundo bastam para a bolha parecer viva.
        if let cached, Date().timeIntervalSince(cached.readAt) < 0.3 {
            scheduleLiveRefresh()
            return cached.live
        }

        if !liveParsing.contains(participant.id) {
            liveParsing.insert(participant.id)
            let id = participant.id
            // A partir do prompt do turno já conhecido: só o turno em curso é
            // relido, não os 4 MB de cauda.
            let from = cached?.live?.promptOffset ?? 0
            parseQueue.async { [weak self] in
                let live = ClaudeTranscript.liveTurn(at: source.transcript,
                                                     notBefore: source.notBefore, from: from)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.liveParsing.remove(id)
                    self.liveCache[id] = LiveEntry(size: size, modified: modified, live: live,
                                                   readAt: Date())
                    self.liveVersion += 1
                    self.refresh()
                }
            }
        }
        return cached?.live
    }

    /// `DispatchSource` no fd do transcript: `.write`/`.extend` chegam a cada
    /// linha que o CLI anexa. O arquivo é só-append, então o fd não fica
    /// órfão por troca de inode; se ficar (conversa nova), o caminho muda e o
    /// vigia é refeito.
    private func watch(_ id: String, path: String) {
        if let current = liveWatchers[id], current.path == path { return }
        unwatch(id)
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleLiveRefresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        liveWatchers[id] = (path, source)
    }

    /// As escritas chegam em rajada (uma por bloco do turno, de vários agentes
    /// ao mesmo tempo) e cada uma pedia uma remontagem. O que chega em 200 ms
    /// vira um refresh só.
    private var liveRefreshPending = false
    private func scheduleLiveRefresh() {
        guard !liveRefreshPending else { return }
        liveRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.liveRefreshPending = false
            guard self.window != nil, self.popupMode == .none else { return }
            self.refresh()
        }
    }

    private func unwatch(_ id: String) {
        liveWatchers[id]?.source.cancel()
        liveWatchers[id] = nil
    }

    /// O que a bolha ao vivo diz no fim: o último passo se o agente está numa
    /// ferramenta, "pensando…" se raciocina, "trabalhando…" no resto.
    private static func liveStatus(_ live: ClaudeTranscript.LiveTurn) -> ChatLive {
        switch live.last {
        case .thinking: return .thinking
        case .tool:
            for part in live.turn.chain.reversed() {
                if case .step(let step) = part { return .step(step) }
            }
            return .working
        default: return .working
        }
    }

    private func records() -> [ChatRecord] {
        guard let url = historyFile?(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return [] }
        let size = (attributes[.size] as? UInt64) ?? 0
        let modified = (attributes[.modificationDate] as? Date) ?? .distantPast
        let cached = historyCache[url]
        if let cached, cached.size == size, cached.modified == modified { return cached.records }

        if !parsing.contains(url) {
            parsing.insert(url)
            parseQueue.async { [weak self] in
                let parsed = ChatHistory.read(url)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.parsing.remove(url)
                    self.historyCache[url] = (size, modified, parsed)
                    self.historyVersion += 1
                    self.refresh()
                }
            }
        }
        // Enquanto a leitura nova não chega, o que já se tinha continua valendo.
        return cached?.records ?? []
    }

    /// Conversa longa tem milhares de turnos; a tabela só desenha o visível,
    /// mas medir todos na primeira montagem pesa e ninguém rola até lá. Entra
    /// o fim, e a janela cresce quando você rola até o começo do que há —
    /// como o WhatsApp carregando mensagens antigas.
    private static let windowStep = 60
    private(set) var loadedMessages = ChatContainer.windowStep
    /// Quantas linhas a tabela tem — para o teste.
    var snapshotBlockCount: Int { thread.blocks.count }
    private var loadingMore = false

    private func loadMoreIfNearTop() {
        guard thread.isNearTop, !loadingMore, messages.count > loadedMessages, !thread.blocks.isEmpty else { return }
        loadingMore = true
        loadedMessages += Self.windowStep
        buildSignature = ""
        refresh()
    }

    /// O que a montagem precisa, colhido na main num instante só. Só valor:
    /// a fila de fundo não toca em estado da view.
    private struct ThreadInput {
        let participants: [ChatParticipant]
        let records: [ChatRecord]
        let live: [String: ClaudeTranscript.LiveTurn]
        let pending: [ChatThread.Pending]
        /// Largura da thread e as medidas da montagem anterior, para reusar.
        let width: CGFloat
        let known: [String: ChatBlockLayout.BubbleMetrics]
        /// Quantas mensagens do fim entram.
        let window: Int
    }
    private struct ThreadOutput {
        let messages: [ChatMessage]
        let pending: [ChatThread.Pending]
        let blocks: [ChatBlock]
        let metrics: [String: ChatBlockLayout.BubbleMetrics]
    }

    /// Cruzar transcripts, ordenar e citar sai da main: com milhares de
    /// registros e vários agentes ao vivo, isso rodava por tique e por rajada
    /// de escrita, competindo com a digitação e o pty.
    private let buildQueue = DispatchQueue(label: "egeon.chat.thread", qos: .userInitiated)
    private var buildSignature = ""
    private var buildGeneration = 0
    private var building = false
    private var buildAgain = false
    /// Sobem quando o cache correspondente muda — é o que a assinatura olha em
    /// vez de comparar conteúdo.
    private var historyVersion = 0
    private var liveVersion = 0
    /// Quantas montagens foram para a fila — para o teste provar que o tique
    /// sem mudança não monta.
    private(set) var threadBuilds = 0

    private func rebuildThread(_ all: [ChatParticipant]) {
        // Ler o vivo tem efeito (vigia no fd, leitura agendada): fica na main,
        // uma vez por agente.
        var live: [String: ClaudeTranscript.LiveTurn] = [:]
        for agent in all where agent.isAgent {
            if let turn = liveTurn(of: agent) { live[agent.id] = turn }
        }
        let input = ThreadInput(participants: all, records: records(), live: live, pending: pending,
                                width: thread.width, known: thread.bubbleMetrics, window: loadedMessages)
        // O tique de 1 s chega sem nada ter mudado: só monta quando alguma
        // entrada mudou de fato.
        let signature = "\(historyVersion)|\(liveVersion)|\(input.width)|\(loadedMessages)|"
            + pending.map { "\($0.sentAt.timeIntervalSince1970)" }.joined(separator: ",") + "|"
            + all.map { "\($0.id):\($0.activity)" }.joined(separator: ",")
        guard signature != buildSignature else { return }
        buildSignature = signature
        buildGeneration += 1
        guard !building else { buildAgain = true; return }
        building = true
        threadBuilds += 1
        let generation = buildGeneration
        buildQueue.async { [weak self] in
            let output = Self.buildThread(input)
            DispatchQueue.main.async {
                guard let self else { return }
                self.building = false
                // Entrada mudou enquanto montava: este resultado já é passado.
                if generation == self.buildGeneration { self.applyThread(output) }
                if self.buildAgain {
                    self.buildAgain = false
                    self.buildSignature = ""
                    self.refresh()
                }
            }
        }
    }

    private static func buildThread(_ input: ThreadInput) -> ThreadOutput {
        let built = ChatThread.build(participants: input.participants, pending: input.pending) {
            turns(of: $0, records: input.records, live: input.live[$0.id]?.turn)
        }
        // O turno ao vivo de cada agente que trabalha: a bolha dele ganha a
        // linha de status. Quem trabalha e ainda não gravou nada do turno (ou
        // não tem transcript) ganha a bolha de "trabalhando…" solta no fim.
        // Terminal subindo não está respondendo a ninguém — a coluna já diz
        // "preparando…", e uma bolha ali era resposta a um prompt que não existe.
        var liveByAgent: [String: (turnId: String, status: ChatLive)] = [:]
        var typing: [ChatParticipant] = []
        let recorded = Set(input.records.map(\.key))
        for agent in input.participants
        where agent.isAgent && (agent.activity == .working || agent.activity == .asking) {
            if let live = input.live[agent.id], live.turn.hasReply,
               !recorded.contains("\(agent.id)#\(live.turn.id)") {
                liveByAgent[agent.id] = (live.turn.id,
                                         agent.activity == .asking ? .asking : liveStatus(live))
            } else if agent.activity == .working {
                typing.append(agent)
            }
        }
        let blocks = ChatBlocks.build(messages: Array(built.messages.suffix(input.window)),
                                      live: liveByAgent, typing: typing)
        let metrics = ChatBlockLayout.measure(blocks, width: input.width, known: input.known)
        return ThreadOutput(messages: built.messages, pending: built.pending,
                            blocks: blocks, metrics: metrics)
    }

    private func applyThread(_ output: ThreadOutput) {
        messages = output.messages
        pending = output.pending
        loadingMore = false
        let wasAtBottom = thread.isAtBottom
        let result = thread.apply(output.blocks, metrics: output.metrics)
        guard result.changed else { return }
        threadRebuilds += 1
        // Puxar para o fim só se você já estava lá — quem subiu para ler não
        // pode ser arrastado de volta a cada mensagem. Linha nova entra com
        // movimento; a bolha ao vivo crescendo só acompanha.
        if wasAtBottom || thread.blocks.count <= 2 {
            thread.scrollToBottom(animated: result.structural)
        }
        emptyThread.isHidden = !thread.blocks.isEmpty || shownTerminal != nil
        updateToBottomButton()
    }

    /// Quem o Tab e o alternador percorrem: só agentes. Shell continua na
    /// coluna e entra por clique — ciclar por ele no meio de uma conversa entre
    /// agentes é parada que não se quer.
    private var cycleable: [ChatParticipant] {
        (participants?() ?? []).filter { $0.isAgent && $0.activity != .dead }
    }

    private func focus(on id: String) {
        focusedId = id
        userChoseFocus = true
        let all = participants?() ?? []
        if let picked = all.first(where: { $0.id == id }), !picked.isAgent {
            showTerminal(of: picked)
        } else {
            leaveTerminal()
        }
        refresh()
    }

    // MARK: Terminal no lugar da thread

    /// Clicar num shell é querer VER o terminal: o card sai do canvas coberto e
    /// entra aqui, no lugar da thread — reparentar não mexe no pty, é o mesmo
    /// truque do mosaico. O composer continua: Enter manda comando para ele.
    private func showTerminal(of participant: ChatParticipant) {
        guard let view = terminalView?(participant.id) else { return }
        if shownTerminal !== view { leaveTerminal() }
        shownTerminal = view
        addSubview(view, positioned: .below, relativeTo: composer)
        thread.scrollView.isHidden = true
        toBottom.isHidden = true
        emptyThread.isHidden = true
        needsLayout = true
    }

    /// De volta à thread; o card volta para o canvas. O shell chama isto ao
    /// sair do modo chat, para o card não ficar preso aqui.
    func leaveTerminal() {
        guard let view = shownTerminal else { return }
        shownTerminal = nil
        view.removeFromSuperview()
        releaseTerminal?(view)
        thread.scrollView.isHidden = false
        needsLayout = true
    }

    private func cycleFocus() {
        let agents = cycleable
        guard !agents.isEmpty else { return }
        let index = agents.firstIndex { $0.id == focusedId } ?? -1
        focus(on: agents[(index + 1) % agents.count].id)
        if popupMode == .switcher { showSwitcher() }
    }

    // MARK: Envio

    private func sendMessage(_ text: String) {
        guard let target = composer.target else { return }
        if let error = send?(text, target) {
            Log.write("chat: envio para \(target.address) falhou: \(error)")
            return
        }
        pending.append(.init(text: text, target: target.id, sentAt: Date(),
                             knownTurnIds: Set(turns(of: target).map(\.id))))
        refresh()
    }

    /// Passo do spinner, no timer de 0.12s do app — o mesmo dos badges do
    /// canvas. No tique de 1s ele parecia travado.
    func tick() {
        thread.tick()
        column.tick()
    }

    func focusComposer() { composer.focus() }

    // MARK: Rota de teste

    /// Escreve na caixa (e opcionalmente aperta Enter) por fora — tecla
    /// sintética exige Acessibilidade, que a assinatura ad-hoc perde a cada
    /// build (ADR-003). Devolve o retrato do estado que saiu.
    func compose(_ text: String, send: Bool) -> [String: Any] {
        composer.text = text
        if send { composer.submitFromOutside() }
        layoutSubtreeIfNeeded()
        return snapshot()
    }

    /// O modo como dados: participantes, foco, popup aberto e a caixa.
    func snapshot() -> [String: Any] {
        let all = participants?() ?? []
        let popupInfo: [String: Any] = popupMode == .none ? ["mode": "none"] : [
            "mode": popupMode == .mention ? "mention" : "switcher",
            "items": popup.items.map(\.name)
        ]
        return [
            "focus": focusedId ?? "",
            "viewing": shownTerminal == nil ? "thread" : (focusedId ?? ""),
            "participants": all.map { p -> [String: Any] in
                ["id": p.id, "address": p.address, "agent": p.isAgent,
                 "activity": "\(p.activity)", "role": p.role ?? ""]
            },
            "composer": ["text": composer.text,
                         "textHeight": composer.currentTextHeight,
                         "height": composer.desiredHeight,
                         "focused": composer.hasFocus,
                         "firstResponder": composer.firstResponderDescription],
            "popup": popupInfo,
            "pending": pending.count,
            "messages": messages.map { message -> [String: Any] in
                let quote = message.quote.map { ["author": $0.authorId ?? "você", "text": $0.text] }
                switch message {
                case .prompt(let to, let turnId, let text, _, _, let from):
                    return ["kind": "prompt", "id": turnId, "to": to.id, "text": text,
                            "from": from ?? "", "quote": quote ?? [:]]
                case .pending(let to, let text, _, _):
                    return ["kind": "pending", "to": to.id, "text": text, "quote": quote ?? [:]]
                case .reply(let from, let turn, _):
                    let live = liveCache[from.id]?.live
                    return ["kind": "reply", "id": turn.id, "from": from.id, "text": turn.replyText,
                            "steps": turn.steps.map { "\($0.glyph) \($0.text)" },
                            "chain": turn.chain.map { part -> String in
                                switch part {
                                case .text(let text): return "¶ \(text)"
                                case .step(let step):
                                    var line = "\(step.glyph) \(step.text)"
                                    if let counts = step.diffCounts { line += " (+\(counts.added) −\(counts.removed))" }
                                    if let output = step.output {
                                        let n = output.split(separator: "\n").count
                                        line += " ⎿ \(n) linha\(n == 1 ? "" : "s")"
                                    }
                                    if step.isError { line += " ✗" }
                                    return line
                                }
                            },
                            "live": live?.turn.id == turn.id && from.activity == .working
                                ? Self.liveStatus(live!).label
                                : (live?.turn.id == turn.id && from.activity == .asking
                                   ? ChatLive.asking.label : ""),
                            "quote": quote ?? [:]]
                }
            }
        ]
    }

    // MARK: Popups

    private func togglePopup(_ mode: PopupMode) {
        if popupMode == mode { closePopup(); return }
        popupMode = mode
        if mode == .switcher { showSwitcher() }
    }

    private func closePopup() {
        popupMode = .none
        popup.isHidden = true
    }

    private func showSwitcher() {
        let agents = cycleable
        popup.show(agents.map {
            .init(name: $0.id, detail: $0.address, color: $0.color, glyph: $0.glyph)
        }, title: "FALAR COM — Tab alterna · Esc fecha")
        popup.onChoose = { [weak self] index in
            guard index < agents.count else { return }
            self?.focus(on: agents[index].id)
            self?.closePopup()
            self?.composer.focus()
        }
        popup.isHidden = false
        needsLayout = true
    }

    private func mentionChanged(_ query: String?) {
        guard let query else {
            if popupMode == .mention { closePopup() }
            return
        }
        let agents = cycleable
        let names = MentionParser.candidates(agents.map(\.id), query: query)
        guard !names.isEmpty else {
            if popupMode == .mention { closePopup() }
            return
        }
        popupMode = .mention
        let items = names.map { name -> ChatListPopup.Item in
            let agent = agents.first { $0.id == name }
            return .init(name: name, detail: agent?.address ?? "",
                         color: agent?.color ?? .systemGray, glyph: "✦")
        }
        popup.show(items, title: "MENCIONAR — o nome entra no prompt")
        popup.onChoose = { [weak self] index in
            guard index < names.count else { return }
            self?.composer.insertMention(names[index])
            self?.closePopup()
        }
        popup.isHidden = false
        needsLayout = true
    }

    private func handlePopupCommand(_ selector: Selector) -> Bool {
        guard popupMode != .none else { return false }
        switch selector {
        case #selector(NSResponder.moveUp(_:)):    popup.moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):  popup.moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)): popup.chooseSelected()
        case #selector(NSResponder.cancelOperation(_:)): closePopup()
        default: return false
        }
        return true
    }

    // MARK: Ciclo de vida

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard window != nil else { return }
        refresh()
        composer.focus()
        // Estado de terminal (trabalhando/laranja/verde) muda sem nos avisar;
        // 1 s acompanha o spinner sem pesar.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            guard let self, self.window != nil, self.popupMode == .none else { return }
            self.refresh()
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let pad: CGFloat = 16
        column.frame = NSRect(x: pad, y: 10, width: 264, height: bounds.height - 10 - pad)

        let contentX = pad + 264 + pad
        let contentWidth = max(0, bounds.width - contentX - pad)
        let wasAtBottom = thread.isAtBottom
        let composerHeight = composer.desiredHeight
        composer.frame = NSRect(x: contentX,
                                y: bounds.height - pad - composerHeight,
                                width: contentWidth, height: composerHeight)

        let scrollView = thread.scrollView
        scrollView.frame = NSRect(x: contentX, y: 10, width: contentWidth,
                                  height: max(0, composer.frame.minY - 20))
        shownTerminal?.frame = scrollView.frame
        toBottom.frame = NSRect(x: scrollView.frame.maxX - 54,
                                y: scrollView.frame.maxY - 48, width: 36, height: 36)
        emptyThread.frame = NSRect(x: contentX, y: composer.frame.minY - 28,
                                   width: contentWidth, height: 15)
        emptyThread.isHidden = !thread.blocks.isEmpty || shownTerminal != nil

        // A caixa cresceu (ou a janela mudou) e a thread encolheu por baixo:
        // quem estava no fim continua vendo a última mensagem em vez de a
        // caixa cobri-la.
        if scrollView.frame.height != threadViewportHeight {
            threadViewportHeight = scrollView.frame.height
            if wasAtBottom { thread.scrollToBottom(animated: false) }
        }
        // Largura nova: as medidas não valem mais. A montagem é assíncrona;
        // até chegar, as linhas ficam com a altura antiga.
        if thread.width != threadWidth {
            threadWidth = thread.width
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }

        if !popup.isHidden {
            let height = popup.desiredHeight
            let anchor = composer.popupAnchor
            popup.frame = NSRect(x: anchor.x, y: anchor.y - height,
                                 width: 320, height: height)
        }
    }

}

/// O botão redondo de "voltar ao fim", com o chevron do sistema centrado —
/// glifo de texto ficava torto dentro do círculo.
private final class ChevronButton: NSView {
    var onClick: (() -> Void)?
    private let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.backgroundColor = NSColor(srgbRed: 0.09, green: 0.11, blue: 0.16, alpha: 0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor
        shadow = NSShadow()
        shadow?.shadowBlurRadius = 10
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.5)

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        icon.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "ir ao fim")?
            .withSymbolConfiguration(config)
        icon.contentTintColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        icon.imageScaling = .scaleNone
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        icon.frame = bounds
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

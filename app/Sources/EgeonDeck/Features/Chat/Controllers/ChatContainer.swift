import AppKit

// MARK: - O modo chat

/// A bancada como conversa: participantes à esquerda, thread no meio, composer
/// embaixo. Fechaduras de leitura, como o EdgeController: quem sabe dos nós e
/// de enviar é o dono lá fora; aqui só se desenha e se coordena.
///
/// A thread sai dos transcripts dos agentes, cruzados por tempo, relidos a
/// cada segundo (só quando o arquivo mudou). O que você acabou de mandar
/// aparece como eco até o transcript confirmar o prompt.
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
    private let threadScroll = NSScrollView()
    private let threadDoc = FlippedView()
    private let composer = ChatComposer()
    private let popup = ChatListPopup()
    private let emptyThread = NSTextField(labelWithString:
        "Sem conversa ainda — Enter envia para o agente em foco")

    /// Só o Claude Code grava transcript hoje; quando outro CLI entrar, o
    /// leitor vem do perfil do agente.
    private let reader: TranscriptReader = ClaudeTranscript()
    private var transcriptCache: [URL: (size: UInt64, modified: Date, turns: [ChatTurn])] = [:]

    private var bubbles: [ThreadBubble] = []
    private var bubbleByKey: [String: ThreadBubble] = [:]
    private var messages: [ChatMessage] = []

    /// Clique na citação ou na resposta: rola até a mensagem original e a
    /// acende um instante.
    private func scrollTo(key: String) {
        guard let bubble = bubbleByKey[key] else { return }
        animateScroll(to: max(0, bubble.frame.minY - 24))
        let old = bubble.layer?.borderColor
        bubble.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { bubble.layer?.borderColor = old }
    }

    private var bottomY: CGFloat {
        max(0, threadDoc.frame.height - threadScroll.contentSize.height)
    }

    /// Rolagem com movimento, como no WhatsApp: pular seco perde a noção de
    /// para onde se foi.
    private func animateScroll(to y: CGFloat) {
        let clip = threadScroll.contentView
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.threadScroll.reflectScrolledClipView(clip)
            self.updateToBottomButton()
        }
    }

    /// A setinha no canto: aparece quando você subiu para ler e some no fim.
    private let toBottom = ChevronButton()

    private func updateToBottomButton() {
        let visible = threadScroll.contentView.documentVisibleRect
        let atBottom = visible.maxY >= threadDoc.frame.height - 40
        toBottom.isHidden = atBottom || bubbles.isEmpty
    }

    private func scrollToBottomClicked() { animateScroll(to: bottomY) }

    /// Rola por fora (`/chat?scroll=top|bottom`) — é como se confere a setinha
    /// e a animação sem mouse.
    func scroll(_ edge: String) {
        animateScroll(to: edge == "top" ? 0 : bottomY)
    }
    private var pending: [ChatThread.Pending] = []
    /// Pilhas de passos abertas, por "agente|instante do prompt".
    private var expandedSteps: Set<String> = []
    private var threadSignature = ""
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

        threadScroll.documentView = threadDoc
        threadScroll.hasVerticalScroller = true
        threadScroll.drawsBackground = false
        addSubview(threadScroll)

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

        // Saber se você está no fim é o que decide a setinha e o auto-scroll.
        threadScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(threadScrolled),
            name: NSView.boundsDidChangeNotification, object: threadScroll.contentView)
    }

    @objc private func threadScrolled() { updateToBottomButton() }

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

    /// Transcript cresce a cada tool call do agente, e chega a dezenas de MB.
    /// Ler e decodificar isso na main thread era o que travava a tela: a
    /// leitura vai para uma fila de fundo, e a main só consome o cache.
    private let parseQueue = DispatchQueue(label: "egeon.chat.transcript", qos: .utility)
    private var parsing: Set<URL> = []

    private func turns(of participant: ChatParticipant) -> [ChatTurn] {
        guard let url = participant.transcript,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return [] }
        let size = (attributes[.size] as? UInt64) ?? 0
        let modified = (attributes[.modificationDate] as? Date) ?? .distantPast
        let cached = transcriptCache[url]
        if let cached, cached.size == size, cached.modified == modified { return cached.turns }

        if !parsing.contains(url) {
            parsing.insert(url)
            let reader = self.reader
            parseQueue.async { [weak self] in
                let parsed = reader.turns(at: url)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.parsing.remove(url)
                    self.transcriptCache[url] = (size, modified, parsed)
                    self.refresh()
                }
            }
        }
        // Enquanto a leitura nova não chega, o que já se tinha continua valendo.
        return cached?.turns ?? []
    }

    /// Conversa longa tem centenas de turnos; desenhar todos a cada mudança
    /// pesa e ninguém rola até lá. Só o fim entra na tela.
    private static let drawnMessages = 80

    private func rebuildThread(_ all: [ChatParticipant]) {
        let built = ChatThread.build(participants: all, pending: pending) { [weak self] in
            self?.turns(of: $0) ?? []
        }
        messages = built.messages
        pending = built.pending
        // Só quem está num turno. Terminal subindo não está respondendo a
        // ninguém — a coluna de participantes já diz "preparando…", e uma bolha
        // de "trabalhando…" ali era resposta a um prompt que não existe.
        let typing = all.filter { $0.isAgent && $0.activity == .working }

        // Remontar view a cada segundo faria a thread piscar: só quando o que
        // se desenha mudou de fato. O spinner anda em cima da bolha existente.
        let signature = "\(messages.count)|\(messages.last?.at.timeIntervalSince1970 ?? 0)|"
            + "\(messages.last.map { "\($0)" }.hashValue)|\(pending.count)|"
            + typing.map(\.id).joined(separator: ",") + "|\(expandedSteps.count)"
        guard signature != threadSignature else { return }
        threadSignature = signature

        let visible = threadScroll.contentView.documentVisibleRect
        let wasAtBottom = visible.maxY >= threadDoc.frame.height - 40

        bubbles.forEach { $0.removeFromSuperview() }
        bubbleByKey = [:]
        bubbles = messages.suffix(Self.drawnMessages).map { message -> ThreadBubble in
            let bubble: ThreadBubble
            switch message {
            case .prompt(let to, _, let text, let at, let quote):
                let view = ChatBubbleView(text: text, target: to, at: at, quote: quote)
                if let quote {
                    view.onQuoteClick = { [weak self] in self?.scrollTo(key: quote.targetKey) }
                }
                bubble = view
            case .pending(let to, let text, let at, let quote):
                let view = ChatBubbleView(text: text, target: to, at: at, pending: true, quote: quote)
                if let quote {
                    view.onQuoteClick = { [weak self] in self?.scrollTo(key: quote.targetKey) }
                }
                bubble = view
            case .reply(let from, let turn, let quote):
                let key = message.key
                let view = AgentBubbleView(from: from, turn: turn,
                                           expanded: expandedSteps.contains(key), quote: quote)
                view.onToggleSteps = { [weak self] in
                    guard let self else { return }
                    if self.expandedSteps.contains(key) { self.expandedSteps.remove(key) }
                    else { self.expandedSteps.insert(key) }
                    self.threadSignature = ""
                    self.refresh()
                }
                // Com ou sem citação, a resposta sabe qual prompt responde.
                let target = quote?.targetKey ?? "p|\(turn.id)"
                view.onQuoteClick = { [weak self] in self?.scrollTo(key: target) }
                bubble = view
            }
            bubbleByKey[message.key] = bubble
            return bubble
        }
        for agent in typing { bubbles.append(AgentBubbleView(typing: agent)) }
        bubbles.forEach(threadDoc.addSubview)

        needsLayout = true
        layoutSubtreeIfNeeded()
        // Puxar para o fim só se você já estava lá — quem subiu para ler não
        // pode ser arrastado de volta a cada mensagem.
        if wasAtBottom || bubbles.count <= 2 {
            animateScroll(to: bottomY)
        }
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
        threadScroll.isHidden = true
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
        threadScroll.isHidden = false
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
        bubbles.forEach { ($0 as? AgentBubbleView)?.tick() }
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
                case .prompt(let to, let turnId, let text, _, _):
                    return ["kind": "prompt", "id": turnId, "to": to.id, "text": text,
                            "quote": quote ?? [:]]
                case .pending(let to, let text, _, _):
                    return ["kind": "pending", "to": to.id, "text": text, "quote": quote ?? [:]]
                case .reply(let from, let turn, _):
                    return ["kind": "reply", "id": turn.id, "from": from.id, "text": turn.replyText,
                            "steps": turn.steps.map { "\($0.glyph) \($0.text)" },
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
        let composerHeight = composer.desiredHeight
        composer.frame = NSRect(x: contentX,
                                y: bounds.height - pad - composerHeight,
                                width: contentWidth, height: composerHeight)

        threadScroll.frame = NSRect(x: contentX, y: 10, width: contentWidth,
                                    height: max(0, composer.frame.minY - 20))
        shownTerminal?.frame = threadScroll.frame
        toBottom.frame = NSRect(x: threadScroll.frame.maxX - 54,
                                y: threadScroll.frame.maxY - 48, width: 36, height: 36)
        emptyThread.frame = NSRect(x: contentX, y: composer.frame.minY - 28,
                                   width: contentWidth, height: 15)
        emptyThread.isHidden = !bubbles.isEmpty || shownTerminal != nil

        layoutBubbles(width: contentWidth)

        if !popup.isHidden {
            let height = popup.desiredHeight
            let anchor = composer.popupAnchor
            popup.frame = NSRect(x: anchor.x, y: anchor.y - height,
                                 width: 320, height: height)
        }
    }

    private func layoutBubbles(width: CGFloat) {
        var y: CGFloat = 10
        for bubble in bubbles {
            let bubbleWidth = bubble.width(for: width - 36)
            let height = bubble.height(for: bubbleWidth)
            bubble.frame = NSRect(x: bubble.alignsRight ? width - bubbleWidth - 18 : 18,
                                  y: y, width: bubbleWidth, height: height)
            y += height + 12
        }
        threadDoc.frame = NSRect(x: 0, y: 0, width: width,
                                 height: max(y, threadScroll.contentSize.height))
    }
}

/// Documento da thread: flipped para as bolhas empilharem de cima para baixo.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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

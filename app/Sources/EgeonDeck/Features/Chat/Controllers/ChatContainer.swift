import AppKit

// MARK: - O modo chat

/// A bancada como conversa: participantes à esquerda, thread no meio, composer
/// embaixo. Fechaduras de leitura, como o EdgeController: quem sabe dos nós e
/// de enviar é o dono lá fora; aqui só se desenha e se coordena.
///
/// Nesta primeira fase a thread mostra o que VOCÊ mandou (o envio é real, via
/// Dispatcher). As bolhas de resposta — transcript, passos, sub-conversas —
/// são a fase seguinte.
final class ChatContainer: NSView {
    /// Os nós da bancada como participantes, lidos na hora.
    var participants: (() -> [ChatParticipant])?
    /// Envia. Devolve mensagem de erro, ou nil se entrou na fila.
    var send: ((String, ChatParticipant) -> String?)?

    private let column = ParticipantsColumn()
    private let threadScroll = NSScrollView()
    private let threadDoc = FlippedView()
    private let composer = ChatComposer()
    private let popup = ChatListPopup()
    private let emptyThread = NSTextField(labelWithString:
        "Enter envia — a resposta do agente continua no terminal dele por enquanto")

    private var bubbles: [ChatBubbleView] = []
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
    }

    private var userChoseFocus = false

    /// Quem o Tab e o alternador percorrem: só agentes. Shell continua na
    /// coluna e entra por clique — ciclar por ele no meio de uma conversa entre
    /// agentes é parada que não se quer.
    private var cycleable: [ChatParticipant] {
        (participants?() ?? []).filter { $0.isAgent && $0.activity != .dead }
    }

    private func focus(on id: String) {
        focusedId = id
        userChoseFocus = true
        refresh()
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
        let bubble = ChatBubbleView(text: text, target: target)
        bubbles.append(bubble)
        threadDoc.addSubview(bubble)
        needsLayout = true
        layoutSubtreeIfNeeded()
        threadDoc.scroll(NSPoint(x: 0, y: max(0, threadDoc.frame.height
                                              - threadScroll.contentSize.height)))
    }

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
            "participants": all.map { p -> [String: Any] in
                ["id": p.id, "address": p.address, "agent": p.isAgent,
                 "activity": "\(p.activity)", "role": p.role ?? ""]
            },
            "composer": ["text": composer.text,
                         "textHeight": composer.currentTextHeight,
                         "height": composer.desiredHeight],
            "popup": popupInfo,
            "sent": bubbles.count
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
        emptyThread.frame = NSRect(x: contentX, y: composer.frame.minY - 28,
                                   width: contentWidth, height: 15)
        emptyThread.isHidden = !bubbles.isEmpty

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
            bubble.frame = NSRect(x: width - bubbleWidth - 18, y: y,
                                  width: bubbleWidth, height: height)
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

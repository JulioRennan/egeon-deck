import AppKit

/// A caixa de escrever do modo Chat.
///
/// Duas coisas ela resolve que o terminal não resolve: **para quem** vai, escolhido
/// sem tirar a mão do teclado, e **quem mais existe**, oferecido enquanto você
/// escreve. No canvas isso é implícito — você clica no card e digita nele. Aqui há
/// um campo e cinco agentes, então o destinatário tem de estar na tela.
final class ChatComposer: NSView {
    /// Ids de destino possíveis, na ordem em que o Tab cicla. `todos` no fim.
    var candidates: [String] = [] {
        didSet {
            guard candidates != oldValue else { return }
            // Enquanto você não escolheu, o padrão é RE-derivado a cada mudança da
            // lista, e não fixado na primeira. Fixado, ele grudava no shell: os
            // alvos entram no Dispatcher na ordem em que os nós sobem, e na primeira
            // leitura só o terminal comum estava registrado — a caixa abria dizendo
            // "escreva pra t1" numa sessão de três agentes, e nunca se corrigia.
            if !chosen || !candidates.contains(target) { target = candidates.first ?? "" }
            restyle()
        }
    }

    /// Você já disse com quem quer falar — por Tab ou clicando no painel. A partir
    /// daí a escolha é sua e a lista não a desfaz.
    private var chosen = false

    private(set) var target: String = "" { didSet { restyle() } }

    /// Texto pronto para entregar, e para quem.
    var onSend: ((_ text: String, _ target: String) -> Void)?

    /// Rótulo de estado de cada candidato, para a lista de menção. Vem de fora
    /// porque quem sabe o estado é o Dispatcher.
    var statusOf: ((String) -> String)?

    private let toLabel = ChatStyle.label("para:", font: ChatStyle.meta, color: ChatStyle.dim)
    private let dot = NSView()
    private let name = ChatStyle.label("", font: ChatStyle.name, color: ChatStyle.text)
    private let hint = ChatStyle.label("⇥ troca o destinatário  ·  @ menciona  ·  ⏎ envia",
                                       font: ChatStyle.meta, color: ChatStyle.faint)
    private let box = NSView()
    private let input = ComposerTextView()
    private let placeholder = ChatStyle.label("", font: ChatStyle.body, color: ChatStyle.faint)
    private let sendButton = NSButton()
    private let mentions = MentionList()

    static let height: CGFloat = 92

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.095, alpha: 1).cgColor

        dot.wantsLayer = true
        addSubview(toLabel)
        addSubview(dot)
        addSubview(name)
        hint.alignment = .right
        addSubview(hint)

        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = ChatStyle.hairline.cgColor
        box.layer?.cornerRadius = 5
        addSubview(box)

        input.font = ChatStyle.body
        input.textColor = ChatStyle.text
        input.drawsBackground = false
        input.isRichText = false
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.insertionPointColor = ChatStyle.text
        input.textContainerInset = NSSize(width: 4, height: 6)
        input.onSubmit = { [weak self] in self?.send() }
        input.onCycle = { [weak self] backwards in self?.cycle(backwards) }
        input.onTextChange = { [weak self] in self?.textChanged() }
        input.onMentionKey = { [weak self] key in self?.mentions.handle(key) ?? false }
        box.addSubview(input)

        placeholder.textColor = ChatStyle.faint
        box.addSubview(placeholder)

        sendButton.image = NSImage(systemSymbolName: "arrow.right",
                                   accessibilityDescription: "enviar")
        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(sendClicked)
        addSubview(sendButton)

        mentions.isHidden = true
        mentions.onPick = { [weak self] id in self?.insertMention(id) }
        addSubview(mentions)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func focus() { window?.makeFirstResponder(input) }

    /// Muda o destinatário de fora — clicar num agente no painel da direita.
    func aim(at id: String) {
        guard candidates.contains(id) else { return }
        chosen = true
        target = id
        focus()
    }

    // MARK: Destinatário

    private func cycle(_ backwards: Bool) {
        guard !candidates.isEmpty else { return }
        chosen = true
        let index = candidates.firstIndex(of: target) ?? 0
        let step = backwards ? -1 : 1
        target = candidates[(index + step + candidates.count) % candidates.count]
    }

    /// `todos` não tem cor de agente — é a sessão inteira, e pintá-la com a cor de
    /// alguém sugeriria que a mensagem é dele.
    private var targetColor: NSColor {
        target == ChatComposer.everyone ? ChatStyle.text : AgentColor.of(target)
    }

    static let everyone = "todos"

    private func restyle() {
        name.stringValue = target
        name.textColor = targetColor
        dot.layer?.backgroundColor = targetColor.cgColor
        box.layer?.borderColor = ChatStyle.hairline.cgColor
        placeholder.stringValue = target.isEmpty
            ? "nenhum terminal de pé nesta sessão"
            : "escreva pra \(target)"
        needsLayout = true
    }

    // MARK: Menção

    private func textChanged() {
        placeholder.isHidden = !input.string.isEmpty
        // A palavra que está sendo digitada antes do cursor. Nada de `@` no meio
        // de e-mail ou de caminho: só vale colado num limite de palavra.
        guard let query = input.pendingMention else {
            mentions.dismiss()
            needsLayout = true
            return
        }
        let items = candidates.filter { $0.lowercased().contains(query.lowercased()) }
        if items.isEmpty { mentions.dismiss() } else {
            mentions.show(items) { [weak self] id in self?.statusOf?(id) ?? "" }
        }
        needsLayout = true
    }

    private func insertMention(_ id: String) {
        input.replacePendingMention(with: "@" + id + " ")
        mentions.dismiss()
        textChanged()
        focus()
    }

    // MARK: Envio

    @objc private func sendClicked() { send() }

    private func send() {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !target.isEmpty else { return }
        input.string = ""
        placeholder.isHidden = false
        mentions.dismiss()
        onSend?(text, target)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let margin: CGFloat = 24
        let width = min(ChatStyle.column, max(200, bounds.width - margin * 2))
        let x = ((bounds.width - width) / 2).rounded()

        let toWidth = toLabel.measured
        toLabel.frame = NSRect(x: x, y: 11, width: toWidth, height: 13)
        dot.frame = NSRect(x: x + toWidth + 6, y: 14, width: 7, height: 7)
        let nameLeft = x + toWidth + 19
        let nameWidth = name.measured
        name.frame = NSRect(x: nameLeft, y: 9, width: nameWidth, height: 15)
        let hintLeft = nameLeft + nameWidth + 12
        hint.frame = NSRect(x: hintLeft, y: 11,
                            width: max(0, x + width - hintLeft), height: 13)

        let boxHeight: CGFloat = 44
        box.frame = NSRect(x: x, y: 30, width: width - 42, height: boxHeight)
        input.frame = box.bounds
        placeholder.frame = NSRect(x: 8, y: 12, width: box.bounds.width - 16, height: 17)
        sendButton.frame = NSRect(x: box.frame.maxX + 8, y: 30, width: 34, height: boxHeight)

        // Acima da caixa: a lista cresce para cima porque a caixa está no rodapé
        // da janela e para baixo ela sairia da tela.
        let size = mentions.fittingSize
        mentions.frame = NSRect(x: x, y: max(0, 30 - size.height - 6),
                                width: size.width, height: size.height)
    }

    /// Fio em cima em vez de sombra: o thread rola encostado nela, e sombra aqui
    /// pousaria sobre a última mensagem.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ChatStyle.rule.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

// MARK: - O campo

/// `NSTextView` que cede Tab e Enter ao composer.
///
/// Sem isto o Tab insere tabulação e o Enter quebra linha — os dois defaults
/// certos num editor de texto e errados numa caixa de mensagem, onde Tab escolhe
/// destinatário e Enter envia.
final class ComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCycle: ((_ backwards: Bool) -> Void)?
    var onTextChange: (() -> Void)?
    /// Seta e Enter enquanto a lista de menção está aberta. Devolve `true` quando
    /// a lista consumiu a tecla.
    var onMentionKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onMentionKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) { onCycle?(false) }
    override func insertBacktab(_ sender: Any?) { onCycle?(true) }

    /// Enter envia, Shift+Enter quebra linha. É a convenção de toda caixa de
    /// mensagem, e quebrar linha é o caso raro aqui.
    override func insertNewline(_ sender: Any?) {
        if NSEvent.modifierFlags.contains(.shift) {
            super.insertNewline(sender)
        } else {
            onSubmit?()
        }
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?()
    }

    /// O `@algo` que o cursor está terminando de escrever, se houver.
    var pendingMention: String? {
        let caret = selectedRange().location
        guard caret > 0, caret <= (string as NSString).length else { return nil }
        let before = (string as NSString).substring(to: caret)
        guard let at = before.lastIndex(of: "@") else { return nil }
        let word = before[before.index(after: at)...]
        // Espaço depois do `@` fecha a menção: você desistiu e seguiu escrevendo.
        guard !word.contains(" "), !word.contains("\n") else { return nil }
        // `@` tem de abrir palavra, senão e-mail e handle viram menção.
        if at > before.startIndex {
            let previous = before[before.index(before: at)]
            guard previous == " " || previous == "\n" else { return nil }
        }
        return String(word)
    }

    func replacePendingMention(with text: String) {
        guard let word = pendingMention else { return }
        let caret = selectedRange().location
        let start = caret - word.count - 1
        guard start >= 0 else { return }
        let range = NSRange(location: start, length: word.count + 1)
        if shouldChangeText(in: range, replacementString: text) {
            replaceCharacters(in: range, with: text)
            didChangeText()
        }
    }
}

// MARK: - Lista de menção

/// Quem existe, oferecido enquanto você escreve `@`.
final class MentionList: NSView {
    var onPick: ((String) -> Void)?

    private var items: [String] = []
    private var rows: [NSView] = []
    private var selected = 0

    private static let rowHeight: CGFloat = 26
    private static let width: CGFloat = 260

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = ChatStyle.rule.cgColor
        layer?.cornerRadius = 5
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 12
        layer?.shadowOffset = NSSize(width: 0, height: -4)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        isHidden ? .zero
            : NSSize(width: Self.width, height: CGFloat(items.count) * Self.rowHeight + 8)
    }

    func show(_ items: [String], status: (String) -> String) {
        let changed = items != self.items
        self.items = items
        if changed { selected = 0 }
        isHidden = false
        guard changed else { highlight(); return }

        rows.forEach { $0.removeFromSuperview() }
        rows = items.map { id in
            let row = NSView()
            row.wantsLayer = true
            let chip = AgentChip(id)
            row.addSubview(chip)
            let state = ChatStyle.label(status(id), font: ChatStyle.meta, color: ChatStyle.faint)
            state.alignment = .right
            row.addSubview(state)
            addSubview(row)
            return row
        }
        needsLayout = true
        highlight()
    }

    func dismiss() {
        guard !isHidden else { return }
        isHidden = true
        items = []
        rows.forEach { $0.removeFromSuperview() }
        rows = []
    }

    /// Seta escolhe, Enter e Tab confirmam, Esc fecha. Devolve `true` quando
    /// consumiu — é o que impede o Enter de enviar a mensagem no meio da escolha.
    func handle(_ event: NSEvent) -> Bool {
        guard !isHidden, !items.isEmpty else { return false }
        switch event.keyCode {
        case 125: selected = (selected + 1) % items.count; highlight(); return true
        case 126: selected = (selected - 1 + items.count) % items.count; highlight(); return true
        case 36, 48: onPick?(items[selected]); return true
        case 53: dismiss(); return true
        default: return false
        }
    }

    private func highlight() {
        for (index, row) in rows.enumerated() {
            row.layer?.backgroundColor = index == selected
                ? NSColor(calibratedWhite: 1, alpha: 0.09).cgColor
                : NSColor.clear.cgColor
        }
    }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 4, y: 4 + CGFloat(index) * Self.rowHeight,
                               width: bounds.width - 8, height: Self.rowHeight)
            guard let chip = row.subviews.first as? AgentChip else { continue }
            let size = chip.fittingSize
            chip.frame = NSRect(x: 7, y: 5, width: size.width, height: size.height)
            row.subviews.last?.frame = NSRect(x: chip.frame.maxX + 8, y: 6,
                                              width: row.bounds.width - chip.frame.maxX - 16,
                                              height: 14)
        }
    }
}

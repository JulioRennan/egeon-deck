import AppKit

// MARK: - O composer

/// A caixa de escrever, no jeito do Slack: cresce PARA CIMA conforme o texto
/// até um teto e daí passa a rolar por dentro. Sem barra de formatação e sem
/// barra de anexos — em cima só o chip de destinatário (Tab alterna) e o botão
/// de enviar embutido do lado do texto.
final class ChatComposer: NSView {
    var onSend: ((String) -> Void)?
    var onCycleTarget: (() -> Void)?
    var onToggleSwitcher: (() -> Void)?
    /// A menção mudou: `nil` fecha o popup, string (pode ser vazia) filtra.
    var onMentionQuery: ((String?) -> Void)?
    /// Um popup está aberto e quer as teclas de navegação do composer.
    var popupCommand: ((Selector) -> Bool)?
    /// A altura ideal mudou — o dono do layout precisa reagir.
    var onHeightChange: (() -> Void)?

    private(set) var target: ChatParticipant?

    private let chip = ChipView()
    private let tabHint = NSTextField(labelWithString: "Tab alterna destinatário")
    private let scroll = NSScrollView()
    private let textView = ComposerTextView()
    private let placeholder = PassthroughLabel(labelWithString: "")
    private let send = NSTextField(labelWithString: "↑")
    private let microcopy = NSTextField(labelWithString: "")

    /// Teto do crescimento: ~6 linhas. Daí em diante o texto rola por dentro.
    private static let maxTextHeight: CGFloat = 132
    private static let minTextHeight: CGFloat = 44

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.05).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor

        chip.onClick = { [weak self] in self?.onToggleSwitcher?() }
        addSubview(chip)

        tabHint.font = .systemFont(ofSize: 10.5)
        tabHint.textColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        addSubview(tabHint)

        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13.5)
        textView.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        textView.insertionPointColor = .white
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 6, height: 9)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.25)
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        scroll.verticalScrollElasticity = .none
        addSubview(scroll)

        placeholder.font = .systemFont(ofSize: 13.5)
        placeholder.textColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        addSubview(placeholder)

        send.font = .systemFont(ofSize: 16, weight: .bold)
        send.alignment = .center
        send.wantsLayer = true
        send.layer?.cornerRadius = 10
        send.layer?.borderWidth = 1
        let click = NSClickGestureRecognizer(target: self, action: #selector(sendClicked))
        send.addGestureRecognizer(click)
        addSubview(send)

        microcopy.font = .systemFont(ofSize: 10.5)
        microcopy.textColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        addSubview(microcopy)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func setTarget(_ participant: ChatParticipant?) {
        target = participant
        let color = participant?.color ?? .systemGray
        chip.set(name: participant.map { "\($0.glyph) \($0.id)" } ?? "—",
                 detail: participant?.address ?? "", color: color)
        placeholder.stringValue = participant.map { "Prompt para \($0.address)…" }
            ?? "Nenhum terminal vivo nesta bancada"
        microcopy.stringValue = participant.map {
            "Enter envia — o prompt entra no terminal de \($0.address) · ⇧Enter quebra linha · @ menciona"
        } ?? ""
        send.textColor = color
        send.layer?.borderColor = color.withAlphaComponent(0.4).cgColor
        send.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
        needsLayout = true
    }

    /// Altura total que o composer quer, já com o teto do texto aplicado.
    var desiredHeight: CGFloat {
        30 + textHeight + 26
    }

    private var textHeight: CGFloat {
        guard let manager = textView.layoutManager,
              let container = textView.textContainer else { return Self.minTextHeight }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container).height + 18
        return min(max(used, Self.minTextHeight), Self.maxTextHeight)
    }

    func focus() { window?.makeFirstResponder(textView) }

    /// A caixa está com o teclado.
    var hasFocus: Bool { window?.firstResponder === textView }

    /// Quem tem o teclado descreve-se — para conferir de fora quem roubou o foco.
    var firstResponderDescription: String {
        guard let responder = window?.firstResponder else { return "nenhum" }
        return String(describing: type(of: responder))
    }

    func insertMention(_ name: String) {
        let text = textView.string
        guard let active = MentionParser.activeMention(in: text,
                                                       caret: textView.selectedRange().location)
        else { return }
        let result = MentionParser.insert(name, into: text, replacing: active.range)
        textView.string = result.text
        textView.setSelectedRange(NSRange(location: result.caret, length: 0))
        onMentionQuery?(nil)
        refreshAfterEdit()
    }

    /// Onde o popup deve encostar: o topo do composer, em coordenadas do pai.
    var popupAnchor: NSPoint { NSPoint(x: frame.minX + 10, y: frame.minY - 8) }

    /// O texto da caixa, para a rota de teste escrever e ler sem teclado.
    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            textView.setSelectedRange(NSRange(location: (newValue as NSString).length,
                                              length: 0))
            refreshAfterEdit()
            reportMention()
        }
    }

    /// Aperta o Enter por fora — o gesto que a rota `/compose?send=1` simula.
    func submitFromOutside() { submit() }

    var currentTextHeight: CGFloat { textHeight }

    @objc private func sendClicked() { submit() }

    private func submit() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        textView.string = ""
        onMentionQuery?(nil)
        refreshAfterEdit()
        onSend?(text)
    }

    private func refreshAfterEdit() {
        placeholder.isHidden = !textView.string.isEmpty
        onHeightChange?()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let chipWidth = chip.desiredWidth
        chip.frame = NSRect(x: 10, y: 8, width: chipWidth, height: 24)
        let hintWidth = tabHint.intrinsicContentSize.width
        tabHint.frame = NSRect(x: bounds.width - hintWidth - 12, y: 13,
                               width: hintWidth, height: 14)
        let textHeight = self.textHeight
        scroll.frame = NSRect(x: 10, y: 38, width: bounds.width - 66,
                              height: textHeight)
        placeholder.frame = NSRect(x: 22, y: 47, width: bounds.width - 90, height: 17)
        send.frame = NSRect(x: bounds.width - 46, y: 38 + textHeight - 36,
                            width: 36, height: 36)
        microcopy.frame = NSRect(x: 12, y: 38 + textHeight + 5,
                                 width: bounds.width - 24, height: 14)
    }
}

// MARK: - Teclas

extension ChatComposer: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        refreshAfterEdit()
        reportMention()
    }

    func textViewDidChangeSelection(_ notification: Notification) { reportMention() }

    fileprivate func reportMention() {
        let active = MentionParser.activeMention(in: textView.string,
                                                 caret: textView.selectedRange().location)
        onMentionQuery?(active?.query)
    }

    func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
        // Popup aberto tem prioridade: setas e Enter navegam a lista.
        if popupCommand?(selector) == true { return true }

        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // ⇧Enter quebra linha; Enter puro envia.
            if NSEvent.modifierFlags.contains(.shift) { return false }
            submit()
            return true
        case #selector(NSResponder.insertTab(_:)):
            onCycleTarget?()
            return true
        default:
            return false
        }
    }
}

// MARK: - Chip de destinatário

private final class ChipView: NSView {
    var onClick: (() -> Void)?
    private let para = NSTextField(labelWithString: "PARA")
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let caret = NSTextField(labelWithString: "▾")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        para.font = .systemFont(ofSize: 9, weight: .semibold)
        name.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        caret.font = .systemFont(ofSize: 11)
        [para, name, detail, caret].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func set(name text: String, detail address: String, color: NSColor) {
        name.stringValue = text
        detail.stringValue = address.isEmpty ? "" : "· \(address)"
        [para, name, caret].forEach { $0.textColor = color }
        para.alphaValue = 0.7
        caret.alphaValue = 0.7
        detail.textColor = color.withAlphaComponent(0.65)
        layer?.borderColor = color.withAlphaComponent(0.35).cgColor
        layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
        needsLayout = true
    }

    var desiredWidth: CGFloat {
        para.intrinsicContentSize.width + name.intrinsicContentSize.width
            + detail.intrinsicContentSize.width + caret.intrinsicContentSize.width + 40
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 10
        for field in [para, name, detail, caret] {
            let width = field.intrinsicContentSize.width
            field.frame = NSRect(x: x, y: 5, width: width, height: 14)
            x += width + 7
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Rótulo que não existe para o mouse. O placeholder fica POR CIMA da caixa,
/// e um NSTextField comum ali engolia o clique: com a caixa vazia e o foco em
/// outro lugar, clicar no "Prompt para…" não fazia nada.
private final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - O NSTextView do composer

private final class ComposerTextView: NSTextView {
    // Esc chega como cancelOperation e o delegate não o vê — repassa como
    // comando para o composer poder fechar popup.
    override func cancelOperation(_ sender: Any?) {
        _ = (delegate as? ChatComposer)?.popupCommand?(#selector(NSResponder.cancelOperation(_:)))
    }
}

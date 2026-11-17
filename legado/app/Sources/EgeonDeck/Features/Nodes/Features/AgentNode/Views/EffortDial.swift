import AppKit

/// O esforço do agente no cabeçalho do card: um slider com uma marca por nível,
/// o nome do nível ao lado e a pílula "auto". Arrastar, clicar na trilha ou rolar
/// em cima dele ajustam.
///
/// Auto é interruptor, não marca da trilha: como primeira marca, ele deixava a
/// barra vazia enquanto o modelo rodava em `high`, e não dava para saber de olhar
/// se o nó estava em auto ou num nível (ADR-090). Em auto a barra mostra, apagada,
/// o nível que o modelo usa; mexer nela escolhe um nível e desliga o auto.
///
/// A escolha só vale quando a mão para (debounce de 1s, e nunca com o botão
/// ainda apertado): cada troca reinicia o processo, e passar
/// de `low` a `max` nível a nível mataria o CLI quatro vezes no caminho.
/// Enquanto não assenta, o nome aparece com `…`.
final class EffortDial: NSView {
    /// A escolha assentou. Nil é o padrão do CLI.
    var onCommit: ((String?) -> Void)?
    /// O texto do nível mudou de largura.
    var onResize: (() -> Void)?

    private let levels: [String]
    private let tint: NSColor
    /// Índice em `levels`; nil é o auto.
    private var selection: Int?
    private let committed: String?
    private var commitTimer: Timer?
    private var scrollAccumulator: CGFloat = 0

    private let slider = NSSlider()
    private let label = NSTextField(labelWithString: "")
    private let autoButton = HandButton.pill(title: "auto")

    private static let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    private static let sliderWidth: CGFloat = 96
    /// Do texto do nível ao slider.
    static let textToSlider: CGFloat = 5
    private static let sliderToAuto: CGFloat = 8
    private static let autoHeight: CGFloat = 14
    private static let height: CGFloat = 18
    /// Quanto de rolagem vale um nível. Trackpad manda deltas em pontos, aos
    /// punhados; roda de mouse manda linhas, uma por clique.
    private static let preciseStep: CGFloat = 14
    private static let settleDelay: TimeInterval = 1.0

    /// O nível que "auto" dá neste modelo — `medium` no Opus 5.5. Nil quando não
    /// se sabe qual é o modelo.
    private let autoLevel: String?

    /// `levels` vazio é modelo sem esforço: o slider fica desligado e diz isso,
    /// em vez de sumir e deixar a faixa mudando de forma a cada troca de modelo.
    init(levels: [String], current: String?, autoLevel: String? = nil, tint: NSColor) {
        self.autoLevel = autoLevel
        var levels = levels
        if !levels.isEmpty, let current, !current.isEmpty, !levels.contains(current) {
            levels.append(current)
        }
        self.levels = levels
        self.tint = tint
        self.selection = current.flatMap { levels.firstIndex(of: $0) }
        self.committed = selection.map { levels[$0] }
        super.init(frame: .zero)

        slider.controlSize = .mini
        slider.minValue = 0
        slider.maxValue = Double(max(levels.count - 1, 1))
        slider.numberOfTickMarks = max(levels.count, 2)
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isEnabled = !levels.isEmpty
        addSubview(slider)

        label.font = Self.font
        label.lineBreakMode = .byClipping
        addSubview(label)

        autoButton.target = self
        autoButton.action = #selector(toggleAuto)
        if !levels.isEmpty { addSubview(autoButton) }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { commitTimer?.invalidate() }

    var value: String? { selection.map { levels[$0] } }

    var isAuto: Bool { selection == nil }

    private var pending: Bool { value != committed }

    var isUsable: Bool { !levels.isEmpty }

    private var autoIndex: Int? { autoLevel.flatMap { levels.firstIndex(of: $0) } }

    /// O nível fica à ESQUERDA do slider e ocupa só a largura do texto atual.
    /// Reservar a do nome mais comprido deixava um buraco antes do vizinho; e,
    /// com a faixa alinhada à direita, o texto crescer empurra só o que está à
    /// esquerda dele — o slider não sai de baixo do cursor no meio do arrasto.
    private var textWidth: CGFloat {
        ceil((label.stringValue as NSString).size(withAttributes: [.font: Self.font]).width) + 2
    }

    private var autoWidth: CGFloat { isUsable ? Self.sliderToAuto + autoButton.pillWidth : 0 }

    var preferredWidth: CGFloat { textWidth + Self.textToSlider + Self.sliderWidth + autoWidth }

    override var fittingSize: NSSize { NSSize(width: preferredWidth, height: Self.height) }
    override var intrinsicContentSize: NSSize { fittingSize }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let sliderX = bounds.width - autoWidth - Self.sliderWidth
        label.frame = NSRect(x: 0, y: (bounds.height - 13) / 2,
                             width: max(0, sliderX - Self.textToSlider), height: 13)
        slider.frame = NSRect(x: sliderX, y: 0, width: Self.sliderWidth, height: bounds.height)
        autoButton.frame = NSRect(x: bounds.width - autoButton.pillWidth,
                                  y: (bounds.height - Self.autoHeight) / 2,
                                  width: autoButton.pillWidth, height: Self.autoHeight)
    }

    override func resetCursorRects() { HandCursor.fill(self, when: isUsable) }

    override func scrollWheel(with event: NSEvent) {
        guard isUsable else { return super.scrollWheel(with: event) }
        // A inércia do trackpad continuaria subindo nível depois do dedo sair.
        guard event.momentumPhase.isEmpty else { return }
        if event.phase == .began { scrollAccumulator = 0 }
        let step = event.hasPreciseScrollingDeltas ? Self.preciseStep : 1
        scrollAccumulator += event.scrollingDeltaY
        while abs(scrollAccumulator) >= step {
            let direction = scrollAccumulator > 0 ? 1 : -1
            scrollAccumulator -= CGFloat(direction) * step
            move(to: (selection ?? autoIndex ?? 0) + direction)
        }
    }

    @objc private func sliderMoved() {
        move(to: slider.integerValue)
    }

    /// Desligar parte do nível que o auto já usava: nada muda de fato até você
    /// mexer. Sem saber qual é, o do meio, longe dos dois extremos caros.
    @objc func toggleAuto() {
        choose(isAuto ? autoIndex ?? (levels.count - 1) / 2 : nil)
    }

    private func move(to target: Int) {
        let clamped = min(max(target, 0), levels.count - 1)
        guard clamped != selection else { return }
        choose(clamped)
    }

    private func choose(_ next: Int?) {
        selection = next
        refresh()
        commitTimer?.invalidate()
        commitTimer = Timer.scheduledTimer(withTimeInterval: Self.settleDelay,
                                           repeats: false) { [weak self] _ in self?.settle() }
    }

    private func settle() {
        commitTimer?.invalidate()
        commitTimer = nil
        guard pending else { return }
        // Parado mas ainda segurando o botão: você está decidindo, não decidiu.
        // Reinício no meio do arrasto mataria o slider junto com o card.
        if NSEvent.pressedMouseButtons & 1 != 0 {
            commitTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                self?.settle()
            }
            return
        }
        onCommit?(value)
    }

    private func refresh() {
        let before = label.stringValue
        defer {
            if label.stringValue != before {
                needsLayout = true
                onResize?()
            }
        }
        let shown = selection ?? autoIndex ?? 0
        if slider.integerValue != shown { slider.integerValue = shown }
        guard isUsable else {
            label.stringValue = "sem esforço"
            label.textColor = NSColor(calibratedWhite: 1, alpha: 0.3)
            toolTip = "Este modelo não aceita nível de esforço"
            slider.toolTip = toolTip
            return
        }
        label.stringValue = (value ?? autoLevel ?? "") + (pending ? "…" : "")
        label.textColor = pending ? tint : NSColor(calibratedWhite: isAuto ? 0.45 : 0.62, alpha: 1)
        slider.trackFillColor = isAuto ? NSColor(calibratedWhite: 0.5, alpha: 1) : tint
        slider.alphaValue = isAuto ? 0.5 : 1
        autoButton.paintPill(on: isAuto, tint: tint)
        autoButton.toolTip = isAuto
            ? "Auto ligado: o modelo decide o esforço. Clique para fixar um nível"
            : "Auto desligado: clique para voltar ao padrão do modelo"
        toolTip = isAuto
            ? "Esforço: auto\(autoLevel.map { " (\($0))" } ?? "") — arraste ou role para fixar um nível. "
                + "Trocar reinicia o terminal; a conversa continua"
            : "Esforço: \(value ?? "") — arraste ou role para ajustar. "
                + "Trocar reinicia o terminal; a conversa continua"
        slider.toolTip = toolTip
    }
}

/// Interruptor em forma de pílula: o texto é o rótulo, e ligado ganha o fundo.
extension HandButton {
    static func pill(title: String) -> HandButton {
        let button = HandButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.font = .systemFont(ofSize: 9, weight: .semibold)
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        return button
    }

    var pillWidth: CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: font as Any]).width) + 8
    }

    func paintPill(on: Bool, tint: NSColor, available: Bool = true) {
        isEnabled = available
        let color = !available ? NSColor(calibratedWhite: 1, alpha: 0.25)
            : on ? tint : NSColor(calibratedWhite: 0.62, alpha: 1)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font as Any, .foregroundColor: color
        ])
        layer?.backgroundColor = on && available ? tint.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
    }
}

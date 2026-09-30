import AppKit

/// O esforço do agente no cabeçalho do card: um slider com uma marca por nível
/// — a primeira é o auto, o padrão do modelo — e o nome do nível ao lado. Arrastar, clicar
/// na trilha ou rolar em cima dele ajustam.
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
    /// 0 é o padrão do CLI; daí em diante, `levels[position - 1]`.
    private var position: Int
    private let committed: Int
    private var commitTimer: Timer?
    private var scrollAccumulator: CGFloat = 0

    private let slider = NSSlider()
    private let label = NSTextField(labelWithString: "")

    private static let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
    private static let sliderWidth: CGFloat = 96
    /// Do texto do nível ao slider.
    static let textToSlider: CGFloat = 5
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
        self.position = current.flatMap { levels.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        self.committed = position
        super.init(frame: .zero)

        slider.controlSize = .mini
        slider.minValue = 0
        slider.maxValue = Double(max(levels.count, 1))
        slider.numberOfTickMarks = max(levels.count + 1, 2)
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.trackFillColor = tint
        slider.isContinuous = true
        slider.integerValue = position
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isEnabled = !levels.isEmpty
        addSubview(slider)

        label.font = Self.font
        label.lineBreakMode = .byClipping
        addSubview(label)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { commitTimer?.invalidate() }

    var value: String? { position > 0 && position <= levels.count ? levels[position - 1] : nil }

    private var pending: Bool { position != committed }

    var isUsable: Bool { !levels.isEmpty }

    private var autoText: String { autoLevel.map { "auto (\($0))" } ?? "auto" }

    /// O nível fica à ESQUERDA do slider e ocupa só a largura do texto atual.
    /// Reservar a do nome mais comprido deixava um buraco antes do vizinho; e,
    /// com a faixa alinhada à direita, o texto crescer empurra só o que está à
    /// esquerda dele — o slider não sai de baixo do cursor no meio do arrasto.
    private var textWidth: CGFloat {
        ceil((label.stringValue as NSString).size(withAttributes: [.font: Self.font]).width) + 2
    }

    var preferredWidth: CGFloat { textWidth + Self.textToSlider + Self.sliderWidth }

    override var fittingSize: NSSize { NSSize(width: preferredWidth, height: Self.height) }
    override var intrinsicContentSize: NSSize { fittingSize }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let text = max(0, bounds.width - Self.sliderWidth - Self.textToSlider)
        label.frame = NSRect(x: 0, y: (bounds.height - 13) / 2, width: text, height: 13)
        slider.frame = NSRect(x: bounds.width - Self.sliderWidth, y: 0,
                              width: Self.sliderWidth, height: bounds.height)
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
            move(to: position + direction)
        }
    }

    @objc private func sliderMoved() {
        move(to: slider.integerValue)
    }

    private func move(to target: Int) {
        let clamped = min(max(target, 0), levels.count)
        guard clamped != position else { return }
        position = clamped
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
        if slider.integerValue != position { slider.integerValue = position }
        guard isUsable else {
            label.stringValue = "sem esforço"
            label.textColor = NSColor(calibratedWhite: 1, alpha: 0.3)
            toolTip = "Este modelo não aceita nível de esforço"
            slider.toolTip = toolTip
            return
        }
        label.stringValue = (value ?? autoText) + (pending ? "…" : "")
        label.textColor = pending ? tint : NSColor(calibratedWhite: 0.62, alpha: 1)
        toolTip = "Esforço: \(value ?? autoText) — arraste ou role para ajustar; a primeira "
            + "marca é o auto, o padrão do modelo. Trocar reinicia o terminal; a conversa continua"
        slider.toolTip = toolTip
    }
}

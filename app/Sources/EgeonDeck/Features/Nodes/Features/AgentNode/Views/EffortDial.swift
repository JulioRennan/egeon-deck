import AppKit

/// O esforço do agente no cabeçalho do card: um slider com uma marca por nível
/// — a primeira é o padrão do CLI — e o nome do nível ao lado. Arrastar, clicar
/// na trilha ou rolar em cima dele ajustam.
///
/// A escolha só vale quando a mão para (debounce de 1s, e nunca com o botão
/// ainda apertado): cada troca reinicia o processo, e passar
/// de `low` a `max` nível a nível mataria o CLI quatro vezes no caminho.
/// Enquanto não assenta, o nome aparece com `…`.
final class EffortDial: NSView {
    /// A escolha assentou. Nil é o padrão do CLI.
    var onCommit: ((String?) -> Void)?

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
    private static let sliderToText: CGFloat = 6
    private static let height: CGFloat = 18
    /// Quanto de rolagem vale um nível. Trackpad manda deltas em pontos, aos
    /// punhados; roda de mouse manda linhas, uma por clique.
    private static let preciseStep: CGFloat = 14
    private static let settleDelay: TimeInterval = 1.0

    init(levels: [String], current: String?, tint: NSColor) {
        var levels = levels
        if let current, !current.isEmpty, !levels.contains(current) { levels.append(current) }
        self.levels = levels
        self.tint = tint
        self.position = current.flatMap { levels.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        self.committed = position
        super.init(frame: .zero)

        slider.controlSize = .mini
        slider.minValue = 0
        slider.maxValue = Double(max(levels.count, 1))
        slider.numberOfTickMarks = levels.count + 1
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.trackFillColor = tint
        slider.isContinuous = true
        slider.integerValue = position
        slider.target = self
        slider.action = #selector(sliderMoved)
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

    /// Largura para o nome mais comprido, e não para o atual: mexer no slider
    /// não pode fazer o cabeçalho dançar.
    var preferredWidth: CGFloat {
        let widest = (levels + ["padrão"]).map {
            ($0 + "…" as NSString).size(withAttributes: [.font: Self.font]).width
        }.max() ?? 0
        return ceil(Self.sliderWidth + Self.sliderToText + widest) + 4
    }

    override var fittingSize: NSSize { NSSize(width: preferredWidth, height: Self.height) }
    override var intrinsicContentSize: NSSize { fittingSize }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        slider.frame = NSRect(x: 0, y: 0, width: Self.sliderWidth, height: bounds.height)
        let x = Self.sliderWidth + Self.sliderToText
        label.frame = NSRect(x: x, y: (bounds.height - 13) / 2,
                             width: max(0, bounds.width - x), height: 13)
    }

    override func resetCursorRects() { HandCursor.fill(self) }

    override func scrollWheel(with event: NSEvent) {
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
        if slider.integerValue != position { slider.integerValue = position }
        label.stringValue = (value ?? "padrão") + (pending ? "…" : "")
        label.textColor = pending ? tint : NSColor(calibratedWhite: 0.62, alpha: 1)
        toolTip = "Esforço: \(value ?? "padrão do CLI") — arraste ou role para ajustar. "
            + "Trocar reinicia o terminal; a conversa continua"
        slider.toolTip = toolTip
    }
}

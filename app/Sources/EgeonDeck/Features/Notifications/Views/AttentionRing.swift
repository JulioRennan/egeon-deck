import AppKit

/// A borda da bancada que parou, girando: laranja quando precisa de você,
/// verde quando terminou. Azul na bancada em foco, mas parado: foco é estado
/// que dura, e um giro sem fim nele dava ansiedade e tirava a concentração.
///
/// Movimento em vez de piscar: um traço laranja percorre a borda sem parar,
/// sobre um aro apagado. Piscar liga e desliga a cor inteira, e é o que cansa
/// quando a pergunta fica esperando; o giro chama o olho da mesma forma sem o
/// clarão. Com "reduzir movimento" ligado no sistema, fica só o aro, parado.
/// É camada por cima da view, não desenho dela: o host só liga, desliga e
/// chama `layout()` do seu `layout()`.
final class AttentionRing {
    private weak var host: NSView?
    private let container = CALayer()
    private let base = CAShapeLayer()
    /// O cometa: fatias curtas e encostadas do mesmo caminho, da cauda apagada à
    /// cabeça cheia — o degradê que o gradiente cônico fazia. Com três traços
    /// sobrepostos o rastro virava três listras; em fatias de poucos pontos o
    /// olho lê transição. Traço e não gradiente girando: o cônico gira em
    /// ângulo constante, e num card largo isso é devagar no meio dos lados
    /// compridos e um disparo nas pontas. Pelo perímetro, o passo é o mesmo.
    private let trail: [CAShapeLayer] = (0..<AttentionRing.slices).map { _ in CAShapeLayer() }
    private static let slices = 24

    /// A opacidade da fatia `k`, na curva do cônico: a cauda sobe devagar até
    /// um terço, e o último trecho acende até a cor cheia.
    private static func alpha(ofSlice k: Int) -> CGFloat {
        let f = (CGFloat(k) + 1) / CGFloat(slices)
        return f < 0.6 ? 0.35 * f / 0.6 : 0.35 + 0.65 * (f - 0.6) / 0.4
    }

    private func cometLength() -> CGFloat { min(perimeter * 0.35, 180) }
    private let cornerRadius: CGFloat
    private let lineWidth: CGFloat
    private var perimeter: CGFloat = 0

    /// Uma volta inteira. Devagar o bastante para não parecer alarme, e para
    /// várias girando juntas não disputarem o olho com a bancada em foco.
    static let period: CFTimeInterval = 6
    private static let spin = "egeon.attention.spin"

    enum Tone {
        /// Precisa de você.
        case asking
        /// Terminou.
        case done
        /// A bancada em foco. A cor de destaque do sistema, que aviso nenhum usa.
        case focus

        var color: NSColor {
            switch self {
            case .asking: return .systemOrange
            case .done:   return .systemGreen
            case .focus:  return .controlAccentColor
            }
        }
    }

    /// `nil` apaga. Quem chama decide a prioridade — laranja vence verde.
    var tone: Tone? {
        didSet {
            guard tone != oldValue else { return }
            container.isHidden = tone == nil
            guard let tone else { stop(); return }
            paint(tone)
            // Entre avisos a volta segue de onde estava.
            if tone == .focus { stop() }
            start()
        }
    }

    var isOn: Bool { tone != nil }

    /// O tom de uma bancada: laranja vence verde, porque um pede coisa e o
    /// outro só informa.
    static func tone(for summary: ActivitySummary) -> Tone? {
        if summary.attention > 0 { return .asking }
        return summary.done > 0 ? .done : nil
    }

    init(host: NSView, cornerRadius: CGFloat, lineWidth: CGFloat = 1.5) {
        self.host = host
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        host.wantsLayer = true

        container.isHidden = true
        // Acima dos subviews: o AppKit reordena as camadas deles, o zPosition não.
        container.zPosition = 50

        base.fillColor = nil
        base.lineWidth = lineWidth
        container.addSublayer(base)
        for layer in trail {
            layer.fillColor = nil
            layer.lineWidth = lineWidth + 0.5
            layer.lineCap = .butt
            container.addSublayer(layer)
        }

        host.layer?.addSublayer(container)
    }

    /// Acompanha o tamanho do host. Chamar do `layout()` dele.
    func layout() {
        guard let host else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = host.bounds
        container.frame = bounds
        let inset = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let radius = max(0, min(cornerRadius - lineWidth / 2, min(inset.width, inset.height) / 2))
        let path = CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil)
        base.frame = bounds
        base.path = path
        let length = max(0, 2 * (inset.width + inset.height) - (8 - 2 * .pi) * radius)
        let changed = abs(length - perimeter) > 0.5
        perimeter = length
        // Meio ponto a mais em cada fatia: encostadas exatas, o antisserrilhado
        // deixa um fio escuro entre uma e outra.
        let slice = cometLength() / CGFloat(Self.slices)
        for layer in trail {
            layer.frame = bounds
            layer.path = path
            layer.lineDashPattern = [NSNumber(value: Double(slice + 0.5)),
                                     NSNumber(value: Double(max(0, length - slice - 0.5)))]
        }
        CATransaction.commit()
        // O perímetro mudou: a volta do traço é medida nele, então recomeça.
        if changed, tone != .focus { stop() }
        if tone != nil, !isSpinning { start() }
    }

    private func paint(_ tone: Tone) {
        let color = tone.color
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Parado, o foco é só o aro — então cheio, para se ver de longe.
        base.strokeColor = color.withAlphaComponent(tone == .focus ? 0.85 : 0.28).cgColor
        for (k, layer) in trail.enumerated() {
            layer.strokeColor = color.withAlphaComponent(Self.alpha(ofSlice: k)).cgColor
        }
        CATransaction.commit()
    }

    private var isSpinning: Bool {
        trail[0].animation(forKey: Self.spin) != nil
    }

    private func stop() {
        trail.forEach { $0.removeAnimation(forKey: Self.spin) }
    }

    private func start() {
        guard let tone, perimeter > 0, !isSpinning else { return }
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        trail.forEach { $0.isHidden = still || tone == .focus }
        guard !still, tone != .focus else { return }
        let slice = cometLength() / CGFloat(Self.slices)
        // Mesmo instante de partida para todas: senão o rastro desalinha.
        let begin = CACurrentMediaTime()
        for (k, layer) in trail.enumerated() {
            // Cada fatia começa adiante da anterior pelo tamanho dela.
            let offset = Double(slice * CGFloat(k))
            let spin = CABasicAnimation(keyPath: "lineDashPhase")
            spin.fromValue = -offset
            spin.toValue = -offset - Double(perimeter)
            spin.duration = Self.period
            spin.beginTime = begin
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            // Sem isto a animação some quando a janela sai da frente e volta.
            spin.isRemovedOnCompletion = false
            layer.add(spin, forKey: Self.spin)
        }
    }
}

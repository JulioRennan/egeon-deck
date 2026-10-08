import AppKit

/// A borda da bancada que parou, girando: laranja quando precisa de você,
/// verde quando terminou.
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
    private let sweep = CAGradientLayer()
    private let mask = CAShapeLayer()
    private let cornerRadius: CGFloat
    private let lineWidth: CGFloat

    /// Uma volta inteira. Devagar o bastante para não parecer alarme.
    static let period: CFTimeInterval = 2.4
    private static let spin = "egeon.attention.spin"

    enum Tone {
        /// Precisa de você.
        case asking
        /// Terminou.
        case done

        var color: NSColor { self == .asking ? .systemOrange : .systemGreen }
    }

    /// `nil` apaga. Quem chama decide a prioridade — laranja vence verde.
    var tone: Tone? {
        didSet {
            guard tone != oldValue else { return }
            container.isHidden = tone == nil
            guard let tone else { sweep.removeAnimation(forKey: Self.spin); return }
            paint(tone.color)
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

        // O cometa: transparente, cresce até a cor cheia e corta. Cônico,
        // girando no centro — a máscara deixa ver só o que cai na borda.
        sweep.type = .conic
        sweep.startPoint = CGPoint(x: 0.5, y: 0.5)
        sweep.endPoint = CGPoint(x: 0.5, y: 0)
        sweep.locations = [0, 0.55, 0.8, 0.97, 1]
        mask.fillColor = nil
        mask.strokeColor = NSColor.black.cgColor
        mask.lineWidth = lineWidth + 0.5
        let clip = CALayer()
        clip.mask = mask
        clip.addSublayer(sweep)
        container.addSublayer(clip)

        host.layer?.addSublayer(container)
    }

    /// Acompanha o tamanho do host. Chamar do `layout()` dele.
    func layout() {
        guard let host else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = host.bounds
        container.frame = bounds
        container.sublayers?.forEach { $0.frame = bounds }
        let inset = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let radius = max(0, cornerRadius - lineWidth / 2)
        let path = CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil)
        base.path = path
        mask.path = path
        mask.frame = bounds
        // Quadrado na diagonal, centrado: girando, ele cobre a borda toda em
        // qualquer ângulo.
        let side = hypot(bounds.width, bounds.height)
        sweep.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        sweep.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        if tone != nil, sweep.animation(forKey: Self.spin) == nil { start() }
    }

    private func paint(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.strokeColor = color.withAlphaComponent(0.28).cgColor
        sweep.colors = [color.withAlphaComponent(0).cgColor,
                        color.withAlphaComponent(0).cgColor,
                        color.withAlphaComponent(0.35).cgColor,
                        color.cgColor,
                        color.withAlphaComponent(0).cgColor]
        CATransaction.commit()
    }

    private func start() {
        // Trocar de tom não reinicia a volta: o traço segue de onde estava.
        guard sweep.animation(forKey: Self.spin) == nil else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        // Na view virada do AppKit, positivo é horário — o sentido que o olho
        // espera, e o que põe a ponta clara na frente do rastro.
        spin.toValue = 2 * Double.pi
        spin.duration = Self.period
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        // Sem isto a animação some quando a janela sai da frente e volta.
        spin.isRemovedOnCompletion = false
        sweep.add(spin, forKey: Self.spin)
    }
}

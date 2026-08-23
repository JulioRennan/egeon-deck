import AppKit

/// Vidro das barras flutuantes.
///
/// Um interruptor de ambiente, e não só `#available`: vidro reamostra o que está
/// atrás a cada quadro, e estas barras ficam por cima de terminal que redesenha
/// oito vezes por segundo com cinco agentes trabalhando. `EGEON_GLASS=0` volta
/// tudo para o fundo semiopaco sem precisar de rebuild.
enum Glass {
    static let enabled: Bool = {
        if ProcessInfo.processInfo.environment["EGEON_GLASS"] == "0" { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }()
}

/// Barra flutuante: vidro por baixo, `content` por cima.
///
/// O conteúdo entra como `contentView` do `NSGlassEffectView`, e nunca por
/// `addSubview`: o header da AppKit é explícito em que só o `contentView` tem
/// z-order garantido dentro do efeito — subview solta pode acabar ATRÁS do
/// vidro, e o sintoma é uma barra que some sem erro nenhum.
final class GlassPanel: NSView {
    let content: NSView
    private let radius: CGFloat
    /// O `NSGlassEffectView`, quando existe. Guardado como `NSView` porque
    /// propriedade armazenada não aceita anotação de disponibilidade.
    private var glass: NSView?

    init(content: NSView, radius: CGFloat = 14, tint: NSColor? = nil) {
        self.content = content
        self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true

        if #available(macOS 26.0, *), Glass.enabled {
            let effect = NSGlassEffectView()
            effect.cornerRadius = radius
            effect.tintColor = tint
            effect.contentView = content
            addSubview(effect)
            glass = effect
        } else {
            layer?.cornerRadius = radius
            layer?.backgroundColor = (tint ?? NSColor(calibratedWhite: 0.13, alpha: 1))
                .withAlphaComponent(0.95).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
            addSubview(content)
        }

        // Sombra dá o descolamento que a barra precisa para não parecer mais um
        // nó pousado no grid. Com `shadowPath` explícito porque o vidro desenha
        // em camada própria: sem ele o AppKit tira a sombra do canal alfa desta
        // camada, que está vazio, e não sai sombra nenhuma.
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -3)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        if let glass {
            glass.frame = bounds
        } else {
            content.frame = bounds
        }
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius,
                                   cornerHeight: radius, transform: nil)
    }
}

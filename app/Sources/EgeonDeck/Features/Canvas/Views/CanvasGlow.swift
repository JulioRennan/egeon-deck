import AppKit

/// A sombra da cor da bancada por dentro da borda do canvas (ADR-086).
///
/// Sombra e não fundo tingido: o meio do canvas, onde estão os terminais, fica
/// como sempre foi, e a cor só se nota de canto de olho — que é onde ela tem
/// de agir, antes de você ler qualquer nome.
final class CanvasGlow: NSView {
    /// Uma moldura grossa FORA da vista projeta a sombra para dentro; o
    /// `masksToBounds` corta a moldura e deixa só o esmaecido.
    private let frameLayer = CAShapeLayer()

    var color: NSColor? {
        didSet {
            frameLayer.isHidden = color == nil
            frameLayer.fillColor = color?.cgColor
            frameLayer.shadowColor = color?.cgColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        frameLayer.fillRule = .evenOdd
        frameLayer.shadowOffset = .zero
        frameLayer.shadowRadius = 28
        frameLayer.shadowOpacity = 0.55
        frameLayer.isHidden = true
        layer?.addSublayer(frameLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Só enfeite: o clique passa para o canvas e os nós por baixo.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameLayer.frame = bounds
        let path = CGMutablePath()
        path.addRect(bounds.insetBy(dx: -80, dy: -80))
        // O retângulo de dentro no sentido contrário: o `shadowPath` é
        // preenchido pela regra não-zero, e no mesmo sentido a sombra cobriria
        // o canvas inteiro.
        path.addLines(between: [NSPoint(x: bounds.minX, y: bounds.minY),
                                NSPoint(x: bounds.minX, y: bounds.maxY),
                                NSPoint(x: bounds.maxX, y: bounds.maxY),
                                NSPoint(x: bounds.maxX, y: bounds.minY)])
        path.closeSubpath()
        frameLayer.path = path
        frameLayer.shadowPath = path
        CATransaction.commit()
    }
}

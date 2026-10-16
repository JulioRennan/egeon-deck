import AppKit

/// A bancada travada porque o macOS não deixa ler a pasta dela.
///
/// Trava de verdade, como a `BusyOverlay`: sem leitura da pasta nenhum agente
/// sobe, e mexer nos cards por baixo só produziria terminal morto. Sai sozinha
/// quando o acesso volta — quem confere é o dono, de tempos em tempos.
final class AccessOverlay: NSView {
    var onOpenSettings: (() -> Void)?
    var onAskAgain: (() -> Void)?

    private let title = NSTextField(labelWithString: "Sem acesso à pasta")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let box = NSView()
    private lazy var panel = GlassPanel(content: box, radius: 14)
    private lazy var settings = HandButton(title: "Abrir Ajustes", target: self, action: #selector(openSettings))
    private lazy var again = HandButton(title: "Pedir de novo", target: self, action: #selector(askAgain))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.7).cgColor

        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .white
        message.font = .systemFont(ofSize: 13)
        message.textColor = NSColor(calibratedWhite: 1, alpha: 0.8)
        settings.bezelStyle = .rounded
        settings.keyEquivalent = "\r"
        again.bezelStyle = .rounded
        [title, message, settings, again].forEach(box.addSubview)
        addSubview(panel)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// `asking`: o pedido do macOS está na tela, esperando você.
    func show(_ text: String, asking: Bool = false) {
        message.stringValue = asking ? "O macOS está perguntando — responda o aviso dele." : text
        again.isEnabled = !asking
        isHidden = false
        needsLayout = true
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func askAgain() { onAskAgain?() }

    override func layout() {
        super.layout()
        let width = min(460, bounds.width - 40)
        let pad: CGFloat = 22
        let textHeight = message.sizeThatFits(NSSize(width: width - 2 * pad, height: 400)).height
        let height = pad + 20 + 10 + textHeight + 18 + 28 + pad
        panel.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                             width: width, height: height)
        box.frame = NSRect(origin: .zero, size: panel.frame.size)
        // O `box` não é virado: a conta vai de cima para baixo à mão.
        title.frame = NSRect(x: pad, y: height - pad - 20, width: width - 2 * pad, height: 20)
        message.frame = NSRect(x: pad, y: title.frame.minY - 10 - textHeight,
                               width: width - 2 * pad, height: textHeight)
        let buttonWidth: CGFloat = 130
        settings.frame = NSRect(x: width - pad - buttonWidth, y: pad, width: buttonWidth, height: 28)
        again.frame = NSRect(x: settings.frame.minX - 10 - buttonWidth, y: pad, width: buttonWidth, height: 28)
    }

    /// Engole o clique fora do painel: a bancada por baixo está travada.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : (super.hitTest(point) ?? self)
    }
}

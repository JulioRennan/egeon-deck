import AppKit

// MARK: - "Um instante"

/// A cortina de um passo que demora e não pode ser interrompido no meio —
/// hoje só a limpeza da bancada (ADR-059).
///
/// Cobre o conteúdo do shell inteiro, e não é só enfeite: enquanto a limpeza
/// espera os agentes assentarem para arquivar, clicar em nó ou mandar mensagem
/// escreveria na conversa que está saindo. A view opaca ao `hitTest` é o que
/// segura isso — nenhum container abaixo precisa saber que existe limpeza.
final class BusyOverlay: NSView {
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private lazy var panel = GlassPanel(content: box, radius: 12)
    private let box = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.55).cgColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        box.addSubview(spinner)

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        box.addSubview(label)

        addSubview(panel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ text: String) {
        label.stringValue = text
        isHidden = false
        spinner.startAnimation(nil)
        needsLayout = true
    }

    func hide() {
        spinner.stopAnimation(nil)
        isHidden = true
    }

    override func layout() {
        super.layout()
        let width = min(max(label.intrinsicContentSize.width + 76, 220), bounds.width - 40)
        panel.frame = NSRect(x: (bounds.width - width) / 2, y: bounds.midY - 24,
                             width: width, height: 48)
        box.frame = NSRect(origin: .zero, size: panel.frame.size)
        spinner.frame = NSRect(x: 18, y: 16, width: 16, height: 16)
        label.frame = NSRect(x: 46, y: 15, width: box.bounds.width - 60, height: 18)
    }

    /// Engole o clique — inclusive o que cairia fora do painel, no escuro.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : (super.hitTest(point) ?? self)
    }
}

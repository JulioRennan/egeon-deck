import AppKit

/// Ícone clicável da barra. É uma view crua em vez de NSButton porque o estado
/// selecionado precisa de um fundo próprio, e domar o desenho do NSButton para
/// isso dá mais trabalho do que desenhar.
final class ToolbarButton: NSView {
    var onClick: (() -> Void)?
    /// Segurar o botão. Usado para oferecer variantes sem cobrar um clique extra
    /// de quem só quer o comportamento padrão.
    var onLongPress: (() -> Void)?

    var isSelected = false { didSet { restyle() } }

    private let icon = NSImageView()
    private var hovering = false { didSet { restyle() } }
    private var trackingArea: NSTrackingArea?

    init(symbols: [String], tooltip: String, size: CGFloat = 32) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = size < 24 ? 5 : 8

        icon.image = Self.symbol(symbols)
        icon.imageScaling = .scaleProportionallyUpOrDown
        // Proporcional ao botão: com valores fixos, um botão de 18pt sairia com
        // um ícone de 4pt.
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size * 0.44, weight: .medium)
        addSubview(icon)

        toolTip = tooltip
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        icon.frame = bounds.insetBy(dx: bounds.width * 0.22, dy: bounds.height * 0.22)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() { HandCursor.fill(self) }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard onLongPress != nil else { onClick?(); return }

        // Soltou dentro de 0.35s é clique; passou disso é pressão. Decidido aqui
        // e não no `mouseUp`, que pode nunca chegar — o menu abre e captura o
        // evento antes.
        let releasedInTime = window?.nextEvent(matching: [.leftMouseUp],
                                               until: Date().addingTimeInterval(0.35),
                                               inMode: .eventTracking,
                                               dequeue: true) != nil
        if releasedInTime { onClick?() } else { onLongPress?() }
    }

    /// Botão direito também abre as variantes: é o gesto que a maioria tenta antes
    /// de descobrir a pressão longa.
    override func rightMouseDown(with event: NSEvent) {
        guard onLongPress != nil else { super.rightMouseDown(with: event); return }
        onLongPress?()
    }

    private func restyle() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            icon.contentTintColor = .controlAccentColor
        } else {
            layer?.backgroundColor = hovering
                ? NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
                : NSColor.clear.cgColor
            icon.contentTintColor = NSColor(calibratedWhite: 1, alpha: hovering ? 0.95 : 0.72)
        }
    }

    /// Troca o ícone. Serve a botão que é um interruptor e diz na cara qual é o
    /// próximo estado — recolher ou abrir.
    func setSymbols(_ names: [String], tooltip: String) {
        icon.image = Self.symbol(names)
        self.toolTip = tooltip
    }

    /// Primeiro nome que existe nesta versão do SF Symbols. Usado também pela
    /// barra superior, que tem os mesmos candidatos a resolver.
    static func symbol(_ names: [String]) -> NSImage? {
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                return image
            }
        }
        return nil
    }
}

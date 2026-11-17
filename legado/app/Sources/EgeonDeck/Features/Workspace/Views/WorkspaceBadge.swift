import AppKit

/// A pastilha do workspace: a imagem escolhida ou, sem ela, a inicial — o
/// mesmo esquema que a bancada já usava no trilho recolhido.
final class WorkspaceBadge: NSView {
    private let image = NSImageView()
    private let letter = NSTextField(labelWithString: "")

    var isSelected = false { didSet { restyle() } }
    /// Aro laranja: alguma bancada lá dentro te espera.
    var wantsAttention = false { didSet { restyle() } }

    init(side: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        wantsLayer = true
        layer?.cornerRadius = (side * 0.27).rounded()
        layer?.masksToBounds = true

        image.imageScaling = .scaleProportionallyUpOrDown
        image.isHidden = true
        addSubview(image)

        letter.font = .systemFont(ofSize: (side * 0.5).rounded(), weight: .semibold)
        letter.alignment = .center
        addSubview(letter)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ workspace: WorkspaceConfig) {
        letter.stringValue = workspace.initial
        if let url = WorkspaceStore.iconURL(of: workspace), let img = NSImage(contentsOf: url) {
            image.image = img
            image.isHidden = false
            letter.isHidden = true
        } else {
            image.image = nil
            image.isHidden = true
            letter.isHidden = false
        }
        restyle()
    }

    /// Prévia de uma imagem ainda não instalada (o formulário).
    func preview(_ img: NSImage?, initial: String) {
        letter.stringValue = initial
        image.image = img
        image.isHidden = img == nil
        letter.isHidden = img != nil
        restyle()
    }

    override func layout() {
        super.layout()
        image.frame = bounds
        letter.frame = NSRect(x: 0, y: ((bounds.height - letter.font!.pointSize * 1.25) / 2).rounded(),
                              width: bounds.width, height: letter.font!.pointSize * 1.25)
    }

    private func restyle() {
        let hasImage = !image.isHidden
        layer?.backgroundColor = hasImage
            ? NSColor.clear.cgColor
            : (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.85)
                          : NSColor(calibratedWhite: 1, alpha: 0.10)).cgColor
        layer?.borderWidth = wantsAttention ? 2 : 0
        layer?.borderColor = NSColor.systemOrange.cgColor
        letter.textColor = isSelected ? .white : NSColor(calibratedWhite: 1, alpha: 0.75)
    }
}

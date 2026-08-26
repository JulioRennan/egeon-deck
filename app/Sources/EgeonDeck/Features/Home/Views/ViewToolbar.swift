import AppKit

/// Botão da barra superior: ícone e nome do modo.
///
/// Com texto, e não só ícone como na barra do canvas: são dois estados
/// mutuamente exclusivos e é o rótulo que diz em qual você está sem passar o
/// mouse por cima.
final class ModeButton: NSView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { restyle() } }

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hovering = false { didSet { restyle() } }
    private var trackingArea: NSTrackingArea?

    init(mode: ViewMode) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7

        icon.image = ToolbarButton.symbol(mode.symbols)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        addSubview(icon)

        label.stringValue = mode.label
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        addSubview(label)

        toolTip = mode.tooltip
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    static let height: CGFloat = 28

    override var fittingSize: NSSize {
        NSSize(width: 22 + 16 + 6 + label.intrinsicContentSize.width, height: Self.height)
    }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 11, y: (bounds.height - 15) / 2, width: 16, height: 15)
        label.frame = NSRect(x: 33, y: (bounds.height - 15) / 2,
                             width: max(0, bounds.width - 39), height: 15)
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

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    /// Selecionado é preenchimento CHEIO, e não texto colorido: dentro da pílula os
    /// dois botões dividem o mesmo fundo, e só a cor da letra deixava "em qual eu
    /// estou" a cargo de comparar dois tons de cinza.
    private func restyle() {
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
            icon.contentTintColor = .white
            label.textColor = .white
        } else {
            layer?.backgroundColor = hovering
                ? NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
                : NSColor.clear.cgColor
            let alpha: CGFloat = hovering ? 0.95 : 0.6
            icon.contentTintColor = NSColor(calibratedWhite: 1, alpha: alpha)
            label.textColor = NSColor(calibratedWhite: 1, alpha: alpha)
        }
    }
}

/// Barra superior: de que jeito você está olhando a bancada.
///
/// Separada da barra do canvas — que é flutuante, mora no rodapé e trata do que
/// você está FAZENDO: ferramenta armada, zoom, template. Esta trata de onde os
/// nós aparecem, e por isso é a única que continua na tela em todos os modos.
final class ViewToolbar: NSView {
    static let height: CGFloat = 46

    var onSelect: ((ViewMode) -> Void)?

    /// Onde o título começa. A barra corre de borda a borda em todo modo e, com
    /// `fullSizeContentView`, os botões da janela ficam sempre em cima dela — o
    /// título nasce depois deles.
    private static let titleInset: CGFloat = 82

    private var buttons: [ViewMode: ModeButton] = [:]
    /// Fundo da dupla de modos. Um trilho atrás dos dois, como abas: sem ele os
    /// botões flutuam no meio da barra e não se leem como um par de estados
    /// mutuamente exclusivos.
    private let pill = NSView()
    private let hint = NSTextField(labelWithString: "")
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 1).cgColor

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 9
        pill.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.06).cgColor
        addSubview(pill)

        for mode in ViewMode.all {
            let button = ModeButton(mode: mode)
            button.onClick = { [weak self] in self?.onSelect?(mode) }
            pill.addSubview(button)
            buttons[mode] = button
        }

        // Qual bancada está na tela. Repetido da barra lateral de propósito: lá é
        // uma lista e o que diz a ativa é um realce; aqui é afirmação.
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)

        subtitle.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        subtitle.textColor = NSColor(calibratedWhite: 1, alpha: 0.4)
        subtitle.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitle)

        hint.font = .systemFont(ofSize: 10)
        hint.textColor = NSColor(calibratedWhite: 1, alpha: 0.35)
        hint.alignment = .right
        hint.lineBreakMode = .byTruncatingTail
        addSubview(hint)
    }

    /// Que bancada a barra está anunciando.
    func setWorkbench(name: String, path: String) {
        title.stringValue = name
        subtitle.stringValue = path
        needsLayout = true
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init() { self.init(frame: .zero) }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let margem: CGFloat = 16
        let padding: CGFloat = 3

        // A pílula primeiro: ela manda no centro, e os dois lados se acomodam ao
        // que sobrar. Centrada na JANELA e não no espaço livre — se dependesse do
        // texto da esquerda, ela andaria a cada troca de bancada.
        var largura = padding
        for mode in ViewMode.all {
            largura += (buttons[mode]?.fittingSize.width ?? 0) + padding
        }
        let altura = ModeButton.height + padding * 2
        pill.frame = NSRect(x: ((bounds.width - largura) / 2).rounded(),
                            y: ((bounds.height - altura) / 2).rounded(),
                            width: largura, height: altura)

        var x = padding
        for mode in ViewMode.all {
            guard let button = buttons[mode] else { continue }
            let width = button.fittingSize.width
            button.frame = NSRect(x: x, y: padding, width: width, height: ModeButton.height)
            x += width + padding
        }

        let esquerda = max(0, pill.frame.minX - Self.titleInset - margem)
        title.frame = NSRect(x: Self.titleInset, y: 8, width: esquerda, height: 16)
        subtitle.frame = NSRect(x: Self.titleInset, y: 25, width: esquerda, height: 13)

        let direita = max(0, bounds.width - pill.frame.maxX - margem * 2)
        hint.frame = NSRect(x: pill.frame.maxX + margem, y: (bounds.height - 13) / 2,
                            width: direita, height: 13)

        // O caminho é truncado no meio e a dica é a única forma de ler inteiro.
        // Vive numa região da barra porque o campo saiu do hit test.
        removeAllToolTips()
        if !subtitle.stringValue.isEmpty {
            addToolTip(subtitle.frame, owner: subtitle.stringValue as NSString, userData: nil)
        }
    }

    // MARK: A barra faz o que a titlebar faria

    /// A janela é `fullSizeContentView`, então esta view cobre a faixa da barra de
    /// título e come os cliques que iriam para ela. Quem trata o arrasto e o duplo
    /// clique ali é a titlebar; sem isto, a faixa do topo do app é a única do
    /// sistema onde arrastar não move e duplo clique não maximiza.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else {
            // `performDrag` roda o laço de arrasto do próprio AppKit — com snap às
            // bordas e a outros monitores, que um `setFrameOrigin` à mão não tem.
            window?.performDrag(with: event)
            return
        }
        // A ação é escolha do usuário em Ajustes › Área de Trabalho e Dock, e o
        // padrão de fábrica (chave ausente) é maximizar.
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window?.performMiniaturize(nil)
        case "None":     break
        default:         window?.performZoom(nil)
        }
    }

    /// Rótulo é texto, não botão: sobre o nome e o caminho da bancada o clique tem
    /// de continuar sendo clique na barra. `NSTextField` é `NSControl` e responde
    /// ao hit test mesmo sem ser editável nem selecionável.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let alvo = super.hitTest(point)
        if alvo === title || alvo === subtitle || alvo === hint { return self }
        return alvo
    }

    /// Fio embaixo em vez de sombra: a barra é fixa e encostada no conteúdo, e
    /// sombra aqui pousaria em cima do primeiro card.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedWhite: 1, alpha: 0.09).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    func select(_ mode: ViewMode) {
        for (key, button) in buttons { button.isSelected = (key == mode) }
        switch mode {
        case .mosaic: hint.stringValue = "as posições do canvas ficam guardadas"
        case .chat:   hint.stringValue = "os terminais continuam rodando"
        case .canvas: hint.stringValue = ""
        }
    }
}

import AppKit


/// Raiz: a barra de bancadas à esquerda e o conteúdo à direita — flutuando por cima
/// dele no canvas, e ao LADO dele no mosaico.
///
/// A diferença é o que cada modo promete. O canvas é uma bancada com sobra de
/// espaço, e ali a barra por cima do grid é o efeito desejado. O mosaico divide a
/// janela inteira entre os cards, e sobreposição ali significa terminal coberto —
/// então ele cede a largura que a barra estiver ocupando.
final class RootView: NSView {
    /// Margem do vidro até a borda da janela.
    private static let margin: CGFloat = 10
    /// Onde a barra começa: logo abaixo da barra de visualização, que agora corre
    /// de borda a borda e é ela que carrega os botões da janela por baixo. Encostar
    /// nela punha 2pt de vidro em cima do fio de baixo da barra.
    private static let top: CGFloat = ViewToolbar.height + 8
    /// Folga entre a barra e o conteúdo.
    private static let gap: CGFloat = 8

    let sidebar: Sidebar
    private let sidebarPanel: GlassPanel
    private var content: NSView?

    /// A bancada na tela está em mosaico. Só muda o LAYOUT: ao lado em vez de por
    /// cima. Não mexe em recolher.
    private var isMosaic = false
    /// Recolhida ao trilho. Quem muda isso é você — ⌘/ ou o botão da barra — e
    /// nada mais: nem o modo, nem o mouse passando por cima.
    private(set) var isCollapsed = false

    init(sidebar: Sidebar) {
        self.sidebar = sidebar
        self.sidebarPanel = GlassPanel(content: sidebar, radius: 16)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1).cgColor
        addSubview(sidebarPanel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var sidebarWidth: CGFloat {
        isCollapsed ? Sidebar.railWidth : Sidebar.expandedWidth
    }

    var contentFrame: NSRect {
        // No canvas o conteúdo vai até a BORDA: o grid corre por baixo da barra, e
        // é isso que faz a barra parecer flutuando. Reservar uma faixa aqui pintava
        // ela com o fundo desta view — cinza neutro 0.09, mais claro que o azulado
        // do canvas —, e o resultado era uma moldura cinza em volta do vidro, com
        // cara de resto da barra antiga.
        //
        // No mosaico cede a largura de verdade, e ali a faixa não aparece porque o
        // fundo do shell é o mesmo 0.09.
        let left = isMosaic ? Self.margin + sidebarWidth + Self.gap : 0
        return NSRect(x: left, y: 0,
                      width: max(0, bounds.width - left), height: bounds.height)
    }

    func show(_ view: NSView) {
        guard content !== view else { return }
        content?.removeFromSuperview()
        view.frame = contentFrame
        // Abaixo da barra: `addSubview` puro empilharia a bancada nova em cima do
        // vidro, e a barra sumiria na primeira troca de bancada.
        addSubview(view, positioned: .below, relativeTo: sidebarPanel)
        content = view
    }

    // MARK: Recolher

    /// Fora do canvas a barra fica ao lado do conteúdo; no canvas, por cima do grid.
    ///
    /// Só o canvas tem folga: o grid corre até a borda e por baixo do vidro, e é isso
    /// que faz a barra parecer flutuando. Mosaico e chat dividem a janela inteira com
    /// conteúdo opaco, e sobreposição ali é terminal — ou mensagem — coberta.
    ///
    /// Chamado por quem troca de modo e por quem troca de bancada.
    func setMosaic(_ on: Bool) {
        guard isMosaic != on else { return }
        isMosaic = on
        relayout()
    }

    /// ⌘/ e o botão da barra.
    func toggleCollapsed() { setCollapsed(!isCollapsed) }

    func setCollapsed(_ state: Bool) {
        guard state != isCollapsed else { return }
        isCollapsed = state
        sidebar.isCompact = state
        relayout()
    }

    private func relayout() {
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        sidebarPanel.frame = NSRect(x: Self.margin, y: Self.top, width: sidebarWidth,
                                    height: max(0, bounds.height - Self.top - Self.margin))
        content?.frame = contentFrame
    }
}

import AppKit


/// Raiz: a barra de bancadas à esquerda e o conteúdo à direita — flutuando por cima
/// dele no canvas, e ao LADO dele no mosaico.
///
/// A diferença é o que cada modo promete. O canvas é uma bancada com sobra de
/// espaço, e ali a barra por cima do grid é o efeito desejado. O mosaico divide a
/// janela inteira entre os cards, e sobreposição ali significa terminal coberto —
/// então ele cede a largura que a barra estiver ocupando.
///
/// A bancada em si ocupa a janela inteira em todo modo; quem cede é só o
/// conteúdo dela, via `WorkbenchShell.contentInset`. Assim a barra de cima é a
/// mesma nos três modos e cobre a faixa da titlebar de ponta a ponta.
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

    /// Quanto da borda esquerda do conteúdo a barra lateral cobre AGORA. No
    /// canvas ela flutua por cima do grid, então enquadrar nós tem de descontar
    /// isto — e lido na hora, porque recolher a barra muda o número.
    var floatingSidebarInset: CGFloat {
        isMosaic ? 0 : Self.margin + sidebarWidth + Self.gap
    }

    var contentFrame: NSRect { bounds }

    /// Quanto o conteúdo da bancada cede à barra lateral. No canvas nada: o grid
    /// corre por baixo do vidro, e é isso que faz a barra parecer flutuando. No
    /// mosaico e no chat cede a largura de verdade — e a faixa que sobra não
    /// aparece porque o fundo do shell é o mesmo 0.09 desta view.
    var contentInset: CGFloat {
        isMosaic ? Self.margin + sidebarWidth + Self.gap : 0
    }

    /// Quanto a bancada cede à barra lateral.
    ///
    /// Aplicado aqui e no `show`, e não só no `layout`: trocar de bancada não
    /// marca a raiz para layout, e a bancada nova entrava com recuo zero — a
    /// faixa de abas nascia por baixo do vidro da barra, invisível e sem
    /// clique.
    private func applyInsets(to view: NSView?) {
        guard let shell = view as? WorkbenchShell else { return }
        shell.contentInset = contentInset
        // A faixa cede SEMPRE, inclusive no canvas, onde o conteúdo corre por
        // baixo do vidro de propósito (ADR-025).
        shell.tabsInset = Self.margin + sidebarWidth + Self.gap
    }

    func show(_ view: NSView) {
        guard content !== view else { return }
        content?.removeFromSuperview()
        applyInsets(to: view)
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
    /// que faz a barra parecer flutuando. O mosaico divide a janela inteira com
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
        applyInsets(to: content)
    }
}

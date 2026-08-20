import AppKit

/// A caixa de escrever do modo Chat.
///
/// Duas coisas ela resolve que o terminal não resolve: **para quem** vai, escolhido
/// sem tirar a mão do teclado, e **quem mais existe**, oferecido enquanto você
/// escreve. No canvas isso é implícito — você clica no card e digita nele. Aqui há
/// um campo e cinco agentes, então o destinatário tem de estar na tela.
///
/// É uma superfície só, de vidro, como as barras flutuantes do app: destinatário em
/// cima, texto no meio, botão à direita. E **cresce com o que você escreve**, até um
/// teto, depois do qual rola por dentro — é a convenção de caixa de mensagem, e sem
/// ela um prompt de dez linhas se escreve às cegas numa fresta de 44pt.
final class ChatComposer: NSView {
    /// Ids de destino possíveis, na ordem em que o Tab cicla. `todos` no fim.
    var candidates: [String] = [] {
        didSet {
            guard candidates != oldValue else { return }
            // Enquanto você não escolheu, o padrão é RE-derivado a cada mudança da
            // lista, e não fixado na primeira. Fixado, ele grudava no shell: os
            // alvos entram no Dispatcher na ordem em que os nós sobem, e na primeira
            // leitura só o terminal comum estava registrado — a caixa abria dizendo
            // "escreva pra t1" numa bancada de três agentes, e nunca se corrigia.
            if !chosen || !candidates.contains(target) { target = candidates.first ?? "" }
            restyle()
        }
    }

    /// Você já disse com quem quer falar — por Tab ou clicando no painel. A partir
    /// daí a escolha é sua e a lista não a desfaz.
    private var chosen = false

    private(set) var target: String = "" { didSet { restyle() } }

    /// Texto pronto para entregar, e para quem.
    var onSend: ((_ text: String, _ target: String) -> Void)?

    /// Rótulo de estado de cada candidato, para a lista de menção. Vem de fora
    /// porque quem sabe o estado é o Dispatcher.
    var statusOf: ((String) -> String)?

    /// A caixa mudou de altura — cresceu com uma linha nova, ou a lista de menção
    /// abriu. Quem dá o frame precisa refazer a conta.
    var onHeightChanged: (() -> Void)?

    /// Quanto a caixa pode ocupar, no total, imposto por quem dá o frame.
    ///
    /// O teto de oito linhas sozinho não basta: em janela baixa ele engole o
    /// histórico, e quem cede área é justamente quem você está lendo. Então o
    /// container passa a sobra dele e o menor dos dois manda.
    var ceiling: CGFloat = .greatestFiniteMagnitude

    // MARK: Peças

    /// O que mora dentro do vidro. Separado porque `NSGlassEffectView` só garante
    /// z-order do `contentView` — subview solta pode acabar ATRÁS do vidro.
    private let surface = FlippedView()
    private lazy var glass = GlassPanel(content: surface, radius: 12)

    private let toLabel = ChatStyle.label("para:", font: ChatStyle.meta, color: ChatStyle.dim)
    private let dot = NSView()
    private let name = ChatStyle.label("", font: ChatStyle.name, color: ChatStyle.text)
    private let hint = ChatStyle.label("⇥ troca o destinatário  ·  @ menciona  ·  ⏎ envia",
                                       font: ChatStyle.meta, color: ChatStyle.faint)
    /// O texto rola por dentro depois do teto. Sem scroll de verdade, texto além do
    /// teto fica escrito num lugar que não existe na tela.
    private let scroll = NSScrollView()
    private let input = ComposerTextView()
    private let placeholder = ChatStyle.label("", font: ChatStyle.body, color: ChatStyle.faint)
    private let sendButton = NSButton()
    private let mentions = MentionList()

    // MARK: Medidas

    /// Recuo do conteúdo dentro do vidro.
    private static let pad: CGFloat = 12
    /// A linha do destinatário.
    private static let headerHeight: CGFloat = 15
    /// Altura de uma linha na fonte do corpo, medida.
    ///
    /// Medida e não chutada porque é ela que define o teto, e teto que não cai em
    /// fronteira de linha corta a última no meio — a nona linha aparecia partida na
    /// borda da caixa.
    private static let lineHeight: CGFloat = ChatStyle.height("Ag", font: ChatStyle.body,
                                                              width: 9999)
    /// Uma linha de texto. É o piso absoluto, para janela baixa.
    private static var oneLine: CGFloat { lineHeight }
    /// O que a caixa mostra vazia. Duas linhas e não uma: a caixa de mensagem é o
    /// lugar onde se escreve um prompt, e uma fresta de uma linha faz ela parecer
    /// campo de busca.
    private static var minText: CGFloat { lineHeight * 2 }
    /// Teto do texto: daí para cima rola por dentro. Seis linhas cobre um prompt
    /// escrito à mão; mais que isso é arquivo, não mensagem.
    private static var maxText: CGFloat { lineHeight * 6 }
    /// Largura do botão de enviar, mais o vão até o texto.
    private static let sendLane: CGFloat = 38
    /// Margem entre a lista de menção e o vidro.
    private static let mentionGap: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        surface.addSubview(toLabel)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        surface.addSubview(dot)
        surface.addSubview(name)
        hint.alignment = .right
        surface.addSubview(hint)

        // A moldura do campo é sutil de propósito: o vidro já é a superfície, e uma
        // segunda borda forte dentro dele viraria caixa dentro de caixa.
        scroll.drawsBackground = false
        // Com `autohides`, a barra aparece só depois do teto — antes dela a caixa
        // cresce, e é o crescimento que diz que há espaço. As duas juntas cobrem os
        // dois casos sem barra permanente numa caixa de uma linha.
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        // Sobreposta: barra que ocupa largura reflui o texto quando aparece, e a
        // linha que você está escrevendo salta no meio da digitação.
        scroll.scrollerStyle = .overlay
        scroll.documentView = input
        surface.addSubview(scroll)

        input.font = ChatStyle.body
        input.textColor = ChatStyle.text
        input.drawsBackground = false
        input.isRichText = false
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.insertionPointColor = ChatStyle.text
        input.textContainerInset = NSSize(width: 0, height: 1)
        // O arranjo canônico de campo que cresce: o container acompanha a largura da
        // view e é infinito na altura, e a view cresce na vertical dentro do scroll.
        input.minSize = NSSize(width: 0, height: Self.minText)
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.containerSize = NSSize(width: 0,
                                                    height: CGFloat.greatestFiniteMagnitude)
        input.onSubmit = { [weak self] in self?.send() }
        input.onCycle = { [weak self] backwards in self?.cycle(backwards) }
        input.onTextChange = { [weak self] in self?.textChanged() }
        input.onMentionKey = { [weak self] key in self?.mentions.handle(key) ?? false }

        placeholder.textColor = ChatStyle.faint
        surface.addSubview(placeholder)

        sendButton.image = NSImage(systemSymbolName: "arrow.up",
                                   accessibilityDescription: "enviar")
        sendButton.bezelStyle = .circular
        sendButton.target = self
        sendButton.action = #selector(sendClicked)
        surface.addSubview(sendButton)

        addSubview(glass)

        mentions.isHidden = true
        mentions.onPick = { [weak self] id in self?.insertMention(id) }
        mentions.onResize = { [weak self] in self?.onHeightChanged?() }
        addSubview(mentions)
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func focus() { window?.makeFirstResponder(input) }

    /// O teclado está na caixa agora.
    var hasKeyboard: Bool { window?.firstResponder === input }

    /// Tecla que chegou em outra view do chat. Traz o foco e entrega a tecla, em vez
    /// de deixar o beep: quem digitou queria escrever na caixa.
    func take(_ event: NSEvent) {
        focus()
        input.keyDown(with: event)
    }

    /// Clique em QUALQUER lugar da caixa põe o teclado no texto.
    ///
    /// O recuo, a linha do destinatário e a faixa do botão são `NSView` comum, que
    /// não aceita foco: clicar ali não devolvia o teclado, e quem tinha roubado
    /// continuava com ele. Daí o "clico no chat e não consigo digitar" — o clique
    /// acertava a caixa e o teclado seguia num terminal coberto pelo chat.
    override func mouseDown(with event: NSEvent) {
        focus()
        super.mouseDown(with: event)
    }

    /// Escreve na caixa sem enviar, como se você tivesse digitado.
    ///
    /// É a mesma história do `/mosaic?swap=` e do `/edge?direction=`: o que só existe
    /// por tecla não é verificável de fora, porque evento sintético exige
    /// Acessibilidade e a assinatura ad-hoc a perde a cada build (ADR-003). Sem isto
    /// não há como conferir que a caixa cresce para cima, que ela para no teto, e que
    /// quem cede área é o histórico.
    func setText(_ text: String) {
        input.string = text
        // Cursor no fim e a vista atrás dele, que é onde digitar deixaria os dois. Sem
        // isto a caixa cheia mostra o COMEÇO do texto, e o retrato mentiria sobre o
        // que você veria escrevendo.
        let end = NSRange(location: (input.string as NSString).length, length: 0)
        input.setSelectedRange(end)
        input.didChangeText()
        input.scrollRangeToVisible(end)
    }

    /// Aperta Enter por você. Devolve `false` quando não havia o que enviar.
    ///
    /// Mesma razão do `setText`: o Enter é tecla, e tecla sintética exige
    /// Acessibilidade (ADR-003). Sem isto a bolha apagada de "entregando" não é
    /// verificável de fora — ela só nasce do envio.
    @discardableResult
    func submit() -> Bool {
        let had = !input.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        send()
        return had
    }

    /// O texto passou do teto e está rolando por dentro.
    var isCapped: Bool {
        let inner = max(40, bounds.width - Self.pad * 2 - Self.sendLane)
        return ChatStyle.height(input.string, font: ChatStyle.body, width: inner)
            > textHeight(forWidth: bounds.width)
    }

    /// Altura do vidro agora, para quem confere de fora.
    var glassHeightNow: CGFloat { glassHeight(forWidth: bounds.width) }

    /// Muda o destinatário de fora — clicar num agente no painel da direita.
    func aim(at id: String) {
        guard candidates.contains(id) else { return }
        chosen = true
        target = id
        focus()
    }

    // MARK: Altura

    /// Altura que a caixa quer nesta largura — o vidro mais a lista de menção
    /// aberta, se estiver.
    ///
    /// Perguntada pelo container antes de dar o frame, porque a altura depende do
    /// texto e o texto depende da largura. Medida com o mesmo helper que o thread
    /// usa: fonte diferente entre quem mede e quem desenha corta a última linha.
    func height(forWidth width: CGFloat) -> CGFloat {
        var total = glassHeight(forWidth: width)
        if !mentions.isHidden { total += mentions.fittingSize.height + Self.mentionGap }
        return total
    }

    private func glassHeight(forWidth width: CGFloat) -> CGFloat {
        Self.chrome + textHeight(forWidth: width)
    }

    private func textHeight(forWidth width: CGFloat) -> CGFloat {
        let inner = max(40, width - Self.pad * 2 - Self.sendLane)
        let measured = ChatStyle.height(input.string, font: ChatStyle.body, width: inner)
        // O menor dos dois tetos, e nunca abaixo de uma linha: `oneLine` por último
        // porque uma caixa de zero altura não é caixa. Os dois arredondados PARA BAIXO
        // em linhas inteiras, senão o teto relativo reintroduz a linha partida.
        let budget = max(Self.oneLine, ceiling - Self.chrome)
        let roof = Self.floorToLine(min(Self.maxText, budget))
        return min(roof, max(Self.minText, measured))
    }

    /// A maior altura em linhas inteiras que cabe em `height`.
    private static func floorToLine(_ height: CGFloat) -> CGFloat {
        max(lineHeight, (height / lineHeight).rounded(.down) * lineHeight)
    }

    /// O que a caixa gasta fora do texto: recuo, linha do destinatário e o vão.
    private static var chrome: CGFloat { pad + headerHeight + 8 + pad }

    // MARK: Destinatário

    private func cycle(_ backwards: Bool) {
        guard !candidates.isEmpty else { return }
        chosen = true
        let index = candidates.firstIndex(of: target) ?? 0
        let step = backwards ? -1 : 1
        target = candidates[(index + step + candidates.count) % candidates.count]
    }

    /// `todos` não tem cor de agente — é a bancada inteira, e pintá-la com a cor de
    /// alguém sugeriria que a mensagem é dele.
    private var targetColor: NSColor {
        target == ChatComposer.everyone ? ChatStyle.text : AgentColor.of(target)
    }

    static let everyone = "todos"

    private func restyle() {
        name.stringValue = target
        name.textColor = targetColor
        dot.layer?.backgroundColor = targetColor.cgColor
        placeholder.stringValue = target.isEmpty
            ? "nenhum terminal de pé nesta bancada"
            : "escreva pra \(target)"
        needsLayout = true
    }

    // MARK: Menção

    private func textChanged() {
        placeholder.isHidden = !input.string.isEmpty
        // A palavra que está sendo digitada antes do cursor. Nada de `@` no meio
        // de e-mail ou de caminho: só vale colado num limite de palavra.
        if let query = input.pendingMention {
            // `@` sozinho oferece TODOS, e é o caso que mais importa: a lista existe
            // para descobrir quem existe, e isso se pergunta ANTES da primeira letra.
            // Filtrar por prefixo vazio devolvia lista vazia porque `contains("")` é
            // false em Swift — o `@` abria e nada aparecia.
            let items = query.isEmpty
                ? candidates
                : candidates.filter { $0.lowercased().contains(query.lowercased()) }
            if items.isEmpty {
                mentions.dismiss()
            } else {
                mentions.show(items) { [weak self] id in self?.statusOf?(id) ?? "" }
            }
        } else {
            mentions.dismiss()
        }
        needsLayout = true
        // Linha nova ou lista abrindo mudam a altura, e quem dá o frame é o
        // container: sem avisar, a caixa cresce por dentro do frame antigo e o
        // texto passa a ser escrito atrás do thread.
        requestFrameIfNeeded()
    }

    /// Pede frame novo quando a altura desejada deixou de ser a que o container já
    /// deu.
    ///
    /// Compara contra a altura EM USO e não contra uma segunda medida: `didChangeText`
    /// chega depois de o texto já ter mudado, então medir duas vezes ali dava sempre
    /// o mesmo número e o container nunca era avisado. O vidro então crescia dentro
    /// do frame de uma linha, passava da borda de baixo e a caixa parecia crescer
    /// para BAIXO — o oposto do que ela faz quando o frame acompanha.
    private func requestFrameIfNeeded() {
        if height(forWidth: bounds.width) != bounds.height { onHeightChanged?() }
    }

    private func insertMention(_ id: String) {
        input.replacePendingMention(with: "@" + id + " ")
        mentions.dismiss()
        textChanged()
        focus()
    }

    // MARK: Envio

    @objc private func sendClicked() { send() }

    private func send() {
        let text = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !target.isEmpty else { return }
        input.string = ""
        placeholder.isHidden = false
        mentions.dismiss()
        onSend?(text, target)
        needsLayout = true
        onHeightChanged?()
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let glassHeight = self.glassHeight(forWidth: bounds.width)
        let top = max(0, bounds.height - glassHeight)
        glass.frame = NSRect(x: 0, y: top, width: bounds.width, height: glassHeight)
        surface.frame = glass.bounds

        // A lista cresce PARA CIMA e por dentro do frame: a caixa mora no rodapé da
        // janela, e para baixo a lista sairia da tela. Dentro do frame porque view
        // que desenha fora dos próprios bounds não recebe clique.
        if mentions.isHidden {
            mentions.frame = .zero
        } else {
            let size = mentions.fittingSize
            mentions.frame = NSRect(x: 0, y: max(0, top - Self.mentionGap - size.height),
                                    width: size.width, height: size.height)
        }

        let pad = Self.pad
        let width = surface.bounds.width
        let toWidth = toLabel.measured
        toLabel.frame = NSRect(x: pad, y: pad, width: toWidth, height: 13)
        dot.frame = NSRect(x: pad + toWidth + 6, y: pad + 3, width: 7, height: 7)
        let nameLeft = pad + toWidth + 19
        let nameWidth = name.measured
        name.frame = NSRect(x: nameLeft, y: pad - 1, width: nameWidth, height: 15)
        let hintLeft = nameLeft + nameWidth + 12
        hint.frame = NSRect(x: hintLeft, y: pad, width: max(0, width - pad - hintLeft),
                            height: 13)

        let textTop = pad + Self.headerHeight + 8
        let textHeight = self.textHeight(forWidth: bounds.width)
        scroll.frame = NSRect(x: pad, y: textTop,
                              width: max(40, width - pad * 2 - Self.sendLane),
                              height: textHeight)
        placeholder.frame = NSRect(x: pad + 1, y: textTop + 1,
                                   width: scroll.frame.width - 2, height: 17)
        // Encostado embaixo: com o texto em três linhas o botão centrado ficaria no
        // meio do parágrafo, e o gesto de enviar é o fim da mensagem.
        sendButton.frame = NSRect(x: width - pad - 26,
                                  y: textTop + textHeight - 26, width: 26, height: 26)
    }
}

// MARK: - O campo

/// `NSTextView` que cede Tab e Enter ao composer.
///
/// Sem isto o Tab insere tabulação e o Enter quebra linha — os dois defaults
/// certos num editor de texto e errados numa caixa de mensagem, onde Tab escolhe
/// destinatário e Enter envia.
final class ComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCycle: ((_ backwards: Bool) -> Void)?
    var onTextChange: (() -> Void)?
    /// Seta e Enter enquanto a lista de menção está aberta. Devolve `true` quando
    /// a lista consumiu a tecla.
    var onMentionKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onMentionKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) { onCycle?(false) }
    override func insertBacktab(_ sender: Any?) { onCycle?(true) }

    /// Enter envia, Shift+Enter quebra linha. É a convenção de toda caixa de
    /// mensagem, e quebrar linha é o caso raro aqui.
    override func insertNewline(_ sender: Any?) {
        if NSEvent.modifierFlags.contains(.shift) {
            super.insertNewline(sender)
        } else {
            onSubmit?()
        }
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?()
    }

    /// O `@algo` que o cursor está terminando de escrever, se houver.
    var pendingMention: String? {
        let caret = selectedRange().location
        guard caret > 0, caret <= (string as NSString).length else { return nil }
        let before = (string as NSString).substring(to: caret)
        guard let at = before.lastIndex(of: "@") else { return nil }
        let word = before[before.index(after: at)...]
        // Espaço depois do `@` fecha a menção: você desistiu e seguiu escrevendo.
        guard !word.contains(" "), !word.contains("\n") else { return nil }
        // `@` tem de abrir palavra, senão e-mail e handle viram menção.
        if at > before.startIndex {
            let previous = before[before.index(before: at)]
            guard previous == " " || previous == "\n" else { return nil }
        }
        return String(word)
    }

    func replacePendingMention(with text: String) {
        guard let word = pendingMention else { return }
        let caret = selectedRange().location
        let start = caret - word.count - 1
        guard start >= 0 else { return }
        let range = NSRange(location: start, length: word.count + 1)
        if shouldChangeText(in: range, replacementString: text) {
            replaceCharacters(in: range, with: text)
            didChangeText()
        }
    }
}

// MARK: - Lista de menção

/// Quem existe, oferecido enquanto você escreve `@`.
///
/// De vidro como a caixa: ela nasce encostada nela e as duas leem como a mesma
/// superfície, com a lista sendo uma extensão do campo para cima.
final class MentionList: NSView {
    var onPick: ((String) -> Void)?
    /// A lista mudou de tamanho — quem dá o frame precisa refazer a conta.
    var onResize: (() -> Void)?

    private let surface = FlippedView()
    private lazy var glass = GlassPanel(content: surface, radius: 10)
    private var items: [String] = []
    private var rows: [NSView] = []
    private var selected = 0

    private static let rowHeight: CGFloat = 26
    private static let width: CGFloat = 260
    private static let padding: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(glass)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        isHidden ? .zero
            : NSSize(width: Self.width,
                     height: CGFloat(items.count) * Self.rowHeight + Self.padding * 2)
    }

    func show(_ items: [String], status: (String) -> String) {
        let changed = items != self.items
        self.items = items
        if changed { selected = 0 }
        let wasHidden = isHidden
        isHidden = false
        guard changed else { highlight(); return }

        rows.forEach { $0.removeFromSuperview() }
        rows = items.map { id in
            let row = NSView()
            row.wantsLayer = true
            row.layer?.cornerRadius = 5
            let chip = AgentChip(id)
            row.addSubview(chip)
            let state = ChatStyle.label(status(id), font: ChatStyle.meta, color: ChatStyle.faint)
            state.alignment = .right
            row.addSubview(state)
            surface.addSubview(row)
            return row
        }
        needsLayout = true
        highlight()
        if wasHidden || changed { onResize?() }
    }

    func dismiss() {
        guard !isHidden else { return }
        isHidden = true
        items = []
        rows.forEach { $0.removeFromSuperview() }
        rows = []
        onResize?()
    }

    /// Seta escolhe, Enter e Tab confirmam, Esc fecha. Devolve `true` quando
    /// consumiu — é o que impede o Enter de enviar a mensagem no meio da escolha.
    func handle(_ event: NSEvent) -> Bool {
        guard !isHidden, !items.isEmpty else { return false }
        switch event.keyCode {
        case 125: selected = (selected + 1) % items.count; highlight(); return true
        case 126: selected = (selected - 1 + items.count) % items.count; highlight(); return true
        case 36, 48: onPick?(items[selected]); return true
        case 53: dismiss(); return true
        default: return false
        }
    }

    private func highlight() {
        for (index, row) in rows.enumerated() {
            row.layer?.backgroundColor = index == selected
                ? NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
                : NSColor.clear.cgColor
        }
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        surface.frame = glass.bounds
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: Self.padding,
                               y: Self.padding + CGFloat(index) * Self.rowHeight,
                               width: surface.bounds.width - Self.padding * 2,
                               height: Self.rowHeight)
            guard let chip = row.subviews.first as? AgentChip else { continue }
            let size = chip.fittingSize
            chip.frame = NSRect(x: 7, y: 5, width: size.width, height: size.height)
            row.subviews.last?.frame = NSRect(x: chip.frame.maxX + 8, y: 6,
                                              width: row.bounds.width - chip.frame.maxX - 16,
                                              height: 14)
        }
    }
}

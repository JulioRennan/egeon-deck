import AppKit

// MARK: - Vocabulário visual do chat

/// Fontes, cores e medida de texto do modo Chat.
///
/// Junto num lugar porque são usados por seis views que precisam concordar: a
/// altura de uma linha é calculada por quem mede e desenhada por quem monta, e
/// fonte diferente entre os dois corta a última linha de toda mensagem.
enum ChatStyle {
    static let body = NSFont.systemFont(ofSize: 13)
    static let mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    static let meta = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    static let name = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold)
    static let sectionTitle = NSFont.systemFont(ofSize: 10, weight: .bold)

    static let text = NSColor(calibratedWhite: 0.93, alpha: 1)
    static let dim = NSColor(calibratedWhite: 1, alpha: 0.45)
    static let faint = NSColor(calibratedWhite: 1, alpha: 0.28)
    static let hairline = NSColor(calibratedWhite: 1, alpha: 0.09)
    static let rule = NSColor(calibratedWhite: 1, alpha: 0.18)

    static let threadBackground = NSColor(calibratedWhite: 0.078, alpha: 1)
    static let boxBackground = NSColor(calibratedWhite: 0.045, alpha: 1)
    /// O fundo do bloco de turno. Um degrau acima do thread, para o bloco se ler como
    /// um cartão sem precisar de borda forte.
    static let turnBackground = NSColor(calibratedWhite: 0.105, alpha: 1)
    /// O fundo das bolhas DENTRO do bloco. Mais um degrau, para a fala se separar do
    /// cartão que a contém.
    static let bubbleBackground = NSColor(calibratedWhite: 0.155, alpha: 1)

    /// Largura máxima do texto no thread. Linha de 1400px é ilegível, e o
    /// mosaico já provou que a janela cheia é larga.
    static let column: CGFloat = 780

    /// A coluna de fato, no espaço disponível. Uma conta só porque o thread e a
    /// caixa de escrever têm de ficar alinhados: bordas diferentes por 60pt leem
    /// como desalinho, não como decisão.
    static func columnWidth(in available: CGFloat) -> CGFloat {
        min(column, max(200, available - 48))
    }

    /// Altura de um texto na largura dada. Usa `usesLineFragmentOrigin` porque
    /// sem ele o retorno é a altura de uma linha só, independentemente do texto.
    static func height(_ string: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard !string.isEmpty, width > 1 else { return 0 }
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let rect = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height)
    }

    /// Largura de um texto, medida.
    ///
    /// Não é `intrinsicContentSize`: o rótulo nasce com a fonte de sistema e recebe
    /// a monoespaçada depois, e a largura intrínseca não acompanha a troca — o nome
    /// do agente saía cortado em `clau…` e a hora em `06:…`. Medir o par
    /// texto-mais-fonte que vai de fato ser desenhado não tem esse buraco.
    static func width(_ string: String, font: NSFont) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let rect = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude,
                         height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        // A folga é de um caractere, e é generosa de propósito: o `NSTextFieldCell`
        // recua o texto dentro dos bounds, e com truncamento ligado faltar UM ponto
        // custa DOIS caracteres na tela — o último glifo sai e a elipse entra no
        // lugar dele. Medido: `AGENTES` virava `AGENT…`.
        return ceil(rect.width) + ceil(font.pointSize * 0.75)
    }

    /// Rótulo que não quebra e não vira campo editável.
    static func label(_ string: String = "", font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    /// Rótulo de várias linhas, para corpo de mensagem.
    static func paragraph(_ string: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = font
        field.textColor = color
        field.isSelectable = true
        field.drawsBackground = false
        field.isBordered = false
        return field
    }
}

extension NSTextField {
    /// A largura que este rótulo precisa, medida com a fonte que ele tem agora.
    var measured: CGFloat { ChatStyle.width(stringValue, font: font ?? ChatStyle.body) }
}

// MARK: - Chip com nome de agente

/// O nome de um terminal, na cor dele. É o átomo do thread: aparece no
/// destinatário, na menção dentro do texto e na lista de acesso.
final class AgentChip: NSView {
    private let label = NSTextField(labelWithString: "")

    init(_ id: String, prefix: String = "") {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.backgroundColor = AgentColor.chipBackground(id).cgColor
        label.stringValue = prefix + id
        label.font = ChatStyle.meta
        label.textColor = AgentColor.of(id)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var fittingSize: NSSize {
        NSSize(width: label.measured + 10, height: 15)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 5, y: 1, width: bounds.width - 10, height: 13)
    }
}

// MARK: - Uma linha do thread

/// Base das linhas: quem monta o thread só precisa saber medir e posicionar.
class ChatRow: NSView {
    override var isFlipped: Bool { true }

    /// Altura desta linha na largura dada. Chamado antes de `frame` existir, então
    /// não pode depender de `bounds`.
    func height(for width: CGFloat) -> CGFloat { 0 }
}

/// Uma fala dentro do bloco do turno.
///
/// Bolha dentro de bolha: o cartão do turno mantém o par junto, e as duas bolhas dizem
/// de quem é cada metade. O que as separa é o LADO, e não a cor — é o mesmo vocabulário
/// do resto do chat, onde o que você diz encosta à direita e o que o agente responde
/// encosta à esquerda.
final class ChatBubble: NSView {
    enum Side {
        /// Você pedindo. Encosta à direita e não ocupa a largura toda.
        case yours
        /// O agente respondendo. Encosta à esquerda.
        case agent
    }

    private let side: Side
    private let blocks: [ChatBlockView]

    private static let padding: CGFloat = 11
    /// Quanto da largura a bolha do pedido ocupa. Menos que tudo, senão ela e a da
    /// resposta se alinham nas duas bordas e o lado deixa de dizer qualquer coisa.
    private static let yoursShare: CGFloat = 0.84

    init(blocks source: [ChatBlock], accent: NSColor, side: Side) {
        self.side = side
        blocks = source.map { ChatBlockView(block: $0, accent: accent) }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = ChatStyle.bubbleBackground.cgColor
        layer?.cornerRadius = 6
        blocks.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func bubbleWidth(_ width: CGFloat) -> CGFloat {
        side == .yours ? (width * Self.yoursShare).rounded() : width
    }

    func height(for width: CGFloat) -> CGFloat {
        let inner = bubbleWidth(width) - Self.padding * 2
        return blocks.reduce(Self.padding * 2) { $0 + $1.height(for: inner) + 4 } - 4
    }

    override func layout() {
        super.layout()
        let inner = bounds.width - Self.padding * 2
        var y = Self.padding
        for block in blocks {
            let height = block.height(for: inner)
            block.frame = NSRect(x: Self.padding, y: y, width: inner, height: height)
            y += height + 4
        }
    }

    /// Onde a bolha começa, na largura útil do bloco. É o que faz o lado.
    func originX(in width: CGFloat) -> CGFloat {
        side == .yours ? width - bubbleWidth(width) : 0
    }

    func widthNeeded(in width: CGFloat) -> CGFloat { bubbleWidth(width) }
}

/// Um TURNO, como um bloco só: o que foi pedido, o caminho, e a resposta.
///
/// É a unidade do thread. Ordenar mensagens soltas por tempo intercala duas conversas
/// e a resposta do A cai no meio da sua terceira pergunta ao B — cisma de piso. O bloco
/// não cinde: tudo dentro dele é do mesmo par.
///
/// Nasce RECOLHIDO no meio. Um turno de trinta chamadas de ferramenta viraria um cartão
/// que não cabe na tela, e aí o agrupamento pioraria a leitura em vez de melhorá-la —
/// então o que fica sempre à vista é a pergunta e a resposta, e o caminho é uma linha
/// que abre.
final class ChatTurnRow: ChatRow {
    /// A altura mudou porque algo abriu ou fechou. Quem empilha refaz a conta.
    var onToggle: (() -> Void)?

    private let turn: ChatTurn
    /// Quem atendeu. O thread usa para casar o "está rodando" sem guardar índice.
    var agent: String { turn.author }
    private let accent: NSColor
    private let bar = NSView()
    private let author: NSTextField
    private let time: NSTextField
    private let fromChip: AgentChip?
    /// Os três pontos, só enquanto o turno está aberto.
    private var dots: [NSView] = []
    private let live: NSTextField?
    private let promptBubble: ChatBubble?
    private let workToggle: DisclosureLine?
    private var workBlocks: [ChatBlockView] = []
    private let answerBubble: ChatBubble?
    private var chainEntries: [ChainEntryView] = []
    /// O caminho nasce DOBRADO. Turno de trinta ferramentas viraria um cartão que não
    /// cabe na tela, e aí o agrupamento pioraria a leitura em vez de melhorá-la. O que
    /// fica sempre à vista é o par que importa: o pedido e a resposta, cada um na sua
    /// bolha. O caminho abre com um clique quando você quiser acompanhar.
    private var workOpen = false

    private static let gutter: CGFloat = 14
    private static let pad: CGFloat = 12
    private static let gap: CGFloat = 8

    init(turn: ChatTurn, note: String?, running: Bool) {
        self.turn = turn
        accent = AgentColor.of(turn.author)
        author = ChatStyle.label(turn.author, font: ChatStyle.name, color: accent)
        time = ChatStyle.label(turn.inFlight ? "entregando…" : turn.timeLabel,
                               font: ChatStyle.meta, color: ChatStyle.faint)
        // Quem pediu, quando não foi você. O chip é a mesma peça do destinatário: em
        // qualquer lugar do chat, nome de agente na cor dele quer dizer a mesma coisa.
        fromChip = turn.from.map { AgentChip($0, prefix: "de ") }
        live = running ? ChatStyle.label(note ?? "pensando", font: ChatStyle.meta,
                                         color: ChatStyle.dim) : nil
        promptBubble = turn.prompt.isEmpty
            ? nil : ChatBubble(blocks: [.prose(turn.prompt)], accent: accent, side: .yours)
        answerBubble = turn.answer.isEmpty
            ? nil : ChatBubble(blocks: turn.answer, accent: accent, side: .agent)
        workToggle = turn.work.isEmpty
            ? nil : DisclosureLine(text: turn.workSummary, color: ChatStyle.faint)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = ChatStyle.turnBackground.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = ChatStyle.hairline.cgColor
        if turn.inFlight { alphaValue = 0.6 }

        bar.wantsLayer = true
        bar.layer?.backgroundColor = accent.cgColor
        addSubview(bar)
        addSubview(author)
        addSubview(time)
        if let fromChip { addSubview(fromChip) }
        if let live {
            for _ in 0..<3 {
                let dot = NSView()
                dot.wantsLayer = true
                dot.layer?.backgroundColor = accent.cgColor
                dot.layer?.cornerRadius = 2.5
                dots.append(dot)
                addSubview(dot)
            }
            addSubview(live)
        }
        if let promptBubble { addSubview(promptBubble) }
        if let workToggle {
            workToggle.onClick = { [weak self] in self?.toggleWork() }
            addSubview(workToggle)
        }
        if let answerBubble { addSubview(answerBubble) }

        chainEntries = turn.chain.map { entry in
            let view = ChainEntryView(turn: entry)
            view.onToggle = { [weak self] in self?.onToggle?() }
            addSubview(view)
            return view
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func toggleWork() {
        workOpen.toggle()
        workToggle?.isOpen = workOpen
        // Montado só quando abre: turno longo constrói dezenas de views que, dobrado,
        // ninguém pediu para ver.
        if workOpen, workBlocks.isEmpty {
            workBlocks = turn.work.map { ChatBlockView(block: $0, accent: accent) }
            workBlocks.forEach { addSubview($0) }
        }
        workBlocks.forEach { $0.isHidden = !workOpen }
        onToggle?()
    }

    private func contentWidth(_ width: CGFloat) -> CGFloat {
        max(120, width - Self.gutter - Self.pad)
    }

    override func height(for width: CGFloat) -> CGFloat {
        let inner = contentWidth(width)
        var y = Self.pad + 16 + Self.gap
        if let promptBubble { y += promptBubble.height(for: inner) + Self.gap }
        if workToggle != nil { y += DisclosureLine.height + Self.gap }
        if workOpen {
            y += workBlocks.reduce(0) { $0 + $1.height(for: inner) + 6 }
        }
        if let answerBubble { y += answerBubble.height(for: inner) + Self.gap }
        y += chainEntries.reduce(0) { $0 + $1.height(for: inner) + Self.gap }
        return y + Self.pad - Self.gap
    }

    /// A animação entra quando a view tem janela. Fora dela o CoreAnimation pausa.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        for (index, dot) in dots.enumerated() {
            dot.layer?.removeAllAnimations()
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.25
            pulse.toValue = 1
            pulse.duration = 0.5
            pulse.autoreverses = true
            pulse.repeatCount = .greatestFiniteMagnitude
            pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.16
            dot.layer?.add(pulse, forKey: "pulse")
        }
    }

    /// Troca só o texto do que está rodando. Remontar reiniciaria a animação, e três
    /// pontos que recomeçam a cada meio segundo leem como travamento.
    func update(note text: String?) {
        live?.stringValue = text ?? "pensando"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inner = contentWidth(bounds.width)
        bar.frame = NSRect(x: 0, y: 0, width: 3, height: bounds.height)

        var y = Self.pad
        var x = Self.gutter
        author.frame = NSRect(x: x, y: y, width: author.measured, height: 15)
        x = author.frame.maxX + 8
        if let fromChip {
            let size = fromChip.fittingSize
            fromChip.frame = NSRect(x: x, y: y + 1, width: size.width, height: size.height)
            x = fromChip.frame.maxX + 8
        }
        time.frame = NSRect(x: x, y: y + 2, width: time.measured, height: 13)
        x = time.frame.maxX + 10
        if let live {
            for dot in dots {
                dot.frame = NSRect(x: x, y: y + 6, width: 5, height: 5)
                x += 8
            }
            live.frame = NSRect(x: x + 3, y: y + 2,
                                width: max(0, bounds.width - x - Self.pad - 3), height: 13)
        }
        y += 16 + Self.gap

        if let promptBubble {
            let height = promptBubble.height(for: inner)
            promptBubble.frame = NSRect(x: Self.gutter + promptBubble.originX(in: inner), y: y,
                                        width: promptBubble.widthNeeded(in: inner), height: height)
            y += height + Self.gap
        }
        if let workToggle {
            workToggle.frame = NSRect(x: Self.gutter, y: y, width: inner,
                                      height: DisclosureLine.height)
            y += DisclosureLine.height + Self.gap
        }
        if workOpen {
            for block in workBlocks {
                let height = block.height(for: inner)
                block.frame = NSRect(x: Self.gutter, y: y, width: inner, height: height)
                y += height + 6
            }
        }
        if let answerBubble {
            let height = answerBubble.height(for: inner)
            answerBubble.frame = NSRect(x: Self.gutter + answerBubble.originX(in: inner), y: y,
                                        width: answerBubble.widthNeeded(in: inner), height: height)
            y += height + Self.gap
        }
        for entry in chainEntries {
            let height = entry.height(for: inner)
            entry.frame = NSRect(x: Self.gutter, y: y, width: inner, height: height)
            y += height + Self.gap
        }
    }
}

/// A linha que abre e fecha: caret, texto, e um fio até a borda.
final class DisclosureLine: NSView {
    var onClick: (() -> Void)?
    var isOpen = false { didSet { caret.stringValue = isOpen ? "▾" : "▸" } }

    static let height: CGFloat = 17

    private let caret = NSTextField(labelWithString: "▸")
    private let label: NSTextField

    init(text: String, color: NSColor) {
        label = ChatStyle.label(text, font: ChatStyle.meta, color: color)
        super.init(frame: .zero)
        caret.font = ChatStyle.meta
        caret.textColor = ChatStyle.faint
        caret.isBordered = false
        caret.drawsBackground = false
        caret.isEditable = false
        addSubview(caret)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setText(_ text: String) { label.stringValue = text; needsLayout = true }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func layout() {
        super.layout()
        caret.frame = NSRect(x: 0, y: 2, width: 12, height: 13)
        label.frame = NSRect(x: 13, y: 2, width: max(0, bounds.width - 13), height: 13)
    }
}

/// Uma fala da cadeia entre agentes, dentro do bloco de quem a começou.
///
/// **É o mesmo cartão, com outro nome em cima.** Nem bolha própria nem seta de
/// aninhamento: o cabeçalho é o do turno — nome do agente na cor dele — e a bolha é a
/// mesma `ChatBubble` da resposta. Quem fala muda; o desenho, não.
///
/// Chegou a ter recuo e seta (`↳`), e as duas foram embora pela mesma razão: três voltas
/// viravam uma escada dentro do cartão, e o desenho passava a falar da topologia em vez
/// da conversa — ficava confuso justamente onde precisava ser claro. Achatado, é uma
/// bolha embaixo da outra e a ordem de leitura é de cima para baixo, como qualquer
/// conversa.
///
/// A pergunta desta fala não é repetida: ela está na bolha de cima, que é a resposta de
/// quem acionou ("perguntei ao vizinho quanto é 7 vezes 6"). Só aparece quando o outro
/// ainda não respondeu — e aí ela entra do lado do PEDIDO, à direita, que é o que diz
/// que ninguém respondeu ainda sem precisar de palavra nenhuma.
final class ChainEntryView: NSView {
    var onToggle: (() -> Void)?

    private let turn: ChatTurn
    private let accent: NSColor
    private let head: NSTextField
    private let bubble: ChatBubble?
    private let workToggle: DisclosureLine?
    private var workBlocks: [ChatBlockView] = []
    private var workOpen = false

    private static let gap: CGFloat = 6

    init(turn: ChatTurn) {
        self.turn = turn
        accent = AgentColor.of(turn.author)
        let pending = turn.answer.isEmpty
        // O mesmo cabeçalho do turno: nome na cor dele, na mesma fonte. É isso que faz
        // a fala se ler como continuação do cartão, e não como caixa dentro de caixa.
        head = ChatStyle.label(turn.author, font: ChatStyle.name, color: accent)
        bubble = pending
            ? (turn.prompt.isEmpty
                ? nil : ChatBubble(blocks: [.prose(turn.prompt)], accent: accent, side: .yours))
            : ChatBubble(blocks: turn.answer, accent: accent, side: .agent)
        workToggle = turn.work.isEmpty
            ? nil : DisclosureLine(text: turn.workSummary, color: ChatStyle.faint)
        super.init(frame: .zero)

        addSubview(head)
        if let workToggle {
            workToggle.onClick = { [weak self] in self?.toggleWork() }
            addSubview(workToggle)
        }
        if let bubble { addSubview(bubble) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func toggleWork() {
        workOpen.toggle()
        workToggle?.isOpen = workOpen
        if workOpen, workBlocks.isEmpty {
            workBlocks = turn.work.map { ChatBlockView(block: $0, accent: accent) }
            workBlocks.forEach { addSubview($0) }
        }
        workBlocks.forEach { $0.isHidden = !workOpen }
        onToggle?()
    }

    func height(for width: CGFloat) -> CGFloat {
        var y = 16 + Self.gap
        if workToggle != nil { y += DisclosureLine.height + Self.gap }
        if workOpen { y += workBlocks.reduce(0) { $0 + $1.height(for: width) + 5 } }
        if let bubble { y += bubble.height(for: width) }
        return y
    }

    override func layout() {
        super.layout()
        head.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 15)
        var y: CGFloat = 16 + Self.gap
        if let workToggle {
            workToggle.frame = NSRect(x: 0, y: y, width: bounds.width,
                                      height: DisclosureLine.height)
            y += DisclosureLine.height + Self.gap
        }
        if workOpen {
            for block in workBlocks {
                let height = block.height(for: bounds.width)
                block.frame = NSRect(x: 0, y: y, width: bounds.width, height: height)
                y += height + 5
            }
        }
        if let bubble {
            let height = bubble.height(for: bounds.width)
            bubble.frame = NSRect(x: bubble.originX(in: bounds.width), y: y,
                                  width: bubble.widthNeeded(in: bounds.width), height: height)
        }
    }
}

/// Linha de fato do app: subiu, caiu, pediu permissão.
final class ChatSystemRow: ChatRow {
    private let dot = NSView()
    private let label: NSTextField

    init(text: String, color: NSColor) {
        label = ChatStyle.label(text, font: ChatStyle.meta, color: color)
        super.init(frame: .zero)
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        addSubview(dot)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func height(for width: CGFloat) -> CGFloat { 20 }

    override func layout() {
        super.layout()
        let width = label.measured
        let x = ((bounds.width - width - 13) / 2).rounded()
        dot.frame = NSRect(x: x, y: 5, width: 5, height: 5)
        label.frame = NSRect(x: x + 13, y: 1, width: width, height: 14)
    }
}

/// O agente está trabalhando: três pontos na cor dele e o que ele está fazendo.
///
/// É o feedback que faltava. O `Activity` já sabia que o turno estava correndo (é o
/// que acende o spinner no cabeçalho do card), mas no chat isso não aparecia em lugar
/// nenhum: você mandava um prompt e ficava olhando o thread parado, sem saber se a
/// entrega passou, se ele estava pensando, ou se nada aconteceu.
///
/// O detalhe vem do adapter do CLI (`ChatAdapter.live`), e é o que separa isto de um
/// spinner: "lendo Canvas.swift" e "$ npx vitest" dizem que o trabalho ANDOU desde a
/// última vez que você olhou.
final class ThinkingRow: ChatRow {
    private let bar = NSView()
    private let author: NSTextField
    private let note: NSTextField
    private let dots = [NSView(), NSView(), NSView()]
    let agentID: String

    private static let gutter: CGFloat = 12

    init(agent: String, note text: String?) {
        agentID = agent
        author = ChatStyle.label(agent, font: ChatStyle.name, color: AgentColor.of(agent))
        note = ChatStyle.label(text ?? "pensando", font: ChatStyle.meta, color: ChatStyle.dim)
        super.init(frame: .zero)

        bar.wantsLayer = true
        bar.layer?.backgroundColor = AgentColor.of(agent).cgColor
        addSubview(bar)
        addSubview(author)
        for dot in dots {
            dot.wantsLayer = true
            dot.layer?.backgroundColor = AgentColor.of(agent).cgColor
            dot.layer?.cornerRadius = 2.5
            addSubview(dot)
        }
        addSubview(note)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Troca só o texto, sem refazer a linha: remontar reinicia a animação, e três
    /// pontos que recomeçam a cada meio segundo leem como travamento, não como
    /// trabalho.
    func update(note text: String?) {
        note.stringValue = text ?? "pensando"
        needsLayout = true
    }

    override func height(for width: CGFloat) -> CGFloat { 34 }

    /// A animação entra quando a view tem janela. Fora dela o CoreAnimation pausa, e
    /// religar no `init` deixaria os pontos parados no primeiro quadro.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        for (index, dot) in dots.enumerated() {
            dot.layer?.removeAllAnimations()
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.25
            pulse.toValue = 1
            pulse.duration = 0.5
            pulse.autoreverses = true
            pulse.repeatCount = .greatestFiniteMagnitude
            pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.16
            dot.layer?.add(pulse, forKey: "pulse")
        }
    }

    override func layout() {
        super.layout()
        bar.frame = NSRect(x: 0, y: 1, width: 2, height: 26)
        author.frame = NSRect(x: Self.gutter, y: 0, width: author.measured, height: 14)
        var x = Self.gutter
        for dot in dots {
            dot.frame = NSRect(x: x, y: 20, width: 5, height: 5)
            x += 8
        }
        note.frame = NSRect(x: x + 4, y: 17, width: max(0, bounds.width - x - 16), height: 13)
    }
}

// MARK: - Um bloco dentro da mensagem de agente

/// Prosa, comando, diff ou linha de ferramenta. Um tipo só porque a mensagem os
/// empilha na ordem em que o agente produziu, e a lista é heterogênea.
final class ChatBlockView: NSView {
    private enum Shape {
        case prose(NSTextField)
        case code(NSTextField)
        case edit(header: NSTextField, adds: NSTextField, dels: NSTextField, lines: [DiffLineView])
        case tool(NSTextField)
    }

    private let shape: Shape
    /// Flipped, e não `NSView`: é esta caixa que posiciona o cabeçalho e as linhas
    /// do diff. Sem inverter, a AppKit conta y de baixo para cima e o diff sai de
    /// cabeça para baixo, com o nome do arquivo no rodapé — medido na tela.
    private let box = FlippedView()
    private let raw: ChatBlock

    private static let padding: CGFloat = 9
    private static let lineHeight: CGFloat = 16

    init(block: ChatBlock, accent: NSColor) {
        raw = block
        switch block {
        case .prose(let text):
            let field = ChatStyle.paragraph(text, font: ChatStyle.body, color: ChatStyle.text)
            shape = .prose(field)
            super.init(frame: .zero)
            addSubview(field)

        case .code(let text):
            let field = ChatStyle.paragraph(text, font: ChatStyle.mono,
                                            color: NSColor(calibratedWhite: 0.8, alpha: 1))
            shape = .code(field)
            super.init(frame: .zero)
            addSubview(box)
            box.addSubview(field)

        case .edit(let edit):
            let header = ChatStyle.label(edit.file, font: ChatStyle.mono,
                                         color: NSColor(calibratedWhite: 0.85, alpha: 1))
            let adds = ChatStyle.label("+\(edit.add)", font: ChatStyle.meta, color: .systemGreen)
            let dels = ChatStyle.label("−\(edit.del)", font: ChatStyle.meta, color: .systemRed)
            let lines = edit.lines.map { DiffLineView(line: $0) }
            shape = .edit(header: header, adds: adds, dels: dels, lines: lines)
            super.init(frame: .zero)
            addSubview(box)
            box.addSubview(header)
            box.addSubview(adds)
            box.addSubview(dels)
            lines.forEach { box.addSubview($0) }

        case .tool(let text):
            let field = ChatStyle.label("· " + text, font: ChatStyle.meta, color: ChatStyle.faint)
            shape = .tool(field)
            super.init(frame: .zero)
            addSubview(field)
        }

        box.wantsLayer = true
        box.layer?.backgroundColor = ChatStyle.boxBackground.cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = ChatStyle.hairline.cgColor
        box.layer?.cornerRadius = 4
        _ = accent
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func height(for width: CGFloat) -> CGFloat {
        switch shape {
        case .prose(let field):
            return ChatStyle.height(field.stringValue, font: ChatStyle.body, width: width)
        case .code(let field):
            return ChatStyle.height(field.stringValue, font: ChatStyle.mono,
                                    width: width - Self.padding * 2) + Self.padding * 2
        case .edit(_, _, _, let lines):
            return 26 + CGFloat(lines.count) * Self.lineHeight + 6
        case .tool:
            return 15
        }
    }

    override func layout() {
        super.layout()
        switch shape {
        case .prose(let field):
            field.frame = bounds

        case .code(let field):
            box.frame = bounds
            field.frame = NSRect(x: Self.padding, y: Self.padding,
                                 width: bounds.width - Self.padding * 2,
                                 height: bounds.height - Self.padding * 2)

        case .edit(let header, let adds, let dels, let lines):
            box.frame = bounds
            header.frame = NSRect(x: 10, y: 6, width: bounds.width - 110, height: 14)
            let delWidth = dels.measured
            let addWidth = adds.measured
            dels.frame = NSRect(x: bounds.width - delWidth - 10, y: 7,
                                width: delWidth, height: 13)
            adds.frame = NSRect(x: dels.frame.minX - addWidth - 6, y: 7,
                                width: addWidth, height: 13)
            var y: CGFloat = 26
            for line in lines {
                line.frame = NSRect(x: 1, y: y, width: bounds.width - 2, height: Self.lineHeight)
                y += Self.lineHeight
            }

        case .tool(let field):
            field.frame = bounds
        }
    }
}

/// Uma linha de diff. Desenhada e não montada com rótulo: o fundo é da linha
/// inteira, e o sinal precisa ficar numa coluna fixa para o olho descer por ela.
final class DiffLineView: NSView {
    private let line: DiffLine

    init(line: DiffLine) {
        self.line = line
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        switch line.mark {
        case "+":
            NSColor.systemGreen.withAlphaComponent(0.09).setFill()
            bounds.fill()
            color = NSColor(srgbRed: 0.66, green: 0.85, blue: 0.61, alpha: 1)
        case "-":
            NSColor.systemRed.withAlphaComponent(0.09).setFill()
            bounds.fill()
            color = NSColor(srgbRed: 0.94, green: 0.58, blue: 0.54, alpha: 1)
        default:
            color = ChatStyle.dim
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: ChatStyle.mono, .foregroundColor: color]
        NSAttributedString(string: String(line.mark), attributes: attributes)
            .draw(at: NSPoint(x: 9, y: 1))
        // Truncar em vez de quebrar: linha de código que embrulha desalinha a
        // coluna dos sinais, que é justamente o que se lê num diff.
        let text = NSAttributedString(string: line.text, attributes: attributes)
        text.draw(with: NSRect(x: 22, y: 1, width: bounds.width - 30, height: bounds.height - 2),
                  options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
    }
}

// MARK: - O thread

/// A lista de mensagens, rolando.
///
/// Empilha com frames calculados à mão, como o resto do app. `NSStackView` daria
/// o empilhamento de graça mas não a medida: cada linha tem altura que depende da
/// largura, e é a largura da coluna — não a do container — que manda.
final class ChatThreadView: NSView {
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private var rows: [ChatRow] = []

    /// O thread está grudado no fim.
    ///
    /// Verdadeiro até você rolar para cima, e verdadeiro de novo quando você volta ao
    /// fim. É o que faz mensagem nova aparecer sem você ir buscá-la, e o que impede o
    /// thread de te arrancar do meio da conversa que você estava lendo.
    ///
    /// Não dá para resolver só rolando depois de montar: a primeira medida acontece
    /// com a largura ainda em zero, as alturas saem enormes, e a posição calculada ali
    /// não vale mais quando o layout de verdade chega — o último bloco ficava cortado
    /// na borda de baixo. Grudar é conferido a CADA remedida.
    private var stickToBottom = true
    /// Rolagem feita por nós. Sem isto, o próprio ajuste dispara a notificação e
    /// reavalia o grude no meio do caminho.
    private var scrollingSelf = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = ChatStyle.threadBackground.cgColor

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        addSubview(scroll)

        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func scrolled() {
        guard !scrollingSelf else { return }
        stickToBottom = isAtBottom
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Assinatura do que está desenhado. Remontar a cada leitura de transcript
    /// perderia a seleção de texto e o estado do que você abriu — e o laço lê a cada
    /// meio segundo.
    private var drawn: String = ""
    private var turnRows: [ChatTurnRow] = []

    /// O texto do que está rodando NÃO entra na assinatura: ele muda a cada
    /// ferramenta, e remontar reinicia a animação dos pontos.
    func show(_ turns: [ChatTurn], working: [(id: String, note: String?)] = []) {
        let runningIDs = Set(working.map(\.id))
        let signature = Self.signature(of: turns) + "|" + runningIDs.sorted().joined(separator: ",")
        if signature == drawn {
            for row in turnRows { row.update(note: working.first { $0.id == row.agent }?.note) }
            return
        }
        drawn = signature

        rows.forEach { $0.removeFromSuperview() }
        turnRows = []
        rows = turns.map { turn -> ChatRow in
            // Só o ÚLTIMO turno de um agente pode estar rodando: o anterior acabou
            // quando este abriu.
            let running = runningIDs.contains(turn.author)
                && turn.id == turns.last(where: { $0.author == turn.author })?.id
            let row = ChatTurnRow(turn: turn,
                                  note: working.first { $0.id == turn.author }?.note,
                                  running: running)
            row.onToggle = { [weak self] in self?.reflow() }
            turnRows.append(row)
            return row
        }
        rows.forEach { document.addSubview($0) }
        reflow()
    }

    /// Identidade do que está na tela, incluindo o aninhamento: sub-conversa nova
    /// dentro de um bloco antigo também é mudança.
    private static func signature(of turns: [ChatTurn]) -> String {
        turns.map { turn in
            turn.id + (turn.replies.isEmpty ? "" : "(" + signature(of: turn.replies) + ")")
        }.joined(separator: ",")
    }

    /// Vazio significa duas coisas diferentes, e a mensagem separa: sessão sem
    /// agente com gancho não vai ter thread nunca, e dizer "ninguém falou" ali
    /// seria mentira por omissão.
    var placeholder: String? {
        didSet {
            guard placeholder != oldValue else { return }
            empty?.removeFromSuperview()
            guard let placeholder, rows.isEmpty else { empty = nil; return }
            let field = ChatStyle.paragraph(placeholder, font: ChatStyle.body, color: ChatStyle.dim)
            document.addSubview(field)
            empty = field
            needsLayout = true
        }
    }
    private var empty: NSTextField?

    private var isAtBottom: Bool {
        let visible = scroll.contentView.bounds
        return visible.maxY >= document.bounds.height - 40
    }

    func scrollToBottom() {
        stickToBottom = true
        pinBottom()
    }

    private func pinBottom() {
        let height = document.bounds.height
        let visible = scroll.contentView.bounds.height
        guard height > visible else { return }
        scrollingSelf = true
        document.scroll(NSPoint(x: 0, y: height - visible))
        scrollingSelf = false
    }

    private func reflow() {
        let width = ChatStyle.columnWidth(in: bounds.width)
        let x = ((bounds.width - width) / 2).rounded()
        var y: CGFloat = 22
        for row in rows {
            let height = row.height(for: width)
            row.frame = NSRect(x: x, y: y, width: width, height: height)
            y += height + 16
        }
        if let empty {
            empty.frame = NSRect(x: x, y: 64, width: width, height: 60)
            y = max(y, 140)
        }
        document.frame = NSRect(x: 0, y: 0, width: bounds.width,
                                height: max(y + 12, scroll.contentView.bounds.height))
        // Depois de o documento ter a altura nova, e não antes: a conta do fim depende
        // dela.
        if stickToBottom { pinBottom() }
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        reflow()
    }
}

/// Documento de rolagem com origem no topo, para o thread crescer para baixo.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

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
    static let bubbleBackground = NSColor(calibratedWhite: 0.145, alpha: 1)

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

/// Você falando: bolha à direita, com os destinatários acima.
final class ChatUserRow: ChatRow {
    private let bubble = NSView()
    private let text: NSTextField
    private let time: NSTextField
    private var chips: [AgentChip] = []

    /// A bolha não vai até a borda: mensagem sua e resposta de agente alinhadas na
    /// mesma largura não se distinguem de relance, e o recuo é o que diz "isto é
    /// meu".
    private static let inset: CGFloat = 90
    private static let padding: CGFloat = 10
    /// Teto da bolha. Sem ele, numa coluna de 780pt a mensagem sua ocupa 690 e para
    /// de se distinguir da resposta do agente, que é o que o recuo existe para
    /// fazer.
    private static let maxWidth: CGFloat = 470

    init(entry: ChatEntry) {
        text = ChatStyle.paragraph(entry.text, font: ChatStyle.body, color: ChatStyle.text)
        time = ChatStyle.label(entry.timeLabel, font: ChatStyle.meta, color: ChatStyle.faint)
        super.init(frame: .zero)

        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = ChatStyle.bubbleBackground.cgColor
        bubble.layer?.cornerRadius = 6
        addSubview(bubble)
        bubble.addSubview(text)

        addSubview(time)
        for id in entry.recipients {
            let chip = AgentChip(id, prefix: "→ ")
            chips.append(chip)
            addSubview(chip)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func bubbleWidth(_ width: CGFloat) -> CGFloat {
        min(Self.maxWidth, max(80, width - Self.inset))
    }

    override func height(for width: CGFloat) -> CGFloat {
        let inner = bubbleWidth(width) - Self.padding * 2
        return 17 + ChatStyle.height(text.stringValue, font: ChatStyle.body, width: inner)
            + Self.padding * 2 + 6
    }

    override func layout() {
        super.layout()
        var x = bounds.width
        for chip in chips.reversed() {
            let size = chip.fittingSize
            x -= size.width
            chip.frame = NSRect(x: x, y: 1, width: size.width, height: size.height)
            x -= 4
        }
        let timeWidth = time.measured
        time.frame = NSRect(x: max(0, x - timeWidth), y: 2, width: timeWidth, height: 13)

        let width = bubbleWidth(bounds.width)
        let inner = width - Self.padding * 2
        let textHeight = ChatStyle.height(text.stringValue, font: ChatStyle.body, width: inner)
        bubble.frame = NSRect(x: bounds.width - width, y: 17,
                              width: width, height: textHeight + Self.padding * 2)
        text.frame = NSRect(x: Self.padding, y: Self.padding, width: inner, height: textHeight)
    }
}

/// O agente respondendo: fio na cor dele à esquerda, e os blocos embaixo do nome.
final class ChatAgentRow: ChatRow {
    private let bar = NSView()
    private let author: NSTextField
    private let time: NSTextField
    private let blocks: [ChatBlockView]

    private static let gutter: CGFloat = 12
    /// Resposta de agente não ocupa a coluna inteira: sobra à direita é o que
    /// deixa a bolha sua se ler como o outro lado da conversa.
    private static let trailing: CGFloat = 70

    init(entry: ChatEntry) {
        let id = entry.author ?? ""
        author = ChatStyle.label(id, font: ChatStyle.name, color: AgentColor.of(id))
        time = ChatStyle.label(entry.timeLabel, font: ChatStyle.meta, color: ChatStyle.faint)
        blocks = entry.blocks.map { ChatBlockView(block: $0, accent: AgentColor.of(id)) }
        super.init(frame: .zero)

        bar.wantsLayer = true
        bar.layer?.backgroundColor = AgentColor.of(id).cgColor
        addSubview(bar)
        addSubview(author)
        addSubview(time)
        blocks.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func contentWidth(_ width: CGFloat) -> CGFloat {
        max(120, width - Self.gutter - Self.trailing)
    }

    override func height(for width: CGFloat) -> CGFloat {
        let inner = contentWidth(width)
        return 18 + blocks.reduce(0) { $0 + $1.height(for: inner) + 7 }
    }

    override func layout() {
        super.layout()
        let inner = contentWidth(bounds.width)
        author.frame = NSRect(x: Self.gutter, y: 0, width: author.measured, height: 14)
        time.frame = NSRect(x: author.frame.maxX + 7, y: 1, width: time.measured, height: 13)

        var y: CGFloat = 18
        for block in blocks {
            let height = block.height(for: inner)
            block.frame = NSRect(x: Self.gutter, y: y, width: inner, height: height)
            y += height + 7
        }
        bar.frame = NSRect(x: 0, y: 1, width: 2, height: max(0, y - 8))
    }
}

/// Um agente acionando outro. Fica recolhido: você quer saber QUE eles falaram,
/// e ler o quê só quando o resultado não fizer sentido.
final class ChatLinkRow: ChatRow {
    private let head = NSTextField(labelWithString: "")
    private let body: NSTextField
    private let caret = NSTextField(labelWithString: "▸")
    private var open = false
    private let bodyText: String

    /// Redesenhar a linha muda a altura, e quem sabe empilhar é o thread.
    var onToggle: (() -> Void)?

    init(entry: ChatEntry) {
        bodyText = entry.text
        body = ChatStyle.paragraph(entry.text, font: ChatStyle.body, color: ChatStyle.dim)
        super.init(frame: .zero)

        let from = entry.author ?? "?"
        let to = entry.recipients.first ?? "?"
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: from, attributes: [
            .font: ChatStyle.name, .foregroundColor: AgentColor.of(from)]))
        line.append(NSAttributedString(string: "  →  ", attributes: [
            .font: ChatStyle.meta, .foregroundColor: ChatStyle.faint]))
        line.append(NSAttributedString(string: to, attributes: [
            .font: ChatStyle.name, .foregroundColor: AgentColor.of(to)]))
        line.append(NSAttributedString(string: "   \(entry.timeLabel)", attributes: [
            .font: ChatStyle.meta, .foregroundColor: ChatStyle.faint]))
        head.attributedStringValue = line
        head.isBordered = false
        head.drawsBackground = false
        head.isEditable = false

        caret.font = ChatStyle.meta
        caret.textColor = ChatStyle.faint
        caret.isBordered = false
        caret.drawsBackground = false
        caret.isEditable = false

        addSubview(caret)
        addSubview(head)
        body.isHidden = true
        addSubview(body)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func bodyWidth(_ width: CGFloat) -> CGFloat { max(80, width - 120) }

    override func height(for width: CGFloat) -> CGFloat {
        guard open else { return 20 }
        return 22 + ChatStyle.height(bodyText, font: ChatStyle.body, width: bodyWidth(width)) + 6
    }

    override func mouseDown(with event: NSEvent) {
        open.toggle()
        caret.stringValue = open ? "▾" : "▸"
        body.isHidden = !open
        onToggle?()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func layout() {
        super.layout()
        // Centrado: tráfego entre agentes não é fala de nenhum dos dois lados da
        // conversa, e alinhá-lo à esquerda o faria passar por resposta.
        let width = head.attributedStringValue.size().width
        let x = ((bounds.width - width) / 2).rounded()
        caret.frame = NSRect(x: max(0, x - 14), y: 3, width: 12, height: 13)
        head.frame = NSRect(x: x, y: 2, width: width, height: 15)
        if open {
            let inner = bodyWidth(bounds.width)
            body.frame = NSRect(x: (bounds.width - inner) / 2, y: 22, width: inner,
                                height: ChatStyle.height(bodyText, font: ChatStyle.body,
                                                         width: inner))
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

/// O CLI está pedindo permissão.
///
/// Sem botão de aprovar: o diálogo é desenhado pela TUI, e responder de fora é
/// injetar seta e Enter às cegas, sem saber em que opção o cursor está. Errar
/// nisso aprova o que você quis negar. O card leva você ao terminal, que é onde a
/// pergunta está escrita.
final class ChatApprovalRow: ChatRow {
    private let box = NSView()
    private let who: NSTextField
    private let what = NSTextField(labelWithString: "pede sua permissão para continuar")
    private let button = NSButton()

    var onReveal: (() -> Void)?

    init(agent: String) {
        who = ChatStyle.label(agent, font: ChatStyle.name, color: AgentColor.of(agent))
        super.init(frame: .zero)

        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.55).cgColor
        box.layer?.cornerRadius = 6
        addSubview(box)

        what.font = ChatStyle.body
        what.textColor = ChatStyle.text
        box.addSubview(who)
        box.addSubview(what)

        button.title = "Abrir o terminal"
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.target = self
        button.action = #selector(reveal)
        box.addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func reveal() { onReveal?() }

    override func height(for width: CGFloat) -> CGFloat { 62 }

    override func layout() {
        super.layout()
        let width = min(bounds.width, 480)
        box.frame = NSRect(x: ((bounds.width - width) / 2).rounded(), y: 0,
                           width: width, height: 54)
        who.frame = NSRect(x: 13, y: 10, width: who.measured, height: 14)
        what.frame = NSRect(x: 13, y: 28, width: width - 26, height: 16)
        let size = button.intrinsicContentSize
        button.frame = NSRect(x: width - size.width - 12, y: 12,
                              width: size.width, height: 24)
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

    /// Levar ao terminal de quem está pedindo permissão.
    var onReveal: ((String) -> Void)?

    /// Quanto o conteúdo cede embaixo para a caixa de escrever.
    ///
    /// O thread corre POR BAIXO do vidro — é isso que faz a caixa parecer flutuando,
    /// como o grid do canvas por baixo da barra (ADR-025). Mas a última mensagem não
    /// pode viver escondida ali, então a folga é somada ao fim do documento.
    var bottomInset: CGFloat = 0 {
        didSet { if bottomInset != oldValue { needsLayout = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = ChatStyle.threadBackground.cgColor

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Assinatura do que está desenhado. Remontar a cada leitura de transcript
    /// perderia a seleção de texto e o estado dos blocos abertos — e o laço lê a
    /// cada meio segundo.
    private var drawn: String = ""

    func show(_ entries: [ChatEntry], asking: [String]) {
        let signature = entries.map(\.id).joined(separator: ",") + "|" + asking.joined(separator: ",")
        guard signature != drawn else { return }
        let wasAtBottom = isAtBottom
        drawn = signature

        rows.forEach { $0.removeFromSuperview() }
        rows = entries.map { entry in
            switch entry.kind {
            case .user: return ChatUserRow(entry: entry) as ChatRow
            case .agent: return ChatAgentRow(entry: entry)
            case .link:
                let row = ChatLinkRow(entry: entry)
                row.onToggle = { [weak self] in self?.reflow() }
                return row
            case .system:
                return ChatSystemRow(text: entry.text,
                                     color: entry.alert ? .systemRed : ChatStyle.faint)
            case .approval:
                return ChatSystemRow(text: entry.text, color: .systemOrange)
            }
        }
        // Pedido de permissão vive no fim e não na ordem do tempo: é o que está
        // te travando agora, e no meio do histórico ele passa em branco.
        for agent in asking {
            let row = ChatApprovalRow(agent: agent)
            row.onReveal = { [weak self] in self?.onReveal?(agent) }
            rows.append(row)
        }
        rows.forEach { document.addSubview($0) }
        reflow()
        if wasAtBottom { scrollToBottom() }
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
        // A folga da caixa entra na conta: sem descontá-la o thread nunca se
        // consideraria no fim, e pararia de acompanhar mensagem nova.
        return visible.maxY >= document.bounds.height - bottomInset - 40
    }

    func scrollToBottom() {
        // Depois do laço de layout: rolar para uma altura que ainda vai mudar não
        // chega ao fim.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let height = document.bounds.height
            let visible = scroll.contentView.bounds.height
            document.scroll(NSPoint(x: 0, y: max(0, height - visible)))
        }
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
                                height: max(y + 12 + bottomInset,
                                            scroll.contentView.bounds.height))
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

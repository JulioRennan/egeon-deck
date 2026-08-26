import AppKit

// MARK: - Bolha de resposta do agente

/// O que o agente respondeu, na ordem em que fez: cabeçalho na cor dele e a
/// cadeia do turno — parágrafo, passo, passo, parágrafo, troca… — cada elo
/// uma linha, sem agrupar e sem recolher (ADR-039): o passo mostra comando,
/// diff e saída sempre — clique não esconde nada, porque esconder era perder
/// a leitura. Enquanto o turno corre, uma linha de status no fim diz o que
/// ele está fazendo agora.
final class AgentBubbleView: NSView, ThreadBubble {
    var onQuoteClick: (() -> Void)?
    private var quoteView: ChatQuoteView?

    /// O que a bolha diz que o agente está fazendo agora. `nil` é turno
    /// fechado — a bolha do histórico.
    enum Live: Equatable {
        case working
        case thinking
        case step(ChatStep)
        /// Permissão pedida no meio do turno: laranja, sem spinner — não há
        /// trabalho andando, há você para decidir.
        case asking

        var label: String {
            switch self {
            case .working:          return "trabalhando…"
            case .thinking:         return "pensando…"
            case .step(let step):   return "\(step.glyph) \(step.text)"
            case .asking:           return "precisa de você"
            }
        }
    }

    private let name = NSTextField(labelWithString: "")
    private let address = NSTextField(labelWithString: "")
    private let time = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")

    /// Um elo desenhado: prosa, ou um grupo de passos consecutivos.
    private enum Row {
        case text(NSTextField)
        case step(box: NSView, field: NSTextField)
        /// Bloco de código da prosa (```): a mesma caixa de um passo, com o
        /// realce pelo rótulo. Prosa colorida solta não lia como código.
        case code(box: NSView, field: NSTextField)
        /// Edição: o diff é uma sub-bolha própria na cadeia, sempre visível —
        /// recolher os passos não a esconde. É o que você quer ler, não
        /// bastidor.
        case diff(DiffView)
        case exchanges(box: NSView, rows: [ExchangeRow])
    }
    private var rows: [Row] = []
    private let live: Live?

    static let maxWidth: CGFloat = 660

    let alignsRight = false

    /// Azul do seu prompt — a cor do fio da citação quando o citado é você.
    static let youColor = NSColor(srgbRed: 0.184, green: 0.498, blue: 0.965, alpha: 1)

    init(from participant: ChatParticipant, turn: ChatTurn,
         quote: ChatQuote? = nil, live: Live? = nil) {
        self.live = live
        super.init(frame: .zero)
        decorate(color: participant.color)

        name.stringValue = "\(participant.glyph) \(participant.id)"
        name.textColor = participant.color
        address.stringValue = participant.address
        time.stringValue = live == nil ? Self.clock.string(from: turn.replyAt ?? turn.promptAt) : "agora"

        if let quote {
            let view = ChatQuoteView(quote: quote, authorLabel: "você → \(participant.id)",
                                     color: Self.youColor)
            view.onClick = { [weak self] in self?.onQuoteClick?() }
            addSubview(view)
            quoteView = view
        }

        rows = Self.group(turn.chain).flatMap { group -> [Row] in
            switch group {
            case .text(let text):
                return makeProseRows(text)
            case .step(let step):
                if let diff = step.diff, !diff.isEmpty {
                    let view = DiffView(file: step.text, diff: diff)
                    addSubview(view)
                    return [.diff(view)]
                }
                return [makeStepBox(step)]
            case .exchanges(let exchanges):
                return [makeExchangesBox(exchanges)]
            }
        }

        status.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        status.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        status.lineBreakMode = .byTruncatingMiddle
        status.isHidden = live == nil
        addSubview(status)
        tick()
    }

    /// A bolha de "digitando…": o agente está trabalhando e ainda não gravou
    /// nada do turno.
    convenience init(typing participant: ChatParticipant) {
        self.init(from: participant, turn: ChatTurn(id: "", prompt: "", promptAt: Date()),
                  live: .working)
    }

    /// Prosa e passo ficam cada um no seu lugar — passo NÃO agrupa: a
    /// sequência é o que se quer ler. Trocas seguidas viram uma caixa só —
    /// sempre aberta: são a própria conversa, não bastidor.
    private enum Group { case text(String), step(ChatStep), exchanges([ChatExchange]) }
    private static func group(_ chain: [ChatPart]) -> [Group] {
        var out: [Group] = []
        for part in chain {
            switch part {
            case .text(let text):
                out.append(.text(text))
            case .step(let step):
                out.append(.step(step))
            case .exchange(let exchange):
                if case .exchanges(var exchanges)? = out.last {
                    exchanges.append(exchange)
                    out[out.count - 1] = .exchanges(exchanges)
                } else {
                    out.append(.exchanges([exchange]))
                }
            }
        }
        return out
    }

    private func makeExchangesBox(_ exchanges: [ChatExchange]) -> Row {
        let box = FlippedBox()
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        box.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.22).cgColor
        let rows = exchanges.map { exchange -> ExchangeRow in
            let row = ExchangeRow(exchange: exchange)
            box.addSubview(row)
            return row
        }
        addSubview(box)
        return .exchanges(box: box, rows: rows)
    }

    /// A prosa em linhas: parágrafos, títulos e listas num campo só; cada
    /// bloco de código na sua caixa.
    private func makeProseRows(_ text: String) -> [Row] {
        var out: [Row] = []
        var run: [MarkdownLite.Block] = []
        func flush() {
            guard !run.isEmpty else { return }
            let field = NSTextField(wrappingLabelWithString: "")
            // Clicar numa label selecionável abre o field editor, e ao sair ele
            // devolvia o texto SEM atributos: a bolha perdia cor e fonte no clique.
            field.allowsEditingTextAttributes = true
            field.attributedStringValue = MarkdownLite.render(
                run, font: .systemFont(ofSize: 13.5), color: NSColor(calibratedWhite: 0.9, alpha: 1))
            addSubview(field)
            out.append(.text(field))
            run = []
        }
        for block in MarkdownLite.blocks(text) {
            if case .code(let language, let code) = block {
                flush()
                let box = FlippedBox()
                box.wantsLayer = true
                box.layer?.cornerRadius = 8
                box.layer?.borderWidth = 1
                box.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
                box.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.03).cgColor
                let field = NSTextField(wrappingLabelWithString: "")
                // Clicar numa label selecionável abre o field editor, e ao sair ele
                // devolvia o texto SEM atributos: a bolha perdia cor e fonte no clique.
                field.allowsEditingTextAttributes = true
                field.attributedStringValue = MarkdownLite.renderCode(
                    language, code, font: .monospacedSystemFont(ofSize: 12, weight: .regular))
                box.addSubview(field)
                addSubview(box)
                out.append(.code(box: box, field: field))
            } else {
                run.append(block)
            }
        }
        flush()
        return out
    }

    private func makeStepBox(_ step: ChatStep) -> Row {
        let box = FlippedBox()
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        box.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.03).cgColor
        let field = NSTextField(wrappingLabelWithString: "")
        // Clicar numa label selecionável abre o field editor, e ao sair ele
        // devolvia o texto SEM atributos: a bolha perdia cor e fonte no clique.
        field.allowsEditingTextAttributes = true
        field.attributedStringValue = Self.render(step)
        box.addSubview(field)
        addSubview(box)
        return .step(box: box, field: field)
    }

    /// Um passo como o terminal o mostra: a linha, o comando por extenso, o
    /// diff com `+` verde e `-` vermelho, a saída recuada com `⎿`. Recolhido,
    /// só a linha — com `+a −b` e o tamanho da saída para não perder a conta.
    static func render(_ step: ChatStep, expanded: Bool = true) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let title = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let small = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let dim = NSColor(calibratedWhite: 0.5, alpha: 1)
        let removed = NSColor(calibratedRed: 0.9, green: 0.45, blue: 0.45, alpha: 1)
        func line(_ text: String, _ font: NSFont, _ color: NSColor) {
            if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: [.font: small])) }
            out.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }
        var head = "\(step.glyph)  \(step.text)"
        if !expanded {
            if let counts = step.diffCounts { head += "  +\(counts.added) −\(counts.removed)" }
            if let output = step.output {
                let n = output.split(separator: "\n").count
                head += "  ⎿ \(n) linha\(n == 1 ? "" : "s")"
            }
        }
        line(head, title, step.isError ? removed : NSColor(calibratedWhite: 0.7, alpha: 1))
        guard expanded else { return out }
        if let detail = step.detail {
            for l in detail.split(separator: "\n", omittingEmptySubsequences: false) { line("   \(l)", small, dim) }
        }
        if let output = step.output {
            // A saída de `cat x.json` é JSON: a linguagem vem do arquivo citado
            // no comando, nunca do texto (ADR-041). Erro fica todo vermelho.
            let language = step.isError ? .plain : Language.detect(inCommand: step.detail ?? step.text)
            for (i, l) in output.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: [.font: small])) }
                let color = step.isError ? removed : dim
                out.append(NSAttributedString(string: "   \(i == 0 ? "⎿ " : "  ")",
                                              attributes: [.font: small, .foregroundColor: color]))
                out.append(CodePalette.attributed(String(l), language: language, font: small,
                                                  base: step.isError ? removed : NSColor(calibratedWhite: 0.62, alpha: 1)))
            }
        }
        return out
    }

    /// Só a linha de status tem o que animar; o resto ignora o tique.
    func tick() {
        guard let live else { return }
        if case .asking = live {
            status.stringValue = "● \(live.label)"
            status.textColor = Activity.asking.color
            return
        }
        status.textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        status.stringValue = "\(Spinner.current) \(live.label)"
    }

    private func decorate(color: NSColor) {
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor(srgbRed: 0.075, green: 0.094, blue: 0.149,
                                         alpha: 0.92).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = color.withAlphaComponent(0.38).cgColor
        name.font = .systemFont(ofSize: 13, weight: .bold)
        address.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        address.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        time.font = .systemFont(ofSize: 10.5)
        time.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        [name, address, time].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    /// Clicar na resposta leva ao prompt original, como no WhatsApp — a bolha
    /// inteira, não só a citação.
    override func mouseDown(with event: NSEvent) { onQuoteClick?() }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: Medidas


    /// Pela célula, não pelo `boundingRect` da string: o campo quebra linha
    /// numa largura interna menor (padding da célula), e com fontes misturadas
    /// — negrito, mono — a diferença virava uma linha a menos, cortada.
    private static func measure(_ field: NSTextField, width: CGFloat) -> CGFloat {
        guard let cell = field.cell else { return 0 }
        return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width,
                                                    height: .greatestFiniteMagnitude)).height)
    }

    private func rowHeight(_ row: Row, width: CGFloat) -> CGFloat {
        switch row {
        case .text(let field):          return Self.measure(field, width: width - 26)
        case .step(_, let field), .code(_, let field):
            return Self.measure(field, width: width - 26 - 20) + 12
        case .diff(let view):           return view.height
        case .exchanges(_, let rows):   return exchangesHeight(rows, width: width)
        }
    }

    private var quoteBlock: CGFloat { quoteView == nil ? 0 : ChatQuoteView.height + 8 }
    private var statusBlock: CGFloat { live == nil ? 0 : 8 + 14 }

    private func exchangesHeight(_ rows: [ExchangeRow], width: CGFloat) -> CGFloat {
        rows.reduce(8) { $0 + $1.height(for: width - 26 - 20) + 6 }
    }

    func height(for width: CGFloat) -> CGFloat {
        var total: CGFloat = 10 + 16 + quoteBlock
        for row in rows { total += 8 + rowHeight(row, width: width) }
        return total + statusBlock + 12
    }

    func width(for available: CGFloat) -> CGFloat {
        // Com diff, a bolha abre até a largura da thread: lado a lado em 660
        // deixa cada metade com 300 px, e a linha que mudou é justamente a
        // que fica cortada.
        let hasDiff = rows.contains { if case .diff = $0 { return true } else { return false } }
        let cap = min(available, hasDiff ? available : Self.maxWidth)
        var textWidth: CGFloat = 0
        for row in rows {
            switch row {
            case .text(let field):
                textWidth = max(textWidth, ceil(field.attributedStringValue
                    .boundingRect(with: NSSize(width: cap - 34, height: .infinity),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading]).width) + 34)
            case .step, .code:
                // Passo tem comando e saída: quer a largura toda.
                textWidth = cap
            case .diff:
                // Lado a lado precisa de largura: sempre a toda.
                textWidth = cap
            case .exchanges:
                // Sub-conversa é leitura: ocupa a largura toda que a bolha pode ter.
                textWidth = cap
            }
        }
        let headerWidth = name.intrinsicContentSize.width + address.intrinsicContentSize.width
            + time.intrinsicContentSize.width + 50
        let quoteMin: CGFloat = quoteView == nil ? 0 : 300
        let statusMin: CGFloat = live == nil ? 0 : min(cap, status.intrinsicContentSize.width + 34)
        return min(cap, max(textWidth, headerWidth, quoteMin, statusMin))
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 10
        let nameWidth = name.intrinsicContentSize.width
        name.frame = NSRect(x: 13, y: y, width: nameWidth, height: 16)
        address.frame = NSRect(x: 13 + nameWidth + 8, y: y + 2,
                               width: address.intrinsicContentSize.width, height: 13)
        let timeWidth = time.intrinsicContentSize.width
        time.frame = NSRect(x: bounds.width - timeWidth - 13, y: y + 2,
                            width: timeWidth, height: 13)
        y += 16

        if let quoteView {
            y += 8
            quoteView.frame = NSRect(x: 13, y: y, width: bounds.width - 26,
                                     height: ChatQuoteView.height)
            y += ChatQuoteView.height
        }

        for row in rows {
            y += 8
            let height = rowHeight(row, width: bounds.width)
            switch row {
            case .text(let field):
                field.frame = NSRect(x: 13, y: y, width: bounds.width - 26, height: height)
            case .step(let box, let field), .code(let box, let field):
                box.frame = NSRect(x: 13, y: y, width: bounds.width - 26, height: height)
                field.frame = NSRect(x: 10, y: 6, width: box.bounds.width - 20, height: height - 12)
            case .diff(let view):
                view.frame = NSRect(x: 13, y: y, width: bounds.width - 26, height: height)
            case .exchanges(let box, let exchangeRows):
                box.frame = NSRect(x: 13, y: y, width: bounds.width - 26, height: height)
                var rowY: CGFloat = 8
                let rowWidth = box.bounds.width - 20
                for row in exchangeRows {
                    let rowHeight = row.height(for: rowWidth)
                    row.frame = NSRect(x: 10, y: rowY, width: rowWidth, height: rowHeight)
                    rowY += rowHeight + 6
                }
            }
            y += height
        }

        if live != nil {
            y += 8
            status.frame = NSRect(x: 13, y: y, width: bounds.width - 26, height: 14)
        }
    }
}

// MARK: - Uma troca entre agentes

/// Uma linha da sub-conversa: "⇄ front → back · 14:24 · 3 passos", o texto que
/// foi, e — se o destino não é o dono da bolha — o que ele anotou ao atender.
final class ExchangeRow: NSView {
    private let header = NSTextField(labelWithString: "")
    private let text = NSTextField(wrappingLabelWithString: "")
    private let note = NSTextField(wrappingLabelWithString: "")
    private let bar = NSView()
    private let hasNote: Bool

    init(exchange: ChatExchange) {
        hasNote = !exchange.note.isEmpty
        super.init(frame: .zero)
        let color = AgentPalette.color(for: exchange.fromId)

        bar.wantsLayer = true
        bar.layer?.backgroundColor = color.withAlphaComponent(0.8).cgColor
        bar.layer?.cornerRadius = 1.5
        addSubview(bar)

        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        var title = "⇄ \(exchange.fromId) → \(exchange.toId) · \(clock.string(from: exchange.at))"
        if exchange.steps > 0 { title += " · \(exchange.steps) passo\(exchange.steps == 1 ? "" : "s")" }
        header.stringValue = title
        header.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        header.textColor = color
        addSubview(header)

        // Clicar numa label selecionável abre o field editor, e ao sair ele
        // devolvia o texto SEM atributos: a bolha perdia cor e fonte no clique.
        text.allowsEditingTextAttributes = true
        text.attributedStringValue = MarkdownLite.render(
            exchange.text, font: .systemFont(ofSize: 12.5), color: NSColor(calibratedWhite: 0.87, alpha: 1))
        addSubview(text)

        // Clicar numa label selecionável abre o field editor, e ao sair ele
        // devolvia o texto SEM atributos: a bolha perdia cor e fonte no clique.
        note.allowsEditingTextAttributes = true
        note.attributedStringValue = MarkdownLite.render(
            "↳ " + exchange.note, font: .systemFont(ofSize: 11.5), color: NSColor(calibratedWhite: 0.55, alpha: 1))
        note.isHidden = !hasNote
        addSubview(note)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private func measure(_ field: NSTextField, width: CGFloat) -> CGFloat {
        guard let cell = field.cell else { return 0 }
        return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 12,
                                                    height: .greatestFiniteMagnitude)).height)
    }

    func height(for width: CGFloat) -> CGFloat {
        var total: CGFloat = 16 + 4 + measure(text, width: width)
        if hasNote { total += 4 + measure(note, width: width) }
        return total + 4
    }

    override func layout() {
        super.layout()
        bar.frame = NSRect(x: 0, y: 2, width: 3, height: bounds.height - 4)
        header.frame = NSRect(x: 12, y: 0, width: bounds.width - 12, height: 15)
        let textHeight = measure(text, width: bounds.width)
        text.frame = NSRect(x: 12, y: 20, width: bounds.width - 12, height: textHeight)
        if hasNote {
            note.frame = NSRect(x: 12, y: 24 + textHeight, width: bounds.width - 12,
                                height: measure(note, width: bounds.width))
        }
    }
}

/// O que a thread empilha: mede a si mesma e diz de que lado fica.
protocol ThreadBubble: NSView {
    var alignsRight: Bool { get }
    func width(for available: CGFloat) -> CGFloat
    func height(for width: CGFloat) -> CGFloat
}

private final class FlippedBox: NSView {
    override var isFlipped: Bool { true }
}

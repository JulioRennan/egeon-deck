import AppKit

// MARK: - Medidas das linhas da thread

/// Altura da linha, largura da bolha a que ela pertence e o texto já
/// renderizado (markdown, realce): medido na fila de fundo, a linha só o
/// mostra — não refaz nada na main. O texto fica fora da igualdade: se o
/// conteúdo mudou, o `ChatBlock` já mudou.
struct ChatRowMetrics: Equatable {
    let height: CGFloat
    let bubbleWidth: CGFloat
    let text: NSAttributedString?

    init(height: CGFloat, bubbleWidth: CGFloat, text: NSAttributedString? = nil) {
        self.height = height
        self.bubbleWidth = bubbleWidth
        self.text = text
    }

    static func == (a: ChatRowMetrics, b: ChatRowMetrics) -> Bool {
        a.height == b.height && a.bubbleWidth == b.bubbleWidth
    }
}

/// O texto de cada linha e a medida dela, com TextKit próprio — sem view.
/// Roda na fila de fundo da thread: a tabela só lê o cache no `heightOfRow`
/// (ADR-042). A linha desenha com o MESMO TextKit (container sem folga,
/// inset zero), para a altura medida ser a altura desenhada.
enum ChatBlockLayout {
    static let gap: CGFloat = 12
    static let sideInset: CGFloat = 18
    static let textInset: CGFloat = 13
    static let agentMaxWidth: CGFloat = 660
    static let promptMaxWidth: CGFloat = 560
    static let quoteHeight: CGFloat = 52
    static let boxPadding: CGFloat = 6
    static let rowGap: CGFloat = 8
    static let headerHeight: CGFloat = 16
    static let statusHeight: CGFloat = 14
    static let timeHeight: CGFloat = 13
    /// `intrinsicContentSize` arredonda para baixo e o rótulo corta o último
    /// glifo ("fron|t"); a folga garante que o texto nunca perde a borda.
    static let labelSlack: CGFloat = 4

    static let proseFont = NSFont.systemFont(ofSize: 13.5)
    static let proseColor = NSColor(calibratedWhite: 0.9, alpha: 1)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let nameFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    static let addressFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
    static let timeFont = NSFont.systemFont(ofSize: 10.5)
    static let statusFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)

    /// Azul do seu prompt — a cor do fio da citação quando o citado é você.
    static let youColor = NSColor(srgbRed: 0.184, green: 0.498, blue: 0.965, alpha: 1)

    /// "14:02" — `FormatStyle` é valor, seguro em qualquer fila; `DateFormatter` não.
    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    // MARK: Texto

    /// O corpo de texto da linha, quando ela tem um. Cabeçalho, status e diff
    /// desenham por conta própria.
    static func attributed(_ kind: ChatBlock.Kind) -> NSAttributedString? {
        switch kind {
        case .prompt(let to, let from, let text, _, _, _, let mention):
            return prompt(text, to: to, from: from, mention: mention)
        case .prose(_, let blocks):
            return MarkdownLite.render(blocks, font: proseFont, color: proseColor)
        case .code(_, let language, let code):
            return MarkdownLite.renderCode(language, code, font: codeFont)
        case .step(_, let step, let expanded):
            return render(step, expanded: expanded)
        case .header, .diff, .status, .typing:
            return nil
        }
    }

    /// Como no WhatsApp: quem mandou em cima (quando não foi você), e — só
    /// quando a mensagem não é contínua — a menção `@destinatário` na cor dele
    /// no começo do texto. Um marcando o outro; sem seta.
    static func prompt(_ text: String, to: ChatParticipant, from: String?,
                       mention: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        if let from {
            out.append(NSAttributedString(
                string: "✦ \(from)\n",
                attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .bold),
                             .foregroundColor: AgentPalette.color(for: from)]))
        }
        if mention {
            out.append(NSAttributedString(
                string: "@\(to.id) ",
                attributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                             .foregroundColor: to.color]))
        }
        out.append(NSAttributedString(
            string: text,
            attributes: [.font: proseFont, .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1)]))
        return out
    }

    /// Um passo como o terminal o mostra: a linha, o comando por extenso, a
    /// saída recuada com `⎿`. Recolhido, só a linha — com `+a −b` e o tamanho
    /// da saída para não perder a conta — e o chevron avisa que há o que abrir.
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
        if step.isExpandable {
            out.append(NSAttributedString(string: expanded ? "▾ " : "▸ ",
                                          attributes: [.font: title, .foregroundColor: dim]))
        }
        out.append(NSAttributedString(
            string: "\(step.glyph)  \(step.text)",
            attributes: [.font: title,
                         .foregroundColor: step.isError ? removed : NSColor(calibratedWhite: 0.7, alpha: 1)]))
        if !expanded {
            var summary = ""
            if let counts = step.diffCounts { summary += "  +\(counts.added) −\(counts.removed)" }
            if let output = step.output {
                let n = output.split(separator: "\n").count
                summary += "  ⎿ \(n) linha\(n == 1 ? "" : "s")"
            }
            out.append(NSAttributedString(string: summary, attributes: [.font: title, .foregroundColor: dim]))
        }
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

    /// O texto da linha de status: spinner (ou ● laranja) e o que está fazendo.
    static func status(_ live: ChatLive, spinner: Character) -> String {
        if case .asking = live { return "● \(live.label)" }
        return "\(spinner) \(live.label)"
    }

    // MARK: Medida

    /// Tamanho de um texto numa largura, com TextKit avulso — o mesmo
    /// arranjo (sem folga de fragmento, sem inset) que a linha usa ao desenhar.
    static func size(of text: NSAttributedString, width: CGFloat) -> NSSize {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        // Layout em segundo plano é para NSTextView na tela; aqui é medir e
        // descartar, numa fila que não é a main.
        manager.backgroundLayoutEnabled = false
        let container = NSTextContainer(size: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        return NSSize(width: ceil(used.width), height: ceil(used.height))
    }

    /// Medidas de todas as linhas para uma largura de thread. A bolha é medida
    /// inteira (a largura dela é a da linha mais larga), e só a bolha que
    /// mudou — ou cuja largura mudou — é medida de novo; `known` são as
    /// medidas da montagem anterior, por bolha.
    static func measure(_ blocks: [ChatBlock], width available: CGFloat,
                        known: [String: BubbleMetrics]) -> [String: BubbleMetrics] {
        var out: [String: BubbleMetrics] = [:]
        var index = 0
        while index < blocks.count {
            let key = blocks[index].messageKey
            var end = index
            while end < blocks.count, blocks[end].messageKey == key { end += 1 }
            let bubble = Array(blocks[index..<end])
            if let cached = known[key], cached.width == available, cached.blocks == bubble {
                out[key] = cached
            } else {
                out[key] = BubbleMetrics(width: available, blocks: bubble,
                                         rows: measureBubble(bubble, available: available))
            }
            index = end
        }
        return out
    }

    /// As medidas de uma bolha: para que largura valem, de que linhas são, e
    /// a medida de cada linha por id.
    struct BubbleMetrics: Equatable {
        let width: CGFloat
        let blocks: [ChatBlock]
        let rows: [String: ChatRowMetrics]
    }

    private static func measureBubble(_ bubble: [ChatBlock], available: CGFloat) -> [String: ChatRowMetrics] {
        let inner = max(0, available - sideInset * 2)
        guard let head = bubble.first else { return [:] }

        if case .prompt(_, _, _, _, let quote, _, _) = head.kind {
            let cap = min(inner, promptMaxWidth)
            let text = attributed(head.kind) ?? NSAttributedString()
            let natural = size(of: text, width: cap - textInset * 2)
            let width = min(cap, max(natural.width + textInset * 2 + labelSlack, quote == nil ? 0 : 300, 90))
            let height = size(of: text, width: width - textInset * 2).height
            let quoteBlock = quote == nil ? 0 : quoteHeight + 8
            return [head.id: ChatRowMetrics(height: 10 + quoteBlock + height + 4 + timeHeight + 9 + gap,
                                            bubbleWidth: width, text: text)]
        }

        // Bolha de agente: com diff abre até a largura da thread — lado a lado
        // em 660 deixa cada metade com 300 px, e a linha que mudou é justamente
        // a que fica cortada. Sem diff, a largura da linha mais larga, até 660.
        let hasDiff = bubble.contains { if case .diff = $0.kind { return true } else { return false } }
        let cap = hasDiff ? inner : min(inner, agentMaxWidth)
        var width: CGFloat = 0
        var texts: [String: NSAttributedString] = [:]
        for block in bubble {
            switch block.kind {
            case .header(let from, let at, let quote):
                let name = size(of: NSAttributedString(string: "\(from.glyph) \(from.id)", attributes: [.font: nameFont]), width: cap).width
                let address = size(of: NSAttributedString(string: from.address, attributes: [.font: addressFont]), width: cap).width
                let time = size(of: NSAttributedString(string: at.map(clock) ?? "agora", attributes: [.font: timeFont]), width: cap).width
                width = max(width, name + address + time + 50 + labelSlack * 3, quote == nil ? 0 : 300)
            case .typing(let from):
                let name = size(of: NSAttributedString(string: "\(from.glyph) \(from.id)", attributes: [.font: nameFont]), width: cap).width
                let address = size(of: NSAttributedString(string: from.address, attributes: [.font: addressFont]), width: cap).width
                let time = size(of: NSAttributedString(string: "agora", attributes: [.font: timeFont]), width: cap).width
                width = max(width, name + address + time + 50 + labelSlack * 3)
            case .prose, .step, .code:
                let text = attributed(block.kind) ?? NSAttributedString()
                texts[block.id] = text
                let natural = size(of: text, width: cap - textInset * 2).width
                width = max(width, natural + textInset * 2 + (isBoxed(block.kind) ? boxPadding * 2 + 8 : 0))
            case .diff:
                width = cap
            case .status(_, let live):
                let text = size(of: NSAttributedString(string: status(live, spinner: "⠋"), attributes: [.font: statusFont]), width: cap).width
                width = max(width, min(cap, text + textInset * 2 + 8))
            case .prompt: break
            }
        }
        width = min(cap, width)

        var rows: [String: ChatRowMetrics] = [:]
        for block in bubble {
            var height: CGFloat
            switch block.kind {
            case .header(_, _, let quote):
                height = 10 + headerHeight + (quote == nil ? 0 : 8 + quoteHeight)
            case .prose:
                height = rowGap + size(of: texts[block.id]!, width: width - textInset * 2).height
            case .step, .code:
                let inner = width - textInset * 2 - 20
                height = rowGap + size(of: texts[block.id]!, width: inner).height + boxPadding * 2
            case .diff(_, _, let diff):
                height = rowGap + DiffView.height(diff: diff)
            case .status:
                height = rowGap + statusHeight
            case .typing:
                height = 10 + headerHeight + rowGap + statusHeight
            case .prompt:
                height = 0
            }
            if block.last { height += 12 + gap }
            rows[block.id] = ChatRowMetrics(height: height, bubbleWidth: width, text: texts[block.id])
        }
        return rows
    }

    /// Passo e bloco de código ficam numa caixa dentro da bolha.
    static func isBoxed(_ kind: ChatBlock.Kind) -> Bool {
        switch kind {
        case .step, .code: return true
        default: return false
        }
    }
}

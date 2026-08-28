import AppKit

// MARK: - O diff de uma edição, lado a lado

/// Desenha o diff como o GitHub em modo split: antes à esquerda, depois à
/// direita, gutter com o número de linha de cada versão, fundo vermelho no
/// que saiu e verde no que entrou, cabeçalho com o arquivo e `+a −b`. Tudo
/// em `draw(_:)`, sem uma view por linha: um diff de 200 linhas dentro de
/// uma thread com dezenas de bolhas não pode custar 400 subviews.
final class DiffView: NSView {
    private let file: String
    private let language: Language
    private let hunks: [DiffHunk]
    private let rows: [[DiffHunk.Row]]

    private static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let headerFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
    private static let rowHeight: CGFloat = 18
    static let headerHeight: CGFloat = 24
    private static let hunkHeight: CGFloat = 16
    private static let gutter: CGFloat = 36

    private static let added = NSColor(calibratedRed: 0.26, green: 0.82, blue: 0.49, alpha: 1)
    private static let removed = NSColor(calibratedRed: 0.94, green: 0.39, blue: 0.39, alpha: 1)

    init(file: String, diff: [String]) {
        self.file = file
        language = Language.detect(path: file)
        hunks = DiffHunk.parse(diff)
        rows = hunks.map(\.rows)
        super.init(frame: .zero)
        wantsLayer = true
        // A mesma moldura da caixa de trocas: é sub-bolha, não passo.
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.22).cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    var height: CGFloat { Self.height(rows: rows) }

    /// A altura sem a view: quem mede a thread fora da main precisa dela
    /// antes de existir uma view.
    static func height(diff: [String]) -> CGFloat {
        height(rows: DiffHunk.parse(diff).map(\.rows))
    }

    private static func height(rows: [[DiffHunk.Row]]) -> CGFloat {
        headerHeight + rows.reduce(0) { $0 + hunkHeight + CGFloat($1.count) * rowHeight }
    }

    private var counts: (added: Int, removed: Int) {
        let all = hunks.flatMap(\.lines)
        return (all.filter { $0.kind == .added }.count, all.filter { $0.kind == .removed }.count)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let width = bounds.width
        let half = floor(width / 2)

        // Cabeçalho: arquivo à esquerda, contagem à direita.
        NSColor(calibratedWhite: 1, alpha: 0.05).setFill()
        NSRect(x: 0, y: 0, width: width, height: Self.headerHeight).fill()
        draw("±  \(file)", at: NSPoint(x: 10, y: 5), font: Self.headerFont,
             color: NSColor(calibratedWhite: 0.85, alpha: 1), maxWidth: width - 120)
        let counts = self.counts
        let summary = NSMutableAttributedString()
        summary.append(NSAttributedString(string: "+\(counts.added) ", attributes: [
            .font: Self.headerFont, .foregroundColor: Self.added]))
        summary.append(NSAttributedString(string: "−\(counts.removed)", attributes: [
            .font: Self.headerFont, .foregroundColor: Self.removed]))
        summary.draw(at: NSPoint(x: width - summary.size().width - 10, y: 5))

        var y = Self.headerHeight
        for (index, hunk) in hunks.enumerated() {
            // Faixa do trecho, como o `@@` do GitHub: diz onde estamos no arquivo.
            NSColor(calibratedRed: 0.3, green: 0.5, blue: 0.9, alpha: 0.12).setFill()
            NSRect(x: 0, y: y, width: width, height: Self.hunkHeight).fill()
            let label: String
            if let o = hunk.oldStart, let n = hunk.newStart { label = "@@ −\(o) +\(n) @@" }
            else { label = "@@" }
            draw(label, at: NSPoint(x: 10, y: y + 1), font: Self.font,
                 color: NSColor(calibratedRed: 0.55, green: 0.7, blue: 1, alpha: 0.9), maxWidth: width)
            y += Self.hunkHeight

            for row in rows[index] {
                drawCell(row.left, x: 0, width: half, y: y)
                drawCell(row.right, x: half, width: width - half, y: y)
                y += Self.rowHeight
            }
        }

        // Divisória entre os lados.
        NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
        NSRect(x: half - 0.5, y: Self.headerHeight, width: 1, height: bounds.height - Self.headerHeight).fill()
    }

    private func drawCell(_ cell: DiffHunk.Cell?, x: CGFloat, width: CGFloat, y: CGFloat) {
        let rect = NSRect(x: x, y: y, width: width, height: Self.rowHeight)
        guard let cell else {
            // Lado sem linha: mais escuro, para o olho ver o buraco.
            NSColor(calibratedWhite: 0, alpha: 0.18).setFill()
            rect.fill()
            return
        }
        let textColor: NSColor
        switch cell.kind {
        case .added:
            Self.added.withAlphaComponent(0.13).setFill(); rect.fill()
            Self.added.withAlphaComponent(0.35).setFill()
            NSRect(x: x, y: y, width: Self.gutter, height: Self.rowHeight).fill()
            textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        case .removed:
            Self.removed.withAlphaComponent(0.13).setFill(); rect.fill()
            Self.removed.withAlphaComponent(0.35).setFill()
            NSRect(x: x, y: y, width: Self.gutter, height: Self.rowHeight).fill()
            textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        case .context:
            textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        case .note:
            textColor = NSColor(calibratedWhite: 0.5, alpha: 1)
        }
        if let number = cell.number {
            let label = "\(number)"
            let size = (label as NSString).size(withAttributes: [.font: Self.font])
            draw(label, at: NSPoint(x: x + Self.gutter - size.width - 6, y: y + 2), font: Self.font,
                 color: NSColor(calibratedWhite: 0.5, alpha: 1), maxWidth: Self.gutter)
        }
        let mark = cell.kind == .added ? "+" : cell.kind == .removed ? "−" : " "
        draw(mark, at: NSPoint(x: x + Self.gutter + 4, y: y + 2), font: Self.font, color: textColor, maxWidth: 12)
        if cell.kind == .note {
            draw(cell.text, at: NSPoint(x: x + Self.gutter + 16, y: y + 2), font: Self.font,
                 color: textColor, maxWidth: width - Self.gutter - 22)
        } else {
            drawTokens(cell.text, at: NSPoint(x: x + Self.gutter + 16, y: y + 2), base: textColor,
                       maxWidth: width - Self.gutter - 22)
        }
    }

    /// Desenha token a token, sem quebrar linha; o que não cabe vira `…`.
    private func drawTokens(_ text: String, at point: NSPoint, base: NSColor, maxWidth: CGFloat) {
        let ellipsis = ("…" as NSString).size(withAttributes: [.font: Self.font]).width
        var x = point.x
        let limit = point.x + maxWidth
        for token in SyntaxLite.tokens(text, language: language) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Self.font, .foregroundColor: CodePalette.color(for: token.kind, base: base)]
            let piece = token.text as NSString
            let width = piece.size(withAttributes: attributes).width
            if x + width > limit - ellipsis {
                // Corta o token no que couber e fecha com reticências.
                var kept = ""
                for char in token.text {
                    let next = kept + String(char)
                    if x + (next as NSString).size(withAttributes: attributes).width > limit - ellipsis { break }
                    kept = next
                }
                (kept as NSString).draw(at: NSPoint(x: x, y: point.y), withAttributes: attributes)
                x += (kept as NSString).size(withAttributes: attributes).width
                ("…" as NSString).draw(at: NSPoint(x: x, y: point.y),
                                        withAttributes: [.font: Self.font, .foregroundColor: base])
                return
            }
            piece.draw(at: NSPoint(x: x, y: point.y), withAttributes: attributes)
            x += width
        }
    }

    /// Uma linha, cortada com `…` no fim: o diff não quebra linha, como no
    /// GitHub — quebrar desalinharia os dois lados.
    private func draw(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, maxWidth: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        (text as NSString).draw(in: NSRect(x: point.x, y: point.y, width: max(0, maxWidth), height: Self.rowHeight),
                                withAttributes: attributes)
    }
}

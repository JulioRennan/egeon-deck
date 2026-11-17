import AppKit

/// O cronômetro da bancada como texto com ícone, o mesmo na barra de cima e na
/// linha da barra lateral (ADR-074).
///
/// Ícone do SF Symbols, e não glifo de fonte: `▶ ● ✕` em 10pt se confundiam
/// com o badge de atividade da barra lateral, que usa as mesmas bolinhas.
enum WorkbenchClockText {
    private static let entries: [(WorkbenchClock.Phase, String, NSColor)] = [
        // Ciano e não verde: verde no app é "terminou" (a bolinha e a borda).
        (.running, "hammer.fill", NSColor(srgbRed: 0.25, green: 0.85, blue: 1, alpha: 1)),
        (.waiting, "hand.raised.fill", NSColor(srgbRed: 1, green: 0.62, blue: 0.1, alpha: 1)),
        (.failed, "xmark.octagon", NSColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1)),
    ]

    /// Cor cheia nas três — apagadas, viravam cinza sobre o fundo escuro e não
    /// se distinguiam. As fases em curso se destacam pelo peso.
    static func attributed(_ clock: WorkbenchClock, phases: Set<WorkbenchClock.Phase>,
                           size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (index, (key, symbol, color)) in entries.enumerated() {
            let lit = phases.contains(key)
            let tint = color.withAlphaComponent(lit ? 1 : 0.8)
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: lit ? .bold : .medium)
            if index > 0 { out.append(NSAttributedString(string: "   ", attributes: [.font: font])) }
            if let icon = icon(symbol, color: tint, size: size, font: font) { out.append(icon) }
            out.append(NSAttributedString(string: " " + WorkbenchClock.format(clock[key]),
                                          attributes: [.font: font, .foregroundColor: tint]))
        }
        return out
    }

    static func tooltip(_ clock: WorkbenchClock) -> String {
        "rodando \(WorkbenchClock.format(clock.running)) · esperando você "
            + "\(WorkbenchClock.format(clock.waiting)) · em erro \(WorkbenchClock.format(clock.failed))"
    }

    /// Chave para não redesenhar a cada tique do spinner o que não mudou.
    static func signature(_ clock: WorkbenchClock, phases: Set<WorkbenchClock.Phase>) -> String {
        [clock.running, clock.waiting, clock.failed].map(WorkbenchClock.format).joined(separator: "/")
            + "/" + phases.map(\.rawValue).sorted().joined(separator: "+")
    }

    private static func icon(_ name: String, color: NSColor, size: CGFloat, font: NSFont) -> NSAttributedString? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Centrado na altura das maiúsculas: na linha de base o ícone fica
        // pendurado abaixo dos números.
        let height = image.size.height
        attachment.bounds = NSRect(x: 0, y: ((font.capHeight - height) / 2).rounded(),
                                   width: image.size.width, height: height)
        return NSAttributedString(attachment: attachment)
    }
}

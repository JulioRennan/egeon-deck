import AppKit

// MARK: - A coluna de participantes

/// O lado esquerdo do chat: quem está na bancada, com papel e estado ao vivo.
/// Clique escolhe para quem o composer fala.
final class ParticipantsColumn: NSView {
    var onPick: ((ChatParticipant) -> Void)?

    private let agentsTitle = NSTextField(labelWithString: "AGENTES")
    private let shellsTitle = NSTextField(labelWithString: "TERMINAIS")
    private let hint = NSTextField(labelWithString: "Clique foca · Tab alterna entre agentes")
    private var agentRows: [ParticipantRow] = []
    private var shellRows: [ParticipantRow] = []
    private var rows: [ParticipantRow] { agentRows + shellRows }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.045).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.09).cgColor

        for title in [agentsTitle, shellsTitle] {
            title.font = .systemFont(ofSize: 10, weight: .semibold)
            title.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
            addSubview(title)
        }

        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        addSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    private var signature = ""

    func tick() { rows.forEach { $0.tick() } }

    func update(_ participants: [ChatParticipant], focused: String?) {
        // Remontar a cada segundo piscava e pesava; só quando algo que se
        // desenha mudou. O spinner anda em cima da linha que já existe.
        let next = participants.map { "\($0.id)|\($0.activity)|\($0.role ?? "")" }
            .joined(separator: ";") + "|\(focused ?? "")"
        guard next != signature else { return }
        signature = next

        rows.forEach { $0.removeFromSuperview() }
        func make(_ list: [ChatParticipant]) -> [ParticipantRow] {
            list.map { participant in
                let row = ParticipantRow(participant: participant,
                                         focused: participant.id == focused)
                row.onClick = { [weak self] in self?.onPick?(participant) }
                addSubview(row)
                return row
            }
        }
        // Duas seções: agente se conversa, terminal se olha e manda comando.
        agentRows = make(participants.filter(\.isAgent))
        shellRows = make(participants.filter { !$0.isAgent })
        shellsTitle.isHidden = shellRows.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        agentsTitle.frame = NSRect(x: 14, y: 12, width: bounds.width - 28, height: 13)
        var y: CGFloat = 34
        for row in agentRows {
            row.frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: 44)
            y += 47
        }
        if !shellRows.isEmpty {
            y += 10
            shellsTitle.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: 13)
            y += 22
            for row in shellRows {
                row.frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: 44)
                y += 47
            }
        }
        hint.frame = NSRect(x: 14, y: bounds.height - 26,
                            width: bounds.width - 28, height: 14)
    }
}

// MARK: - Uma linha

private final class ParticipantRow: NSView {
    var onClick: (() -> Void)?
    private let dead: Bool

    init(participant: ChatParticipant, focused: Bool) {
        dead = participant.activity == .dead
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        if focused {
            layer?.borderWidth = 1
            layer?.borderColor = participant.color.withAlphaComponent(0.45).cgColor
            layer?.backgroundColor = participant.color.withAlphaComponent(0.06).cgColor
        }

        if participant.isAgent {
            let glyph = NSTextField(labelWithString: participant.glyph)
            glyph.font = .systemFont(ofSize: 13)
            glyph.textColor = participant.color
            glyph.frame = NSRect(x: 10, y: 14, width: 16, height: 16)
            addSubview(glyph)
        } else {
            // Terminal tem ícone de terminal — o glifo de prompt confundia com
            // um agente de cor cinza.
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "terminal")?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            icon.contentTintColor = participant.color
            icon.imageScaling = .scaleNone
            icon.frame = NSRect(x: 8, y: 13, width: 20, height: 18)
            addSubview(icon)
        }

        let name = NSTextField(labelWithString: participant.id)
        name.font = .systemFont(ofSize: 12.5, weight: .semibold)
        name.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        name.frame = NSRect(x: 31, y: 7, width: 160, height: 15)
        name.lineBreakMode = .byTruncatingTail
        addSubview(name)

        let role = NSTextField(labelWithString: roleText(participant))
        role.font = .systemFont(ofSize: 10.5)
        role.textColor = roleColor(participant)
        role.frame = NSRect(x: 31, y: 23, width: 190, height: 13)
        role.lineBreakMode = .byTruncatingTail
        addSubview(role)

        let status = NSTextField(labelWithString: statusGlyph(participant.activity))
        status.font = .systemFont(ofSize: 10)
        status.textColor = statusColor(participant)
        status.alignment = .right
        status.frame = NSRect(x: 0, y: 16, width: 0, height: 13)
        status.autoresizingMask = [.minXMargin]
        addSubview(status)
        statusField = status
        spinning = participant.activity == .working || participant.activity == .starting

        if dead { alphaValue = 0.42 }
    }

    private var statusField: NSTextField?
    private var spinning = false

    func tick() {
        guard spinning else { return }
        statusField?.stringValue = String(Spinner.current)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        statusField?.frame = NSRect(x: bounds.width - 34, y: 16, width: 24, height: 13)
    }

    override func mouseDown(with event: NSEvent) {
        guard !dead else { return }
        onClick?()
    }

    private func roleText(_ participant: ChatParticipant) -> String {
        switch participant.activity {
        case .dead:     return "terminal fechado"
        case .working:  return "trabalhando…"
        case .starting: return "subindo…"
        case .asking:   return "precisa de você"
        default:        return participant.role ?? ""
        }
    }

    private func roleColor(_ participant: ChatParticipant) -> NSColor {
        switch participant.activity {
        case .asking:  return .systemOrange
        case .working: return participant.color.withAlphaComponent(0.85)
        default:       return NSColor(calibratedWhite: 0.55, alpha: 1)
        }
    }

    private func statusGlyph(_ activity: Activity) -> String {
        switch activity {
        case .working, .starting: return String(Spinner.current)
        case .dead:               return "✕"
        default:                  return "●"
        }
    }

    private func statusColor(_ participant: ChatParticipant) -> NSColor {
        switch participant.activity {
        case .waiting:            return .systemGreen
        case .asking:             return .systemOrange
        case .working, .starting: return participant.color
        case .dead:               return NSColor(calibratedWhite: 0.4, alpha: 1)
        case .ready:              return NSColor(calibratedWhite: 1, alpha: 0.18)
        }
    }
}

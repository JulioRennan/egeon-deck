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
    /// Tempo e custo da bancada embaixo da lista, e o custo de cada agente na
    /// linha dele (ADR-085). No chat não há barra de ações para carregá-los.
    let clock = ClockChip()
    let usage = UsagePill()
    /// Custo por nó (o id, não o endereço): sobrevive à remontagem das linhas.
    private var costs: [String: String] = [:]

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
        addSubview(clock)
        addSubview(usage)
    }

    /// Muda a cada leitura do consumo; atualiza as linhas no lugar, sem
    /// remontar — remontar piscava.
    func showUsage(_ text: String, tooltip: String?, byNode: [String: String]) {
        usage.show(text, tooltip: tooltip)
        costs = byNode
        rows.forEach { $0.showCost(costs[$0.node]) }
        needsLayout = true
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
                row.showCost(costs[row.node])
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
            row.frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: ParticipantRow.height)
            y += ParticipantRow.height + 3
        }
        if !shellRows.isEmpty {
            y += 10
            shellsTitle.frame = NSRect(x: 14, y: y, width: bounds.width - 28, height: 13)
            y += 22
            for row in shellRows {
                row.frame = NSRect(x: 8, y: y, width: bounds.width - 16, height: ParticipantRow.height)
                y += ParticipantRow.height + 3
            }
        }
        hint.frame = NSRect(x: 14, y: bounds.height - 26,
                            width: bounds.width - 28, height: 14)
        usage.frame = NSRect(x: 8, y: bounds.height - 26 - 38, width: bounds.width - 16, height: 30)
        clock.frame = NSRect(x: 8, y: usage.frame.minY - 34, width: bounds.width - 16, height: 30)
    }
}

// MARK: - Uma linha

private final class ParticipantRow: NSView {
    var onClick: (() -> Void)?
    private let dead: Bool
    /// O id do nó — a chave do consumo.
    let node: String
    /// Três linhas: nome, papel (ou estado) e o custo — o custo na mesma
    /// linha do papel brigava com ele.
    static let height: CGFloat = 56
    private let costField = NSTextField(labelWithString: "")
    private var nameField: NSTextField?
    private var roleField: NSTextField?

    init(participant: ChatParticipant, focused: Bool) {
        dead = participant.activity == .dead
        node = participant.address.split(separator: "/").last.map(String.init) ?? participant.id
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
            glyph.frame = NSRect(x: 10, y: (Self.height - 16) / 2, width: 16, height: 16)
            addSubview(glyph)
        } else {
            // Terminal tem ícone de terminal — o glifo de prompt confundia com
            // um agente de cor cinza.
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "terminal")?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            icon.contentTintColor = participant.color
            icon.imageScaling = .scaleNone
            icon.frame = NSRect(x: 8, y: (Self.height - 18) / 2, width: 20, height: 18)
            addSubview(icon)
        }

        // Sem segunda linha — agente ocioso e sem prompt —, o nome desce para o
        // meio em vez de deixar o vão embaixo. A altura da linha não muda: o
        // estado ("trabalhando…") entra e sai, e a lista não pode pular junto.
        let roleLabel = roleText(participant)
        let name = NSTextField(labelWithString: participant.id)
        name.font = .systemFont(ofSize: 12.5, weight: .semibold)
        name.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        name.frame = NSRect(x: 31, y: 0, width: 160, height: 15)
        nameField = name
        name.lineBreakMode = .byTruncatingTail
        addSubview(name)

        if !roleLabel.isEmpty {
            let role = NSTextField(labelWithString: roleLabel)
            role.font = .systemFont(ofSize: 10.5)
            role.textColor = roleColor(participant)
            role.frame = NSRect(x: 31, y: 0, width: 190, height: 13)
            roleField = role
            role.lineBreakMode = .byTruncatingTail
            addSubview(role)
        }

        let status = NSTextField(labelWithString: statusGlyph(participant.activity))
        status.font = .systemFont(ofSize: 10)
        status.textColor = statusColor(participant)
        status.alignment = .right
        status.frame = NSRect(x: 0, y: 16, width: 0, height: 13)
        status.autoresizingMask = [.minXMargin]
        addSubview(status)
        statusField = status
        spinning = participant.activity == .working || participant.activity == .starting

        costField.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        costField.textColor = NSColor(calibratedWhite: 1, alpha: 0.45)
        costField.alignment = .left
        addSubview(costField)

        if dead { alphaValue = 0.42 }
    }

    func showCost(_ text: String?) {
        costField.stringValue = text ?? ""
        costField.toolTip = text.map { "Consumo deste agente: \($0)" }
        needsLayout = true
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
        statusField?.frame = NSRect(x: bounds.width - 34, y: (bounds.height - 13) / 2, width: 24, height: 13)
        // Embaixo do estado, na coluna da direita: o nome e o papel continuam
        // com a largura que já tinham.
        // As linhas que existem, centradas na altura: agente ocioso sem papel
        // e sem custo fica com o nome no meio, sem vão embaixo.
        var lines: [(NSView, CGFloat)] = []
        if let nameField { lines.append((nameField, 15)) }
        if let roleField { lines.append((roleField, 13)) }
        if !costField.stringValue.isEmpty { lines.append((costField, 12)) }
        let gap: CGFloat = 3
        var y = ((bounds.height - lines.reduce(0) { $0 + $1.1 } - gap * CGFloat(max(0, lines.count - 1))) / 2).rounded()
        for (view, height) in lines {
            view.frame = NSRect(x: 31, y: y, width: bounds.width - 31 - 40, height: height)
            y += height + gap
        }
        costField.isHidden = costField.stringValue.isEmpty
    }

    override func resetCursorRects() { HandCursor.fill(self, when: !dead) }

    override func mouseDown(with event: NSEvent) {
        guard !dead else { return }
        onClick?()
    }

    private func roleText(_ participant: ChatParticipant) -> String {
        switch participant.activity {
        case .dead:     return "terminal fechado"
        case .working:  return "trabalhando…"
        case .starting: return "preparando…"
        case .asking:   return "precisa de você"
        case .background: return "em segundo plano"
        case .awaiting(let peers):
            return "aguardando " + (peers.isEmpty ? "vizinho" : peers.joined(separator: ", "))
        case .retrying(let attempt, _):
            return "tentando de novo (\(attempt)/\(ApiFailure.maxAttempts))"
        case .failed(let why):  return "falhou — \(why)"
        default:        return participant.role ?? ""
        }
    }

    private func roleColor(_ participant: ChatParticipant) -> NSColor {
        switch participant.activity {
        case .asking:  return .systemOrange
        case .failed:  return .systemRed
        case .working: return participant.color.withAlphaComponent(0.85)
        default:       return NSColor(calibratedWhite: 0.55, alpha: 1)
        }
    }

    private func statusGlyph(_ activity: Activity) -> String {
        switch activity {
        case .working, .starting: return String(Spinner.current)
        case .background, .awaiting, .retrying: return String(Spinner.hourglass)
        case .dead:               return "✕"
        default:                  return "●"
        }
    }

    private func statusColor(_ participant: ChatParticipant) -> NSColor {
        switch participant.activity {
        case .waiting:            return .systemGreen
        case .asking:             return .systemOrange
        // A bolinha vermelha: o agente parou por erro e o app desistiu de
        // tentar sozinho (ADR-072).
        case .failed:             return .systemRed
        case .working, .starting, .background, .awaiting, .retrying: return participant.color
        case .dead:               return NSColor(calibratedWhite: 0.4, alpha: 1)
        case .ready:              return NSColor(calibratedWhite: 1, alpha: 0.18)
        }
    }
}

import AppKit

/// Os pedidos de permissão abertos da bancada, logo acima do composer
/// (ADR-068).
///
/// Fica fora da thread de propósito: pedido não é turno de ninguém, e some
/// quando é respondido — aqui ou no terminal. Dentro da linha do tempo ele
/// viraria uma bolha órfã a cada resposta.
///
/// A pergunta do `AskUserQuestion` chega pelo mesmo gancho e entra aqui com as
/// opções como botões: é a mesma situação — o agente parado esperando você.
final class PermissionTray: NSView {
    /// Devolvem se a resposta foi aceita; recusada, a linha volta a responder.
    var onAnswer: ((String, PermissionAnswer) -> Bool)?
    var onChoose: ((String, [String: [String]]) -> Bool)?

    private var rows: [String: Row] = [:]
    private var order: [String] = []

    static let gap: CGFloat = 8

    var desiredHeight: CGFloat {
        order.reduce(0) { $0 + (rows[$1]?.height ?? 0) + Self.gap }
    }

    override var isFlipped: Bool { true }

    /// Redesenha só o que mudou: linha que já existe fica, e o clique em curso
    /// não perde o botão debaixo do ponteiro a cada tique.
    func update(_ asks: [(ask: PermissionAsk, name: String, color: NSColor)]) {
        let ids = asks.map(\.ask.id)
        for (id, row) in rows where !ids.contains(id) {
            row.removeFromSuperview()
            rows.removeValue(forKey: id)
        }
        for entry in asks where rows[entry.ask.id] == nil {
            let id = entry.ask.id
            let row = Row(ask: entry.ask, name: entry.name, color: entry.color)
            row.onAnswer = { [weak self] answer in self?.onAnswer?(id, answer) ?? false }
            row.onChoose = { [weak self] choices in self?.onChoose?(id, choices) ?? false }
            rows[id] = row
            addSubview(row)
        }
        order = ids
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for id in order {
            guard let row = rows[id] else { continue }
            row.frame = NSRect(x: 0, y: y, width: bounds.width, height: row.height)
            y += row.height + Self.gap
        }
    }

    private final class Row: NSView {
        var onAnswer: ((PermissionAnswer) -> Bool)?
        var onChoose: (([String: [String]]) -> Bool)?

        private let title = NSTextField(labelWithString: "")
        private let summary = NSTextField(labelWithString: "")
        /// Linha de botões de resposta (permissão) ou de envio (pergunta
        /// com várias escolhas). Fica embaixo de tudo.
        private var actions: [(button: NSButton, answer: PermissionAnswer?)] = []
        private var questionLabels: [NSTextField] = []
        private var optionButtons: [[NSButton]] = []
        private let questions: [PermissionAsk.Question]
        private var picked: [String: [String]] = [:]
        private var submit: NSButton?

        private static let line: CGFloat = 26

        var height: CGFloat {
            if questions.isEmpty { return 74 }
            let perQuestion = CGFloat(questions.count) * (17 + Self.line + 4)
            let needsSubmit = questions.count > 1 || questions.contains(where: \.multiSelect)
            return 30 + perQuestion + (needsSubmit ? Self.line : 0) + 8
        }

        init(ask: PermissionAsk, name: String, color: NSColor) {
            questions = ask.questions
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 8
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.7).cgColor
            layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor

            let who = NSMutableAttributedString(string: "⚠ ", attributes: [
                .foregroundColor: NSColor.systemOrange, .font: NSFont.boldSystemFont(ofSize: 12)])
            who.append(NSAttributedString(string: name, attributes: [
                .foregroundColor: color, .font: NSFont.boldSystemFont(ofSize: 12)]))
            let verb: String
            if !questions.isEmpty {
                verb = " pergunta"
            } else {
                verb = ask.detail.map { " quer usar \(ask.tool) — \($0)" } ?? " quer usar \(ask.tool)"
            }
            who.append(NSAttributedString(string: verb, attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1),
                .font: NSFont.systemFont(ofSize: 12)]))
            title.attributedStringValue = who
            title.lineBreakMode = .byTruncatingTail
            addSubview(title)

            if questions.isEmpty {
                summary.stringValue = ask.summary.replacingOccurrences(of: "\n", with: " ⏎ ")
                summary.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                summary.textColor = NSColor(calibratedWhite: 0.75, alpha: 1)
                summary.lineBreakMode = .byTruncatingMiddle
                summary.toolTip = ask.summary
                addSubview(summary)

                var answers: [(String, PermissionAnswer)] = [("Permitir", .allow)]
                if ask.canAlwaysAllow { answers.append(("Sempre", .always)) }
                answers.append(("Negar", .deny))
                for (label, answer) in answers {
                    let button = makeButton(label, action: #selector(answered(_:)))
                    if answer == .allow { button.bezelColor = .systemGreen }
                    if answer == .deny { button.bezelColor = .systemRed }
                    if answer == .always {
                        button.toolTip = "Permite e grava a regra que o CLI sugeriu, sem perguntar de novo"
                    }
                    button.tag = actions.count
                    actions.append((button, answer))
                }
                return
            }

            let collects = questions.count > 1 || questions.contains(where: \.multiSelect)
            for (index, question) in questions.enumerated() {
                let label = NSTextField(labelWithString: (question.header.map { "\($0) · " } ?? "")
                                        + question.question)
                label.font = .systemFont(ofSize: 12)
                label.textColor = NSColor(calibratedWhite: 0.9, alpha: 1)
                label.lineBreakMode = .byTruncatingTail
                label.toolTip = question.question
                addSubview(label)
                questionLabels.append(label)
                optionButtons.append(question.options.enumerated().map { option, text in
                    let button = makeButton(text, action: #selector(chose(_:)))
                    // Com "Responder", a escolha precisa ficar marcada até o envio.
                    button.setButtonType(collects ? .pushOnPushOff : .momentaryPushIn)
                    button.tag = index * 1000 + option
                    return button
                })
            }
            if collects {
                let button = makeButton("Responder", action: #selector(submitted))
                button.bezelColor = .systemGreen
                button.isEnabled = false
                submit = button
            }
            let cancel = makeButton("Recusar", action: #selector(answered(_:)))
            cancel.toolTip = "Recusa a pergunta: o agente segue sem a resposta"
            cancel.tag = actions.count
            actions.append((cancel, .deny))
        }

        required init?(coder: NSCoder) { fatalError() }
        override var isFlipped: Bool { true }

        private func makeButton(_ title: String, action: Selector) -> NSButton {
            let button = HandButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
            addSubview(button)
            return button
        }

        private func setEnabled(_ enabled: Bool) {
            (actions.map(\.button) + optionButtons.flatMap { $0 }).forEach { $0.isEnabled = enabled }
            submit?.isEnabled = enabled && questions.allSatisfy { picked[$0.question] != nil }
        }

        @objc private func answered(_ sender: NSButton) {
            guard let answer = actions[sender.tag].answer else { return }
            setEnabled(false)
            if onAnswer?(answer) != true { setEnabled(true) }
        }

        @objc private func chose(_ sender: NSButton) {
            let question = questions[sender.tag / 1000]
            let option = question.options[sender.tag % 1000]
            if question.multiSelect {
                var list = picked[question.question] ?? []
                if sender.state == .on { list.append(option) } else { list.removeAll { $0 == option } }
                picked[question.question] = list.isEmpty ? nil : list
            } else {
                picked[question.question] = [option]
                // Uma pergunta, uma escolha: o clique já é a resposta.
                if submit == nil {
                    setEnabled(false)
                    if onChoose?(picked) != true {
                        picked = [:]
                        setEnabled(true)
                    }
                    return
                }
                for button in optionButtons[sender.tag / 1000] {
                    button.state = button === sender ? .on : .off
                }
            }
            submit?.isEnabled = questions.allSatisfy { picked[$0.question] != nil }
        }

        @objc private func submitted() {
            setEnabled(false)
            if onChoose?(picked) != true { setEnabled(true) }
        }

        override func layout() {
            super.layout()
            let pad: CGFloat = 12
            title.frame = NSRect(x: pad, y: 8, width: bounds.width - 2 * pad, height: 17)

            func place(_ buttons: [NSButton], y: CGFloat) {
                var x = pad
                for button in buttons {
                    let width = max(76, button.intrinsicContentSize.width + 12)
                    button.frame = NSRect(x: x, y: y, width: width, height: 22)
                    x += width + 6
                }
            }

            if questions.isEmpty {
                summary.frame = NSRect(x: pad, y: 27, width: bounds.width - 2 * pad, height: 15)
                place(actions.map(\.button), y: 46)
                return
            }
            var y: CGFloat = 30
            for (index, label) in questionLabels.enumerated() {
                label.frame = NSRect(x: pad, y: y, width: bounds.width - 2 * pad, height: 17)
                y += 19
                // Recusar fica na linha da única pergunta; com mais de uma, ao lado do Responder.
                let extra = (submit == nil && index == questionLabels.count - 1) ? actions.map(\.button) : []
                place(optionButtons[index] + extra, y: y)
                y += Self.line + 2
            }
            if let submit { place([submit] + actions.map(\.button), y: y) }
        }
    }
}

import AppKit

/// A faixa do cabeçalho do card de agente: modelo, esforço e ultracode.
///
/// Tudo o que ela mostra depende do modelo — o nome ("Opus 5.5"), os níveis
/// do slider, o "auto (medium)", se o ultracode existe — e o modelo de fato só
/// se sabe depois do primeiro turno, pelo transcript. Por isso é uma view só,
/// que se remonta quando o modelo em vigor muda, em vez de três controles
/// soltos no `TerminalNode`.
final class ModelRow: NSView {
    /// Você mexeu em algo. Quem atende reinicia o processo e mantém a conversa.
    var onChoice: ((ModelChoice) -> Void)?
    /// A largura pedida mudou — o nome do modelo cresceu ou encolheu.
    var onResize: (() -> Void)?
    /// Quem sabe o modelo que respondeu — lê o transcript. A view não sabe onde
    /// a conversa é gravada.
    var modelResolver: (() -> String?)? {
        didSet { refresh(force: true) }
    }

    private let profile: AgentProfile
    private var catalog: ModelCatalog?
    private let chosenModel: String?
    private let chosenEffort: String?
    private let ultracodeOn: Bool
    private let tint: NSColor

    private let modelCaption = ModelRow.caption("modelo")
    private let effortCaption = ModelRow.caption("esforço")
    private let picker = HandPopUpButton(frame: .zero, pullsDown: true)
    private var pickerWidth: CGFloat = 60
    private var dial: EffortDial?
    /// O modelo por trás do slider montado agora — remonta quando muda.
    private var dialModel: String??
    private let ultracodeButton = HandButton(title: "ultracode", target: nil, action: nil)

    private var literalModel: String?
    private var lastProbe = Date.distantPast

    /// Os dois espaços da faixa — rótulo para o seu controle, e grupo para
    /// grupo. Medidos no que se VÊ: o pull-down sem borda já traz um respiro
    /// dele à esquerda do texto, e o botão do ultracode tem folga de pílula.
    static let gap: CGFloat = EffortDial.textToSlider
    private static let groupGap: CGFloat = 14
    private static let pickerInset: CGFloat = 5
    private static let pillPadding: CGFloat = 4
    private static let height: CGFloat = 18

    init(profile: AgentProfile, catalog: ModelCatalog?, model: String?, effort: String?,
         ultracode: Bool, tint: NSColor) {
        self.profile = profile
        self.catalog = catalog
        self.chosenModel = model
        self.chosenEffort = effort
        self.ultracodeOn = ultracode
        self.tint = tint
        super.init(frame: .zero)

        picker.controlSize = .small
        picker.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        picker.isBordered = false
        picker.autoenablesItems = false
        if profile.offersModelChoice(catalog: catalog, current: model) {
            addSubview(modelCaption)
            addSubview(picker)
        }

        ultracodeButton.isBordered = false
        ultracodeButton.font = .systemFont(ofSize: 9, weight: .semibold)
        ultracodeButton.target = self
        ultracodeButton.action = #selector(toggleUltracode)
        ultracodeButton.wantsLayer = true
        ultracodeButton.layer?.cornerRadius = 4
        if profile.ultracode != nil, profile.offersEfforts { addSubview(ultracodeButton) }

        rebuildMenu()
        refresh(force: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Chegou um catálogo novo (o Claude Code foi atualizado).
    func apply(catalog: ModelCatalog?) {
        guard catalog != self.catalog else { return }
        self.catalog = catalog
        rebuildMenu()
        dialModel = nil
        refresh(force: true)
    }

    // MARK: medida

    var preferredWidth: CGFloat {
        var width: CGFloat = 0
        for (index, view) in visibleItems.enumerated() {
            width += itemWidth(view) + (index == 0 ? 0 : spacing(before: view))
        }
        return ceil(width)
    }

    override var fittingSize: NSSize { NSSize(width: preferredWidth, height: Self.height) }
    override var isFlipped: Bool { true }

    private var visibleItems: [NSView] {
        [modelCaption, picker, effortCaption, dial, ultracodeButton]
            .compactMap { $0 }
            .filter { $0.superview === self }
    }

    private func itemWidth(_ view: NSView) -> CGFloat {
        switch view {
        case picker: return pickerWidth
        case let dial as EffortDial: return dial.preferredWidth
        case ultracodeButton:
            let text = (ultracodeButton.title as NSString).size(withAttributes: [.font: ultracodeButton.font as Any])
            return ceil(text.width) + Self.pillPadding * 2
        default: return ceil(view.fittingSize.width)
        }
    }

    /// Rótulo cola no controle dele; grupos se afastam. Descontado o respiro
    /// que o próprio controle já desenha, para o espaço visível ser o mesmo.
    private func spacing(before view: NSView) -> CGFloat {
        switch view {
        case picker: return max(0, Self.gap - Self.pickerInset)
        case ultracodeButton: return Self.groupGap - Self.pillPadding
        case modelCaption, effortCaption: return Self.groupGap
        default: return Self.gap
        }
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for (index, view) in visibleItems.enumerated() {
            if index > 0 { x += spacing(before: view) }
            let width = itemWidth(view)
            let height = min(Self.height, max(view.fittingSize.height, 13))
            view.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: width, height: height)
            x += width
        }
    }

    // MARK: modelo

    /// O menu: o mais novo de cada família com o nome de gente, as versões
    /// anteriores num submenu, os apelidos ("sempre o mais recente") e o
    /// padrão. Sem catálogo, só apelidos e padrão, como antes.
    private func rebuildMenu() {
        guard picker.superview === self else { return }
        picker.removeAllItems()
        picker.addItem(withTitle: "")
        let menu = picker.menu!

        if let catalog {
            for model in catalog.featured { menu.addItem(item(model.label, value: model.id)) }
            let older = catalog.older
            if !older.isEmpty {
                let parent = NSMenuItem(title: "Versões anteriores", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for model in older { submenu.addItem(item(model.label, value: model.id)) }
                parent.submenu = submenu
                menu.addItem(parent)
            }
            menu.addItem(.separator())
            menu.addItem(header("sempre o mais recente"))
        }
        var aliases = profile.models ?? []
        if let chosenModel, !chosenModel.isEmpty, !aliases.contains(chosenModel),
           catalog?.models.contains(where: { $0.id == chosenModel }) != true {
            aliases.append(chosenModel)
        }
        for alias in aliases {
            let resolved = catalog?.model(for: alias)?.label
            menu.addItem(item(resolved.map { "\(alias) — \($0)" } ?? alias, value: alias))
        }
        menu.addItem(.separator())
        menu.addItem(item("padrão do CLI", value: nil))
    }

    private func item(_ title: String, value: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(modelPicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = value
        item.state = value == chosenModel ? .on : .off
        return item
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func modelPicked(_ sender: NSMenuItem) {
        onChoice?(.model(sender.representedObject as? String))
    }

    @objc private func toggleUltracode() {
        onChoice?(.ultracode(!ultracodeOn))
    }

    /// Nome para o título: o do catálogo; senão o id sem o prefixo do
    /// fornecedor, que é igual em todo item e só come largura.
    private func displayName(_ name: String) -> String {
        if let label = catalog?.label(for: name), catalog?.models.contains(where: { name.hasPrefix($0.id) }) == true {
            return label
        }
        return name.hasPrefix("claude-") ? String(name.dropFirst("claude-".count)) : name
    }

    /// O modelo que manda nos níveis: o pedido, senão o que respondeu.
    private var effectiveModel: ModelCatalog.Model? {
        catalog?.model(for: chosenModel) ?? catalog?.model(for: literalModel)
    }

    /// Consulta o transcript no máximo a cada 2s — é leitura de arquivo, e o
    /// tick do badge é de 0,25s.
    func refresh(force: Bool = false) {
        let now = Date()
        if force || now.timeIntervalSince(lastProbe) >= 2 {
            lastProbe = now
            literalModel = modelResolver?()
        }
        var resized = false
        if picker.superview === self { resized = refreshTitle() || resized }
        if profile.offersEfforts { resized = refreshDial() || resized }
        refreshUltracode()
        if resized {
            needsLayout = true
            onResize?()
        }
    }

    /// Título: quem respondeu, com o pedido entre parênteses quando é outro
    /// (`Opus 5.5 (opusplan)`); antes do primeiro turno, o pedido.
    private func refreshTitle() -> Bool {
        let literal = literalModel.map(displayName)
        let chosen = chosenModel.map(displayName)
        let same: Bool = {
            guard let literalModel, let chosenModel else { return false }
            if literalModel.contains(chosenModel) { return true }
            // Id pedido e id que respondeu são o mesmo modelo; apelido não conta
            // — "opus" pedido e "Opus 5.5" respondendo merece mostrar os dois.
            guard catalog?.models.contains(where: { $0.id == chosenModel }) == true else { return false }
            return catalog?.model(for: literalModel)?.id == catalog?.model(for: chosenModel)?.id
        }()
        let title: String
        switch (literal, chosen) {
        case let (literal?, chosen?) where !same: title = "\(literal) (\(chosen))"
        case let (literal?, _): title = literal
        case let (nil, chosen?): title = chosen
        case (nil, nil): title = "padrão"
        }
        guard picker.item(at: 0)?.title != title else { return false }
        picker.item(at: 0)?.title = title
        picker.toolTip = "Modelo em uso: \(literalModel ?? chosenModel ?? "padrão do CLI") — "
            + "escolher outro reinicia o terminal, a conversa continua"
        // Texto mais a seta do pull-down e o respiro da célula.
        let text = (title as NSString).size(withAttributes: [.font: picker.font as Any]).width
        pickerWidth = ceil(text) + 26
        return true
    }

    /// Remonta o slider quando o modelo por trás dele muda: cada modelo tem os
    /// seus níveis e o seu "auto".
    private func refreshDial() -> Bool {
        let model = effectiveModel
        guard dial == nil || dialModel != .some(model?.id) else { return false }
        dialModel = .some(model?.id)
        dial?.removeFromSuperview()
        let levels = model?.efforts ?? profile.efforts ?? []
        let dial = EffortDial(levels: levels, current: chosenEffort,
                              autoLevel: model?.defaultEffort, tint: tint)
        dial.onCommit = { [weak self] effort in self?.onChoice?(.effort(effort)) }
        dial.onResize = { [weak self] in
            self?.needsLayout = true
            self?.onResize?()
        }
        if effortCaption.superview == nil { addSubview(effortCaption) }
        addSubview(dial)
        self.dial = dial
        return true
    }

    private func refreshUltracode() {
        guard ultracodeButton.superview === self else { return }
        // Modelo sem esforço não tem ultracode ("isn't available on …").
        let available = effectiveModel.map { !$0.efforts.isEmpty } ?? true
        ultracodeButton.isEnabled = available
        let color = !available ? NSColor(calibratedWhite: 1, alpha: 0.25)
            : ultracodeOn ? tint : NSColor(calibratedWhite: 0.62, alpha: 1)
        ultracodeButton.attributedTitle = NSAttributedString(string: "ultracode", attributes: [
            .font: ultracodeButton.font as Any, .foregroundColor: color
        ])
        ultracodeButton.layer?.backgroundColor = ultracodeOn && available
            ? tint.withAlphaComponent(0.18).cgColor : NSColor.clear.cgColor
        ultracodeButton.toolTip = available
            ? "Ultracode \(ultracodeOn ? "ligado" : "desligado") — workflow dinâmico em toda "
                + "tarefa, em qualquer esforço (precisa dos dynamic workflows ligados no /config). "
                + "Trocar reinicia o terminal; a conversa continua"
            : "Este modelo não tem ultracode"
    }

    private static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 9, weight: .semibold)
        label.textColor = NSColor(calibratedWhite: 1, alpha: 0.32)
        label.sizeToFit()
        return label
    }
}

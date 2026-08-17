import AppKit
import WebKit

// MARK: - Perfis de navegação
//
// Um perfil é um `WKWebsiteDataStore` persistente identificado por UUID:
// cookies, localStorage e sessão isolados por nome, sobrevivendo a reinícios.
//
// Não é o perfil do Chrome. WKWebView é WebKit; o Chrome guarda a sessão dele
// em SQLite cifrado com uma chave do Keychain, e as duas pilhas não conversam.
// Login é feito uma vez por perfil daqui.

enum WebProfileStore {
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("web-profiles.json").path)

    static let defaultName = "pessoal"

    private static var cache: [String: UUID]?

    /// Nomes em ordem estável — a ordem de um dicionário muda a cada execução,
    /// e o popup de perfil ficaria embaralhando sozinho.
    static var names: [String] {
        let all = load()
        return all.isEmpty ? [defaultName] : all.keys.sorted()
    }

    static func identifier(for name: String) -> UUID {
        var all = load()
        if let existing = all[name] { return existing }
        let created = UUID()
        all[name] = created
        save(all)
        Log.write("web: perfil \"\(name)\" criado (\(created.uuidString))")
        return created
    }

    static func dataStore(for name: String) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: identifier(for: name))
    }

    private static func load() -> [String: UUID] {
        if let cache { return cache }
        let decoded = (try? Data(contentsOf: configURL))
            .flatMap { try? JSONDecoder().decode([String: UUID].self, from: $0) } ?? [:]
        cache = decoded
        return decoded
    }

    private static func save(_ all: [String: UUID]) {
        cache = all
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(all).write(to: configURL)
    }
}

// MARK: - Nó web

/// Navegador dentro do canvas. Ao contrário de ancorar uma janela real do
/// Chrome (ADR-003), isto é uma view nossa: escala com o zoom, é clipada e
/// obedece o z-order como qualquer nó.
final class WebNode: NodeView {
    static let barHeight: CGFloat = 30
    static let homeURL = "https://www.google.com"

    /// UA de Safari completo. O padrão do WKWebView embutido não traz
    /// `Version/… Safari/…`, e vários sites de login tratam isso como navegador
    /// não suportado.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    private(set) var address: String
    private(set) var profileName: String
    private(set) var currentURL: String

    /// URL ou perfil mudaram — quem escuta grava no sessions.json.
    var onStateChanged: ((WebNode) -> Void)?

    private var webView: WKWebView!
    private let bar = NSView()
    private let backButton = ToolbarButton(symbols: ["chevron.left"], tooltip: "Voltar", size: 24)
    private let forwardButton = ToolbarButton(symbols: ["chevron.right"], tooltip: "Avançar", size: 24)
    private let reloadButton = ToolbarButton(symbols: ["arrow.clockwise"], tooltip: "Recarregar", size: 24)
    private let urlField = NSTextField()
    private let profilePicker = NSPopUpButton(frame: .zero, pullsDown: false)

    private static let newProfileItem = "Novo perfil…"

    init(frame: NSRect, address: String, title: String, url: String?, profile: String?) {
        self.address = address
        self.profileName = profile ?? WebProfileStore.defaultName
        self.currentURL = url ?? Self.homeURL

        super.init(frame: frame,
                   title: "◍ " + String(address.split(separator: "/").last ?? ""),
                   accent: NSColor.systemBlue,
                   nodeID: String(address.split(separator: "/").last ?? ""))
        // A URL já está na barra do corpo; o subtítulo diz o que ela não diz —
        // com qual perfil de navegação esta página está logada.
        subtitle = "perfil: \(profileName)"
        titleLabel.toolTip = address

        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1).cgColor
        body.addSubview(bar)

        backButton.onClick = { [weak self] in self?.webView.goBack() }
        forwardButton.onClick = { [weak self] in self?.webView.goForward() }
        reloadButton.onClick = { [weak self] in self?.webView.reload() }
        [backButton, forwardButton, reloadButton].forEach(bar.addSubview)

        urlField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        urlField.textColor = NSColor(calibratedWhite: 1, alpha: 0.85)
        urlField.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1)
        urlField.drawsBackground = true
        urlField.isBordered = false
        urlField.focusRingType = .none
        urlField.lineBreakMode = .byTruncatingTail
        urlField.usesSingleLineMode = true
        urlField.cell?.wraps = false
        urlField.cell?.isScrollable = true
        urlField.target = self
        urlField.action = #selector(urlSubmitted)
        urlField.stringValue = currentURL
        bar.addSubview(urlField)

        profilePicker.font = .systemFont(ofSize: 10)
        profilePicker.bezelStyle = .inline
        profilePicker.target = self
        profilePicker.action = #selector(profilePicked)
        bar.addSubview(profilePicker)
        rebuildProfileMenu()

        rebuildWebView()
        load(currentURL)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var removalWarning: String {
        "A sessão fica salva no perfil \"\(profileName)\" — reabrir um nó web "
        + "com esse perfil volta logado."
    }

    override func prepareForRemoval() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
    }

    /// Só o rótulo: o nó web não está em índice nenhum, e a página segue carregada.
    override func sessionRenamed(to session: String) {
        address = "\(session)/\(nodeID)"
        titleLabel.toolTip = address
    }

    override func layout() {
        super.layout()
        bar.frame = NSRect(x: 0, y: 0, width: body.bounds.width, height: Self.barHeight)
        webView?.frame = NSRect(x: 0, y: Self.barHeight,
                                width: body.bounds.width,
                                height: max(0, body.bounds.height - Self.barHeight))

        var x: CGFloat = 4
        for button in [backButton, forwardButton, reloadButton] {
            button.frame = NSRect(x: x, y: 3, width: 24, height: 24)
            x += 25
        }
        x += 4

        let pickerWidth: CGFloat = 104
        let fieldWidth = max(80, bar.bounds.width - x - pickerWidth - 12)
        urlField.frame = NSRect(x: x, y: 7, width: fieldWidth, height: 16)
        profilePicker.frame = NSRect(x: x + fieldWidth + 6, y: 5, width: pickerWidth, height: 20)
    }

    // MARK: - Navegação

    @objc private func urlSubmitted() {
        load(urlField.stringValue)
    }

    func load(_ raw: String) {
        guard let url = Self.normalize(raw) else { return }
        currentURL = url.absoluteString
        urlField.stringValue = currentURL
        webView.load(URLRequest(url: url))
        onStateChanged?(self)
    }

    /// Barra de endereço de navegador: com esquema, vai direto; parecendo um
    /// host, vira https; o resto vira busca.
    static func normalize(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.contains("://"), let url = URL(string: text) { return url }

        let head = text.split(separator: "/").first.map(String.init) ?? text
        let looksLikeHost = !head.contains(" ")
            && (head.contains(".") || head.hasPrefix("localhost") || head.hasPrefix("127.0.0.1"))
        if looksLikeHost, let url = URL(string: "https://\(text)") { return url }

        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://www.google.com/search?q=\(query)")
    }

    // MARK: - Perfis

    private func rebuildProfileMenu() {
        profilePicker.removeAllItems()
        var names = WebProfileStore.names
        if !names.contains(profileName) { names.append(profileName) }
        profilePicker.addItems(withTitles: names.sorted())
        profilePicker.menu?.addItem(.separator())
        profilePicker.addItem(withTitle: Self.newProfileItem)
        profilePicker.selectItem(withTitle: profileName)
        profilePicker.toolTip = "Perfil de navegação (cookies e sessão isolados)"
    }

    @objc private func profilePicked() {
        guard let chosen = profilePicker.titleOfSelectedItem else { return }

        if chosen == Self.newProfileItem {
            guard let name = askForProfileName(), !name.isEmpty else {
                profilePicker.selectItem(withTitle: profileName)
                return
            }
            _ = WebProfileStore.identifier(for: name)
            switchProfile(to: name)
            return
        }

        guard chosen != profileName else { return }
        switchProfile(to: chosen)
    }

    /// O data store é fixado na criação do WKWebView, então trocar de perfil é
    /// jogar a view fora e montar outra na mesma URL.
    private func switchProfile(to name: String) {
        profileName = name
        rebuildProfileMenu()
        rebuildWebView()
        load(currentURL)
        Log.write("web[\(address)]: perfil agora é \"\(name)\"")
        onStateChanged?(self)
    }

    private func askForProfileName() -> String? {
        let alert = NSAlert()
        alert.messageText = "Novo perfil de navegação"
        alert.informativeText = "Cookies e sessão ficam isolados por perfil."
        alert.addButton(withTitle: "Criar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "trabalho"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - WebView

    private func rebuildWebView() {
        webView?.removeFromSuperview()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WebProfileStore.dataStore(for: profileName)
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = Self.userAgent
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = self
        body.addSubview(view)
        webView = view

        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

extension WebNode: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else { return }
        currentURL = url
        // Não mexe no campo enquanto o usuário está digitando nele.
        if urlField.currentEditor() == nil { urlField.stringValue = url }
        onStateChanged?(self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.write("web[\(address)]: falhou \(currentURL) — \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        Log.write("web[\(address)]: não carregou \(currentURL) — \(error.localizedDescription)")
    }
}

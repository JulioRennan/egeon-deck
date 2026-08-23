import AppKit
import WebKit

/// Índice de nós de editor por endereço `workspace/id`, para o socket de
/// controle conseguir inspecioná-los de fora (screenshot, sonda de DOM).
enum EditorRegistry {
    private static var nodes: [String: () -> EditorNode?] = [:]

    static func register(_ node: EditorNode) {
        nodes[node.address] = { [weak node] in node }
    }

    static func node(_ address: String) -> EditorNode? { nodes[address]?() }

    static func unregister(_ address: String) { nodes[address] = nil }

    static var addresses: [String] { nodes.keys.sorted() }

    /// Usado quando o code-server volta depois de cair: os nós na tela ainda
    /// apontam para o servidor que morreu e não recarregam sozinhos.
    static func reloadAll() {
        for address in addresses {
            guard let node = node(address) else {
                nodes[address] = nil   // nó já liberado; limpa a entrada morta
                continue
            }
            Log.write("editor[\(address)]: recarregando (code-server voltou)")
            node.open(folder: node.folder)
        }
    }
}

/// Nó de editor: o workbench do VSCode servido pelo code-server, dentro da
/// nossa janela — de fato DENTRO do canvas, ao contrário da janela de outro app,
/// que o macOS não deixa conter (ADR-001): escala, é clipado e obedece o
/// z-order como qualquer view.
final class EditorNode: NodeView {
    private(set) var address: String
    let folder: String
    let webView: WKWebView

    private let status = NSTextField(labelWithString: "aguardando code-server…")

    init(frame: NSRect, address: String, title: String, folder: String) {
        self.address = address
        self.folder = folder

        let config = WKWebViewConfiguration()
        // O workbench usa storage próprio; um datastore persistente mantém
        // layout, arquivos abertos e estado da bancada entre reinícios do app.
        config.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init(frame: frame,
                   title: "◧ " + String(address.split(separator: "/").last ?? ""),
                   accent: NSColor.systemOrange,
                   nodeID: String(address.split(separator: "/").last ?? ""))
        subtitle = NodeWorktreePlanner.short(folder)
        titleLabel.toolTip = address

        webView.setValue(false, forKey: "drawsBackground")
        body.addSubview(webView)

        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = NSColor(calibratedWhite: 1, alpha: 0.4)
        status.alignment = .center
        body.addSubview(status)

        EditorRegistry.register(self)

        CodeServer.shared.whenReady { [weak self] in self?.load() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var removalWarning: String {
        "O code-server continua rodando; só o nó sai do canvas."
    }

    /// Re-registra sob o endereço novo. O workbench não recarrega: a página
    /// depende da pasta, e a pasta não mudou.
    override func workbenchRenamed(to workbench: String) {
        EditorRegistry.unregister(address)
        address = "\(workbench)/\(nodeID)"
        EditorRegistry.register(self)
        titleLabel.toolTip = address
    }

    /// O endereço sai do índice, senão `/probe` e `/shot` continuariam achando
    /// um nó que já não está na tela.
    override func prepareForRemoval() {
        EditorRegistry.unregister(address)
        webView.stopLoading()
    }

    override func layout() {
        super.layout()
        webView.frame = body.bounds
        status.frame = NSRect(x: 10, y: body.bounds.midY - 10,
                              width: body.bounds.width - 20, height: 20)
    }

    private func load() { open(folder: folder) }

    /// Troca a pasta aberta no workbench. O `?folder=` do code-server é o único
    /// jeito estável de dirigir o editor de fora — comandos do VSCode não são
    /// alcançáveis por JavaScript da página.
    func open(folder path: String) {
        let url = CodeServer.shared.url(forFolder: path)
        Log.write("editor[\(address)]: carregando \(url.absoluteString)")
        subtitle = NodeWorktreePlanner.short(path)
        status.isHidden = true
        webView.load(URLRequest(url: url))
    }

    /// Foca uma view da activity bar ("Explorer", "Search", "Source Control"…).
    /// Comandos do VSCode não são alcançáveis por JavaScript da página, então o
    /// caminho é clicar no próprio item da barra pelo aria-label.
    func focusView(named name: String, completion: @escaping (String) -> Void) {
        let escaped = name.replacingOccurrences(of: "'", with: "\\'")
        let script = """
            (function () {
              var items = Array.from(document.querySelectorAll('.activitybar .action-item a, .activitybar .action-item'));
              var hit = items.find(function (el) {
                var label = (el.getAttribute('aria-label') || el.title || '').toLowerCase();
                return label.indexOf('\(escaped)'.toLowerCase()) !== -1;
              });
              if (!hit) {
                return 'não achei: ' + items.map(function (el) {
                  return el.getAttribute('aria-label') || el.title || '?';
                }).join(' | ');
              }
              hit.click();
              return 'ok: ' + (hit.getAttribute('aria-label') || hit.title);
            })()
            """
        webView.evaluateJavaScript(script) { value, error in
            if let error { completion("erro: \(error.localizedDescription)") }
            else { completion(value as? String ?? "sem resposta") }
        }
    }

    /// Clica numa linha do Explorer pelo nome — abre arquivo ou expande pasta.
    func openInExplorer(named name: String, completion: @escaping (String) -> Void) {
        clickListRow(in: ".explorer-folders-view", matching: name, completion: completion)
    }

    /// Monaco ignora `element.click()` puro nas listas: elas escutam a sequência
    /// de mouse, então ela é reproduzida inteira.
    private func clickListRow(in container: String, matching name: String,
                              completion: @escaping (String) -> Void) {
        let needle = name.replacingOccurrences(of: "'", with: "\\'")
        let script = """
            (function () {
              var rows = Array.from(document.querySelectorAll('\(container) .monaco-list-row'));
              if (!rows.length) return 'lista vazia em \(container)';
              var row = rows.find(function (r) {
                return (r.textContent || '').indexOf('\(needle)') !== -1;
              });
              if (!row) {
                return 'não achei "\(needle)" entre: '
                     + rows.map(function (r) { return (r.textContent || '').trim().slice(0, 24); })
                           .join(' | ');
              }
              var target = row.querySelector('.monaco-icon-label') || row;
              var box = target.getBoundingClientRect();
              ['mousedown', 'mouseup', 'click'].forEach(function (type) {
                target.dispatchEvent(new MouseEvent(type, {
                  bubbles: true, cancelable: true, view: window,
                  clientX: box.left + box.width / 2, clientY: box.top + box.height / 2,
                  button: 0, detail: 1
                }));
              });
              return 'cliquei: ' + (target.textContent || '').trim().slice(0, 60);
            })()
            """
        webView.evaluateJavaScript(script) { value, error in
            if let error { completion("erro: \(error.localizedDescription)") }
            else { completion(value as? String ?? "sem resposta") }
        }
    }

    /// Abre a n-ésima mudança do Source Control, o que faz o workbench montar o
    /// diff editor.
    func openChange(index: Int, matching name: String?, completion: @escaping (String) -> Void) {
        let needle = (name ?? "").replacingOccurrences(of: "'", with: "\\'")
        let script = """
            (function () {
              var rows = Array.from(document.querySelectorAll('.scm-view .monaco-list-row'));
              if (!rows.length) return 'nenhuma linha no Source Control';
              var needle = '\(needle)';
              var row = needle
                ? rows.find(function (r) { return (r.textContent || '').indexOf(needle) !== -1; })
                : rows[\(index)];
              if (!row) {
                return 'não achei "' + needle + '" entre: '
                     + rows.map(function (r) { return (r.textContent || '').trim().slice(0, 30); }).join(' | ');
              }
              var target = row.querySelector('.monaco-icon-label') || row;
              var box = target.getBoundingClientRect();
              var x = box.left + box.width / 2;
              var y = box.top + box.height / 2;
              ['mousedown', 'mouseup', 'click'].forEach(function (type) {
                target.dispatchEvent(new MouseEvent(type, {
                  bubbles: true, cancelable: true, view: window,
                  clientX: x, clientY: y, button: 0, detail: 1
                }));
              });
              return 'cliquei: ' + (target.textContent || '').trim().slice(0, 80);
            })()
            """
        webView.evaluateJavaScript(script) { value, error in
            if let error { completion("erro: \(error.localizedDescription)") }
            else { completion(value as? String ?? "sem resposta") }
        }
    }

    // MARK: - Verificação

    /// Sonda o DOM. `.monaco-workbench` só existe quando o workbench montou de
    /// verdade — distingue "a página carregou" de "o VSCode subiu".
    func probe(_ completion: @escaping (String) -> Void) {
        let script = """
            (function () {
              var wb = document.querySelector('.monaco-workbench');
              var diff = document.querySelectorAll('.monaco-diff-editor').length;
              var tabs = Array.from(document.querySelectorAll('.tabs-container .tab-label'))
                              .map(function (t) { return t.textContent.trim(); });
              return JSON.stringify({
                url: location.href,
                workbench: !!wb,
                diffEditors: diff,
                tabs: tabs,
                title: document.title
              });
            })()
            """
        webView.evaluateJavaScript(script) { value, error in
            if let error { completion("erro: \(error.localizedDescription)") }
            else { completion(value as? String ?? "sem resposta") }
        }
    }

    /// Screenshot do nó. Serve para verificar o que realmente apareceu — o
    /// mesmo papel que `/peek` cumpriu para os terminais.
    func snapshot(to url: URL, completion: @escaping (String) -> Void) {
        // Janela ocluída faz o WebKit estrangular requestAnimationFrame, e o
        // Monaco só pinta o texto quando roda um frame — o snapshot sai com a
        // área de código em branco. Trazer a janela à frente e esperar um par
        // de frames resolve.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else {
                completion("erro: nó liberado antes do snapshot")
                return
            }
            self.takeSnapshot(to: url, completion: completion)
        }
    }

    private func takeSnapshot(to url: URL, completion: @escaping (String) -> Void) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { image, error in
            if let error {
                completion("erro: \(error.localizedDescription)")
                return
            }
            guard let image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                completion("erro: falha ao converter imagem")
                return
            }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try png.write(to: url)
                completion(url.path)
            } catch {
                completion("erro: \(error.localizedDescription)")
            }
        }
    }
}

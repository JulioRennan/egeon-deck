import Cocoa
import WebKit

/// Uma página web de verdade, dona de um `WKWebView` e de tudo que o Dart
/// precisa saber dela. O dono (o plugin) a guarda por id e a solta no
/// `dispose`: nada aqui retém a vista depois disso.
final class WebHost: NSObject, WKNavigationDelegate {
    /// UA de Safari completo. O padrão do WKWebView embutido não traz
    /// `Version/… Safari/…`, e vários sites de login tratam isso como navegador
    /// não suportado.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    let id: Int
    let view: WKWebView
    /// Chamado a cada mudança de URL, histórico ou carga.
    var onState: ((WebHost) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    /// O perfil é um `WKWebsiteDataStore` persistente identificado por UUID:
    /// cookies, localStorage e bancada isolados por perfil, sobrevivendo a
    /// reinícios. O UUID é o do `web-profiles.json`, que o core manda em
    /// `profile_id`; sem ele não há como reabrir logado, então a criação falha
    /// em vez de inventar um.
    init?(id: Int, profileId: String) {
        guard let identifier = UUID(uuidString: profileId) else { return nil }
        self.id = id
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        view.customUserAgent = Self.userAgent
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = self

        // `didCommit` não cobre `pushState` nem a volta do histórico; a vista
        // avisa o que muda.
        observations = [
            view.observe(\.url) { [weak self] _, _ in self.map { $0.onState?($0) } },
            view.observe(\.canGoBack) { [weak self] _, _ in self.map { $0.onState?($0) } },
            view.observe(\.canGoForward) { [weak self] _, _ in self.map { $0.onState?($0) } },
            view.observe(\.isLoading) { [weak self] _, _ in self.map { $0.onState?($0) } },
        ]
    }

    var state: [String: Any] {
        [
            "id": id,
            "url": view.url?.absoluteString ?? "",
            "canGoBack": view.canGoBack,
            "canGoForward": view.canGoForward,
            "loading": view.isLoading,
        ]
    }

    func load(_ url: String) {
        guard let url = URL(string: url) else { return }
        view.load(URLRequest(url: url))
    }

    /// A página como PNG, no tamanho que a vista tem na tela agora.
    func snapshot(completion: @escaping (Data?) -> Void) {
        // Vista ainda sem tamanho (ou já recolhida): não há o que fotografar.
        guard view.bounds.width > 0, view.bounds.height > 0 else { return completion(nil) }
        let config = WKSnapshotConfiguration()
        config.rect = view.bounds
        view.takeSnapshot(with: config) { image, _ in
            guard let tiff = image?.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff)
            else { return completion(nil) }
            completion(bitmap.representation(using: .png, properties: [:]))
        }
    }

    /// Solta tudo que prende a vista: observadores, delegado, carga e a
    /// hierarquia de views.
    func dispose() {
        observations.forEach { $0.invalidate() }
        observations = []
        onState = nil
        view.navigationDelegate = nil
        view.stopLoading()
        view.removeFromSuperview()
    }
}

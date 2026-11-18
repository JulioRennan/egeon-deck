import Cocoa
import FlutterMacOS

/// O nó web nativo: uma vista `WKWebView` por página, comandada pelo canal
/// `egeon/web` e mostrada como platform view `egeon/web-view`.
///
/// Substitui o pacote `webview_flutter_wkwebview` porque o pacote não deixa
/// escolher o data store (perfil) nem tirar a captura da página — as duas
/// coisas que o nó web precisa.
final class EgeonWebPlugin: NSObject, FlutterPlugin {
    static let channelName = "egeon/web"
    static let viewType = "egeon/web-view"

    private let channel: FlutterMethodChannel
    private var hosts: [Int: WebHost] = [:]
    private var nextId = 1

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName, binaryMessenger: registrar.messenger)
        let plugin = EgeonWebPlugin(channel: channel)
        registrar.addMethodCallDelegate(plugin, channel: channel)
        registrar.register(WebViewFactory(plugin: plugin), withId: viewType)
    }

    fileprivate func host(_ id: Int) -> WebHost? { hosts[id] }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        if call.method == "create" {
            let id = nextId
            guard let host = WebHost(id: id, profileId: args["profileId"] as? String ?? "") else {
                return result(FlutterError(
                    code: "no-profile-id", message: "perfil sem UUID válido", details: nil))
            }
            host.onState = { [weak self] host in
                self?.channel.invokeMethod("state", arguments: host.state)
            }
            nextId += 1
            hosts[id] = host
            return result(id)
        }
        guard let id = args["id"] as? Int, let host = hosts[id] else {
            return result(FlutterError(code: "no-host", message: "página desconhecida", details: nil))
        }
        switch call.method {
        case "load":
            host.load(args["url"] as? String ?? "")
            result(nil)
        case "goBack":
            host.view.goBack()
            result(nil)
        case "goForward":
            host.view.goForward()
            result(nil)
        case "reload":
            host.view.reload()
            result(nil)
        case "snapshot":
            host.snapshot { data in
                result(data.map { FlutterStandardTypedData(bytes: $0) })
            }
        case "dispose":
            host.dispose()
            hosts[id] = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Entrega a vista de uma página já criada: ao voltar do modo congelado a
/// mesma `WKWebView` volta, com a página onde estava.
private final class WebViewFactory: NSObject, FlutterPlatformViewFactory {
    private weak var plugin: EgeonWebPlugin?

    init(plugin: EgeonWebPlugin) { self.plugin = plugin }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        let id = (args as? [String: Any])?["id"] as? Int ?? -1
        guard let view = plugin?.host(id)?.view else { return NSView() }
        view.removeFromSuperview()
        return view
    }
}

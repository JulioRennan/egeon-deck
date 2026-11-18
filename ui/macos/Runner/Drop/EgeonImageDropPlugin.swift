import Cocoa
import FlutterMacOS

/// Imagem arrastada SEM arquivo: o `desktop_drop` só enxerga arquivos (URL ou
/// promessa), mas um print arrastado de certos apps só deixa PNG ou TIFF na área
/// de arrasto. Este plugin faz duas coisas: manda o alvo de drop do pacote
/// aceitar esses tipos, e devolve a imagem como PNG quando o Dart pede (no
/// `onDragDone` sem arquivos).
final class EgeonImageDropPlugin: NSObject, FlutterPlugin {
    static let channelName = "egeon/image-drop"

    /// Os tipos de imagem pura que a área de arrasto pode carregar.
    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName, binaryMessenger: registrar.messenger)
        let plugin = EgeonImageDropPlugin()
        registrar.addMethodCallDelegate(plugin, channel: channel)
        // O alvo do pacote é criado no registro dele; aqui só se acrescentam os
        // tipos, depois que a janela montou.
        DispatchQueue.main.async {
            // Se o pacote renomear a view, o drop de imagem para sem erro nenhum:
            // o log é o único aviso.
            if !acceptImageDrags(in: registrar.view?.window?.contentView) {
                NSLog("EgeonImageDropPlugin: view \"DropTarget\" do desktop_drop não encontrada — "
                    + "drop de imagem sem arquivo desligado")
            }
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "draggedImage":
            result(Self.draggedPNG().map { FlutterStandardTypedData(bytes: $0) })
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Acrescenta PNG e TIFF aos tipos que o alvo de drop do `desktop_drop`
    /// aceita; sem isso o arrasto de uma imagem pura nem chega a cair. Devolve
    /// se achou o alvo.
    @discardableResult
    static func acceptImageDrags(in root: NSView?) -> Bool {
        guard let root else { return false }
        if String(describing: type(of: root)) == "DropTarget" {
            root.registerForDraggedTypes(root.registeredDraggedTypes + imageTypes)
            return true
        }
        return root.subviews.contains { acceptImageDrags(in: $0) }
    }

    /// A imagem da área de arrasto em PNG: o PNG como veio, ou o TIFF
    /// convertido. Nulo quando o arrasto não carrega imagem.
    static func draggedPNG(from pasteboard: NSPasteboard = NSPasteboard(name: .drag)) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return pngData(fromTIFF: tiff)
    }

    static func pngData(fromTIFF tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}

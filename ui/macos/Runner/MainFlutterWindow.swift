import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // O nó web: WKWebView com perfil isolado e captura, atrás do canal egeon/web.
    EgeonWebPlugin.register(
      with: flutterViewController.registrar(forPlugin: "EgeonWebPlugin"))
    // Imagem arrastada sem arquivo (o PNG do pasteboard), para o drop no terminal.
    EgeonImageDropPlugin.register(
      with: flutterViewController.registrar(forPlugin: "EgeonImageDropPlugin"))

    // Onde a janela está na tela, para quem dirige gestos de fora (/geometry).
    let frameChannel = FlutterMethodChannel(
      name: "egeon/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    frameChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "activate", let self {
        // Clique numa notificação: traz o app, mesmo minimizado.
        if self.isMiniaturized { self.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
        return result(nil)
      }
      guard call.method == "frame", let self,
        let view = self.contentView
      else { return result(FlutterMethodNotImplemented) }
      // O AppKit mede a tela de baixo para cima; o CGEvent, de cima para baixo.
      let screenHeight = (self.screen ?? NSScreen.main)?.frame.height ?? 0
      let rect = self.convertToScreen(view.convert(view.bounds, to: nil))
      result([
        "x": rect.minX,
        "y": screenHeight - rect.maxY,
        "width": rect.width,
        "height": rect.height,
        "screenHeight": screenHeight,
      ])
    }

    // O menu Editar do Flutter não tem os itens do sistema; a página web copia e
    // cola pela cadeia de responders, então o item manda a ação para ela.
    let editChannel = FlutterMethodChannel(
      name: "egeon/edit",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    editChannel.setMethodCallHandler { call, result in
      guard call.method == "send", let name = call.arguments as? String else {
        return result(FlutterMethodNotImplemented)
      }
      let selectors: [String: Selector] = [
        "undo": Selector(("undo:")),
        "redo": Selector(("redo:")),
        "cut": #selector(NSText.cut(_:)),
        "copy": #selector(NSText.copy(_:)),
        "paste": #selector(NSText.paste(_:)),
        "selectAll": #selector(NSText.selectAll(_:)),
      ]
      guard let selector = selectors[name] else { return result(false) }
      result(NSApp.sendAction(selector, to: nil, from: nil))
    }

    super.awakeFromNib()
  }
}

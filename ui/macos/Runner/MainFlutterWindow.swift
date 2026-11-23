import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  /// A altura da faixa de cima do app (`EgeonSize.titlebar`, 44): os semáforos
  /// ficam centrados nela, na mesma linha dos controles do Flutter.
  private static let titlebarHeight: CGFloat = 44

  /// Onde o primeiro semáforo começa: na linha da borda esquerda do trilho de
  /// bancadas (`BenchRail.left`, 24). O vão e o passo entre os três ficam os do
  /// sistema.
  private static let trafficLightsLeft: CGFloat = 24

  /// O macOS põe os semáforos numa barra de título de ~28pt e os recoloca a
  /// cada resize, tela cheia e troca de aparência: a barra é alargada até
  /// `titlebarHeight`, os três botões voltam ao centro dela e andam juntos até
  /// o primeiro cair em `trafficLightsLeft`. Sem NSToolbar, porque a altura dela
  /// muda de uma versão do sistema para outra. Só escreve o que mudou: o AppKit
  /// refaz a barra no próprio layout, e uma escrita a cada chamada armaria um
  /// vaivém.
  private func alignTrafficLights() {
    guard !exitingFullScreen, !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let mini = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let bar = close.superview,
      let container = bar.superview,
      let host = container.superview
    else { return }
    let height = MainFlutterWindow.titlebarHeight
    let wanted = NSRect(
      x: container.frame.minX, y: host.bounds.height - height,
      width: container.frame.width, height: height)
    if container.frame != wanted { container.frame = wanted }
    if bar.frame != container.bounds { bar.frame = container.bounds }
    let shift = MainFlutterWindow.trafficLightsLeft - close.frame.minX
    for button in [close, mini, zoom] {
      let origin = NSPoint(
        x: button.frame.minX + shift, y: (height - button.frame.height) / 2)
      if button.frame.origin != origin { button.setFrameOrigin(origin) }
    }
    if container.isHidden { container.isHidden = false }
  }

  /// A animação de saída da tela cheia está em curso: o `styleMask` já perdeu
  /// o `.fullScreen`, mas o AppKit ainda desenha os botões no lugar padrão, e
  /// alinhar agora mostraria a barra antes da hora (o `exiting_fullscreen_` do
  /// Electron).
  private var exitingFullScreen = false

  /// Na saída da tela cheia a barra some e só volta, já alinhada, no fim da
  /// animação: senão os botões pulariam do lugar padrão para o certo.
  private func hideTitlebarForExit() {
    exitingFullScreen = true
    let container = standardWindowButton(.closeButton)?.superview?.superview
    if container?.isHidden == false { container?.isHidden = true }
  }

  /// A saída da tela cheia não aconteceu: o AppKit não manda `didExit`, só
  /// este aviso do delegate. Sem ele a barra ficaria escondida para sempre.
  func windowDidFailToExitFullScreen(_ window: NSWindow) {
    finishExitFullScreen()
  }

  private func finishExitFullScreen() {
    exitingFullScreen = false
    alignTrafficLights()
  }

  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    alignTrafficLights()
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    // Sem barra de título: o conteúdo vai até o topo e os semáforos ficam por
    // cima dele, dentro da faixa de cima do app (44).
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    // Abaixo disto a gaveta aberta ao lado no chat, os participantes e a
    // conversa não cabem; repete `RootLayout.minWindow`.
    self.contentMinSize = NSSize(width: 1000, height: 600)
    self.contentViewController = flutterViewController
    self.delegate = self
    self.setFrame(windowFrame, display: true)
    alignTrafficLights()
    for name in [
      NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
      NSWindow.didEndLiveResizeNotification,
    ] {
      NotificationCenter.default.addObserver(
        forName: name, object: self, queue: .main
      ) { [weak self] _ in self?.alignTrafficLights() }
    }
    // A saída da tela cheia pode falhar (sem `didExit`): entrando de novo, a
    // barra deixa de esperar por ela.
    NotificationCenter.default.addObserver(
      forName: NSWindow.didEnterFullScreenNotification, object: self,
      queue: .main
    ) { [weak self] _ in self?.exitingFullScreen = false }
    NotificationCenter.default.addObserver(
      forName: NSWindow.didExitFullScreenNotification, object: self,
      queue: .main
    ) { [weak self] _ in self?.finishExitFullScreen() }
    NotificationCenter.default.addObserver(
      forName: NSWindow.willExitFullScreenNotification, object: self,
      queue: .main
    ) { [weak self] _ in self?.hideTitlebarForExit() }

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
      if call.method == "startDrag", let self {
        // O arrasto da faixa de cima: o evento do clique ainda é o corrente.
        if let event = NSApp.currentEvent { self.performDrag(with: event) }
        return result(nil)
      }
      if call.method == "toggleZoom", let self {
        self.zoom(nil)
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

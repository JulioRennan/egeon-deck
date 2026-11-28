import 'package:flutter/services.dart';

/// A moldura da janela como o runner a deixa: sem barra de título, o conteúdo
/// vai até o topo e quem arrasta a janela é a faixa de cima do app. Só o
/// runner nativo sabe.
abstract interface class WindowChrome {
  /// Começa o arrasto da janela (chamado no toque da faixa de cima).
  void startDrag();

  /// Duplo clique na faixa: maximiza ou restaura, como a barra de título.
  void toggleZoom();
}

/// A moldura pelo canal `egeon/window` do runner.
class ChannelWindowChrome implements WindowChrome {
  const ChannelWindowChrome();

  static const _channel = MethodChannel('egeon/window');

  @override
  void startDrag() => _call('startDrag');

  @override
  void toggleZoom() => _call('toggleZoom');

  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Fora do macOS não há janela nativa a mover.
    }
  }
}

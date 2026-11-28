import 'package:flutter/services.dart';

/// Onde a área de conteúdo da janela está na tela, de cima para baixo (a
/// convenção do CGEvent), em pontos.
class WindowFrame {
  const WindowFrame({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.screenHeight,
  });

  factory WindowFrame.fromMap(Map<Object?, Object?> map) => WindowFrame(
    x: (map['x']! as num).toDouble(),
    y: (map['y']! as num).toDouble(),
    width: (map['width']! as num).toDouble(),
    height: (map['height']! as num).toDouble(),
    screenHeight: (map['screenHeight']! as num).toDouble(),
  );

  /// O canto superior esquerdo do conteúdo, na tela.
  final double x;
  final double y;
  final double width;
  final double height;
  final double screenHeight;
}

/// De onde vem a posição da janela. Só o runner nativo sabe.
abstract interface class WindowFrameSource {
  Future<WindowFrame> read();
}

/// Traz a janela do app para a frente. Só o runner nativo sabe.
abstract interface class WindowActivator {
  Future<void> activate();
}

/// A posição da janela pelo canal `egeon/window` do runner.
class ChannelWindowFrame implements WindowFrameSource, WindowActivator {
  const ChannelWindowFrame();

  static const _channel = MethodChannel('egeon/window');

  @override
  Future<WindowFrame> read() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('frame');
    return WindowFrame.fromMap(map!);
  }

  @override
  Future<void> activate() async {
    try {
      await _channel.invokeMethod<void>('activate');
    } on MissingPluginException {
      // Fora do macOS não há janela nativa a trazer.
    }
  }
}

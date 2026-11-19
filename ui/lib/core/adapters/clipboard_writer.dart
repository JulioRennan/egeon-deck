import 'package:flutter/services.dart';

/// A área de transferência do sistema, para o que o app copia por conta
/// própria (os alvos de dispatch). O terminal e os campos de texto copiam pelo
/// caminho deles.
abstract interface class ClipboardWriter {
  Future<void> write(String text);
}

class SystemClipboard implements ClipboardWriter {
  const SystemClipboard();

  @override
  Future<void> write(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

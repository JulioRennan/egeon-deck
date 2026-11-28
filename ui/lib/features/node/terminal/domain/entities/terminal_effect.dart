/// Um efeito colateral que o programa do terminal pede à UI.
sealed class TerminalEffect {
  const TerminalEffect();

  /// O efeito que o core manda em `screen/<id>`, ou nulo para os que não são
  /// do terminal (o tópico de uma fila também manda `draft` e `open_item`).
  static TerminalEffect? tryParse(Map<String, Object?> map) =>
      switch (map['effect']) {
        'bell' => const Bell(),
        'clipboard' => ClipboardWrite(map['text'] as String? ?? ''),
        'clipboard_request' => const ClipboardRequest(),
        _ => null,
      };
}

/// O beep.
class Bell extends TerminalEffect {
  const Bell();
}

/// OSC 52: grave na área de transferência.
class ClipboardWrite extends TerminalEffect {
  const ClipboardWrite(this.text);
  final String text;
}

/// OSC 52: o programa quer ler a área de transferência. A UI a lê e manda o
/// texto ao core — só quando o programa pede.
class ClipboardRequest extends TerminalEffect {
  const ClipboardRequest();
}

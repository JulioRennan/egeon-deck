/// Uma tecla como a UI a captura. Quem a codifica para o pty é o componente
/// terminal do Rust; a UI só descreve o que foi apertado.
class TerminalKey {
  const TerminalKey({
    required this.key,
    this.text,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  /// A tecla sem modificador, em minúsculas: `a`, `enter`, `tab`, `backspace`,
  /// `escape`, `up`, `pageup`, `f5`…
  final String key;

  /// Caractere digitado, já com o layout do teclado aplicado.
  final String? text;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  /// Os campos do comando `key`, sem `id`, `cmd` e `node`.
  Map<String, Object?> toMap() => {
    'key': key,
    'mods': {
      if (ctrl) 'ctrl': true,
      if (alt) 'alt': true,
      if (shift) 'shift': true,
      if (meta) 'meta': true,
    },
    if (text != null) 'text': text,
  };
}

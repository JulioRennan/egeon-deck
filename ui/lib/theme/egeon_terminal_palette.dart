import 'dart:ui';

import 'egeon_colors.dart';

/// Paleta do terminal no Graphite: os 16 ANSI do design system, o cubo 6×6×6
/// e a rampa de cinzas (a parte padronizada do xterm). Mesma forma do
/// `TerminalPalette` antigo, para o pintor trocar de uma para a outra; sem o
/// pacote xterm, porque o emulador é o libghostty no Rust.
abstract final class EgeonTerminalPalette {
  static const _c = EgeonColors.dark;

  static final background = _c.termBg;
  static final foreground = _c.termFg;
  static final cursor = _c.termCursor;
  static final selection = _c.termSelection;

  /// Busca no terminal: não está no `tokens.json`, vem do tema xterm do DS.
  static const searchHitBackground = Color(0x66FF9B45);
  static const searchHitBackgroundCurrent = Color(0xCCFF9B45);
  static const searchHitForeground = Color(0xFF0B0D10);

  static final List<Color> ansi = [
    _c.termBlack,
    _c.termRed,
    _c.termGreen,
    _c.termYellow,
    _c.termBlue,
    _c.termMagenta,
    _c.termCyan,
    _c.termWhite,
    _c.termBrightBlack,
    _c.termBrightRed,
    _c.termBrightGreen,
    _c.termBrightYellow,
    _c.termBrightBlue,
    _c.termBrightMagenta,
    _c.termBrightCyan,
    _c.termBrightWhite,
  ];

  static final List<Color> _table = List.generate(256, _build, growable: false);

  static Color _build(int i) {
    if (i < 16) return ansi[i];
    if (i < 232) {
      final n = i - 16;
      int level(int v) => v == 0 ? 0 : 55 + v * 40;
      return Color.fromARGB(
        255,
        level(n ~/ 36),
        level((n ~/ 6) % 6),
        level(n % 6),
      );
    }
    final gray = 8 + (i - 232) * 10;
    return Color.fromARGB(255, gray, gray, gray);
  }

  static Color indexed(int index) => _table[index.clamp(0, 255)];

  static Color rgb(int value) => Color(0xFF000000 | value);
}

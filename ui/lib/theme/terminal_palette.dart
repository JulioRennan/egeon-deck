import 'dart:ui';

/// Paleta de 256 cores do terminal: 16 ANSI no tema escuro, cubo 6×6×6 e
/// rampa de cinzas (a parte padronizada do xterm).
abstract final class TerminalPalette {
  static const _ansi = <int>[
    0x1A1A1A,
    0xE06C75,
    0x98C379,
    0xE5C07B,
    0x61AFEF,
    0xC678DD,
    0x56B6C2,
    0xD0D0D0,
    0x5C6370,
    0xFF7B86,
    0xA9D68A,
    0xF2D18B,
    0x75C1FF,
    0xD78AEF,
    0x6CC8D4,
    0xFFFFFF,
  ];

  static final List<Color> _table = List.generate(256, _build, growable: false);

  static Color _build(int i) {
    if (i < 16) return Color(0xFF000000 | _ansi[i]);
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

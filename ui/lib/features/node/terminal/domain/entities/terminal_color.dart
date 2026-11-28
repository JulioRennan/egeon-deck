/// Cor como o core manda: índice da paleta de 256 ou RGB (`"#rrggbb"`).
/// Quem a transforma em pixel é o tema.
class TerminalColor {
  const TerminalColor.indexed(int this.index) : rgb = null;
  const TerminalColor.rgb(int this.rgb) : index = null;

  final int? index;
  final int? rgb;

  static TerminalColor? fromValue(Object? value) {
    if (value is int) return TerminalColor.indexed(value);
    if (value is String && value.startsWith('#') && value.length == 7) {
      return TerminalColor.rgb(int.parse(value.substring(1), radix: 16));
    }
    return null;
  }

  Object toValue() => index ?? '#${rgb!.toRadixString(16).padLeft(6, '0')}';
}

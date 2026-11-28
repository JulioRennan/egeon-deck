import 'terminal_color.dart';

/// Estilo de um trecho de texto; `null` na cor é a cor padrão do terminal.
class TerminalStyle {
  const TerminalStyle({
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.inverse = false,
    this.dim = false,
  });

  static const plain = TerminalStyle();

  final TerminalColor? foreground;
  final TerminalColor? background;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool inverse;
  final bool dim;

  factory TerminalStyle.fromMap(Map<String, Object?> map) => TerminalStyle(
    foreground: TerminalColor.fromValue(map['fg']),
    background: TerminalColor.fromValue(map['bg']),
    bold: map['bold'] == true,
    italic: map['italic'] == true,
    underline: map['underline'] == true,
    strike: map['strike'] == true,
    inverse: map['inverse'] == true,
    dim: map['dim'] == true,
  );

  /// Só os campos ligados, como o core os manda.
  Map<String, Object?> toMap() => {
    if (foreground != null) 'fg': foreground!.toValue(),
    if (background != null) 'bg': background!.toValue(),
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    if (underline) 'underline': true,
    if (strike) 'strike': true,
    if (inverse) 'inverse': true,
    if (dim) 'dim': true,
  };
}

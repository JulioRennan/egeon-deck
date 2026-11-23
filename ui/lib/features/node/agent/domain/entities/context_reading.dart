import 'dart:math' as math;

/// Quanto da janela de contexto do modelo está em uso. O core lê o transcript e
/// manda os dois números; aqui só se mostra.
class ContextReading {
  const ContextReading({required this.used, required this.window});

  final int used;
  final int window;

  /// O medidor como o core o manda: sem leitura do transcript ainda, `used` e
  /// `window` vêm nulos e não há o que medir (anel vazio e travessão).
  static ContextReading? tryFromMap(Map<String, Object?> map) {
    final used = map['used'] as num?;
    final window = map['window'] as num?;
    if (used == null || window == null) return null;
    return ContextReading(used: used.toInt(), window: window.toInt());
  }

  Map<String, Object?> toMap() => {'used': used, 'window': window};

  double get fraction => math.min(1, used / window);

  /// Para cima: dizer "0%" com a conversa já ocupando algo seria mentira, e
  /// "100%" só quando a janela encheu de fato é o que o arredondamento garante.
  int get usedPercent => math.min(100, (fraction * 100).ceil());

  /// Do verde (120°) ao vermelho (0°), passando pelo amarelo na metade.
  double get hue => 120 * (1 - fraction);

  String get text => '$usedPercent%';

  String get detail => '${short(used)} de ${short(window)} em uso';

  static String short(int tokens) {
    if (tokens >= 1000000) {
      final value = tokens / 1000000;
      return value == value.roundToDouble()
          ? '${value.round()}M'
          : '${value.toStringAsFixed(1)}M';
    }
    return tokens >= 1000 ? '${tokens ~/ 1000}K' : '$tokens';
  }

  @override
  bool operator ==(Object other) =>
      other is ContextReading && other.used == used && other.window == window;

  @override
  int get hashCode => Object.hash(used, window);
}

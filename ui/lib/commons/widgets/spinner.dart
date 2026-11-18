import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Os glifos de "trabalhando". Saem do relógio, e não de um contador de cada
/// widget: todos giram em fase e um que entra na tela não começa do zero.
abstract final class SpinnerGlyph {
  static const _frames = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏';
  static const frameDuration = Duration(milliseconds: 90);

  static String current([DateTime? now]) {
    final step = _step(now, frameDuration);
    return _frames[step % _frames.length];
  }

  /// A ampulheta de quem parou mas deixou trabalho rodando por baixo. Vira
  /// devagar de propósito: não é o agente trabalhando na sua frente.
  static String hourglass([DateTime? now]) =>
      _step(now, const Duration(milliseconds: 600)).isEven ? '⏳' : '⌛';

  static int _step(DateTime? now, Duration every) =>
      (now ?? DateTime.now()).millisecondsSinceEpoch ~/ every.inMilliseconds;
}

/// Reconstrói a cada quadro do spinner (ou da ampulheta) e entrega o glifo.
class SpinnerBuilder extends StatefulWidget {
  const SpinnerBuilder({
    required this.builder,
    this.hourglass = false,
    super.key,
  });

  final Widget Function(BuildContext context, String glyph) builder;
  final bool hourglass;

  @override
  State<SpinnerBuilder> createState() => _SpinnerBuilderState();
}

class _SpinnerBuilderState extends State<SpinnerBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late String _shown = _glyph();

  @override
  void initState() {
    super.initState();
    // Criado aqui, e não num `late final` preguiçoso: nada o lia até o dispose,
    // e o ticker nunca rodava.
    _ticker = createTicker((_) {
      final glyph = _glyph();
      if (glyph != _shown) setState(() => _shown = glyph);
    })..start();
  }

  String _glyph() =>
      widget.hourglass ? SpinnerGlyph.hourglass() : SpinnerGlyph.current();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown);
}

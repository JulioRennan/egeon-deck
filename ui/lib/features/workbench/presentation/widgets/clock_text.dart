import 'package:flutter/widgets.dart';

import '../../../../core/domain/entities/workbench_clock.dart';

/// Os três tempos lado a lado: rodando (ciano — verde no app é "terminou"),
/// esperando você (laranja) e em erro (vermelho). A fase que está contando fica
/// em negrito e em cor cheia.
class ClockText extends StatelessWidget {
  const ClockText(this.clock, {this.size = 11, super.key});

  final WorkbenchClock clock;
  final double size;

  // O texto vem com `︎` (seletor de apresentação) para o símbolo não virar
  // emoji colorido.
  static const _entries = <(ClockPhase, String, Color)>[
    (ClockPhase.running, '⚒︎', Color(0xFF40D9FF)),
    (ClockPhase.waiting, '✋︎', Color(0xFFFF9E1A)),
    (ClockPhase.failed, '⊗', Color(0xFFFF4D4D)),
  ];

  /// O texto inteiro, sem estilo: é o que os testes leem.
  static String plain(WorkbenchClock clock) => [
    for (final (phase, symbol, _) in _entries)
      '$symbol ${WorkbenchClock.format(clock.of(phase))}',
  ].join('   ');

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final (index, (phase, symbol, color)) in _entries.indexed) {
      final lit = clock.ticking.contains(phase);
      final tint = color.withValues(alpha: lit ? 1 : 0.8);
      final style = TextStyle(
        fontSize: size,
        fontWeight: lit ? FontWeight.w700 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: tint,
        decoration: TextDecoration.none,
      );
      if (index > 0) spans.add(TextSpan(text: '   ', style: style));
      spans.add(
        TextSpan(
          text: '$symbol ${WorkbenchClock.format(clock.of(phase))}',
          style: style,
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
    );
  }
}

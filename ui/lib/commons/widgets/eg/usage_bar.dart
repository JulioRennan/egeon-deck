import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'field.dart';
import 'identity.dart';

/// A faixa de preço de um trecho da barra de consumo.
enum Tariff {
  output('Saída', Identity.iris),
  input('Entrada', Identity.slate),
  cacheWrite('Cache escrito', Identity.olive),
  cacheRead('Cache lido', Identity.teal);

  const Tariff(this.label, this.identity);

  final String label;
  final Identity identity;
}

/// Um trecho: o valor mede a largura; [display] é o que se lê (`US$ 0,42`) e
/// [tokens] o detalhe (`14,1K`). Sem [tariff], dê [label] e [color].
class UsageSegment {
  const UsageSegment({
    required this.value,
    required this.display,
    this.tariff,
    this.label,
    this.tokens,
    this.color,
  });

  final double value;
  final String display;
  final Tariff? tariff;
  final String? label;
  final String? tokens;
  final Color? color;
}

/// A barra de consumo: trechos coloridos por tarifa numa faixa de 8, e a
/// legenda com cada tarifa, os tokens e o valor.
class UsageBar extends StatelessWidget {
  const UsageBar({
    required this.segments,
    this.title,
    this.totalLabel,
    this.max,
    this.legend = true,
    super.key,
  });

  final List<UsageSegment> segments;
  final String? title;
  final String? totalLabel;

  /// O que a faixa inteira representa; sem ele, a soma dos trechos.
  final double? max;
  final bool legend;

  Color _color(EgeonColors c, UsageSegment s, int i) =>
      s.color ?? (s.tariff?.identity ?? Identity.auto(i * 3)).color(c);

  String _label(UsageSegment s) => s.label ?? s.tariff?.label ?? '';

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final total = segments.fold<double>(0, (a, s) => a + s.value);
    final scale = max ?? total;
    TextStyle mono(Color color, double size, {FontWeight? weight}) =>
        EgeonType.monoMeta.copyWith(
          fontSize: size,
          height: size == 13 ? 18 / 13 : null,
          fontWeight: weight ?? FontWeight.w400,
          color: color,
          decoration: TextDecoration.none,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null || totalLabel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: fieldText(c.textSecondary, weight: FontWeight.w500),
                  ),
                const Spacer(),
                if (totalLabel != null)
                  Text(totalLabel!, style: mono(c.textPrimary, 13)),
              ],
            ),
          ),
        Semantics(
          label: segments.map((s) => '${_label(s)} ${s.display}').join(', '),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EgeonRadius.xs),
            child: SizedBox(
              height: EgeonSize.dot,
              child: ColoredBox(
                color: c.steel,
                child: Row(
                  children: [
                    for (var i = 0; i < segments.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      Expanded(
                        flex: (segments[i].value / scale * 10000).round().clamp(
                          0,
                          10000,
                        ),
                        child: ColoredBox(color: _color(c, segments[i], i)),
                      ),
                    ],
                    Expanded(
                      flex: ((1 - total / scale).clamp(0, 1) * 10000).round(),
                      child: const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (legend)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: LayoutBuilder(
              builder: (context, box) {
                final cell = (box.maxWidth - EgeonSpace.s6) / 2;
                return Wrap(
                  spacing: EgeonSpace.s6,
                  runSpacing: EgeonSpace.s2,
                  children: [
                    for (var i = 0; i < segments.length; i++)
                      SizedBox(
                        width: cell,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: SizedBox(
                                width: 8,
                                height: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _color(c, segments[i], i),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _label(segments[i]),
                                    style: EgeonType.caption.copyWith(
                                      fontWeight: FontWeight.w400,
                                      color: c.textMuted,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  if (segments[i].tokens != null)
                                    Text(
                                      '${segments[i].tokens} tokens',
                                      style: mono(c.textMuted, 11),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              segments[i].display,
                              style: mono(
                                c.textSecondary,
                                12,
                                weight: const FontWeight(450),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }
}

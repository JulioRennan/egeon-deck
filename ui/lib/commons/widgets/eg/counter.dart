import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';

enum CounterTone { neutral, attention, waiting }

/// O contador redondo (DS `.eg-counter`): 20×20 no mínimo, respiro de 6, mono
/// 11 w600. Neutro em `steelActive`; pedidos de permissão em `attention`;
/// segundo plano em `waitingSoft` com ampulheta de 10. Acima de 99, `99+`.
class Counter extends StatelessWidget {
  const Counter(
    this.count, {
    this.tone = CounterTone.neutral,
    this.icon,
    this.label,
    super.key,
  });

  final int count;
  final CounterTone tone;
  final EgIconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final (background, foreground) = switch (tone) {
      CounterTone.neutral => (c.steelActive, c.textSecondary),
      CounterTone.attention => (c.attention, c.onAttention),
      CounterTone.waiting => (c.waitingSoft, c.waiting),
    };
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(EgeonRadius.full),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  EgIcon(icon!, size: 10, strokeWidth: 1.75, color: foreground),
                  const SizedBox(width: 2),
                ],
                Text(
                  count > 99 ? '99+' : '$count',
                  style: EgeonType.monoMeta.copyWith(
                    fontSize: 11,
                    height: 1,
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

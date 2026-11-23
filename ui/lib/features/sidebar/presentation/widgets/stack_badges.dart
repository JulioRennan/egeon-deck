import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../theme/egeon_colors.dart';
import '../../domain/entities/stack_badge.dart';

/// Os selos de stack do projeto (a v3): até 5, 16 × 16, raio 4, a sigla em
/// 7,5 w600 sobre `steelActive`, com o nome na dica. Sem selos, não ocupa
/// lugar — o core ainda não detecta a stack, e a linha fica como está.
class StackBadges extends StatelessWidget {
  const StackBadges(this.badges, {super.key});

  final List<StackBadge> badges;

  static const max = 5;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    final c = context.eg;
    final shown = badges.take(max).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Tooltip(
        message: shown.map((b) => b.name).join(' · '),
        child: Semantics(
          label: 'Stack: ${shown.map((b) => b.name).join(' · ')}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, badge) in shown.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                SizedBox(
                  key: ValueKey('stack-${badge.abbr}'),
                  width: 16,
                  height: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.steelActive,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        badge.abbr,
                        style: TextStyle(
                          fontFamily: 'Noto Sans',
                          fontSize: 7.5,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

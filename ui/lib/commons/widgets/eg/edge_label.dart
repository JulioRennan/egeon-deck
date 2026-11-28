import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'tooltip.dart';

/// `active` (com tráfego, `running`), `spent` (limite gasto) ou `selected`.
enum EdgeLabelState { active, spent, selected }

/// O rótulo no meio da aresta (DS `.eg-edge-label`): 22 de altura, raio 6,
/// fundo `graphite` com fio de 1px `line`, mono 11 em `textMuted`. Mostra quantas
/// vezes um lado pode acionar o outro (`3/5`, ou `∞` sem limite). Ativa vira
/// `running`; gasta, `textDisabled`; selecionada, `accent`.
class EdgeLabel extends StatelessWidget {
  const EdgeLabel({this.used, this.max, this.state, super.key});

  final int? used;

  /// Nulo é sem limite.
  final int? max;
  final EdgeLabelState? state;

  String get text => '${used == null ? '' : '$used/'}${max ?? '∞'}';

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final (ring, foreground) = switch (state) {
      EdgeLabelState.active => (c.running, c.running),
      EdgeLabelState.spent => (c.line, c.textDisabled),
      EdgeLabelState.selected => (c.accent, c.accent),
      null => (c.line, c.textMuted),
    };
    return Tooltip(
      message: 'Envios usados / limite da aresta',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.graphite,
          borderRadius: BorderRadius.circular(EgeonRadius.sm),
          border: Border.all(color: ring),
        ),
        child: SizedBox(
          height: 22,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EgeonSpace.s2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                EgIcon(EgIcons.refresh, size: 12, color: foreground),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: EgeonType.monoMeta.copyWith(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w400,
                    color: foreground,
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

import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';

enum ClockPhase { work, you, error }

/// O cronômetro da bancada (DS `.eg-clock`) em três fases: martelo
/// (trabalhando), mão (esperando você) e octógono (em erro), cada uma com o
/// seu `mm:ss`. Fase zerada: ícone `textDisabled`, texto `textMuted`. Ligada:
/// texto `textSecondary`, ícone `textMuted`; `you` é `attention` e `error` é
/// `danger`. A que está contando agora ([active]) leva o texto em
/// `textPrimary`. No [compact] (barra lateral) só a fase que manda aparece:
/// você, depois erro, depois trabalho.
class WorkbenchClock extends StatelessWidget {
  const WorkbenchClock({
    this.work = Duration.zero,
    this.you = Duration.zero,
    this.error = Duration.zero,
    this.active,
    this.compact = false,
    super.key,
  });

  final Duration work;
  final Duration you;
  final Duration error;
  final ClockPhase? active;
  final bool compact;

  Duration _value(ClockPhase p) => switch (p) {
    ClockPhase.work => work,
    ClockPhase.you => you,
    ClockPhase.error => error,
  };

  /// A fase que manda no [compact]; nula se tudo está zerado.
  ClockPhase? get lead {
    for (final p in [ClockPhase.you, ClockPhase.error, ClockPhase.work]) {
      if (_value(p) > Duration.zero) return p;
    }
    return null;
  }

  /// `mm:ss`, ou `h:mm:ss` a partir de uma hora (o mesmo formato do core).
  static String format(Duration d) {
    final hours = d.inHours;
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final phases = compact ? [?lead] : ClockPhase.values;
    Widget phase(ClockPhase p) {
      final on = _value(p) > Duration.zero;
      var text = on ? c.textSecondary : c.textMuted;
      var icon = on ? c.textMuted : c.textDisabled;
      if (on && p == ClockPhase.you) text = icon = c.attention;
      if (on && p == ClockPhase.error) text = icon = c.danger;
      if (active == p) text = c.textPrimary;
      final glyph = switch (p) {
        ClockPhase.work => EgIcons.hammer,
        ClockPhase.you => EgIcons.hand,
        ClockPhase.error => EgIcons.octagon,
      };
      final title = switch (p) {
        ClockPhase.work => 'Trabalhando',
        ClockPhase.you => 'Esperando você',
        ClockPhase.error => 'Em erro',
      };
      return Semantics(
        label: '$title ${format(_value(p))}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EgIcon(glyph, size: 12, color: icon),
            const SizedBox(width: 4),
            Text(
              format(_value(p)),
              style: EgeonType.monoMeta.copyWith(
                color: text,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < phases.length; i++) ...[
          if (i > 0) SizedBox(width: compact ? EgeonSpace.s2 : EgeonSpace.s3),
          phase(phases[i]),
        ],
      ],
    );
  }
}

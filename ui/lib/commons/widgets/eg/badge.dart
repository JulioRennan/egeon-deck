import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'spinner.dart';
import 'status.dart';

/// `neutral` e `outline` são do próprio Badge; os demais tons são os estados.
sealed class BadgeTone {
  const BadgeTone();

  static const neutral = _Neutral();
  static const outline = _Outline();
  static BadgeTone status(Status status) => _OfStatus(status);
}

class _Neutral extends BadgeTone {
  const _Neutral();
}

class _Outline extends BadgeTone {
  const _Outline();
}

class _OfStatus extends BadgeTone {
  const _OfStatus(this.status);

  final Status status;
}

/// Etiqueta (DS `.eg-badge`): 24 de altura, respiro de 10, raio 6, vão de 6.
/// Estado = fundo suave na cor do estado, texto e glifo na cor cheia. Neutro e
/// contorno: sem fundo, fio interno de 1px `lineStrong`, mono 12 w450, respiro
/// de 8, glifo em `textMuted`.
class Badge extends StatelessWidget {
  const Badge(
    this.text, {
    this.tone = BadgeTone.neutral,
    this.icon,
    this.showIcon = true,
    super.key,
  });

  final String text;
  final BadgeTone tone;

  /// Troca o ícone padrão do tom.
  final EgIconData? icon;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final plain = tone is! _OfStatus;
    final (background, foreground) = switch (tone) {
      _OfStatus(:final status) => switch (status) {
        Status.attention => (c.attentionSoft, c.attention),
        Status.running => (c.runningSoft, c.running),
        Status.success => (c.successSoft, c.success),
        Status.danger => (c.dangerSoft, c.danger),
        Status.background || Status.waiting => (c.waitingSoft, c.waiting),
        Status.retrying ||
        Status.idle ||
        Status.dead => (c.steel, c.textSecondary),
      },
      _ => (null, c.textSecondary),
    };
    Widget? lead;
    if (showIcon) {
      final iconColor = plain ? c.textMuted : foreground;
      if (icon != null) {
        lead = EgIcon(icon!, size: 12, color: iconColor);
      } else if (tone is _OfStatus) {
        lead = switch ((tone as _OfStatus).status) {
          Status.running => const Spinner(size: 12),
          Status.attention => SizedBox(
            width: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Status.success => EgIcon(EgIcons.check, size: 12, color: iconColor),
          Status.danger => EgIcon(EgIcons.octagon, size: 12, color: iconColor),
          Status.background || Status.waiting => EgIcon(
            EgIcons.hourglass,
            size: 12,
            color: iconColor,
          ),
          Status.retrying => EgIcon(
            EgIcons.refresh,
            size: 12,
            color: iconColor,
          ),
          Status.idle || Status.dead => null,
        };
      }
    }
    final style = plain
        ? EgeonType.monoMeta
        : EgeonType.caption.copyWith(letterSpacing: 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(EgeonRadius.sm),
        border: plain ? Border.all(color: c.lineStrong) : null,
      ),
      child: SizedBox(
        height: 24,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: plain ? 8 : 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 6)],
              Text(
                text,
                style: style.copyWith(
                  color: foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

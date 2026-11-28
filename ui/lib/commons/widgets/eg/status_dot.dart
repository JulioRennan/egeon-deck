import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'attention_ring.dart';
import 'eg_icon.dart';
import 'spinner.dart';
import 'status.dart';

enum StatusDotSize { sm, md }

/// O estado de um agente em cor **e** forma: dot (precisa de você, terminou,
/// falhou), spinner (trabalhando), ampulheta (segundo plano, aguardando),
/// ⟳ (tentando de novo), dot vazado (parado, encerrado). Dot redondo é só
/// estado, nunca identidade.
class StatusDot extends StatelessWidget {
  const StatusDot(
    this.status, {
    this.size = StatusDotSize.md,
    this.animated = false,
    this.label,
    this.showLabel = false,
    super.key,
  });

  final Status status;
  final StatusDotSize size;

  /// `attention` pulsa (o halo) e `running` vira spinner.
  final bool animated;

  /// Texto ao lado; sem ele, [showLabel] usa o nome do estado.
  final String? label;
  final bool showLabel;

  static double dotSize(StatusDotSize s) =>
      s == StatusDotSize.sm ? 6 : EgeonSize.dot;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final d = dotSize(size);
    Widget solid(Color color) => SizedBox(
      width: d,
      height: d,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
    Widget hollow(Color color) => SizedBox(
      width: d,
      height: d,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      ),
    );
    final Widget glyph = switch (status) {
      Status.attention =>
        animated
            ? AttentionRing(round: true, ring: false, child: solid(c.attention))
            : solid(c.attention),
      Status.running => animated ? const Spinner(size: 12) : solid(c.running),
      Status.success => solid(c.success),
      Status.danger => solid(c.danger),
      Status.background ||
      Status.waiting => EgIcon(EgIcons.hourglass, size: 12, color: c.waiting),
      Status.retrying => EgIcon(
        EgIcons.refresh,
        size: 12,
        color: c.textSecondary,
      ),
      Status.idle => hollow(c.textDisabled),
      Status.dead => hollow(c.lineStrong),
    };
    final text = label ?? (showLabel ? status.label : null);
    final dot = Semantics(
      label: text == null ? status.label : null,
      child: glyph,
    );
    if (text == null) return dot;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: EgeonSpace.s2),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EgeonType.small.copyWith(
              color: c.textSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

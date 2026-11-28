import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_type.dart';

/// O contexto em uso do agente: anel que enche (cinza, laranja a partir de 80%,
/// vermelho a partir de 95%) e a porcentagem em mono. Sem valor, só o trilho e
/// "—".
class ContextRing extends StatelessWidget {
  const ContextRing(
    this.value, {
    this.size = 14,
    this.showValue = true,
    super.key,
  });

  /// De 0 a 1, ou nulo (ainda não medido).
  final double? value;
  final double size;
  final bool showValue;

  static Color tone(EgeonColors c, double v) => v >= 0.95
      ? c.danger
      : v >= 0.8
      ? c.attention
      : c.textSecondary;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final v = value;
    return Semantics(
      label: 'Contexto em uso',
      value: v == null ? null : '${(v * 100).ceil()}%',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(
              v,
              track: c.steelActive,
              fill: v == null ? c.steelActive : tone(c, v),
            ),
          ),
          if (showValue) ...[
            const SizedBox(width: 6),
            Text(
              v == null ? '—' : '${(v * 100).ceil()}%',
              style: EgeonType.monoMeta.copyWith(
                color: c.textMuted,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, {required this.track, required this.fill});

  final double? value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1.5;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, r, paint..color = track);
    final v = value;
    if (v == null) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * v.clamp(0, 1),
      false,
      paint..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/domain/entities/activity_summary.dart';
import '../../theme/app_colors.dart';

/// O recado da borda: um cometa que dá a volta no item quando o agente pede
/// você (laranja) ou terminou (verde). `focus` é só o aro parado.
enum AttentionTone {
  asking(AppColors.attention),
  done(AppColors.done),
  focus(AppColors.accent);

  const AttentionTone(this.color);

  final Color color;

  /// Pedir você vale mais que ter terminado.
  static AttentionTone? of(ActivitySummary summary) {
    if (summary.attention > 0) return asking;
    return summary.done > 0 ? done : null;
  }
}

class AttentionRing extends StatefulWidget {
  const AttentionRing({
    required this.tone,
    required this.radius,
    required this.child,
    this.lineWidth = 1.5,
    this.focusColor,
    super.key,
  });

  final AttentionTone? tone;

  /// A cor do aro de foco (a da bancada); sem ela vale o destaque do app.
  final Color? focusColor;
  final double radius;
  final double lineWidth;
  final Widget child;

  /// Uma volta completa do cometa.
  static const period = Duration(seconds: 6);

  @override
  State<AttentionRing> createState() => _AttentionRingState();
}

class _AttentionRingState extends State<AttentionRing>
    with SingleTickerProviderStateMixin {
  final _progress = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((elapsed) {
    _progress.value =
        (elapsed.inMicroseconds % AttentionRing.period.inMicroseconds) /
        AttentionRing.period.inMicroseconds;
  });

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AttentionRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Só gira com cometa: `focus` é aro parado, e sem tom nada se mexe.
  void _sync() {
    final spins = widget.tone != null && widget.tone != AttentionTone.focus;
    if (spins && !_ticker.isActive) _ticker.start();
    if (!spins && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    if (tone == null) return widget.child;
    return CustomPaint(
      foregroundPainter: _RingPainter(
        tone: tone,
        color: tone == AttentionTone.focus ? widget.focusColor : null,
        radius: widget.radius,
        lineWidth: widget.lineWidth,
        progress: _progress,
      ),
      child: widget.child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.tone,
    required this.color,
    required this.radius,
    required this.lineWidth,
    required this.progress,
  }) : super(repaint: progress);

  final AttentionTone tone;
  final Color? color;
  final double radius;
  final double lineWidth;
  final ValueListenable<double> progress;

  static const _slices = 24;

  /// A cauda some devagar e a cabeça acende de uma vez.
  static double _alpha(int slice) {
    final f = (slice + 1) / _slices;
    return f < 0.6 ? 0.35 * f / 0.6 : 0.35 + 0.65 * (f - 0.6) / 0.4;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(lineWidth / 2);
    final r = math.max(
      0.0,
      math.min(radius - lineWidth / 2, math.min(inset.width, inset.height) / 2),
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(inset, Radius.circular(r)));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth;

    final base = color ?? tone.color;
    final focus = tone == AttentionTone.focus;
    canvas.drawPath(
      path,
      stroke..color = base.withValues(alpha: focus ? 0.85 : 0.28),
    );
    if (focus) return;

    final metric = path.computeMetrics().first;
    final length = metric.length;
    final comet = math.min(length * 0.35, 180.0);
    final slice = comet / _slices;
    final head = progress.value * length;
    stroke.strokeWidth = lineWidth + 0.5;
    for (var k = 0; k < _slices; k++) {
      // Meio ponto a mais em cada fatia: encostadas exatas, o antisserrilhado
      // deixa um fio escuro entre uma e outra.
      final from = head - comet + k * slice;
      stroke.color = base.withValues(alpha: _alpha(k));
      for (final piece in _wrap(from, from + slice + 0.5, length)) {
        canvas.drawPath(metric.extractPath(piece.$1, piece.$2), stroke);
      }
    }
  }

  /// O traço que passa do fim do perímetro volta pelo começo.
  static List<(double, double)> _wrap(double a, double b, double length) {
    final start = a % length;
    final end = start + (b - a);
    if (end <= length) return [(start, end)];
    return [(start, length), (0, end - length)];
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.tone != tone ||
      old.color != color ||
      old.radius != radius ||
      old.lineWidth != lineWidth;
}

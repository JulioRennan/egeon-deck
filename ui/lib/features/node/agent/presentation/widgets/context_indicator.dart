import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../../theme/app_colors.dart';
import '../../domain/entities/context_reading.dart';

/// O contexto em uso no cabeçalho do card: uma pizza que enche com a
/// porcentagem ao lado, as duas indo do verde ao vermelho conforme a janela
/// enche. Nulo é "não se sabe": anel vazio e travessão.
class ContextIndicator extends StatelessWidget {
  const ContextIndicator({required this.reading, super.key});

  final ContextReading? reading;

  static const pieSize = 12.0;
  static final _idle = AppColors.white(0.62);

  Color get _color {
    final reading = this.reading;
    if (reading == null) return _idle;
    return HSVColor.fromAHSV(1, reading.hue, 0.72, 0.95).toColor();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CustomPaint(
        size: const Size.square(pieSize),
        painter: _PiePainter(reading, _color),
      ),
      const SizedBox(width: 4),
      Text(
        reading?.text ?? '—',
        key: const ValueKey('context-text'),
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          fontFamily: 'Menlo',
          decoration: TextDecoration.none,
        ),
      ),
    ],
  );
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.reading, this.color);

  final ContextReading? reading;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    canvas.drawOval(circle, Paint()..color = AppColors.white(0.1));
    final reading = this.reading;
    if (reading == null || reading.used <= 0) {
      canvas.drawOval(
        circle,
        Paint()
          ..color = AppColors.white(0.28)
          ..style = PaintingStyle.stroke,
      );
      return;
    }
    canvas.drawOval(
      circle,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke,
    );
    final fill = Paint()..color = color;
    if (reading.fraction >= 1) {
      canvas.drawOval(circle, fill);
      return;
    }
    // Começa no topo e anda no sentido horário.
    canvas.drawArc(
      circle,
      -math.pi / 2,
      2 * math.pi * reading.fraction,
      true,
      fill,
    );
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.reading != reading || old.color != color;
}

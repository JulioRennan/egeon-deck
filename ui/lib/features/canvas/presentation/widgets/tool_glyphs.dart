import 'package:flutter/widgets.dart';

enum ToolGlyphKind {
  cursor,
  terminal,
  web,
  queue,
  minus,
  plus,
  fit,
  saveTemplate,
  updateTemplate,
  branch,
}

/// Os ícones da barra, desenhados: não há fonte de símbolos no app.
class ToolGlyph extends StatelessWidget {
  const ToolGlyph(this.kind, {required this.color, this.size = 18, super.key});

  final ToolGlyphKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ToolGlyphPainter(kind, color),
  );
}

class _ToolGlyphPainter extends CustomPainter {
  _ToolGlyphPainter(this.kind, this.color);

  final ToolGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    switch (kind) {
      case ToolGlyphKind.cursor:
        canvas.drawPath(
          Path()
            ..moveTo(s * 0.26, s * 0.14)
            ..lineTo(s * 0.26, s * 0.82)
            ..lineTo(s * 0.44, s * 0.64)
            ..lineTo(s * 0.58, s * 0.9)
            ..lineTo(s * 0.68, s * 0.84)
            ..lineTo(s * 0.54, s * 0.58)
            ..lineTo(s * 0.8, s * 0.58)
            ..close(),
          fill,
        );
      case ToolGlyphKind.terminal:
        canvas
          ..drawRRect(
            RRect.fromLTRBR(
              s * 0.1,
              s * 0.18,
              s * 0.9,
              s * 0.82,
              Radius.circular(s * 0.14),
            ),
            stroke,
          )
          ..drawPath(
            Path()
              ..moveTo(s * 0.26, s * 0.38)
              ..lineTo(s * 0.4, s * 0.5)
              ..lineTo(s * 0.26, s * 0.62),
            stroke,
          )
          ..drawLine(
            Offset(s * 0.5, s * 0.64),
            Offset(s * 0.7, s * 0.64),
            stroke,
          );
      case ToolGlyphKind.web:
        final c = Offset(s / 2, s / 2);
        canvas
          ..drawCircle(c, s * 0.38, stroke)
          ..drawOval(
            Rect.fromCenter(center: c, width: s * 0.36, height: s * 0.76),
            stroke,
          )
          ..drawLine(Offset(s * 0.12, s / 2), Offset(s * 0.88, s / 2), stroke);
      case ToolGlyphKind.queue:
        for (var i = 0; i < 3; i++) {
          final y = s * (0.26 + i * 0.24);
          canvas
            ..drawCircle(Offset(s * 0.18, y), s * 0.045, fill)
            ..drawLine(Offset(s * 0.34, y), Offset(s * 0.86, y), stroke);
        }
      case ToolGlyphKind.minus:
        canvas.drawLine(
          Offset(s * 0.25, s / 2),
          Offset(s * 0.75, s / 2),
          stroke,
        );
      case ToolGlyphKind.plus:
        canvas
          ..drawLine(Offset(s * 0.25, s / 2), Offset(s * 0.75, s / 2), stroke)
          ..drawLine(Offset(s / 2, s * 0.25), Offset(s / 2, s * 0.75), stroke);
      case ToolGlyphKind.fit:
        const a = 0.14, b = 0.34;
        for (final (sx, sy) in [
          (1.0, 1.0),
          (-1.0, 1.0),
          (1.0, -1.0),
          (-1.0, -1.0),
        ]) {
          final cx = sx > 0 ? s * a : s * (1 - a);
          final cy = sy > 0 ? s * a : s * (1 - a);
          canvas.drawPath(
            Path()
              ..moveTo(cx, cy + sy * s * b)
              ..lineTo(cx, cy)
              ..lineTo(cx + sx * s * b, cy),
            stroke,
          );
        }
      case ToolGlyphKind.saveTemplate:
        // Bandeja com a seta descendo: guardar a montagem.
        canvas
          ..drawPath(
            Path()
              ..moveTo(s * 0.16, s * 0.56)
              ..lineTo(s * 0.16, s * 0.84)
              ..lineTo(s * 0.84, s * 0.84)
              ..lineTo(s * 0.84, s * 0.56),
            stroke,
          )
          ..drawLine(Offset(s / 2, s * 0.14), Offset(s / 2, s * 0.64), stroke)
          ..drawPath(
            Path()
              ..moveTo(s * 0.32, s * 0.46)
              ..lineTo(s / 2, s * 0.64)
              ..lineTo(s * 0.68, s * 0.46),
            stroke,
          );
      case ToolGlyphKind.updateTemplate:
        final c = Offset(s / 2, s / 2);
        final r = s * 0.32;
        canvas
          ..drawArc(
            Rect.fromCircle(center: c, radius: r),
            -1.2,
            5.2,
            false,
            stroke,
          )
          ..drawPath(
            Path()
              ..moveTo(s * 0.62, s * 0.12)
              ..lineTo(s * 0.66, s * 0.22)
              ..lineTo(s * 0.54, s * 0.27),
            stroke,
          );
      case ToolGlyphKind.branch:
        canvas
          ..drawCircle(Offset(s * 0.3, s * 0.2), s * 0.09, stroke)
          ..drawCircle(Offset(s * 0.3, s * 0.8), s * 0.09, stroke)
          ..drawCircle(Offset(s * 0.72, s * 0.32), s * 0.09, stroke)
          ..drawLine(
            Offset(s * 0.3, s * 0.29),
            Offset(s * 0.3, s * 0.71),
            stroke,
          )
          ..drawPath(
            Path()
              ..moveTo(s * 0.72, s * 0.41)
              ..quadraticBezierTo(s * 0.72, s * 0.62, s * 0.3, s * 0.66),
            stroke,
          );
    }
  }

  @override
  bool shouldRepaint(_ToolGlyphPainter old) =>
      old.kind != kind || old.color != color;
}

import 'package:flutter/widgets.dart';

/// A sombra da cor da bancada por dentro da borda do canvas (ADR-086). Sombra e
/// não fundo tingido: o meio do canvas, onde estão os terminais, fica como
/// sempre foi, e a cor só se nota de canto de olho. Só enfeite: o clique passa.
class CanvasGlow extends StatelessWidget {
  const CanvasGlow({required this.color, super.key});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final glow = color;
    if (glow == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(size: Size.infinite, painter: _GlowPainter(glow)),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    // Uma moldura grossa FORA da vista projeta a sombra para dentro; o recorte
    // corta a moldura e deixa só o esmaecido.
    final frame = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds.inflate(80))
      ..addRect(bounds);
    canvas.drawPath(
      frame,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color;
}

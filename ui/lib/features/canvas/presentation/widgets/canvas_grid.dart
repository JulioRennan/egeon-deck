import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/canvas_viewport.dart';

/// O fundo do canvas: cor lisa e o grid de 40 unidades de documento. Pintado
/// no espaço da janela, só no que está visível — o documento chega a 120 mil
/// unidades e não cabe numa textura.
class CanvasGrid extends StatelessWidget {
  const CanvasGrid({required this.viewport, super.key});

  final CanvasViewport viewport;

  static const step = 40.0;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(size: Size.infinite, painter: _GridPainter(viewport)),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.viewport);

  final CanvasViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.canvasBackground,
    );

    final zoom = viewport.zoom;
    final origin = viewport.origin;
    final line = Paint()
      ..color = AppColors.white(0.045)
      ..strokeWidth = 1;
    final firstX = (origin.dx / CanvasGrid.step).floor() * CanvasGrid.step;
    for (
      var x = firstX;
      (x - origin.dx) * zoom < size.width;
      x += CanvasGrid.step
    ) {
      final sx = ((x - origin.dx) * zoom).roundToDouble() + 0.5;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), line);
    }
    final firstY = (origin.dy / CanvasGrid.step).floor() * CanvasGrid.step;
    for (
      var y = firstY;
      (y - origin.dy) * zoom < size.height;
      y += CanvasGrid.step
    ) {
      final sy = ((y - origin.dy) * zoom).roundToDouble() + 0.5;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.viewport.zoom != viewport.zoom ||
      old.viewport.origin != viewport.origin;
}

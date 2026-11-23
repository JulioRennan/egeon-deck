import 'dart:ui' show PointMode;

import 'package:flutter/widgets.dart';

import '../../../../theme/egeon_colors.dart';
import '../../domain/entities/canvas_viewport.dart';

/// O fundo do canvas: `graphite` liso e a grade de pontos de 24 unidades de
/// documento (raio 1, cor `line`), que anda e cresce com a vista. Pintado no
/// espaço da janela, só no que está visível — o documento chega a 120 mil
/// unidades e não cabe numa textura. Sem sombra e sem desfoque.
class CanvasGrid extends StatelessWidget {
  const CanvasGrid({required this.viewport, super.key});

  final CanvasViewport viewport;

  static const step = 24.0;

  /// Abaixo disto o ponto vira poeira: a grade passa a pular de duas em duas.
  static const minSpacing = 10.0;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.infinite,
      painter: _GridPainter(viewport, context.eg),
    ),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.viewport, this.colors);

  final CanvasViewport viewport;
  final EgeonColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.graphite);

    final zoom = viewport.zoom;
    final origin = viewport.origin;
    var step = CanvasGrid.step;
    while (step * zoom < CanvasGrid.minSpacing) {
      step *= 2;
    }
    final dots = <Offset>[];
    final firstX = (origin.dx / step).floor() * step;
    final firstY = (origin.dy / step).floor() * step;
    for (var y = firstY; (y - origin.dy) * zoom < size.height; y += step) {
      final sy = (y - origin.dy) * zoom;
      for (var x = firstX; (x - origin.dx) * zoom < size.width; x += step) {
        dots.add(Offset((x - origin.dx) * zoom, sy));
      }
    }
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..color = colors.line
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.viewport.zoom != viewport.zoom ||
      old.viewport.origin != viewport.origin ||
      old.colors != colors;
}

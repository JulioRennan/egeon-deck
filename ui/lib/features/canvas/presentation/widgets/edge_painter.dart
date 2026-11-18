import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';

import '../../../../theme/app_colors.dart';
import '../../domain/entities/edge_curve.dart';
import '../../domain/entities/edge_layout.dart';
import '../../domain/entities/edge_link.dart';
import '../cubit/canvas_cubit.dart';

/// Desenha as arestas atrás dos nós, no espaço do documento.
///
/// Camada à parte do grid: o grid é enorme, e invalidá-lo a cada pixel de
/// arrasto de nó repintaria o grid junto. Aqui só as curvas são refeitas.
///
/// Tudo que existe para ser LIDO — ponta, bolinha, espessura — é medido em
/// pontos de TELA e multiplicado por [screenPoint]; o traçado em si não, porque
/// quem escala são os cards.
class EdgePainter extends CustomPainter {
  EdgePainter({
    required this.links,
    required this.frames,
    required this.zoom,
    this.hovered,
    this.pending,
  });

  final List<EdgeLink> links;
  final Map<String, Rect> frames;
  final double zoom;
  final EdgeLink? hovered;
  final PendingLink? pending;

  /// Quanto vale um ponto de tela em unidades de documento. O piso de 0.05 é
  /// contra divisão por zero na animação de zoom.
  double get screenPoint => zoom > 0.05 ? 1 / zoom : 20;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in links) {
      final a = frames[link.a];
      final b = frames[link.b];
      if (a == null || b == null) continue;
      _draw(canvas, EdgeLayout.lay(link, a, b), highlighted: link == hovered);
    }
    final pending = this.pending;
    final source = pending == null ? null : frames[pending.from];
    if (pending != null && source != null) {
      // Arrastando, o destino ainda é o cursor e não um card: rota direta,
      // tracejada, sem decidir loop por um ponto que vai mudar. Com as duas
      // pontas, porque é bidirecional que vai nascer quando você soltar.
      _draw(
        canvas,
        LaidEdge(
          route: DirectRoute(EdgeCurve.sourcePort(source), pending.to),
          headAtStart: true,
          headAtEnd: true,
        ),
        highlighted: true,
        dashed: true,
      );
    }
  }

  void _draw(
    Canvas canvas,
    LaidEdge laid, {
    required bool highlighted,
    bool dashed = false,
  }) {
    final z = screenPoint;
    var path = EdgeCurve.path(laid.route);
    if (dashed) path = _dash(path, 6 * z, 5 * z);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (highlighted ? 2.5 : 1.8) * z
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = highlighted ? AppColors.attention : AppColors.white(0.32),
    );

    // Ponta e bolinha em cor OPACA, e não na translúcida da linha: o triângulo
    // cresce por cima do traçado, e com os dois a 32% os alphas somam — dá para
    // ver o fio atravessando a seta por dentro.
    final solid = highlighted ? AppColors.attention : AppColors.edgeLineSolid;
    final ends = EdgeCurve.endpoints(laid.route);
    // Bolinha só na extremidade sem ponta: as duas no mesmo lugar viram um
    // borrão, e a ponta já diz que a linha encosta ali.
    if (!laid.headAtStart) _port(canvas, ends.start, solid);
    if (!laid.headAtEnd) _port(canvas, ends.end, solid);
    if (laid.headAtStart) _head(canvas, ends.start, ends.startTangent, solid);
    if (laid.headAtEnd) _head(canvas, ends.end, ends.endTangent, solid);
  }

  void _port(Canvas canvas, Offset point, Color color) => canvas.drawCircle(
    point,
    EdgeCurve.portRadius * screenPoint,
    Paint()..color = color,
  );

  /// Triângulo com o vértice encostado na borda do card e o corpo para fora
  /// dele: crescer para dentro cobriria o cabeçalho, onde ficam o título e os
  /// avisos de estado.
  void _head(Canvas canvas, Offset tip, Offset direction, Color color) {
    final size = EdgeCurve.arrowSize * screenPoint;
    final normal = Offset(-direction.dy, direction.dx);
    final base = tip - direction * size;
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        base.dx + normal.dx * size * 0.42,
        base.dy + normal.dy * size * 0.42,
      )
      ..lineTo(
        base.dx - normal.dx * size * 0.42,
        base.dy - normal.dy * size * 0.42,
      )
      ..close();
    canvas.drawPath(head, Paint()..color = color);
  }

  static Path _dash(Path source, double on, double off) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        out.addPath(
          metric.extractPath(
            distance,
            ui.clampDouble(distance + on, 0, metric.length),
          ),
          Offset.zero,
        );
        distance += on + off;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(EdgePainter old) =>
      old.zoom != zoom ||
      old.hovered != hovered ||
      old.links != links ||
      !mapEquals(old.frames, frames) ||
      old.pending?.from != pending?.from ||
      old.pending?.to != pending?.to;
}

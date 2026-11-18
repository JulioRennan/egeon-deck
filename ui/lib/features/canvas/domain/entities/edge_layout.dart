import 'dart:math' as math;
import 'dart:ui';

import 'canvas_viewport.dart';
import 'edge_curve.dart';
import 'edge_link.dart';

/// Onde a linha de uma ligação passa, e em qual extremidade vai cada ponta.
class LaidEdge {
  const LaidEdge({
    required this.route,
    required this.headAtStart,
    required this.headAtEnd,
  });

  final EdgeRoute route;
  final bool headAtStart;

  /// A extremidade em que o traçado termina leva ponta.
  final bool headAtEnd;

  /// O glifo mostra o que a linha faz AGORA, na orientação em que ela está
  /// desenhada — clicar troca para o próximo estado.
  String get directionGlyph {
    if (headAtEnd && headAtStart) return '↔';
    return headAtEnd ? '→' : '←';
  }
}

/// Os três controles da ligação sob o cursor, em pixels da janela.
class EdgeControls {
  const EdgeControls({
    required this.direction,
    required this.pill,
    required this.remove,
    required this.hull,
  });

  final Rect direction;
  final Rect pill;
  final Rect remove;

  /// Área invisível que mantém os controles no ar. Sem ela o realce seria
  /// decidido só pela distância à curva, e os controles ficam acima dela: subir
  /// o mouse para clicar sai da zona e eles somem antes de você chegar.
  final Rect hull;

  bool hit(Offset point) =>
      direction.contains(point) ||
      pill.contains(point) ||
      remove.contains(point);
}

/// Geometria de desenho e de mouse das ligações. Tudo que existe para ser LIDO
/// ou CLICADO — controles, tolerância — é medido em pixels de TELA, e por isso
/// vive no espaço da janela; o traçado em si vive no do documento, porque
/// quem escala são os cards.
abstract final class EdgeLayout {
  /// Controles do tamanho de alvo de clique de verdade.
  static const buttonSize = 32.0;
  static const pillSize = Size(68, 32);
  static const controlGap = 7.0;

  /// Altura entre a curva e a base dos controles.
  static const controlLift = 14.0;

  /// Quão perto da linha o cursor tem de estar, em pixels de tela.
  static const hoverTolerance = 14.0;

  static LaidEdge lay(EdgeLink link, Rect frameA, Rect frameB) {
    final aFirst =
        EdgeCurve.prefersDirect(frameA, frameB) ||
        !EdgeCurve.prefersDirect(frameB, frameA);
    final route = aFirst
        ? EdgeCurve.route(frameA, frameB)
        : EdgeCurve.route(frameB, frameA);
    // A ponta fica onde o sentido CHEGA: `a→b` desenha ponta do lado de b, e
    // quem é o lado de b depende de quem virou origem do traçado.
    return LaidEdge(
      route: route,
      headAtEnd: aFirst ? link.aToB : link.bToA,
      headAtStart: aFirst ? link.bToA : link.aToB,
    );
  }

  /// Controles acima da curva, e não sobre ela: em cima da linha eles tapam a
  /// ponta da seta justamente quando você precisa conferir o sentido.
  static EdgeControls controls(LaidEdge laid, CanvasViewport viewport) {
    final (mid, _) = EdgeCurve.midpoint(laid.route);
    final point = viewport.toScreen(mid);
    final total =
        buttonSize + controlGap + pillSize.width + controlGap + buttonSize;
    final top = EdgeCurve.controlsTop(
      route: laid.route,
      midpoint: point,
      height: math.max(pillSize.height, buttonSize),
      lift: controlLift,
    );
    final left = point.dx - total / 2;
    final direction = Rect.fromLTWH(left, top, buttonSize, buttonSize);
    final pill = Rect.fromLTWH(
      left + buttonSize + controlGap,
      top,
      pillSize.width,
      pillSize.height,
    );
    final remove = Rect.fromLTWH(
      left + total - buttonSize,
      top,
      buttonSize,
      buttonSize,
    );
    final all = direction.expandToInclude(pill).expandToInclude(remove);
    // Na de pé os controles centram sobre a linha; na deitada, o casco desce
    // colando nela para fechar o vão por onde o cursor passa.
    final hull = laid.route.isStacked
        ? all.inflateBy(dx: 10, dy: 8)
        : Rect.fromLTWH(
            all.left,
            all.top,
            all.width,
            point.dy - all.top + 6,
          ).inflateBy(dx: 10, dy: 8);
    return EdgeControls(
      direction: direction,
      pill: pill,
      remove: remove,
      hull: hull,
    );
  }

  /// Qual ligação está perto deste ponto da janela. Amostra a curva em vez de
  /// resolver a cúbica: a tolerância de clique é maior que o erro da amostragem.
  ///
  /// A ligação já realçada ganha primeiro: enquanto o cursor estiver na área
  /// dos controles dela, é ela que continua no ar. Sem esta precedência, uma
  /// curva vizinha passando perto rouba o realce no meio do seu clique.
  static EdgeLink? linkNear({
    required Offset screenPoint,
    required Iterable<EdgeLink> links,
    required Map<String, Rect> frames,
    required CanvasViewport viewport,
    EdgeLink? hovered,
  }) {
    if (hovered != null) {
      final laid = _lay(hovered, frames);
      if (laid != null && controls(laid, viewport).hull.contains(screenPoint)) {
        return hovered;
      }
    }
    EdgeLink? best;
    var bestDistance = double.infinity;
    for (final link in links) {
      final laid = _lay(link, frames);
      if (laid == null) continue;
      var closest = double.infinity;
      for (final sample in EdgeCurve.densePolyline(laid.route)) {
        closest = math.min(
          closest,
          (viewport.toScreen(sample) - screenPoint).distance,
        );
      }
      if (closest <= hoverTolerance && closest < bestDistance) {
        best = link;
        bestDistance = closest;
      }
    }
    return best;
  }

  static LaidEdge? _lay(EdgeLink link, Map<String, Rect> frames) {
    final a = frames[link.a];
    final b = frames[link.b];
    return a == null || b == null ? null : lay(link, a, b);
  }
}

extension on Rect {
  Rect inflateBy({double dx = 0, double dy = 0}) =>
      Rect.fromLTRB(left - dx, top - dy, right + dx, bottom + dy);
}

import 'dart:math' as math;
import 'dart:ui';

/// Como uma aresta vai da origem ao destino.
sealed class EdgeRoute {
  const EdgeRoute();

  bool get isStacked => this is StackedRoute;
}

/// Destino à direita: Bézier direta, tangentes horizontais.
class DirectRoute extends EdgeRoute {
  const DirectRoute(this.from, this.to);
  final Offset from;
  final Offset to;
}

/// Destino à esquerda: desce por baixo dos dois cards, volta e sobe. Cantos em
/// ângulo reto, arredondados.
class LoopRoute extends EdgeRoute {
  const LoopRoute(this.corners);
  final List<Offset> corners;
}

/// Um card embaixo do outro: da base do de cima ao topo do de baixo, tangentes
/// verticais. Pelas portas laterais, quem está na mesma coluna parece "atrás" e
/// a linha dava a volta inteira por baixo do de baixo para entrar pela esquerda
/// dele.
class StackedRoute extends EdgeRoute {
  const StackedRoute(this.from, this.to);
  final Offset from;
  final Offset to;
}

/// Extremidades do traçado com a direção em que ele chega e sai.
typedef EdgeEndpoints = ({
  Offset start,
  Offset startTangent,
  Offset end,
  Offset endTangent,
});

/// Traçado no estilo n8n. Coordenadas do documento do canvas: y cresce para
/// baixo.
///
/// Aresta para trás não é a mesma curva com outros parâmetros, é **outra
/// rota**. Ida e volta ficam em faixas diferentes e por isso não têm como se
/// cruzar — e o retorno parece um retorno, em vez de uma linha que some atrás
/// dos cards.
abstract final class EdgeCurve {
  /// Raio das bolinhas de porta.
  static const portRadius = 4.0;

  /// Lado do triângulo da ponta, em pontos de TELA — não encolhe com o zoom.
  static const arrowSize = 12.0;

  /// `loopClearance` é adaptação do n8n: lá o padding é fixo, o que funciona
  /// porque um nó deles tem ~100pt de altura. Aqui um terminal passa de 380, e
  /// a faixa é medida a partir da base do card mais baixo.
  static const loopOffsetX = 40.0;
  static const loopClearance = 46.0;
  static const cornerRadius = 16.0;

  /// Zona morta para o destino "quase" alinhado não virar loop.
  static const backwardThreshold = 20.0;

  /// Quanto da largura do card mais estreito tem de estar sob o outro para os
  /// dois contarem como coluna. Metade: deslocados menos que isso, a linha
  /// vertical ainda é a curta; mais, já se lê como "ao lado".
  static const stackOverlap = 0.5;

  static EdgeRoute route(Rect source, Rect target) {
    final stacked = stackedRoute(source, target);
    if (stacked != null) return stacked;
    final from = sourcePort(source);
    final to = targetPort(target);
    if (!(from.dx - backwardThreshold > to.dx)) return DirectRoute(from, to);
    final lane = math.max(source.bottom, target.bottom) + loopClearance;
    return LoopRoute([
      from,
      Offset(from.dx + loopOffsetX, from.dy),
      Offset(from.dx + loopOffsetX, lane),
      Offset(to.dx - loopOffsetX, lane),
      Offset(to.dx - loopOffsetX, to.dy),
      to,
    ]);
  }

  /// Os dois cards estão um sobre o outro, sem se tocar na vertical. A rota vai
  /// sempre do de cima para o de baixo, seja qual for a origem — a ponta é que
  /// diz o sentido.
  static StackedRoute? stackedRoute(Rect a, Rect b) {
    final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
    if (overlap < stackOverlap * math.min(a.width, b.width)) return null;
    final (upper, lower) = a.top <= b.top ? (a, b) : (b, a);
    if (!(lower.top - upper.bottom > backwardThreshold)) return null;
    // No meio da faixa que os dois dividem: com cards de larguras ou posições
    // diferentes, a linha sai e entra reta.
    final x = (math.max(a.left, b.left) + math.min(a.right, b.right)) / 2;
    return StackedRoute(Offset(x, upper.bottom), Offset(x, lower.top));
  }

  /// Se a rota entre estes dois cards sai reta, sem dar a volta por baixo. É
  /// como o desenho escolhe qual das duas pontas do par é a origem do traçado:
  /// a linha fica reta quando pode, e a volta sobra para quem de fato está atrás.
  static bool prefersDirect(Rect source, Rect target) {
    if (stackedRoute(source, target) != null) return source.top <= target.top;
    return sourcePort(source).dx - backwardThreshold <= targetPort(target).dx;
  }

  /// Portas no meio vertical do card, como no n8n. No cabeçalho elas ficariam em
  /// cima dos botões de fechar e configurar.
  static Offset sourcePort(Rect frame) => Offset(frame.right, frame.center.dy);

  static Offset targetPort(Rect frame) => Offset(frame.left, frame.center.dy);

  /// Onde a fileira de controles da aresta (direção, limite, remover) começa,
  /// em y. Na linha deitada ela sobe acima do meio para não cobrir a linha; na
  /// de pé, subir é deslizar ao longo dela — ali se centram no ponto médio.
  static double controlsTop({
    required EdgeRoute route,
    required Offset midpoint,
    required double height,
    required double lift,
  }) =>
      route.isStacked ? midpoint.dy - height / 2 : midpoint.dy - height - lift;

  static Path path(EdgeRoute route) {
    final path = Path();
    switch (route) {
      case DirectRoute(:final from, :final to):
      case StackedRoute(:final from, :final to):
        final (c1, c2) = _controls(route);
        path
          ..moveTo(from.dx, from.dy)
          ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
      case LoopRoute(:final corners):
        path.moveTo(corners.first.dx, corners.first.dy);
        for (var i = 1; i < corners.length - 1; i++) {
          // Raio limitado pelo trecho mais curto, senão dois cantos próximos se
          // comem.
          final radius = math.min(
            cornerRadius,
            math.min(
              _length(corners[i - 1], corners[i]) / 2,
              _length(corners[i], corners[i + 1]) / 2,
            ),
          );
          _roundedCorner(
            path,
            corners[i - 1],
            corners[i],
            corners[i + 1],
            radius,
          );
        }
        path.lineTo(corners.last.dx, corners.last.dy);
    }
    return path;
  }

  /// A reta até o ponto de tangência e o arco que dobra o canto.
  static void _roundedCorner(
    Path path,
    Offset a,
    Offset corner,
    Offset b,
    double radius,
  ) {
    final inward = _unit(a, corner);
    final outward = _unit(corner, b);
    final cross = inward.dx * outward.dy - inward.dy * outward.dx;
    final dot = (inward.dx * outward.dx + inward.dy * outward.dy).clamp(
      -1.0,
      1.0,
    );
    if (cross.abs() < 1e-9 || radius <= 0) {
      path.lineTo(corner.dx, corner.dy);
      return;
    }
    final turn = math.acos(dot);
    final tangent = radius * math.tan(turn / 2);
    final enter = corner - inward * tangent;
    final leave = corner + outward * tangent;
    path
      ..lineTo(enter.dx, enter.dy)
      ..arcToPoint(
        leave,
        radius: Radius.circular(radius),
        clockwise: cross > 0,
      );
  }

  static double _length(Offset a, Offset b) =>
      math.max(0.0001, (b - a).distance);

  static Offset _unit(Offset from, Offset to) {
    final length = _length(from, to);
    return Offset((to.dx - from.dx) / length, (to.dy - from.dy) / length);
  }

  /// Pontos de controle da cúbica: na horizontal para a rota direta, na
  /// vertical para a empilhada — é o que faz a linha sair e entrar reta na borda
  /// de onde parte. Loop não tem curva.
  static (Offset, Offset) _controls(EdgeRoute route) => switch (route) {
    DirectRoute(:final from, :final to) => () {
      final reach = math.min(300.0, math.max(70.0, (to.dx - from.dx) * 0.5));
      return (Offset(from.dx + reach, from.dy), Offset(to.dx - reach, to.dy));
    }(),
    StackedRoute(:final from, :final to) => () {
      final reach = math.min(300.0, math.max(40.0, (to.dy - from.dy) * 0.5));
      return (Offset(from.dx, from.dy + reach), Offset(to.dx, to.dy - reach));
    }(),
    LoopRoute(:final corners) => (corners.first, corners.last),
  };

  /// Polilinha do traçado. Serve para achar o meio — mede por comprimento, o
  /// que faz o meio do loop cair no meio do caminho, e não no meio da lista de
  /// cantos.
  static List<Offset> polyline(EdgeRoute route) => switch (route) {
    DirectRoute(:final from, :final to) ||
    StackedRoute(:final from, :final to) => () {
      final (c1, c2) = _controls(route);
      return [
        for (var step = 0; step <= 48; step++)
          () {
            final t = step / 48;
            final u = 1 - t;
            return Offset(
              u * u * u * from.dx +
                  3 * u * u * t * c1.dx +
                  3 * u * t * t * c2.dx +
                  t * t * t * to.dx,
              u * u * u * from.dy +
                  3 * u * u * t * c1.dy +
                  3 * u * t * t * c2.dy +
                  t * t * t * to.dy,
            );
          }(),
      ];
    }(),
    LoopRoute(:final corners) => corners,
  };

  /// A mesma polilinha, subdividida a cada ~8pt. O teste de proximidade precisa
  /// disto: na rota de loop, [polyline] devolve só os seis cantos, e um trecho
  /// reto de 1500pt entre dois deles não teria amostra no meio.
  static List<Offset> densePolyline(EdgeRoute route) {
    final coarse = polyline(route);
    if (coarse.length < 2) return coarse;
    final dense = <Offset>[coarse.first];
    for (var i = 1; i < coarse.length; i++) {
      final a = coarse[i - 1];
      final b = coarse[i];
      final steps = math.max(1, (_length(a, b) / 8).floor());
      for (var step = 1; step <= steps; step++) {
        dense.add(Offset.lerp(a, b, step / steps)!);
      }
    }
    return dense;
  }

  /// Extremidades do traçado com a direção em que ele chega e sai. `start` é a
  /// saída da porta de origem, e `startTangent` aponta PARA FORA do card — é a
  /// direção da ponta de quem aciona no sentido contrário.
  static EdgeEndpoints endpoints(EdgeRoute route) => switch (route) {
    DirectRoute(:final from, :final to) ||
    StackedRoute(:final from, :final to) => () {
      // Derivada da cúbica em t=0 e t=1: é o que faz a ponta encostar reta na
      // borda do card em vez de entrar torta.
      final (c1, c2) = _controls(route);
      return (
        start: from,
        startTangent: _unit(c1, from),
        end: to,
        endTangent: _unit(c2, to),
      );
    }(),
    LoopRoute(:final corners) => (
      start: corners.first,
      startTangent: _unit(corners[1], corners.first),
      end: corners.last,
      endTangent: _unit(corners[corners.length - 2], corners.last),
    ),
  };

  /// Ponto e direção no meio do traçado, medido por comprimento. É onde os
  /// controles do hover se penduram.
  static (Offset, Offset) midpoint(EdgeRoute route) {
    final points = polyline(route);
    final lengths = <double>[0];
    for (var i = 1; i < points.length; i++) {
      lengths.add(lengths[i - 1] + _length(points[i - 1], points[i]));
    }
    final half = lengths.last / 2;
    var index = lengths.indexWhere((length) => length >= half);
    if (index < 1) index = 1;
    final a = points[index - 1];
    final b = points[index];
    final span = _length(a, b);
    final t = (half - lengths[index - 1]) / span;
    return (
      Offset.lerp(a, b, t)!,
      Offset((b.dx - a.dx) / span, (b.dy - a.dy) / span),
    );
  }
}

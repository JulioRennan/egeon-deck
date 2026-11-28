import 'dart:ui';

import 'package:egeon_deck/features/canvas/domain/entities/edge_curve.dart';
import 'package:flutter_test/flutter_test.dart';

/// Porte de EdgeCurveTests: qual rota a aresta toma entre dois cards.
/// Coordenadas do documento: y cresce para baixo.
void main() {
  const size = Size(720, 460);
  Rect card(double x, double y) => Offset(x, y) & size;

  test('cards empilhados ligam a base ao topo', () {
    final upper = card(784, 40);
    final lower = card(784, 524);
    for (final (a, b) in [(upper, lower), (lower, upper)]) {
      final route = EdgeCurve.route(a, b);
      expect(route, isA<StackedRoute>(), reason: 'coluna virou $route');
      final stacked = route as StackedRoute;
      expect(stacked.from.dy, upper.bottom, reason: 'sai da base do de cima');
      expect(stacked.to.dy, lower.top, reason: 'entra no topo do de baixo');
      expect(
        stacked.from.dx,
        stacked.to.dx,
        reason: 'reta, no meio da faixa comum',
      );
    }
    expect(EdgeCurve.prefersDirect(upper, lower), isTrue);
    expect(EdgeCurve.prefersDirect(lower, upper), isFalse);
  });

  test('coluna levemente deslocada ainda é empilhada', () {
    expect(EdgeCurve.route(card(100, 40), card(300, 600)), isA<StackedRoute>());
  });

  test('lado a lado continua direta', () {
    expect(EdgeCurve.route(card(40, 40), card(784, 40)), isA<DirectRoute>());
    // Na diagonal, sem faixa comum: continua lateral.
    expect(EdgeCurve.route(card(40, 40), card(784, 524)), isA<DirectRoute>());
  });

  test('destino atrás e fora da coluna ainda volta por baixo', () {
    expect(EdgeCurve.route(card(784, 40), card(40, 40)), isA<LoopRoute>());
  });

  test('cards sobrepostos não ganham rota vertical', () {
    // Um sobre o outro mas se tocando: não há vão para a linha vertical.
    expect(
      EdgeCurve.route(card(40, 40), card(40, 300)),
      isNot(isA<StackedRoute>()),
    );
  });

  test('as pontas da rota empilhada apontam ao longo da coluna', () {
    final route = EdgeCurve.route(card(784, 40), card(784, 524));
    final ends = EdgeCurve.endpoints(route);
    expect(
      ends.endTangent.dy,
      closeTo(1, 0.001),
      reason: 'entra de cima para baixo',
    );
    expect(
      ends.startTangent.dy,
      closeTo(-1, 0.001),
      reason: 'a ponta de volta aponta para cima',
    );
  });

  test('os controles ficam no meio da linha de pé e acima na deitada', () {
    final stacked = EdgeCurve.route(card(784, 40), card(784, 664));
    final (mid, _) = EdgeCurve.midpoint(stacked);
    final top = EdgeCurve.controlsTop(
      route: stacked,
      midpoint: mid,
      height: 24,
      lift: 10,
    );
    expect(
      top + 12,
      closeTo(mid.dy, 0.001),
      reason: 'centrados no ponto médio',
    );
    expect(
      mid.dy,
      closeTo((40 + 460 + 664) / 2, 1),
      reason: 'o ponto médio é o meio do vão',
    );

    final side = EdgeCurve.route(card(40, 40), card(1100, 40));
    final (sideMid, _) = EdgeCurve.midpoint(side);
    expect(
      EdgeCurve.controlsTop(
        route: side,
        midpoint: sideMid,
        height: 24,
        lift: 10,
      ),
      closeTo(sideMid.dy - 34, 0.001),
      reason: 'deitada: acima da linha',
    );
  });

  test('a polilinha densa tem amostra no meio de um trecho longo do loop', () {
    final loop = EdgeCurve.route(card(2000, 40), card(40, 40));
    final dense = EdgeCurve.densePolyline(loop);
    for (var i = 1; i < dense.length; i++) {
      expect((dense[i] - dense[i - 1]).distance, lessThan(16));
    }
  });

  test('o caminho do loop e o da curva têm limites dentro da faixa', () {
    final loop = EdgeCurve.route(card(784, 40), card(40, 40));
    final bounds = EdgeCurve.path(loop).getBounds();
    // A faixa de volta passa abaixo da base dos cards.
    expect(bounds.bottom, closeTo(40 + 460 + EdgeCurve.loopClearance, 0.5));
  });
}

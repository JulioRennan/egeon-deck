import 'dart:ui';

import 'package:egeon_deck/features/canvas/domain/entities/canvas_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zoom com âncora no cursor, detente e enquadrar tudo (CanvasContainer).
void main() {
  const view = CanvasViewport(size: Size(1000, 700));
  const frames = <Rect>[];

  test('o ponto sob o cursor fica parado no zoom', () {
    final start = view.copyWith(origin: const Offset(800, 500));
    const anchor = Offset(300, 200);
    final before = start.toDocument(anchor);

    final zoomed = start.zoomAt(2, anchor, frames);

    expect(zoomed.zoom, 2);
    expect(zoomed.toDocument(anchor).dx, closeTo(before.dx, 0.001));
    expect(zoomed.toDocument(anchor).dy, closeTo(before.dy, 0.001));
  });

  test('a detente gruda no passo mais próximo dentro de 3%', () {
    expect(CanvasViewport.detente(1.02), 1.0);
    expect(CanvasViewport.detente(0.98), 1.0);
    expect(CanvasViewport.detente(1.1), 1.1);
    expect(CanvasViewport.detente(0.51), 0.5);
  });

  test('a roda atravessa a detente porque parte do valor cru', () {
    var current = view.copyWith(origin: const Offset(100, 100));
    // Cada passo da roda é pequeno demais para sair de 100% de uma vez.
    for (var i = 0; i < 30; i++) {
      current = current.wheelZoom(-4, const Offset(500, 350), frames);
    }
    expect(current.zoom, greaterThan(1.0));
  });

  test('zoom por fora invalida o valor cru', () {
    // Zoom mudou sem passar pelo valor cru: o cru (1.0) está velho.
    final outside = view.copyWith(zoom: 1.5);
    final wheel = outside.wheelZoom(-20, Offset.zero, frames);
    expect(wheel.zoom, greaterThan(1.5));
  });

  test('o zoom respeita os extremos', () {
    expect(view.zoomAt(100, Offset.zero, frames).zoom, CanvasViewport.maxZoom);
    expect(
      view.zoomAt(0.001, Offset.zero, frames).zoom,
      CanvasViewport.minZoom,
    );
  });

  test('stepZoom anda pela lista de passos nos dois sentidos', () {
    expect(view.stepZoom(-1, frames).zoom, 0.8);
    expect(view.stepZoom(1, frames).zoom, 1.25);
    expect(
      view.copyWith(zoom: 0.25, rawZoom: 0.25).stepZoom(-1, frames).zoom,
      0.25,
    );
  });

  test('em zoom out o documento cresce para cobrir a vista', () {
    final out = view.zoomAt(0.25, Offset.zero, frames);
    expect(out.document.width, greaterThanOrEqualTo(out.visible.width * 1.5));
  });

  test('o roda sem trackpad dá passo 6x maior', () {
    final precise = view.wheelZoom(-1, Offset.zero, frames);
    final coarse = view.wheelZoom(-1, Offset.zero, frames, precise: false);
    expect(coarse.rawZoom, greaterThan(precise.rawZoom));
  });

  group('enquadrar tudo', () {
    const nodes = [
      Rect.fromLTWH(1000, 800, 720, 460),
      Rect.fromLTWH(1900, 800, 720, 460),
    ];
    final union = nodes.first.expandToInclude(nodes.last);

    test('centra a união dos cards na área visível', () {
      const area = Rect.fromLTWH(0, 120, 1000, 580);
      final fitted = view.fit(union, area, nodes);

      expect(fitted.zoom, lessThanOrEqualTo(1));
      final center = fitted.toScreen(union.center);
      expect(center.dx, closeTo(area.center.dx, 0.5));
      expect(center.dy, closeTo(area.center.dy, 0.5));
    });

    test('a área menor (barra lateral) empurra o centro', () {
      const wide = Rect.fromLTWH(0, 0, 1000, 700);
      const narrow = Rect.fromLTWH(300, 0, 700, 700);
      final a = view.fit(union, wide, nodes);
      final b = view.fit(union, narrow, nodes);
      expect(b.zoom, lessThan(a.zoom));
    });
  });
}

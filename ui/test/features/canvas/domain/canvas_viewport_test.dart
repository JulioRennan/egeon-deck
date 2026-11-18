import 'dart:ui';

import 'package:egeon_deck/features/canvas/domain/entities/canvas_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Porte de CanvasFitTests e CanvasDocumentGrowthTests do legado.
void main() {
  group('enquadrar: cabe com margem, nunca amplia além de 100%', () {
    test('conteúdo largo cabe pela largura', () {
      final zoom = CanvasViewport.fitZoom(
        const Rect.fromLTWH(0, 0, 2000, 500),
        const Size(1120, 800),
      );
      // 1120 − 2·60 = 1000 útil para 2000 de conteúdo.
      expect(zoom, closeTo(0.5, 0.001));
    });

    test('nunca amplia além de 100%', () {
      final zoom = CanvasViewport.fitZoom(
        const Rect.fromLTWH(40, 40, 300, 200),
        const Size(1600, 1000),
      );
      expect(zoom, 1);
    });

    test('prende no menor passo', () {
      final zoom = CanvasViewport.fitZoom(
        const Rect.fromLTWH(0, 0, 50000, 100),
        const Size(1000, 800),
      );
      expect(zoom, CanvasViewport.zoomSteps.first);
    });

    test('entradas degeneradas caem em 1', () {
      expect(CanvasViewport.fitZoom(Rect.zero, const Size(800, 600)), 1);
      expect(
        CanvasViewport.fitZoom(
          const Rect.fromLTWH(0, 0, 100, 100),
          const Size(50, 50),
        ),
        1,
      );
    });
  });

  group('o canvas é infinito para os quatro lados', () {
    const window = Size(1000, 700);
    const start = CanvasViewport(size: window);

    test('pan além da borda direita cresce o documento', () {
      final before = start.document;
      expect(start.visible.width, 1000);

      final grown = start.extendDocument(Offset(before.width + 300, 0));

      expect(grown.document.width, before.width + 300 + start.visible.width);
      expect(grown.document.height, before.height);
    });

    test('pan além da borda de baixo cresce o documento', () {
      final before = start.document;

      final grown = start.extendDocument(Offset(0, before.height + 50));

      expect(grown.document.width, before.width);
      expect(grown.document.height, before.height + 50 + start.visible.height);
    });

    test('o documento nunca encolhe', () {
      final shown = start.extendDocument(Offset.zero);
      final grown = start.growDocument(const Size(10, 10));
      expect(shown.document, start.document);
      expect(grown.document, start.document);
    });

    test('o crescimento para no teto', () {
      const far = CanvasViewport.maxDocumentSize * 2;
      final grown = start.extendDocument(const Offset(far, far));
      expect(grown.document.width, CanvasViewport.maxDocumentSize);
      expect(grown.document.height, CanvasViewport.maxDocumentSize);
    });

    test('à esquerda e no topo o mundo se desloca (makeSpace)', () {
      final opened = start.makeSpace(const Size(300, 120));
      expect(opened.shift, const Offset(300, 120));
      expect(opened.viewport.origin, const Offset(300, 120));
      expect(opened.viewport.document.width, start.document.width + 300);
    });

    test('no teto o makeSpace recusa inteiro, sem deslocar nada', () {
      final huge = start.copyWith(
        document: const Size(CanvasViewport.maxDocumentSize - 10, 4000),
      );
      final refused = huge.makeSpace(const Size(300, 0));
      expect(refused.shift, Offset.zero);
      expect(refused.viewport.document, huge.document);
    });

    test('pan além do canto esquerdo abre espaço e compensa a âncora', () {
      final moved = start.panTo(const Offset(-200, -50));
      expect(moved.shift, const Offset(200, 50));
      // A vista fica onde o gesto pediu, em coordenadas já deslocadas.
      expect(moved.viewport.origin, Offset.zero);
    });

    test('a origem nunca escapa do documento', () {
      final moved = start.panTo(const Offset(-200, -50), openSpace: false);
      expect(moved.viewport.origin, Offset.zero);
    });
  });
}

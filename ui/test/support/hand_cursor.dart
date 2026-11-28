import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Onde se clica, o ponteiro diz": todo `GestureDetector` que responde a toque
/// tem de ter, acima dele, uma região de mouse com a mão. É o que pega o
/// clicável novo que nasceu sem cursor (porte de HandCursorTests.swift).
void expectHandOnEveryClickable(WidgetTester tester) {
  final bare = <String>[];
  for (final element in tester.elementList(find.byType(GestureDetector))) {
    final detector = element.widget as GestureDetector;
    final clicks = detector.onTap != null || detector.onTapUp != null;
    if (!clicks) continue;
    var hand = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is MouseRegion && widget.cursor == SystemMouseCursors.click) {
        hand = true;
        return false;
      }
      return true;
    });
    if (!hand) bare.add('$detector em ${element.debugGetCreatorChain(4)}');
  }
  expect(bare, isEmpty, reason: 'responde a clique e não diz nada ao ponteiro');
}

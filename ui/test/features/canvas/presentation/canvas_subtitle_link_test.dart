import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump_canvas.dart';

/// O subtítulo do card (`NodeView.swift`): sem ⌘ é cabeçalho e arrasta; com ⌘
/// o clique abre a pasta do terminal no Finder. O web não tem pasta.
void main() {
  const shell = CanvasCard(
    id: 'sh',
    kind: NodeKind.shell,
    title: 'sh',
    subtitle: '~/x/api',
    frame: Rect.fromLTWH(200, 300, 720, 460),
  );
  const web = CanvasCard(
    id: 'w',
    kind: NodeKind.web,
    title: 'w',
    subtitle: 'https://docs.rs',
    frame: Rect.fromLTWH(1100, 300, 720, 460),
  );

  Finder subtitle(String id) => find.descendant(
    of: find.byKey(ValueKey('card-$id')),
    matching: find.byKey(const ValueKey('card-subtitle')),
  );

  Future<(InMemoryCanvasRepository, List<String>)> mount(
    WidgetTester tester,
  ) async {
    final repo = InMemoryCanvasRepository(cards: const [shell, web]);
    final opened = <String>[];
    await pumpCanvas(tester, repo, onOpenFolder: (card) => opened.add(card.id));
    return (repo, opened);
  }

  testWidgets('⌘-clique no subtítulo abre a pasta e não arrasta', (
    tester,
  ) async {
    final (_, opened) = await mount(tester);
    final card = find.byKey(const ValueKey('card-sh'));
    final before = tester.getTopLeft(card);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    final gesture = await tester.startGesture(tester.getCenter(subtitle('sh')));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(opened, ['sh']);
    expect(tester.getTopLeft(card), before);
  });

  testWidgets('sem ⌘ o subtítulo é cabeçalho: arrasta e não abre', (
    tester,
  ) async {
    final (_, opened) = await mount(tester);
    final card = find.byKey(const ValueKey('card-sh'));
    final before = tester.getTopLeft(card);
    final gesture = await tester.startGesture(tester.getCenter(subtitle('sh')));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.getTopLeft(card).dx, closeTo(before.dx + 80, 1.5));
    await gesture.up();
    expect(opened, isEmpty);
  });

  testWidgets('o subtítulo do web é a página: ⌘-clique não abre nada', (
    tester,
  ) async {
    final (_, opened) = await mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.tap(subtitle('w'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(opened, isEmpty);
  });
}

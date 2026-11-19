import 'dart:ui';

import 'package:egeon_deck/commons/widgets/app_tooltip.dart';
import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump_canvas.dart';

/// A dica do título do card (`TerminalNode.swift`): o endereço e, no agente,
/// o CLI. O título continua sendo por onde se arrasta o card.
void main() {
  const agent = CanvasCard(
    id: 'dev',
    kind: NodeKind.agent,
    title: 'dev',
    address: 'deck/dev',
    cliName: 'Claude Code',
    subtitle: '~/x',
    frame: Rect.fromLTWH(200, 300, 720, 460),
  );

  Finder title() => find.descendant(
    of: find.byKey(const ValueKey('card-dev')),
    matching: find.byKey(const ValueKey('card-title')),
  );

  testWidgets('parar o mouse no título mostra endereço · CLI', (tester) async {
    await pumpCanvas(tester, InMemoryCanvasRepository(cards: const [agent]));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(title()));
    await tester.pump();
    await tester.pump(AppTooltip.delay);
    expect(find.text('deck/dev · Claude Code'), findsOneWidget);
  });

  testWidgets('arrastar pelo título ainda move o card', (tester) async {
    await pumpCanvas(tester, InMemoryCanvasRepository(cards: const [agent]));
    final card = find.byKey(const ValueKey('card-dev'));
    final before = tester.getTopLeft(card);
    final gesture = await tester.startGesture(tester.getCenter(title()));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(tester.getTopLeft(card).dx, closeTo(before.dx + 80, 1.5));
    await gesture.up();
  });
}

import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump_canvas.dart';

/// Tentativa agendada depois de uma falha da API: o status do agente vira
/// botão, com "Tentar agora" e "Cancelar tentativa" (ADR-072).
void main() {
  CanvasCard agent(String state) => CanvasCard(
    id: 'dev',
    kind: NodeKind.agent,
    title: 'dev',
    subtitle: '~/x',
    frame: const Rect.fromLTWH(200, 300, 720, 460),
    activity: CardActivity(
      state: state,
      label: 'tentando de novo às 14:05 (2/3)',
      glyph: ActivityGlyph.retry,
    ),
  );

  Future<List<bool>> mount(WidgetTester tester, String state) async {
    final asked = <bool>[];
    await pumpCanvas(
      tester,
      InMemoryCanvasRepository(cards: [agent(state)]),
      onRetry: (card, {required now}) => asked.add(now),
    );
    return asked;
  }

  testWidgets('em tentativa, o status oferece tentar agora e cancelar', (
    tester,
  ) async {
    final asked = await mount(tester, 'retrying');
    await tester.tap(find.byKey(const ValueKey('card-retry')));
    await tester.pump();
    await tester.tap(find.text('Tentar agora'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('card-retry')));
    await tester.pump();
    await tester.tap(find.text('Cancelar tentativa'));
    await tester.pump();
    expect(asked, [true, false]);
  });

  testWidgets('fora de tentativa o status só mostra', (tester) async {
    await mount(tester, 'working');
    expect(find.byKey(const ValueKey('card-retry')), findsNothing);
    expect(find.byKey(const ValueKey('card-status')), findsOneWidget);
  });
}

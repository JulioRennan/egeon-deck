import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';

import '../../../support/in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/canvas/presentation/page/canvas_page.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/agent_accessory.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/eg_host.dart';

import '../../../support/fake_agent_repository.dart';
import '../../../support/inject_fakes.dart';

/// A faixa do agente dentro do card: o corpo desce, e os controles dela não
/// arrastam o card.
void main() {
  testWidgets('arrastar o slider de esforço não move o card', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final canvas = InMemoryCanvasRepository(
      cards: const [
        CanvasCard(
          id: 'claude',
          kind: NodeKind.agent,
          title: 'claude',
          frame: Rect.fromLTWH(1200, 900, 800, 500),
        ),
      ],
      links: const [],
    );
    final agent = FakeAgentRepository();
    injectFakes(canvas: canvas, agent: (_) => agent);
    await tester.pumpWidget(
      egHost(
        fill: true,
        size: const Size(1200, 800),
        CanvasPage(
          workbenchId: 'b',
          bodyBuilder: (context, card) => ColoredBox(
            key: const ValueKey('body'),
            color: const Color(0xFF111111),
          ),
          accessoryBuilder: (context, card) => card.kind == NodeKind.agent
              ? AgentAccessory(workbenchId: 'b', nodeId: card.id)
              : null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final cardFinder = find.byKey(const ValueKey('card-claude'));
    final topBefore = tester.getTopLeft(cardFinder);
    // O corpo começa depois da faixa: 56 do cabeçalho + 36 da faixa, vezes o zoom.
    final zoom = (tester.getBottomRight(cardFinder).dx - topBefore.dx) / 800;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('body'))).dy - topBefore.dy,
      closeTo(92 * zoom, 0.5),
    );

    // Arrastar a partir de uma pastilha da faixa não leva o card junto.
    final chip = tester.getCenter(find.byKey(const ValueKey('model-picker')));
    final gesture = await tester.startGesture(chip);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    expect(
      tester.getTopLeft(cardFinder),
      topBefore,
      reason: 'o card ficou parado',
    );
  });
}

import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';

import '../../../support/in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/canvas/presentation/page/canvas_page.dart';
import 'package:egeon_deck/features/node/agent/presentation/widgets/agent_accessory.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/model_choice.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
      WidgetsApp(
        color: const Color(0xFF000000),
        textStyle: AppTheme.textStyle,
        builder: (context, _) => CanvasPage(
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
    // O corpo começa depois da faixa: 46 do nome + 46 da faixa, vezes o zoom.
    final zoom = (tester.getBottomRight(cardFinder).dx - topBefore.dx) / 800;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('body'))).dy - topBefore.dy,
      closeTo(92 * zoom, 0.5),
    );

    final slider = tester.getRect(find.byKey(const ValueKey('effort-slider')));
    final gesture = await tester.startGesture(
      Offset(slider.left + 10, slider.center.dy),
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));

    expect(
      tester.getTopLeft(cardFinder),
      topBefore,
      reason: 'o card ficou parado',
    );
    expect(
      agent.choices.first,
      isA<EffortMove>(),
      reason: 'e o gesto foi ao core',
    );
  });
}

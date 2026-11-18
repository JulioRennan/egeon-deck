import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';

import '../../../support/in_memory_canvas_repository.dart';

import 'package:egeon_deck/features/canvas/presentation/page/canvas_page.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_body.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_view.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_terminal_repository.dart';
import '../../../support/inject_fakes.dart';

/// Vários terminais vivos no canvas ao mesmo tempo (US-402).
void main() {
  testWidgets('cada card de terminal assina a sua tela e fecha ao sair', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final canvas = InMemoryCanvasRepository(
      cards: const [
        CanvasCard(
          id: 't1',
          kind: NodeKind.shell,
          frame: Rect.fromLTWH(1100, 900, 600, 400),
        ),
        CanvasCard(
          id: 't2',
          kind: NodeKind.agent,
          frame: Rect.fromLTWH(1800, 900, 600, 400),
        ),
        CanvasCard(
          id: 'w1',
          kind: NodeKind.web,
          frame: Rect.fromLTWH(1100, 1400, 600, 400),
        ),
      ],
      links: const [],
    );
    final terminals = FakeTerminalRepository();
    injectFakes(canvas: canvas, terminals: terminals);

    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        textStyle: AppTheme.textStyle,
        builder: (context, _) => CanvasPage(
          workbenchId: 'b',
          bodyBuilder: (context, card) => card.kind != NodeKind.web
              ? TerminalBody(nodeId: card.id)
              : const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(TerminalView), findsNWidgets(2));
    expect(terminals.watchers, 2);

    // ignore: avoid_print
    print(
      'POS ${tester.getTopLeft(find.byKey(const ValueKey('card-t2')))} close ${tester.getCenter(find.descendant(of: find.byKey(const ValueKey('card-t2')), matching: find.byKey(const ValueKey('card-close'))))}',
    );
    // O X do card tira o terminal da tela e solta a assinatura dele.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('card-t2')),
        matching: find.byKey(const ValueKey('card-close')),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('card-t2')), findsNothing);
    expect(find.byType(TerminalView), findsOneWidget);
    expect(terminals.watchers, 1);
  });
}

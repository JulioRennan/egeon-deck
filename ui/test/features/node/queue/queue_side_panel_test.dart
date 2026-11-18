import 'package:egeon_deck/features/node/queue/presentation/widgets/queue_side_panel.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_queue_repository.dart';
import '../../../support/inject_fakes.dart';
import 'queue_body_test.dart' show seeded;

/// A conversa com a fila ao lado: divisória, largura e fechar.
void main() {
  Future<List<double?>> pump(
    WidgetTester tester, {
    double? preferred,
    VoidCallback? onClose,
    double width = 1200,
  }) async {
    tester.view
      ..physicalSize = Size(width, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final widths = <double?>[];
    final repo = InMemoryQueueRepository(queue: seeded());
    injectFakes(queue: (_) => repo);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        textStyle: AppTheme.textStyle,
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: QueueSidePanel(
          thread: const SizedBox(key: ValueKey('thread')),
          workbenchId: 'bancada',
          queueNodeId: 'fila',
          preferredWidth: preferred,
          onWidth: widths.add,
          onClose: onClose ?? () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return widths;
  }

  testWidgets('largura padrão e a conversa com o resto', (tester) async {
    await pump(tester);
    final panel = tester.getSize(find.byType(QueueSidePanel)).width;
    expect(panel, 1200);
    // 42% de 1184 = 497; a conversa fica com o que sobra menos a divisória.
    final thread = tester.getSize(find.byKey(const ValueKey('thread'))).width;
    expect(thread, closeTo(1200 - 16 - 497, 1));
  });

  testWidgets('arrastar a divisória para a esquerda alarga o painel', (
    tester,
  ) async {
    final widths = await pump(tester, preferred: 400);
    await tester.drag(
      find.byKey(const ValueKey('queue-split')),
      const Offset(-100, 0),
    );
    await tester.pump(const Duration(seconds: 1));
    // O primeiro trecho do arrasto some no limiar do gesto.
    expect(widths.last, closeTo(500, 25));
  });

  testWidgets('a conversa não passa do mínimo, mesmo arrastando longe', (
    tester,
  ) async {
    final widths = await pump(tester, preferred: 400);
    await tester.drag(
      find.byKey(const ValueKey('queue-split')),
      const Offset(-900, 0),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(widths.last, 1200 - 16 - 400);
  });

  testWidgets('duplo clique na divisória volta ao padrão', (tester) async {
    final widths = await pump(tester, preferred: 400);
    final split = find.byKey(const ValueKey('queue-split'));
    await tester.tap(split);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(split);
    await tester.pump(const Duration(milliseconds: 500));
    expect(widths, [null]);
  });

  testWidgets('o ✕ fecha o painel', (tester) async {
    var closed = 0;
    await pump(tester, onClose: () => closed++);
    await tester.tap(find.byKey(const ValueKey('queue-close')));
    expect(closed, 1);
  });
}

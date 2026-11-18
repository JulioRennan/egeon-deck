import 'package:egeon_deck/features/node/queue/domain/entities/prompt_queue.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_item.dart';

import '../../../support/in_memory_queue_repository.dart';
import '../../../support/inject_fakes.dart';

import 'package:egeon_deck/features/node/queue/presentation/widgets/queue_body.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpQueue(
  WidgetTester tester,
  InMemoryQueueRepository repo,
) async {
  tester.view
    ..physicalSize = const Size(540, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  injectFakes(queue: (_) => repo);
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      textStyle: AppTheme.textStyle,
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      home: const QueueBody(workbenchId: 'bancada', nodeId: 'fila'),
    ),
  );
  await tester.pump();
  await tester.pump();
}

PromptQueue seeded({bool linked = true}) => PromptQueue(
  items: const [
    QueueItem(id: 'a1', text: 'Toast atrás do header'),
    QueueItem(id: 'b2', text: 'Segunda tarefa'),
  ],
  targets: linked ? const [QueueTarget(id: 'dev', label: 'Dev')] : const [],
);

void main() {
  testWidgets('lista as tarefas e diz ninguém ligado quando não há destino', (
    tester,
  ) async {
    await pumpQueue(
      tester,
      InMemoryQueueRepository(queue: seeded(linked: false)),
    );
    expect(find.text('Toast atrás do header'), findsOneWidget);
    expect(find.text('Segunda tarefa'), findsOneWidget);
    expect(find.text('ninguém ligado'), findsOneWidget);
    expect(
      find.text('Nova tarefa'),
      findsOneWidget,
      reason: 'a linha de baixo',
    );
  });

  testWidgets(
    'digitar na linha de baixo e dar Enter anota e deixa o campo limpo',
    (tester) async {
      final repo = InMemoryQueueRepository(queue: seeded());
      await pumpQueue(tester, repo);

      await tester.tap(find.text('Nova tarefa'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'terceira');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      expect(repo.queue.items.last.text, 'terceira');
      expect(find.text('terceira'), findsOneWidget);
    },
  );

  testWidgets('clicar na tarefa abre o editor e editar grava a cada tecla', (
    tester,
  ) async {
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);

    await tester.tap(find.text('Segunda tarefa'));
    await tester.pump();
    await tester.pump();
    final editor = find.descendant(
      of: find.byKey(const ValueKey('editor-b2')),
      matching: find.byType(EditableText),
    );
    expect(editor, findsOneWidget);
    await tester.enterText(editor, 'Segunda, editada');
    await tester.pump();
    expect(repo.queue.items[1].text, 'Segunda, editada');
  });

  testWidgets('mandar a tarefa aberta marca como enviada e trava o editor', (
    tester,
  ) async {
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);
    await tester.tap(find.text('Segunda tarefa'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('send-item')));
    await tester.pump();
    await tester.pump();

    expect(repo.queue.items[1].status, ItemStatus.sent);
    expect(find.byKey(const ValueKey('send-item')), findsNothing);
    expect(find.textContaining('enviada para Dev'), findsOneWidget);
  });

  testWidgets('sem ligação, mandar mostra o aviso em laranja', (tester) async {
    final repo = InMemoryQueueRepository(queue: seeded(linked: false));
    await pumpQueue(tester, repo);
    await tester.tap(find.byKey(const ValueKey('send-next')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('queue-notice')), findsOneWidget);
    expect(find.textContaining('Ligue a fila'), findsOneWidget);
    // O aviso some depois de seis segundos.
    await tester.pump(const Duration(seconds: 7));
    expect(find.byKey(const ValueKey('queue-notice')), findsNothing);
  });

  testWidgets('responder numa tarefa enviada entra na thread', (tester) async {
    final repo = InMemoryQueueRepository(
      queue: PromptQueue(
        items: [
          QueueItem(
            id: 'a1',
            text: 'Toast',
            status: ItemStatus.sent,
            sentTo: 'dev',
            sentAt: DateTime(2026),
            awaiting: true,
            thread: [
              QueueMessage(
                kind: MessageKind.question,
                text: 'Qual z-index?',
                author: 'dev',
                at: DateTime(2026),
              ),
            ],
          ),
        ],
        targets: const [QueueTarget(id: 'dev', label: 'Dev')],
      ),
    );
    await pumpQueue(tester, repo);
    await tester.tap(find.text('Toast'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Qual z-index?'), findsOneWidget);
    expect(find.text('Responder ao agente'), findsOneWidget);

    final reply = find.descendant(
      of: find.byKey(const ValueKey('reply-a1-0')),
      matching: find.byType(EditableText),
    );
    await tester.tap(reply);
    await tester.pump();
    await tester.enterText(reply, 'é o 90');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.single.thread.last.text, 'é o 90');
    expect(repo.queue.items.single.awaiting, isFalse);
  });

  testWidgets('a bolinha marca como feita e a barra limpa o que foi', (
    tester,
  ) async {
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);
    await tester.tap(find.byKey(const ValueKey('status-dot')).first);
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.first.status, ItemStatus.done);

    await tester.tap(find.byKey(const ValueKey('clear-done')));
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.map((i) => i.id), ['b2']);
  });

  testWidgets('o automático liga e desliga', (tester) async {
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);
    await tester.tap(find.byKey(const ValueKey('queue-auto')));
    await tester.pump();
    await tester.pump();
    expect(repo.queue.auto, isTrue);
  });

  testWidgets('o destino escolhe-se no menu quando há mais de um ligado', (
    tester,
  ) async {
    final repo = InMemoryQueueRepository(
      queue: const PromptQueue(
        targets: [
          QueueTarget(id: 'dev', label: 'Dev'),
          QueueTarget(id: 'front', label: 'Front'),
        ],
      ),
    );
    await pumpQueue(tester, repo);
    await tester.tap(find.byKey(const ValueKey('queue-target')));
    await tester.pump();
    await tester.tap(find.text('Front'));
    await tester.pump();
    await tester.pump();
    expect(repo.queue.destination, 'front');
  });

  testWidgets('arrastar uma tarefa pelo corpo (segurando) reordena', (
    tester,
  ) async {
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);
    final first = tester.getCenter(find.text('Toast atrás do header'));
    final second = tester.getCenter(find.text('Segunda tarefa'));

    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(second + const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();

    expect(repo.queue.items.map((i) => i.id), ['b2', 'a1']);
  });

  testWidgets('botão direito: subir, descer, remover', (tester) async {
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);
    await tester.tap(find.text('Segunda tarefa'), buttons: kSecondaryButton);
    await tester.pump();
    await tester.tap(find.text('Subir'));
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.map((i) => i.id), ['b2', 'a1']);

    await tester.tap(
      find.text('Toast atrás do header'),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.tap(find.text('Remover'));
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.map((i) => i.id), ['b2']);
  });

  testWidgets('mão em tudo que responde a clique', (tester) async {
    final repo = InMemoryQueueRepository(
      queue: PromptQueue(
        items: const [
          QueueItem(id: 'a1', text: 'Toast', images: ['p.png']),
        ],
        targets: const [
          QueueTarget(id: 'dev', label: 'Dev'),
          QueueTarget(id: 'f', label: 'F'),
        ],
      ),
    );
    await pumpQueue(tester, repo);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    Future<void> expectHand(Finder finder, String name) async {
      await mouse.moveTo(tester.getCenter(finder));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
        reason: '$name responde a clique',
      );
    }

    await expectHand(find.byKey(const ValueKey('queue-target')), 'destino');
    await expectHand(find.byKey(const ValueKey('queue-auto')), 'automático');
    await expectHand(
      find.byKey(const ValueKey('send-next')),
      'enviar a próxima',
    );
    await expectHand(find.byKey(const ValueKey('clear-done')), 'limpar');
    await expectHand(find.byKey(const ValueKey('status-dot')), 'bolinha');
    await expectHand(find.byKey(const ValueKey('queue-row')), 'tarefa');
    await tester.tap(find.byKey(const ValueKey('queue-row')));
    await tester.pump();
    await tester.pump();
    await expectHand(find.byKey(const ValueKey('send-item')), 'enviar');
    await expectHand(find.byKey(const ValueKey('detach-p.png')), 'tirar print');
  });
}

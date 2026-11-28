import 'package:egeon_deck/features/node/queue/domain/entities/prompt_queue.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_item.dart';

import '../../../support/in_memory_queue_repository.dart';
import '../../../support/inject_fakes.dart';

import 'package:egeon_deck/features/node/queue/presentation/widgets/queue_body.dart';
import 'package:egeon_deck/features/node/queue/presentation/widgets/queue_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:egeon_deck/commons/widgets/eg/spinner.dart';

import '../../../support/eg_host.dart';

import 'package:egeon_deck/commons/utils/app_shortcut.dart';

Future<TestGesture> pumpQueue(
  WidgetTester tester,
  InMemoryQueueRepository repo,
) async {
  tester.view
    ..physicalSize = const Size(540, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  injectFakes(queue: (_) => repo);
  await tester.pumpWidget(
    egHost(
      fill: true,
      size: const Size(540, 800),
      const QueueBody(workbenchId: 'bancada', nodeId: 'fila'),
    ),
  );
  await tester.pump();
  await tester.pump();
  // A barra (destino, Automático…) só aparece com o ponteiro no card: o ponteiro
  // fica no canto de cima, onde não toca em nenhuma tarefa.
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(2, 2));
  addTearDown(mouse.removePointer);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return mouse;
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
    expect(
      find.textContaining('enviada'),
      findsNothing,
      reason: 'a v3 não escreve o estado: o spinner o diz',
    );
    expect(
      find.byType(Spinner),
      findsOneWidget,
      reason: 'entregue = trabalhando',
    );
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
    expect(find.text('Responder a pergunta…'), findsOneWidget);

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
    final mouse = await pumpQueue(tester, repo);
    // Pendente é só texto; a bolinha (o checkbox) aparece com o ponteiro na linha.
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('queue-row')).first),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('status-dot')).first);
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.first.status, ItemStatus.done);

    await tester.tap(find.byKey(const ValueKey('clear-done')));
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.map((i) => i.id), ['b2']);
  });

  testWidgets('a barra do card só aparece com o ponteiro nele', (tester) async {
    tester.view
      ..physicalSize = const Size(540, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    injectFakes(queue: (_) => InMemoryQueueRepository(queue: seeded()));
    await tester.pumpWidget(
      egHost(
        fill: true,
        size: const Size(540, 800),
        const QueueBody(workbenchId: 'bancada', nodeId: 'fila'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('queue-auto')), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(2, 2));
    addTearDown(mouse.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('queue-auto')), findsOneWidget);
    await mouse.moveTo(const Offset(900, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('queue-auto')), findsNothing);
  });

  testWidgets('pendente e feita são só texto; a bolinha vem com o ponteiro', (
    tester,
  ) async {
    final repo = InMemoryQueueRepository(
      queue: const PromptQueue(
        items: [
          QueueItem(id: 'a1', text: 'Pendente'),
          QueueItem(id: 'b2', text: 'Feita', status: ItemStatus.done),
        ],
      ),
    );
    final mouse = await pumpQueue(tester, repo);
    expect(find.byKey(const ValueKey('status-dot')), findsNothing);
    expect(find.text('feita'), findsNothing, reason: 'sem legenda de estado');
    await mouse.moveTo(tester.getCenter(find.text('Pendente')));
    await tester.pump();
    expect(find.byKey(const ValueKey('status-dot')), findsOneWidget);
  });

  testWidgets('a linha "Nova tarefa" só vem com o ponteiro; no painel fica', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(540, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    injectFakes(queue: (_) => InMemoryQueueRepository(queue: seeded()));
    Future<void> mount({VoidCallback? onClose}) async {
      await tester.pumpWidget(
        egHost(
          fill: true,
          size: const Size(540, 800),
          QueueBody(workbenchId: 'bancada', nodeId: 'fila', onClose: onClose),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    await mount();
    expect(find.text('Nova tarefa'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(2, 2));
    addTearDown(mouse.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Nova tarefa'), findsOneWidget);
    await mouse.moveTo(const Offset(900, 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Nova tarefa'), findsNothing);

    await mount(onClose: () {});
    expect(find.text('Nova tarefa'), findsOneWidget, reason: 'no painel fica');
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

  testWidgets('botão direito: mover para cima e apagar', (tester) async {
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);
    await tester.tap(find.text('Segunda tarefa'), buttons: kSecondaryButton);
    await tester.pump();
    expect(find.text('Enviar agora'), findsOneWidget);
    expect(find.text('Mover para baixo'), findsOneWidget);
    await tester.tap(find.text('Mover para cima'));
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.map((i) => i.id), ['b2', 'a1']);

    await tester.tap(
      find.text('Toast atrás do header'),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.tap(find.text('Apagar'));
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items.map((i) => i.id), ['b2']);
  });

  testWidgets(
    'tarefa enviada: o menu não apaga, não reenvia nem volta a pendente',
    (tester) async {
      final repo = InMemoryQueueRepository(
        queue: PromptQueue(
          items: [
            QueueItem(
              id: 'a1',
              text: 'Toast',
              status: ItemStatus.sent,
              sentTo: 'dev',
              sentAt: DateTime(2026),
            ),
          ],
          targets: const [QueueTarget(id: 'dev', label: 'Dev')],
        ),
      );
      await pumpQueue(tester, repo);
      await tester.tap(find.text('Toast'), buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Mover para cima'), findsOneWidget);
      expect(find.text('Apagar'), findsNothing);
      expect(find.text('Enviar agora'), findsNothing);
      expect(find.text('Voltar para pendente'), findsNothing);
    },
  );

  testWidgets('comentar uma tarefa pendente: vai junto quando enviar', (
    tester,
  ) async {
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);
    await tester.tap(find.text('Segunda tarefa'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Comentar — vai junto quando enviar'), findsOneWidget);
    final reply = find.descendant(
      of: find.byKey(const ValueKey('reply-b2-0')),
      matching: find.byType(EditableText),
    );
    await tester.tap(reply);
    await tester.pump();
    await tester.enterText(reply, 'olha o mobile também');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(repo.queue.items[1].thread.last.text, 'olha o mobile também');
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
    final mouse = await pumpQueue(tester, repo);
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
    // A bolinha só aparece com o ponteiro na linha: primeiro a linha.
    await expectHand(find.byKey(const ValueKey('queue-row')), 'tarefa');
    await expectHand(find.byKey(const ValueKey('status-dot')), 'bolinha');
    await tester.tap(find.byKey(const ValueKey('queue-row')));
    await tester.pump();
    await tester.pump();
    await expectHand(find.byKey(const ValueKey('send-item')), 'enviar');
    await expectHand(find.byKey(const ValueKey('detach-p.png')), 'tirar print');
    await expectHand(find.byKey(const ValueKey('thumb-p.png')), 'abrir print');
    await tester.tap(find.byKey(const ValueKey('thumb-p.png')));
    await tester.pump();
    expect(repo.openedImages.single.$2, 'p.png');
  });

  testWidgets('fora do macOS é o Ctrl+V que cola a imagem na tarefa', (
    tester,
  ) async {
    debugUsesCommandKey = false;
    addTearDown(() => debugUsesCommandKey = true);
    final repo = InMemoryQueueRepository(queue: seeded());
    await pumpQueue(tester, repo);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('egeon/image-drop'),
      (call) async => call.method == 'pastedImage'
          ? {
              'png': Uint8List.fromList([9, 9]),
            }
          : null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': ''};
      if (call.method == 'Clipboard.hasStrings') return {'value': false};
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('egeon/image-drop'),
        null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final typing = find.descendant(
      of: find.byKey(const ValueKey('new-field-0')),
      matching: find.byType(EditableText),
    );
    await tester.tap(typing);
    await tester.enterText(typing, 'olha o header');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final created = repo.queue.items.last;
    expect(created.text, 'olha o header');
    expect(repo.attached[created.id]!.single.bytes, [9, 9]);
  });

  testWidgets(
    'fora do macOS AltGr+V digita: não cola a área de transferência',
    (tester) async {
      debugUsesCommandKey = false;
      addTearDown(() => debugUsesCommandKey = true);
      final repo = InMemoryQueueRepository(queue: seeded());
      await pumpQueue(tester, repo);
      final messenger = tester.binding.defaultBinaryMessenger;
      var reads = 0;
      messenger.setMockMethodCallHandler(
        const MethodChannel('egeon/image-drop'),
        (call) async {
          if (call.method == 'pastedImage') reads++;
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('egeon/image-drop'),
          null,
        ),
      );
      final typing = find.descendant(
        of: find.byKey(const ValueKey('new-field-0')),
        matching: find.byType(EditableText),
      );
      await tester.tap(typing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV, character: '@');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();
      expect(reads, 0, reason: 'AltGr+V não é o colar');
    },
  );

  group('⌘V', () {
    /// A área de transferência como o plugin do runner a lê (`pastedImage`) e o
    /// texto que o `Clipboard` do Flutter devolve.
    void clipboard(
      WidgetTester tester, {
      Map<String, Object?>? image,
      String text = '',
    }) {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('egeon/image-drop'),
        (call) async => call.method == 'pastedImage' ? image : null,
      );
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': text};
        if (call.method == 'Clipboard.hasStrings') {
          return {'value': text.isNotEmpty};
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('egeon/image-drop'),
          null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
    }

    Future<void> commandV(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    );

    testWidgets('print na linha de baixo vira tarefa aberta com o texto', (
      tester,
    ) async {
      final repo = InMemoryQueueRepository(queue: seeded());
      await pumpQueue(tester, repo);
      clipboard(
        tester,
        image: {
          'png': Uint8List.fromList([9, 9]),
        },
      );
      final typing = field('new-field-0');
      await tester.tap(typing);
      await tester.enterText(typing, 'olha o header');
      await commandV(tester);

      final created = repo.queue.items.last;
      expect(created.text, 'olha o header');
      expect(repo.attached[created.id]!.single.bytes, [9, 9]);
      expect(repo.attached[created.id]!.single.path, isNull);
      // A tarefa abre, e a linha de baixo se esvazia para a próxima.
      expect(field('editor-${created.id}'), findsOneWidget);
      final newRow = find.descendant(
        of: find.byKey(const ValueKey('new-row')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(newRow).controller.text, isEmpty);
    });

    testWidgets('no editor, só os arquivos de imagem vão para a tarefa', (
      tester,
    ) async {
      final repo = InMemoryQueueRepository(queue: seeded());
      await pumpQueue(tester, repo);
      clipboard(
        tester,
        image: {
          'files': ['/tmp/tela.PNG', '/tmp/notas.txt'],
        },
      );
      await tester.tap(find.text('Segunda tarefa'));
      await tester.pump();
      await tester.pump();
      await commandV(tester);

      expect(repo.attached['b2']!.map((i) => i.path), ['/tmp/tela.PNG']);
      expect(repo.queue.items, hasLength(2));
    });

    testWidgets('sem imagem que sirva, cola o texto', (tester) async {
      final repo = InMemoryQueueRepository(queue: seeded());
      await pumpQueue(tester, repo);
      clipboard(
        tester,
        image: {
          'files': ['/tmp/notas.txt'],
        },
        text: '/tmp/notas.txt',
      );
      final newRow = field('new-field-0');
      await tester.tap(newRow);
      await tester.pump();
      await commandV(tester);

      expect(repo.attached, isEmpty);
      expect(repo.queue.items, hasLength(2));
      expect(
        tester.widget<EditableText>(field('new-field-0')).controller.text,
        '/tmp/notas.txt',
      );
    });
  });

  testWidgets(
    'aberta, o clique no vazio do cartão é escrever, não fechar; fora dele '
    'fecha',
    (tester) async {
      await pumpQueue(tester, InMemoryQueueRepository(queue: seeded()));
      await tester.tap(find.text('Toast atrás do header'));
      await tester.pump();
      await tester.pump();
      final editor = find.byKey(const ValueKey('editor-a1'));
      expect(editor, findsOneWidget);
      FocusNode focusOf(Finder of) => tester
          .widget<EditableText>(
            find.descendant(of: of, matching: find.byType(EditableText)),
          )
          .focusNode;

      // O teclado na resposta; o vazio do cartão o traz de volta à tarefa.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('reply-a1-0')),
          matching: find.byType(EditableText),
        ),
      );
      await tester.pump();
      expect(focusOf(editor).hasFocus, isFalse);
      final card = find.byType(QueueRow).first;
      await tester.tapAt(tester.getBottomLeft(card) + const Offset(40, -10));
      await tester.pump();
      await tester.pump();
      expect(editor, findsOneWidget, reason: 'continua aberta');
      expect(focusOf(editor).hasFocus, isTrue);

      // O vazio da lista, abaixo da linha nova, fecha.
      await tester.tapAt(const Offset(270, 780));
      await tester.pump();
      await tester.pump();
      expect(editor, findsNothing);
    },
  );
}

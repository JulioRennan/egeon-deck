import 'dart:convert';
import 'dart:io';

import 'package:egeon_deck/features/chat/domain/entities/chat_queue.dart';
import 'package:egeon_deck/core/adapters/injector.dart';
import 'package:egeon_deck/features/chat/presentation/cubit/queue_panel_width.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_composer.dart';
import 'package:egeon_deck/features/node/queue/presentation/widgets/queue_body.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_thread.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_update.dart';
import 'package:egeon_deck/features/chat/presentation/page/chat_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/chat_fixtures.dart';
import '../../support/fake_chat_repository.dart';
import '../../support/in_memory_queue_repository.dart';
import '../../support/inject_fakes.dart';
import '../../support/overlay_host.dart';

const _fila = ChatQueueInfo(id: 'fila1', summary: '2 pendentes · com front');
const _pergunta = ChatQueueInfo(
  id: 'fila2',
  summary: '? pergunta',
  asking: true,
);

Future<FakeChatRepository> mount(
  WidgetTester tester, {
  Size size = const Size(1100, 600),
  bool withPanel = true,
  double? width,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = FakeChatRepository();
  final queues = InMemoryQueueRepository();
  injectFakes(chat: repository, queue: (_) => queues);
  inject<QueuePanelWidth>().notifier.value = width;
  await tester.pumpWidget(
    overlayHost(
      ChatPage(workbenchId: 'b1', offerQueues: withPanel),
      size: size,
    ),
  );
  repository.reset(
    1,
    const [],
    participants: [frontInfo, backInfo],
    queues: [_fila, _pergunta],
  );
  await tester.pump();
  await tester.pump();
  return repository;
}

void main() {
  test('o op queues da fixture do core vira a lista de filas', () {
    final raw = jsonDecode(
      File('../rust/crates/egeon-core/fixtures/chat/events.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final ops = <Map<String, Object?>>[];
    void walk(Object? node) {
      if (node is Map<String, Object?>) {
        if (node['op'] == 'queues') ops.add(node);
        node.values.forEach(walk);
      } else if (node is List<Object?>) {
        node.forEach(walk);
      }
    }

    walk(raw);
    expect(ops, isNotEmpty);
    for (final map in ops) {
      final op = BlockOp.fromMap(map);
      expect(op, isA<QueuesOp>());
      expect((op as QueuesOp).list.length, (map['list']! as List).length);
    }

    final withItems = [
      for (final map in ops)
        if ((map['list']! as List).isNotEmpty) map,
    ];
    expect(withItems, isNotEmpty, reason: 'a fixture traz filas de verdade');
    for (final map in withItems) {
      for (final raw in map['list']! as List) {
        final item = raw as Map<String, Object?>;
        final read = ChatQueueInfo.fromMap(item);
        expect(read.id, item['id']);
        expect(read.summary, item['summary']);
        expect(read.asking, item['asking']);
      }
    }

    final thread = const ChatThread().apply(
      ChatUpdate(
        workbench: 'w',
        rev: 1,
        ops: [
          BlockOp.fromMap({
            'op': 'queues',
            'list': [
              {'id': 'f', 'summary': '? pergunta', 'asking': true},
            ],
          }),
        ],
      ),
    );
    expect(thread.queues.single.asking, isTrue);
    expect(thread.queues.single.summary, '? pergunta');
  });

  testWidgets('a coluna lista as filas; a pergunta vai em laranja', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('FILAS'), findsOneWidget);
    expect(find.text('2 pendentes · com front'), findsOneWidget);
    expect(find.text('? pergunta'), findsOneWidget);
    final asking = tester.widget<Text>(
      find.byKey(const ValueKey('queue-summary-fila2')),
    );
    final calm = tester.widget<Text>(
      find.byKey(const ValueKey('queue-summary-fila1')),
    );
    expect(asking.style!.color, isNot(calm.style!.color));
    expect(find.byKey(const ValueKey('new-queue')), findsOneWidget);
  });

  testWidgets('o clique abre o painel da fila ao lado; outro clique a fecha', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('queue-split')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('queue-fila1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('queue-split')), findsOneWidget);
    expect(find.byType(QueueBody), findsOneWidget);
    expect(tester.widget<QueueBody>(find.byType(QueueBody)).nodeId, 'fila1');

    await tester.tap(find.byKey(const ValueKey('queue-fila2')));
    await tester.pump();
    expect(
      tester.widget<QueueBody>(find.byType(QueueBody)).nodeId,
      'fila2',
      reason: 'a outra fila ocupa o mesmo painel',
    );

    await tester.tap(find.byKey(const ValueKey('queue-fila2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('queue-split')), findsNothing);
  });

  testWidgets(
    'abrir e fechar o painel guarda o texto do composer; o teclado vai à '
    'fila e volta',
    (tester) async {
      await mount(tester);
      EditableText field(Finder of) => tester.widget<EditableText>(
        find.descendant(of: of, matching: find.byType(EditableText)),
      );
      final composer = find.byKey(const ValueKey('composer-field'));
      await tester.enterText(
        find.descendant(of: composer, matching: find.byType(EditableText)),
        'meio escrito',
      );

      await tester.tap(find.byKey(const ValueKey('queue-fila1')));
      await tester.pump();
      await tester.pump();
      expect(field(composer).controller.text, 'meio escrito');
      expect(
        field(find.byKey(const ValueKey('new-row'))).focusNode.hasFocus,
        isTrue,
        reason: 'abrir leva o teclado a "Nova tarefa"',
      );

      await tester.tap(find.byKey(const ValueKey('queue-fila1')));
      await tester.pump();
      expect(field(composer).controller.text, 'meio escrito');
      expect(
        field(composer).focusNode.hasFocus,
        isTrue,
        reason: 'fechar devolve o teclado ao composer',
      );
    },
  );

  testWidgets('o ✕ do painel também devolve o teclado ao composer', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('queue-fila1')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('queue-close')));
    await tester.pump();
    expect(find.byType(QueueBody), findsNothing);
    final composer = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('composer-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(composer.focusNode.hasFocus, isTrue);
  });

  testWidgets('a conversa fica ao lado do painel, com o composer à mão', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('queue-fila1')));
    await tester.pump();
    expect(find.byType(ChatComposer), findsOneWidget);
    expect(
      tester.getTopRight(find.byType(ChatComposer)).dx,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('queue-split'))).dx,
      ),
    );
  });

  testWidgets('+ Nova fila pede ao core e abre a fila criada', (tester) async {
    final repository = await mount(tester);
    repository.newQueueId = 'fila2';
    await tester.tap(find.byKey(const ValueKey('new-queue')));
    await tester.pump();
    await tester.pump();
    expect(repository.newQueues, 1);
    expect(tester.widget<QueueBody>(find.byType(QueueBody)).nodeId, 'fila2');
  });

  testWidgets('a fila nova é ligada ao agente em foco, que só a tela sabe', (
    tester,
  ) async {
    final repository = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('participant-back')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-queue')));
    await tester.pump();
    await tester.pump();
    expect(repository.newQueueAgents, ['back']);
  });

  testWidgets('terminal em foco não vale: a fila liga ao primeiro agente', (
    tester,
  ) async {
    final repository = await mount(tester);
    repository.reset(
      2,
      const [],
      participants: [frontInfo, backInfo, shellInfo],
      queues: [_fila],
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('participant-sh1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-queue')));
    await tester.pump();
    await tester.pump();
    expect(repository.newQueueAgents, ['front']);
  });

  testWidgets('bancada sem agente: a fila nasce solta, sem `agent`', (
    tester,
  ) async {
    final repository = await mount(tester);
    // A fila nova tem de estar na lista que o core publica para o painel abrir.
    repository.newQueueId = 'fila1';
    repository.reset(2, const [], participants: [shellInfo], queues: [_fila]);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('new-queue')));
    await tester.pump();
    await tester.pump();
    expect(repository.newQueueAgents, [null]);
    expect(find.byKey(const ValueKey('chat-notice')), findsNothing);
    expect(find.byKey(const ValueKey('queue-split')), findsOneWidget);
  });

  testWidgets('a recusa do core aparece como aviso e some sozinha', (
    tester,
  ) async {
    final repository = await mount(tester);
    repository.refuseNewQueue = "'xyz' não é um agente da bancada";
    await tester.tap(find.byKey(const ValueKey('new-queue')));
    await tester.pump();
    await tester.pump();
    expect(find.text("'xyz' não é um agente da bancada"), findsOneWidget);
    expect(find.byKey(const ValueKey('queue-split')), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('chat-notice')), findsNothing);
  });

  testWidgets('a fila aberta que sai da bancada fecha o painel', (
    tester,
  ) async {
    final repository = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('queue-fila1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('queue-split')), findsOneWidget);

    repository.push(
      ChatUpdate(
        workbench: 'b1',
        rev: 2,
        ops: [
          QueuesOp(const [_pergunta]),
        ],
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('queue-split')), findsNothing);
  });

  testWidgets('sem quem hospede o painel, a coluna não oferece filas', (
    tester,
  ) async {
    await mount(tester, withPanel: false);
    expect(find.text('FILAS'), findsNothing);
    expect(find.byKey(const ValueKey('new-queue')), findsNothing);
  });

  testWidgets('a largura do painel é uma só e vem de fora do chat', (
    tester,
  ) async {
    await mount(tester, width: 440);
    final width = inject<QueuePanelWidth>();
    await tester.tap(find.byKey(const ValueKey('queue-fila1')));
    await tester.pump();
    final body = tester.getSize(find.byType(QueueBody)).width;
    expect(body, closeTo(440, 1));

    width.notifier.value = null;
    await tester.pump();
    expect(
      tester.getSize(find.byType(QueueBody)).width,
      isNot(closeTo(440, 1)),
      reason: 'sem largura escolhida volta ao padrão',
    );
  });
}

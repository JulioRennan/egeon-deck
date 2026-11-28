import 'dart:convert';
import 'dart:io';

import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/core/adapters/event_parsing.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_thread.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_update.dart';
import 'package:egeon_deck/features/chat/domain/repository/socket_chat_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/chat_fixtures.dart';
import '../../support/fake_transport.dart';
import '../../support/protocol_fixtures.dart';
import '../../support/pump.dart';

// O envelope e os comandos do chat são os de commands.json/replies.json do
// core: cada comando que a UI manda é comparado com a fixture. As linhas em si
// são a fixture de chat (chat_blocks_test).
void main() {
  final commands = loadProtocolFixture('commands');
  final replies = loadProtocolFixture('replies');
  const wb = '1a2b3c4d';
  late FakeConnection connection;
  late EgeonSocketClient client;
  late SocketChatRepository repository;

  setUp(() async {
    final transport = FakeTransport();
    client = EgeonSocketClient(
      transport,
      retryDelay: const Duration(milliseconds: 10),
    )..start();
    await pump();
    connection = transport.connections.last..upgrade();
    await client.whenConnected;
    repository = SocketChatRepository(client);
  });

  tearDown(() => client.dispose());

  Future<Map<String, Object?>> answered(Future<void> action) async {
    await pump();
    final sent = connection.sent.last;
    connection.say({'re': sent['id'], 'ok': true});
    await action;
    return withoutId(sent);
  }

  Map<String, Object?> fixture(String name) => withoutId(commands[name]!);

  test('assina chat/<bancada> e entrega o diff de linhas', () async {
    final first = repository.watch(wb).first;
    await pump();
    expect(withoutId(connection.sent.single), fixture('subscribe_chat'));
    connection.say({
      'topic': 'chat/$wb',
      'workbench': wb,
      'rev': 1,
      'ops': [
        {
          'op': 'reset',
          'blocks': [prompt(1).raw],
        },
      ],
    });
    final update = await first;
    expect(update.rev, 1);
    expect((update.ops.single as ResetOp).blocks.single.id, 'p|u1');
  });

  test(
    'um diff ilegível vira o aviso de evento perdido, e o stream segue',
    () async {
      final previous = ParseFailures.sink;
      ParseFailures.reset();
      ParseFailures.sink = (what, error, stack) {};
      addTearDown(() {
        ParseFailures.sink = previous;
        ParseFailures.reset();
      });
      final seen = <ChatUpdate>[];
      final sub = repository.watch(wb).listen(seen.add);
      await pump();
      Map<String, Object?> good(int rev) => {
        'topic': 'chat/$wb',
        'workbench': wb,
        'rev': rev,
        'ops': [
          {
            'op': 'reset',
            'blocks': [prompt(1).raw],
          },
        ],
      };
      connection.say(good(1));
      connection.say({'topic': 'chat/$wb', 'workbench': wb, 'rev': 'torto'});
      connection.say(good(3));
      await pump();

      expect(seen.map((u) => u.unreadable), [false, true, false]);
      expect(seen[1].workbench, wb);
      await sub.cancel();
    },
  );

  test('os eventos de participantes e permissão do core são lidos', () {
    final events = jsonDecode(
      File('../rust/crates/egeon-core/fixtures/chat/events.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final updates = [
      for (final e in events['events']! as List<Object?>)
        ChatUpdate.fromMap(e! as Map<String, Object?>),
    ];
    // A barra de quem está na conversa, as filas, o pedido aberto e o fechado:
    // pelo tipo da op, e não pela posição, que o core muda ao gravar mais casos.
    T single<T extends BlockOp>(Iterable<ChatUpdate> from) =>
        from.expand((u) => u.ops).whereType<T>().toList().first;
    final first = single<ParticipantsOp>(updates).list;
    expect(first.map((p) => p.id), ['front', 'back']);
    expect(first.first.activity, 'working');
    expect(first.first.address, 'deck/front');
    expect(first.first.isAgent, isTrue);
    final trays = [
      for (final op in updates.expand((u) => u.ops).whereType<PermissionsOp>())
        op.list,
    ];
    final stacked = trays.firstWhere((l) => l.isNotEmpty);
    expect(stacked.map((r) => r.id), ['p1', 'p2'], reason: 'empilhados');
    expect(stacked.first.tool, 'Bash');
    expect(stacked.first.detail, 'rm -rf x');
    expect(stacked.last.isQuestion, isTrue);
    expect(trays.last, isEmpty);
    expect(
      updates.expand((u) => u.ops).whereType<QueuesOp>(),
      isNotEmpty,
      reason: 'o core manda as filas',
    );
  });

  test('a assinatura traz tudo: linhas, participantes e permissão', () {
    final events = jsonDecode(
      File('../rust/crates/egeon-core/fixtures/chat/events.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final thread = const ChatThread().apply(
      ChatUpdate.fromMap(events['subscribe']! as Map<String, Object?>),
    );
    expect(thread.rev, greaterThan(0));
    expect(thread.blocks, isEmpty);
    expect(thread.participants.map((p) => p.id), ['front', 'back']);
    expect(thread.permissions, isEmpty);
  });

  test('evento a evento, a thread guarda a barra e o pedido', () {
    final events = jsonDecode(
      File('../rust/crates/egeon-core/fixtures/chat/events.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    var thread = const ChatThread();
    final seen = <String?>[];
    for (final e in events['events']! as List<Object?>) {
      thread = thread.apply(ChatUpdate.fromMap(e! as Map<String, Object?>));
      seen.add(thread.permissions.firstOrNull?.id);
    }
    expect(seen.where((id) => id != null), isNotEmpty);
    expect(seen.first, isNull);
    expect(seen.last, isNull, reason: 'o pedido abre e fecha');
    expect(
      thread.participants,
      hasLength(2),
      reason: 'a barra fica entre eventos',
    );
  });

  test('uma op que a UI não conhece não quebra a thread', () {
    final update = ChatUpdate.fromMap({
      'workbench': wb,
      'rev': 2,
      'ops': [
        {'op': 'futura'},
        {'op': 'remove', 'id': 'p|u1'},
      ],
    });
    expect(update.ops.first, isA<UnknownOp>());
    expect(applyOps([prompt(1)], update.ops), isEmpty);
  });

  test('as respostas da bandeja saem como as fixtures do core', () async {
    expect(
      await answered(repository.answerPermission(wb, 'p7', answer: 'always')),
      fixture('permission_answer'),
    );
    expect(
      await answered(
        repository.answerPermission(
          wb,
          'p8',
          choice: 'Sim, e não pergunte de novo',
        ),
      ),
      fixture('permission_answer_escolha'),
    );
    final several = commands['permission_answer_varias']!['answers']! as Map;
    expect(
      await answered(
        repository.answerPermission(
          wb,
          commands['permission_answer_varias']!['request']! as String,
          answers: {
            for (final e in several.entries)
              e.key as String: [for (final o in e.value as List) o as String],
          },
        ),
      ),
      fixture('permission_answer_varias'),
    );
  });

  test('passo e capa são o mesmo chat_step, como na fixture', () async {
    final step = repository.toggleStep(wb, 'b|u1|2');
    expect(await answered(step), fixture('chat_step'));
    final group = repository.cycleGroup(wb, 'b|u1|2');
    expect(await answered(group), fixture('chat_step'));
  });

  test('mais histórico, arquivar e instantâneo, como na fixture', () async {
    expect(await answered(repository.loadMore(wb)), fixture('chat_more'));
    expect(await answered(repository.clear(wb)), fixture('chat_clear'));
    expect(
      await answered(repository.openLink('https://example.com/docs')),
      fixture('open_url'),
    );

    final future = repository.snapshot(wb);
    await pump();
    final sent = connection.sent.last;
    expect(withoutId(sent), fixture('chat_snapshot'));
    connection.say({
      ...replies['chat_snapshot']!,
      're': sent['id'],
      'blocks': [prompt(2).raw],
      // O core manda também a coluna, as filas e a bandeja
      // (`ChatView::snapshot`); a recuperação não pode perdê-las.
      'participants': [
        {
          'id': 'sh1',
          'address': 'deck/sh1',
          'isAgent': false,
          'role': 'zsh',
          'activity': 'ready',
          'needsAttention': false,
          'screen': 'w1.sh1',
        },
      ],
      'queues': [
        {'id': 'fila1', 'summary': '2 pendentes', 'asking': false},
      ],
      'permissions': [
        {'id': 'p1', 'tool': 'Bash', 'detail': 'rm -rf x'},
      ],
    });
    final thread = await future;
    expect(thread.rev, 42);
    expect(thread.blocks.single.id, 'p|u2');
    expect(thread.participants.single.screen, 'w1.sh1');
    expect(thread.queues.single.id, 'fila1');
    expect(thread.permissions.single.id, 'p1');
  });

  test(
    'o envio leva destinatários, texto e citação, como na fixture',
    () async {
      expect(
        await answered(
          repository.send(
            wb,
            to: ['claude', 'rev'],
            text: 'revisa o delta da US-105',
            quoteKey: 'r|u1',
          ),
        ),
        fixture('chat_send'),
      );
      expect(
        (await answered(repository.send(wb, to: ['claude'], text: 'oi')))
            .containsKey('quote'),
        isFalse,
      );
    },
  );
}

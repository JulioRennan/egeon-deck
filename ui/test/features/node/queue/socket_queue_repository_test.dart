import 'dart:convert';
import 'dart:typed_data';

import 'package:egeon_deck/features/node/queue/domain/entities/queue_effect.dart';
import 'package:egeon_deck/features/node/queue/domain/entities/queue_item.dart';
import 'package:egeon_deck/features/node/queue/domain/repository/queue_repository.dart';
import 'package:egeon_deck/features/node/queue/domain/repository/socket_queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pasted_image_fake.dart';
import '../../../support/protocol_fixtures.dart';
import '../../../support/pump.dart';
import '../../../support/socket_fixture_harness.dart';

import 'package:egeon_deck/features/node/queue/domain/errors/queue_error.dart';

void main() {
  late SocketHarness harness;
  late SocketQueueRepository repository;
  final commands = loadProtocolFixture('commands');
  final events = loadProtocolFixture('events');
  final replies = loadProtocolFixture('replies');
  const wb = '1a2b3c4d';

  setUp(() async {
    harness = await SocketHarness.start();
    repository = SocketQueueRepository(harness.client, wb);
  });
  tearDown(() => harness.dispose());

  test('o estado da fila: tarefas, thread, destino e bloqueio', () async {
    final first = repository.watch('fila').first;
    await pump();
    harness.connection.say(events['node_queue']!);
    final queue = await first;

    expect(queue.auto, isTrue);
    expect(queue.blocker, 'claude está trabalhando');
    expect(queue.destination, 'claude');
    expect(queue.pending, 1);
    expect(queue.asking, isTrue);
    expect(queue.subtitle, '1 pendente');
    expect(queue.imageExtensions, contains('png'));
    expect(queue.imagesDir, endsWith('/queues/fila/images'));
    expect(queue.items.map((i) => i.id), ['a1b2c3', 'd4e5f6']);

    final sent = queue.items[0];
    expect(sent.status, ItemStatus.sent);
    expect(sent.awaiting, isTrue);
    expect(sent.locked, isTrue);
    expect(sent.sentAt, DateTime.utc(2026, 11, 18, 3, 12));
    expect(
      sent.thread.single.kind,
      MessageKind.question,
      reason: 'a pergunta do agente é `question` no fio',
    );
    expect(sent.thread.single.text, 'Posso apagar o target?');

    final pending = queue.items[1];
    expect(pending.status, ItemStatus.pending);
    expect(pending.images, ['img-9f8e7d6c.png']);
    expect(pending.locked, isFalse);
    expect(pending.empty, isFalse);
    expect(queue.summary, '? pergunta');
  });

  test('rascunho e abrir tarefa chegam como efeitos', () async {
    final seen = <QueueEffect>[];
    final sub = repository.effects('fila').listen(seen.add);
    await pump();
    harness.connection.say(events['node_draft']!);
    harness.connection.say(events['node_open_item']!);
    harness.connection.say(events['node_queue']!);
    await pump();
    expect((seen[0] as QueueDraft).text, 'rascunho vindo do egeon');
    expect((seen[1] as QueueOpenItem).item, 'a1b2c3');
    expect(seen, hasLength(2), reason: 'o estado não é efeito');
    await sub.cancel();
  });

  test('o estado da fila ignora os efeitos', () async {
    final seen = <Object>[];
    final sub = repository.watch('fila').listen(seen.add);
    await pump();
    harness.connection.say(events['node_draft']!);
    await pump();
    expect(seen, isEmpty);
    await sub.cancel();
  });

  test('os comandos batem com as fixtures', () async {
    expect(
      await harness.sent(
        () => repository.add('fila', text: 'roda os testes', after: 'a1b2c3'),
      ),
      withoutId(commands['queue_add']!),
    );
    expect(
      await harness.sent(
        () => repository.update('fila', 'a1b2c3', 'roda os testes do core'),
      ),
      withoutId(commands['queue_update']!),
    );
    expect(
      await harness.sent(() => repository.remove('fila', 'a1b2c3')),
      withoutId(commands['queue_remove']!),
    );
    expect(
      await harness.sent(() => repository.move('fila', 'a1b2c3', to: 0)),
      withoutId(commands['queue_move']!),
    );
    expect(
      await harness.sent(() => repository.toggleDone('fila', 'a1b2c3')),
      withoutId(commands['queue_toggle_done']!),
    );
    expect(
      await harness.sent(() => repository.reopen('fila', 'a1b2c3')),
      withoutId(commands['queue_reopen']!),
    );
    expect(
      await harness.sent(() => repository.send('fila')),
      withoutId(commands['queue_send_proximo']!),
    );
    expect(
      await harness.sent(() => repository.reply('fila', 'a1b2c3', 'sim, pode')),
      withoutId(commands['queue_reply']!),
    );
    expect(
      await harness.sent(() => repository.clearDone('fila')),
      withoutId(commands['queue_clear_done']!),
    );
    expect(
      await harness.sent(
        () => repository.detach('fila', 'a1b2c3', 'img-9f8e7d6c.png'),
      ),
      withoutId(commands['queue_detach']!),
    );
    expect(
      await harness.sent(
        () => repository.openImage('fila', 'a1b2c3', 'img-9f8e7d6c.png'),
      ),
      withoutId(commands['queue_open_image']!),
    );
  });

  test('automático e destino vão em queue_set', () async {
    final auto = await harness.sent(() => repository.setAuto('fila', on: true));
    expect(auto['cmd'], 'queue_set');
    expect(auto['auto'], isTrue);
    final target = await harness.sent(
      () => repository.setTarget('fila', 'claude'),
    );
    expect(target['target'], 'claude');
    expect(commands['queue_set']!['auto'], isTrue);
  });

  test(
    'anexar: arquivo vai por caminho; print colado, em png base64',
    () async {
      final byPath = await harness.sent(
        () => repository.attach('fila', 'a1b2c3', [
          PastedImage(
            name: 'tela.png',
            bytes: Uint8ListFake.bytes,
            path: '/Users/eu/Desktop/tela.png',
          ),
        ]),
      );
      expect(byPath, withoutId(commands['queue_attach']!));

      // A fixture do colado traz os bytes do PNG em base64.
      final png = base64Decode(
        commands['queue_attach_colado']!['png']! as String,
      );
      final pasted = await harness.sent(
        () => repository.attach('fila', 'a1b2c3', [
          PastedImage(name: 'colado.png', bytes: Uint8List.fromList(png)),
        ]),
      );
      expect(pasted, withoutId(commands['queue_attach_colado']!));
      expect(pasted.containsKey('path'), isFalse);
    },
  );

  test(
    'print solto: a primeira imagem decide a tarefa, as outras vão nela',
    () async {
      final fixture = commands['queue_attach_solto']!;
      final future = repository.attachLoose('fila', [
        PastedImage(
          name: 'tela.png',
          bytes: Uint8List(0),
          path: fixture['path']! as String,
        ),
        PastedImage(name: 'colado.png', bytes: Uint8List.fromList([1])),
      ], open: fixture['open']! as String);
      await pump();
      final first = harness.connection.sent.last;
      expect(withoutId(first), withoutId(fixture));
      harness.connection.say({'re': first['id'], 'ok': true, 'item': 'n9n9n9'});
      await pump();
      final second = harness.connection.sent.last;
      expect(
        second['item'],
        'n9n9n9',
        reason: 'a segunda vai na tarefa criada',
      );
      expect(second.containsKey('open'), isFalse);
      harness.connection.say({'re': second['id'], 'ok': true});
      expect(await future, 'n9n9n9');
    },
  );

  test('a recusa do core vira QueueRefused com o texto dele', () async {
    final error = replies['erro_fila']!['error']! as String;
    final future = repository.send('fila', id: 'a1b2c3');
    await pump();
    harness.connection.say({
      're': harness.connection.sent.last['id'],
      'ok': false,
      'error': error,
    });
    await expectLater(
      future,
      throwsA(isA<QueueRefused>().having((e) => e.message, 'message', error)),
    );
  });

  test('anotar devolve o id que o core responde (fixture queue_add)', () async {
    final reply = replies['queue_add']!;
    final future = repository.add('fila', text: 'x');
    await pump();
    harness.connection.say({
      ...reply,
      're': harness.connection.sent.last['id'],
    });
    expect(await future, 'd4e5f6');
  });
}

import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_key.dart';
import 'package:egeon_deck/features/node/terminal/domain/repository/socket_terminal_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fake_transport.dart';
import '../../../../support/protocol_fixtures.dart';
import '../../../../support/pump.dart';

void main() {
  late FakeTransport transport;
  late EgeonSocketClient client;
  late FakeConnection connection;
  late SocketTerminalRepository repository;
  final commands = loadProtocolFixture('commands');
  final events = loadProtocolFixture('events');
  final replies = loadProtocolFixture('replies');

  setUp(() async {
    transport = FakeTransport();
    client = EgeonSocketClient(
      transport,
      retryDelay: const Duration(milliseconds: 10),
    )..start();
    await pump();
    connection = transport.connections.last..upgrade();
    await client.whenConnected;
    repository = SocketTerminalRepository(client);
  });

  tearDown(() => client.dispose());

  test('manda os comandos do jeito que o core espera', () async {
    final done = Future.wait([
      repository.sendKey('t1', const TerminalKey(key: 'enter')),
      repository.sendText('t1', 'echo oi\r'),
      repository.resize('t1', 120, 40),
    ]);
    await pump();

    final sent = connection.sent.map(withoutId).toList();
    expect(sent[0], withoutId(commands['key_enter']!));
    expect(sent[1], withoutId(commands['input']!));
    expect(sent[2], withoutId(commands['resize']!));
    for (final m in connection.sent) {
      connection.say({'re': m['id'], 'ok': true});
    }
    await done;
  });

  test('paste manda o comando da fixture do core', () async {
    final fixture = commands['paste']!;
    final done = repository.paste(
      fixture['node']! as String,
      fixture['text']! as String,
    );
    await pump();
    final sent = connection.sent.single;
    expect(withoutId(sent), withoutId(fixture));
    connection.say({'re': sent['id'], 'ok': true});
    await done;
  });

  test('assina screen/<id> e entrega quadros', () async {
    final first = repository.watch('t1').first;
    await pump();
    expect(
      withoutId(connection.sent.single),
      withoutId(commands['subscribe_screen']!),
    );

    connection.say(events['screen_full']!);
    final frame = await first;
    expect(frame.full, isTrue);
    expect(frame.lines[0]!.runs.first.text, 'hello ');
  });

  test('create_terminal devolve o terminal criado', () async {
    final created = repository.create();
    await pump();
    expect(withoutId(connection.sent.single), {'cmd': 'create_terminal'});
    connection.say({
      ...replies['terminal_criado']!,
      're': connection.sent.single['id'],
    });
    expect((await created).id, 't1');
  });
}

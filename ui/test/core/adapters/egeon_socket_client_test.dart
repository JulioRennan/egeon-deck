import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_transport.dart';
import '../../support/pump.dart';

void main() {
  late FakeTransport transport;
  late EgeonSocketClient client;

  setUp(() {
    transport = FakeTransport();
    client = EgeonSocketClient(
      transport,
      retryDelay: const Duration(milliseconds: 10),
    );
  });

  tearDown(() => client.dispose());

  Future<FakeConnection> connect() async {
    client.start();
    await pump();
    final connection = transport.connections.last;
    connection.upgrade();
    await client.whenConnected;
    return connection;
  }

  test('abre o canal com GET /ui e Upgrade: egeon-ndjson', () async {
    final connection = await connect();
    expect(connection.head, startsWith('GET /ui HTTP/1.1\r\n'));
    expect(connection.head, contains('Upgrade: egeon-ndjson'));
    expect(client.link, EgeonLink.connected);
  });

  test('resposta volta pelo id do comando', () async {
    final connection = await connect();
    final reply = client.request('ping', {'x': 1});
    await pump();
    final sent = connection.sent.single;
    expect(sent['cmd'], 'ping');
    expect(sent['x'], 1);
    connection.say({'re': sent['id'], 'ok': true, 'pong': true});
    expect((await reply)['pong'], true);
  });

  test('ok:false vira EgeonCommandError', () async {
    final connection = await connect();
    final reply = client.request('quebra');
    await pump();
    connection.say({'re': connection.sent.single['id'], 'ok': false});
    await expectLater(reply, throwsA(isA<EgeonCommandError>()));
  });

  test('evento colado no 101 chega ao assinante', () async {
    final events = client.subscribe('t');
    final first = events.first;
    client.start();
    await pump();
    transport.connections.last.serve(
      'HTTP/1.1 101 Switching Protocols\r\n\r\n'
      '{"topic":"t","n":1}\n',
    );
    expect((await first)['n'], 1);
  });

  test('assina por tópico e só entrega os eventos dele', () async {
    final connection = await connect();
    final received = <int>[];
    final sub = client
        .subscribe('a')
        .listen((m) => received.add(m['n'] as int));
    await pump();
    expect(connection.sent.single['cmd'], 'subscribe');
    expect(connection.sent.single['topic'], 'a');
    connection.say({'topic': 'b', 'n': 1});
    connection.say({'topic': 'a', 'n': 2});
    await pump();
    expect(received, [2]);
    await sub.cancel();
    await pump();
    expect(connection.sent.last['cmd'], 'unsubscribe');
  });

  test(
    'um 2º ouvinte do mesmo tópico pede o estado de novo e o recebe',
    () async {
      final connection = await connect();
      final first = <int>[];
      final second = <int>[];
      final a = client
          .subscribe('screen')
          .listen((m) => first.add(m['n'] as int));
      await pump();
      final b = client
          .subscribe('screen')
          .listen((m) => second.add(m['n'] as int));
      await pump();

      // Dois `subscribe`: o core responde ao segundo com o quadro inteiro.
      expect(connection.sent.where((m) => m['cmd'] == 'subscribe').length, 2);
      connection.say({'topic': 'screen', 'n': 7});
      await pump();
      expect(second, [7], reason: 'o ouvinte novo não fica em branco');
      expect(first, [7], reason: 'o quadro inteiro vale também para o antigo');

      // Só desassina quando o último sai.
      await a.cancel();
      await pump();
      expect(connection.sent.where((m) => m['cmd'] == 'unsubscribe'), isEmpty);
      await b.cancel();
      await pump();
      expect(
        connection.sent.where((m) => m['cmd'] == 'unsubscribe'),
        hasLength(1),
      );
    },
  );

  test('reconecta e reassina os tópicos abertos', () async {
    final first = await connect();
    final sub = client.subscribe('a').listen((_) {});
    await pump();
    await first.drop();
    await pump();
    expect(client.link, EgeonLink.disconnected);

    await pump();
    final second = transport.connections.last;
    expect(second, isNot(same(first)));
    second.upgrade();
    await pump();
    expect(client.link, EgeonLink.connected);
    expect(second.sent.single['cmd'], 'subscribe');
    expect(second.sent.single['topic'], 'a');
    await sub.cancel();
  });

  test('comando pendente falha quando a conexão cai', () async {
    final connection = await connect();
    final reply = client.request('lento');
    final failure = expectLater(reply, throwsA(isA<EgeonDisconnected>()));
    await pump();
    await connection.drop();
    await failure;
  });

  test('sem conexão o comando falha na hora', () async {
    await expectLater(client.request('x'), throwsA(isA<EgeonDisconnected>()));
  });

  test('upgrade recusado derruba e tenta de novo', () async {
    client.start();
    await pump();
    transport.connections.last.serve('HTTP/1.1 404 Not Found\r\n\r\n');
    await pump();
    await pump();
    expect(transport.connections.length, greaterThan(1));
    expect(client.link, EgeonLink.disconnected);
  });
}

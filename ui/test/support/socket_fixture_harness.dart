import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';

import 'fake_transport.dart';
import 'protocol_fixtures.dart';
import 'pump.dart';

/// Um cliente de socket de mentira e o que os testes de contrato precisam
/// dele: mandar um comando e responder, e ler o que saiu.
class SocketHarness {
  SocketHarness._(this.transport, this.client, this.connection);

  final FakeTransport transport;
  final EgeonSocketClient client;
  final FakeConnection connection;

  static Future<SocketHarness> start() async {
    final transport = FakeTransport();
    final client = EgeonSocketClient(
      transport,
      retryDelay: const Duration(milliseconds: 10),
    )..start();
    await pump();
    final connection = transport.connections.last..upgrade();
    await client.whenConnected;
    return SocketHarness._(transport, client, connection);
  }

  /// Executa o gesto, responde `ok` (com [reply]) ao comando que ele mandou e
  /// devolve o comando sem o `id`.
  Future<Map<String, Object?>> sent(
    Future<Object?> Function() act, {
    Map<String, Object?> reply = const {},
    bool ok = true,
  }) async {
    final before = connection.sent.length;
    final future = act();
    await pump();
    final message = connection.sent[before];
    connection.say({'re': message['id'], 'ok': ok, ...reply});
    await future;
    return withoutId(message);
  }

  Future<void> dispose() => client.dispose();
}

/// O comando sem os campos que o teste não confere.
Map<String, Object?> only(
  Map<String, Object?> message,
  Iterable<String> keys,
) => {
  for (final key in keys)
    if (message.containsKey(key)) key: message[key],
};

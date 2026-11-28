import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/features/home/domain/entities/ui_request.dart';
import 'package:egeon_deck/features/home/domain/repository/socket_ui_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';
import '../support/protocol_fixtures.dart';
import '../support/pump.dart';

/// O pedido de tela e a resposta, conferidos contra o que o core grava.
void main() {
  final events = loadProtocolFixture('events');
  final commands = loadProtocolFixture('commands');

  test(
    'o ui_request do core vira pedido; o ui_reply sai como a fixture',
    () async {
      final transport = FakeTransport();
      final client = EgeonSocketClient(
        transport,
        retryDelay: const Duration(milliseconds: 10),
      )..start();
      addTearDown(client.dispose);
      await pump();
      final connection = transport.connections.last..upgrade();
      await client.whenConnected;

      final repository = SocketUiRequestRepository(client);
      final received = <UiRequest>[];
      var activated = 0;
      final subscription = repository.watch().listen(received.add);
      final activations = repository.activations().listen((_) => activated++);
      addTearDown(subscription.cancel);
      addTearDown(activations.cancel);
      await pump();

      connection.say({
        'topic': 'app',
        'effect': 'update_message',
        'text': 'outro efeito do app não é pedido',
      });
      connection.say(events['app_activate']!);
      connection.say(events['app_ui_request']!);
      await pump();

      expect(received, hasLength(1), reason: 'activate não é pedido de tela');
      expect(activated, 1, reason: 'activate é pedido de janela');
      expect(received.single.id, 7);
      expect(received.single.route, 'layout');
      expect(received.single.params, {'mode': 'chat'});

      final expected = withoutId(commands['ui_reply']!);
      final reply = repository.reply(
        received.single.id,
        UiReply(expected['value']),
      );
      await pump();
      final sent = connection.sent.where((m) => m['cmd'] == 'ui_reply').single;
      expect(withoutId(sent), expected);
      connection.say({'re': sent['id'], 'ok': true});
      await reply;
    },
  );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_effect.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_pointer.dart';
import 'package:egeon_deck/features/node/terminal/domain/repository/socket_terminal_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fake_transport.dart';
import '../../../../support/protocol_fixtures.dart';
import '../../../../support/pump.dart';

/// Os comandos de tela do /ui contra as fixtures que o core grava: pointer,
/// scroll, select_all, copy, clipboard_reply, link_hover, drop e os efeitos.
void main() {
  late FakeTransport transport;
  late EgeonSocketClient client;
  late FakeConnection connection;
  late SocketTerminalRepository repository;
  final commands = loadProtocolFixture('commands');
  final events = loadProtocolFixture('events');
  const node = '1a2b3c4d.claude';

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

  Future<T> run<T>(
    Future<T> Function() act, {
    Map<String, Object?> reply = const {},
  }) async {
    final before = connection.sent.length;
    final future = act();
    await pump();
    final sent = connection.sent[before];
    connection.say({'re': sent['id'], 'ok': true, ...reply});
    return future;
  }

  Map<String, Object?> lastSent() => withoutId(connection.sent.last);

  group('gestos', () {
    test('pointer: press e release com ⌘ batem com a fixture', () async {
      await run(
        () => repository.sendPointer(
          node,
          const TerminalPointer(
            kind: PointerKind.press,
            button: PointerButton.left,
            x: 3.5,
            y: 2,
            timeMs: 1000,
          ),
        ),
      );
      expect(lastSent(), withoutId(commands['pointer_press']!));

      await run(
        () => repository.sendPointer(
          node,
          const TerminalPointer(
            kind: PointerKind.release,
            button: PointerButton.left,
            x: 12.25,
            y: 4,
            timeMs: 1080,
            meta: true,
          ),
        ),
      );
      expect(lastSent(), withoutId(commands['pointer_release_meta']!));
    });

    test('scroll: linhas e o fim usam o campo `to`', () async {
      await run(() => repository.scroll(node, const ScrollRows(-3)));
      expect(lastSent(), withoutId(commands['scroll_linhas']!));
      await run(() => repository.scroll(node, const ScrollBottom()));
      expect(lastSent(), withoutId(commands['scroll_fim']!));
    });

    test('select_all, copy e clipboard_reply', () async {
      await run(() => repository.selectAll(node));
      expect(lastSent(), withoutId(commands['select_all']!));

      final text = await run(
        () => repository.copy(node),
        reply: {'text': 'hello'},
      );
      expect(lastSent(), withoutId(commands['copy']!));
      expect(text, 'hello');

      await run(() => repository.sendClipboard(node, 'o que estava copiado'));
      expect(lastSent(), withoutId(commands['clipboard_reply']!));
    });

    test('copy sem seleção: sem texto', () async {
      expect(await run(() => repository.copy(node)), isNull);
    });

    test('link_hover pergunta pela célula e devolve se há link', () async {
      final hit = await run(
        () => repository.linkHover(node, 12.25, 4),
        reply: {'link': true},
      );
      expect(lastSent(), withoutId(commands['link_hover']!));
      expect(hit, isTrue);
      expect(
        await run(
          () => repository.linkHover(node, 0, 0),
          reply: {'link': false},
        ),
        isFalse,
      );
    });

    test('drop: caminhos, ou a imagem em PNG base64', () async {
      await run(
        () => repository.dropFiles(node, [
          '/tmp/um arquivo.pdf',
          '/tmp/outro.swift',
        ]),
      );
      expect(lastSent(), withoutId(commands['drop_caminhos']!));

      final fixture = commands['drop_imagem']!['png']! as String;
      await run(
        () => repository.dropImage(
          node,
          Uint8List.fromList(base64Decode(fixture)),
        ),
      );
      expect(lastSent(), withoutId(commands['drop_imagem']!));
    });
  });

  group('o tópico screen/<id> traz quadros e efeitos', () {
    test('os efeitos saem do fluxo de quadros, e vice-versa', () async {
      final frames = <Object>[];
      final effects = <TerminalEffect>[];
      final f = repository.watch(node).listen(frames.add);
      final e = repository.effects(node).listen(effects.add);
      await pump();

      // A fixture do quadro vem de outro terminal (t1): só o tópico muda.
      connection.say({...events['screen_full']!, 'topic': 'screen/$node'});
      connection.say(events['screen_bell']!);
      connection.say(events['screen_clipboard']!);
      connection.say(events['screen_clipboard_request']!);
      await pump();

      expect(frames, hasLength(1), reason: 'efeito não vira quadro');
      expect(effects[0], isA<Bell>());
      expect((effects[1] as ClipboardWrite).text, 'copiado pelo programa');
      expect(effects[2], isA<ClipboardRequest>());
      expect(effects, hasLength(3));
      await f.cancel();
      await e.cancel();
    });
  });
}

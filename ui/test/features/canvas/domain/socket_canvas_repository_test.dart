import 'dart:ui';

import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_tool.dart';
import 'package:egeon_deck/features/canvas/domain/entities/edge_link.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';
import 'package:egeon_deck/features/canvas/domain/repository/socket_canvas_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_transport.dart';
import '../../../support/protocol_fixtures.dart';
import '../../../support/pump.dart';

/// O canvas contra as fixtures que o core Rust grava (decisão 24): a UI lê o
/// que ele manda e escreve exatamente o que ele espera.
void main() {
  late FakeTransport transport;
  late EgeonSocketClient client;
  late FakeConnection connection;
  late SocketCanvasRepository repository;
  final commands = loadProtocolFixture('commands');
  final events = loadProtocolFixture('events');
  final replies = loadProtocolFixture('replies');
  const wb = '1a2b3c4d';

  setUp(() async {
    transport = FakeTransport();
    client = EgeonSocketClient(
      transport,
      retryDelay: const Duration(milliseconds: 10),
    )..start();
    await pump();
    connection = transport.connections.last..upgrade();
    await client.whenConnected;
    repository = SocketCanvasRepository(client);
  });

  tearDown(() => client.dispose());

  Future<Map<String, Object?>> sentAfter(Future<void> Function() act) async {
    final before = connection.sent.length;
    final future = act();
    await pump();
    final sent = connection.sent[before];
    connection.say({'re': sent['id'], 'ok': true});
    await future;
    return withoutId(sent);
  }

  Future<CanvasSnapshot> firstSnapshot() async {
    final first = repository.watch(wb).first;
    await pump();
    expect(
      withoutId(connection.sent.single),
      withoutId(commands['subscribe_nodes']!),
    );
    connection.say(events['nodes']!);
    return first;
  }

  group('o subtítulo do card da fila', () {
    test('a fila mostra o resumo que o core manda, e não a pasta', () {
      final queue = CanvasCard.fromNode({
        'id': 'fila',
        'type': 'queue',
        'dir': '~/Documents/agro/deck',
        'subtitle': '2 pendentes',
      });
      expect(queue.subtitle, '2 pendentes');
      final shell = CanvasCard.fromNode({
        'id': 'sh',
        'type': 'shell',
        'dir': '~/Documents/agro/deck',
        'subtitle': 'ignorado',
      });
      expect(shell.subtitle, '~/Documents/agro/deck');
      expect(
        CanvasCard.fromNode({'id': 'f2', 'type': 'queue'}).subtitle,
        isEmpty,
        reason: 'sem o campo (core antigo), fica vazio',
      );
    });
  });

  group('o estado da bancada (workbench/<id>/nodes)', () {
    test('os nós chegam com tipo, frame, tela e subtítulo', () async {
      final snapshot = await firstSnapshot();
      expect(snapshot.cards.map((c) => c.id), ['claude', 'sh', 'docs']);

      final claude = snapshot.cards[0];
      expect(claude.kind, NodeKind.agent);
      expect(claude.title, 'claude', reason: 'o título é o id, como no Swift');
      expect(claude.subtitle, '~/Documents/agro/deck');
      expect(claude.screen, '1a2b3c4d.claude');
      expect(claude.maestro, isTrue);
      expect(
        claude.titleTooltip,
        'deck/claude · Claude Code',
        reason: 'a dica do título: endereço e o CLI do agente',
      );
      expect(
        snapshot.cards[1].titleTooltip,
        'deck/sh',
        reason: 'shell: só o endereço',
      );
      expect(claude.frame, const Rect.fromLTWH(120, 80.5, 640, 420));

      final web = snapshot.cards[2];
      expect(web.kind, NodeKind.web);
      expect(
        web.subtitle,
        'https://docs.rs',
        reason: 'no web o subtítulo é a página',
      );
      expect(web.alive, isFalse);
    });

    test(
      'a atividade vem pronta: a borda acende por needs_attention',
      () async {
        final snapshot = await firstSnapshot();
        expect(snapshot.cards[0].activity.needsAttention, isTrue);
        expect(snapshot.cards[0].activity.state, 'asking');
        expect(snapshot.cards[1].activity.needsAttention, isFalse);
        expect(snapshot.cards[1].activity.state, 'working');
        expect(
          snapshot.cards[2].activity.needsAttention,
          isFalse,
          reason: 'o web não tem atividade',
        );
      },
    );

    test(
      'nó sem frame aparece num lugar de reserva e nada é gravado',
      () async {
        final snapshot = await firstSnapshot();
        expect(snapshot.cards[1].kind, NodeKind.shell);
        expect(snapshot.cards[1].frame, CanvasCard.fallbackFrame);
        await pump();
        expect(connection.sent.where((m) => m['cmd'] == 'move_node'), isEmpty);
      },
    );

    test('a lista de quem liga a quem vem do core (`linkable`)', () async {
      final cards = (await firstSnapshot()).cards;
      expect(cards[0].linkable, ['sh']);
      expect(cards[1].linkable, ['claude']);
      expect(cards[2].linkable, isEmpty, reason: 'o web não é alvo');
    });

    test('a porta vem do core (`port`), não da lista de destinos', () async {
      final cards = (await firstSnapshot()).cards;
      expect(cards.map((c) => c.port), [true, true, false]);
    });

    test('as ligações já chegam colapsadas', () async {
      final snapshot = await firstSnapshot();
      expect(snapshot.links, hasLength(2));
      final one = snapshot.links[0];
      expect((one.a, one.b, one.aToB, one.bToA), ('claude', 'sh', true, false));
      expect(one.maxSends, isNull);
      final both = snapshot.links[1];
      expect(both.isBidirectional, isTrue);
      expect(both.maxSends, 2);
    });
  });

  group('os gestos viram os comandos do core', () {
    test('mover grava só o que mudou, com o frame da fixture', () async {
      await firstSnapshot();
      final frame = (commands['move_node']!['frame']! as Map)
          .cast<String, double>();
      final rect = Rect.fromLTWH(
        frame['x']!,
        frame['y']!,
        frame['w']!,
        frame['h']!,
      );
      // O claude já está lá; o mesmo frame não vai de novo.
      final before = connection.sent.length;
      await repository.saveFrames(wb, {
        'claude': const Rect.fromLTWH(120, 80.5, 640, 420),
      });
      expect(connection.sent.length, before);

      final sent = await sentAfter(
        () => repository.saveFrames(wb, {
          'claude': rect.shift(const Offset(10, 0)),
        }),
      );
      expect(sent['cmd'], 'move_node');
      expect(sent['workbench'], wb);
      expect(sent['node'], 'claude');
      expect((sent['frame']! as Map)['x'], 130.0);
    });

    test('criar nó pela ferramenta manda tipo e retângulo', () async {
      final fixture = commands['create_node_web']!;
      final sent = await sentAfter(
        () => repository.placeNode(
          wb,
          CanvasTool.web,
          const Rect.fromLTWH(120, 80.5, 640, 420),
        ),
      );
      expect(sent['cmd'], fixture['cmd']);
      expect(sent['type'], fixture['type']);
      expect(sent['frame'], fixture['frame']);
      expect(sent['workbench'], fixture['workbench']);
    });

    test('criar com componente leva o nome dele', () async {
      final sent = await sentAfter(
        () => repository.placeNode(
          wb,
          CanvasTool.shell,
          const Rect.fromLTWH(0, 0, 720, 460),
          component: 'revisor',
        ),
      );
      expect(sent['type'], 'shell');
      expect(sent['component'], commands['create_node']!['component']);
    });

    test('a resposta do core à criação é só ok com o id do nó', () {
      expect(replies['no_criado']!['node'], 'revisor');
    });

    test(
      'ligar pelo +: o par nasce nos dois sentidos (`both: true`)',
      () async {
        final sent = await sentAfter(
          () => repository.createLink(wb, 'claude', 'rev'),
        );
        final fixture = {...withoutId(commands['link_ida_e_volta']!)}
          ..remove('max_sends');
        expect(sent, fixture, reason: 'o limite de envios é gesto do botão');
      },
    );

    test('remover a ligação: `unlink` nos dois sentidos', () async {
      final sent = await sentAfter(
        () => repository.removeLink(wb, const EdgeLink(a: 'claude', b: 'rev')),
      );
      expect(sent, withoutId(commands['unlink']!));
    });

    test('o botão de direção manda `set_edge` cycle', () async {
      final sent = await sentAfter(
        () => repository.cycleLink(wb, const EdgeLink(a: 'claude', b: 'rev')),
      );
      expect(sent, withoutId(commands['set_edge_ciclo']!));
    });

    test(
      'limite vazio vai com a chave e valor nulo; com número, o número',
      () async {
        final none = await sentAfter(
          () => repository.setLinkLimit(
            wb,
            const EdgeLink(a: 'claude', b: 'rev'),
            null,
          ),
        );
        expect(none.containsKey('max_sends'), isTrue);
        expect(none['max_sends'], isNull);
        expect(none['cmd'], 'set_edge');
        expect(none['from'], 'claude');

        final three = await sentAfter(
          () => repository.setLinkLimit(
            wb,
            const EdgeLink(a: 'claude', b: 'rev'),
            3,
          ),
        );
        expect(three['max_sends'], 3);
      },
    );

    test(
      'o foco da interface: app ativo com nó, e em segundo plano sem nó',
      () async {
        final focused = await sentAfter(
          () => repository.setFocus(
            appActive: true,
            workbenchId: wb,
            nodeId: 'claude',
            window: const Size(1440, 900),
          ),
        );
        expect(focused, withoutId(commands['ui_focus']!));
        final background = await sentAfter(
          () => repository.setFocus(appActive: false),
        );
        expect(background, withoutId(commands['ui_focus_fundo']!));
      },
    );

    test('remover o nó', () async {
      final sent = await sentAfter(() => repository.removeNode(wb, 'sh'));
      expect(sent, withoutId(commands['remove_node']!));
      expect(
        await sentAfter(() => repository.openFolder(wb, 'claude')),
        withoutId(commands['open_node_folder']!),
      );
    });
  });
}

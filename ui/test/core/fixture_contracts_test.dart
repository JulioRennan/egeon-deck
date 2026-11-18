import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/core/adapters/organization_feed.dart';
import 'package:egeon_deck/features/workspace/domain/errors/workspace_error.dart';
import 'package:egeon_deck/core/domain/entities/organization.dart';
import 'package:egeon_deck/features/home/domain/entities/shell_snapshot.dart';
import 'package:egeon_deck/features/home/domain/repository/socket_shell_repository.dart';
import 'package:egeon_deck/features/canvas/domain/entities/edge_link.dart';
import 'package:egeon_deck/features/canvas/domain/repository/socket_canvas_repository.dart';
import 'package:egeon_deck/features/chat/domain/repository/socket_chat_repository.dart';
import 'package:egeon_deck/features/node/terminal/domain/repository/socket_terminal_repository.dart';
import 'package:egeon_deck/features/sidebar/domain/repository/socket_sidebar_repository.dart';
import 'package:egeon_deck/features/workspace/domain/repository/socket_workspace_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';
import '../support/protocol_fixtures.dart';
import '../support/pump.dart';

/// Ficam sem leitura de propósito as fixtures de comandos que a UI não manda:
/// `create_workspace`, `add_project` e `multi_project` (a UI usa
/// `save_workspace`, `multi_name` e `create_project`), `close_terminal` e
/// `subscribe_terminals` (o canvas fecha o nó por `remove_node` e o terminal é
/// assinado por `screen/<id>`), e `link_ida_e_volta` (a UI cria a ligação de um
/// sentido só e a ida e volta nasce do ciclo da direção).
///
/// As fixtures do core que ainda não tinham leitura: cada comando que a UI
/// manda é igual ao gravado, e cada resposta (inclusive a de erro) é lida como
/// o core a escreve.
void main() {
  final commands = loadProtocolFixture('commands');
  final replies = loadProtocolFixture('replies');
  late FakeConnection connection;
  late EgeonSocketClient client;

  setUp(() async {
    final transport = FakeTransport();
    client = EgeonSocketClient(
      transport,
      retryDelay: const Duration(milliseconds: 10),
    )..start();
    await pump();
    connection = transport.connections.last..upgrade();
    await client.whenConnected;
  });

  tearDown(() => client.dispose());

  Map<String, Object?> command(String name) => withoutId(commands[name]!);

  /// O que a UI mandou, sem o id; responde com a fixture [reply] (o `re` é o
  /// do pedido, não o da fixture).
  Future<Map<String, Object?>> exchange(String reply) async {
    await pump();
    final sent = connection.sent.last;
    connection.say({...replies[reply]!, 're': sent['id']});
    await pump();
    return withoutId(sent);
  }

  test('plan_move: o comando e o pouso que o core responde', () async {
    final sidebar = SocketSidebarRepository(OrganizationFeed(client));
    final landing = sidebar.planMove(
      'project',
      'p2',
      parent: '9f8e7d6c',
      to: 1,
    );
    expect(await exchange('plan_move'), command('plan_move'));
    final lands = await landing;
    expect(lands?.parent, '9f8e7d6c');
    expect(lands?.to, 1);
  });

  test('plan_move recusado pelo core não é pouso', () async {
    final sidebar = SocketSidebarRepository(OrganizationFeed(client));
    final landing = sidebar.planMove(
      'project',
      'p2',
      parent: '9f8e7d6c',
      to: 1,
    );
    await exchange('erro_bancada');
    expect(await landing, isNull);
  });

  test('chat_complete: o comando e o menu que o core responde', () async {
    final chat = SocketChatRepository(client);
    final completion = chat.complete('1a2b3c4d', 'pede ao @re', 11);
    expect(await exchange('chat_complete'), command('chat_complete'));
    final read = await completion;
    expect(read.items.single.insert, '@rev ');
    expect((read.start, read.end), (8, 11));
  });

  test('list_terminals e create_terminal sem pasta', () async {
    final terminals = SocketTerminalRepository(client);
    final listed = terminals.list();
    expect(await exchange('lista'), command('list_terminals'));
    final all = await listed;
    expect(all, hasLength(2));
    expect(all.first.alive, isTrue);
    expect(all.last.alive, isFalse);

    final created = terminals.create();
    expect(
      await exchange('terminal_criado'),
      command('create_terminal_minimo'),
    );
    expect((await created).id, isNotEmpty);
  });

  test(
    'ligação de ida e volta e limite apagado: o que o canvas manda',
    () async {
      final canvas = SocketCanvasRepository(client);
      const link = EdgeLink(a: 'claude', b: 'rev');

      final cleared = canvas.setLinkLimit('1a2b3c4d', link, null);
      // O `direction` da fixture é opcional no core (`SetEdge`): quem só tira o
      // limite não o repete.
      expect(
        await exchange('ok'),
        command('set_edge_sem_limite')..remove('direction'),
      );
      await cleared;

      // A ligação nova nasce de um sentido só; a de ida e volta é a que o core
      // grava com `both`, e a UI a remove inteira.
      final removed = canvas.removeLink('1a2b3c4d', link);
      final sent = await exchange('ok');
      expect(sent['cmd'], 'unlink');
      expect(sent['both'], isTrue);
      await removed;
    },
  );

  test('erro do core chega ao repositório com o texto dele', () async {
    final feed = OrganizationFeed(client);
    final failing = feed.command('close_terminal', {'node': 't9'});
    final expectation = expectLater(
      failing,
      throwsA(
        isA<EgeonCommandError>().having(
          (e) => e.message,
          'message',
          "terminal desconhecido 't9'",
        ),
      ),
    );
    await exchange('erro');
    await expectation;
  });

  test(
    'workspace com bancadas: a recusa chega com o motivo e o nome',
    () async {
      final workspace = SocketWorkspaceRepository(OrganizationFeed(client));
      final removal = workspace.removeWorkspace('9f8e7d6c');
      final expectation = expectLater(
        removal,
        throwsA(
          isA<WorkspaceRefused>().having(
            (e) => e.message,
            'message',
            allOf(contains('"Agro"'), contains('2 bancada(s)')),
          ),
        ),
      );
      await exchange('erro_workspace_com_bancadas');
      await expectation;
    },
  );

  test('o erro cru do cliente guarda o comando e a resposta inteira', () async {
    final failing = client.request('close_terminal', {'node': 't9'});
    final expectation = expectLater(
      failing,
      throwsA(
        isA<EgeonCommandError>()
            .having((e) => e.cmd, 'cmd', 'close_terminal')
            .having((e) => e.reply['ok'], 'ok', false),
      ),
    );
    await exchange('erro');
    await expectation;
  });

  test(
    'sem acesso: o aviso vem do estado e os botões mandam as fixtures',
    () async {
      final events = loadProtocolFixture('events');
      final org = Organization.fromMap({
        ...events['workspaces']!,
        'workbenches': [
          for (final b
              in events['workspaces']!['workbenches']! as List<Object?>)
            {
              ...(b! as Map<String, Object?>),
              'tab_active': (b as Map<String, Object?>)['id'] == '0c0c0c0c',
            },
        ],
      });
      final locked = org.bench('0c0c0c0c')!;
      expect(locked.access?.folder, 'Documentos');
      expect(
        ShellSnapshot.fromOrganization(org).lock?.text,
        locked.access!.message,
        reason: 'o texto da cortina é o do core',
      );
      expect(
        org.bench('1a2b3c4d')!.access,
        isNull,
        reason: 'sem o campo, sem cortina',
      );

      // Os comandos valem para a bancada na tela (a da aba ativa).
      final feed = OrganizationFeed(client);
      final shell = SocketShellRepository(feed);
      final watching = shell.watch().listen((_) {});
      addTearDown(watching.cancel);
      await pump();
      connection.say({
        ...events['workspaces']!,
        'workbenches': [
          for (final b
              in events['workspaces']!['workbenches']! as List<Object?>)
            {
              ...(b! as Map<String, Object?>),
              'tab_active': (b as Map<String, Object?>)['id'] == '1a2b3c4d',
            },
        ],
      });
      await pump();

      final settings = shell.openSettings();
      expect(await exchange('ok'), command('access_open_settings'));
      await settings;

      final again = shell.askAccessAgain();
      expect(await exchange('access_ask_again'), command('access_ask_again'));
      await again;
    },
  );

  test('chat_new_queue manda o agente em foco e lê o nó criado', () async {
    final chat = SocketChatRepository(client);
    final created = chat.newQueue('1a2b3c4d', agent: 'claude');
    expect(await exchange('chat_new_queue'), command('chat_new_queue'));
    expect(await created, 'fila1');

    final loose = chat.newQueue('1a2b3c4d');
    await pump();
    final sent = withoutId(connection.sent.last);
    expect(
      sent.containsKey('agent'),
      isFalse,
      reason: 'sem agente, fila solta',
    );
    connection.say({
      ...replies['chat_new_queue']!,
      're': connection.sent.last['id'],
    });
    await loose;
  });
}

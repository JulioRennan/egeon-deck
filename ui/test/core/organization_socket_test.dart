import 'dart:async';

import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/core/adapters/organization_feed.dart';
import 'package:egeon_deck/features/workbench/domain/errors/workbench_error.dart';
import 'package:egeon_deck/features/workspace/domain/errors/workspace_error.dart';
import 'package:egeon_deck/core/domain/entities/view_mode.dart';
import 'package:egeon_deck/features/home/domain/repository/socket_shell_repository.dart';
import 'package:egeon_deck/features/sidebar/domain/repository/socket_sidebar_repository.dart';
import 'package:egeon_deck/features/tabs/domain/repository/socket_tabs_repository.dart';
import 'package:egeon_deck/features/workbench/domain/repository/socket_workbench_repository.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_info.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_plan.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_source.dart';
import 'package:egeon_deck/features/workspace/domain/entities/workspace_draft.dart';
import 'package:egeon_deck/features/workspace/domain/repository/socket_workspace_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_transport.dart';
import '../support/protocol_fixtures.dart';
import '../support/pump.dart';

/// Os ids da fixture do core.
const ws = '9f8e7d6c';
const deck = '1a2b3c4d';

void main() {
  final events = loadProtocolFixture('events');
  final commands = loadProtocolFixture('commands');
  final replies = loadProtocolFixture('replies');
  late FakeConnection connection;
  var answered = 0;
  late EgeonSocketClient client;
  late OrganizationFeed feed;

  Map<String, Object?> organization() => {...events['workspaces']!};

  setUp(() async {
    final transport = FakeTransport();
    client = EgeonSocketClient(
      transport,
      retryDelay: const Duration(milliseconds: 10),
    )..start();
    await pump();
    connection = transport.connections.last..upgrade();
    await client.whenConnected;
    answered = 0;
    feed = OrganizationFeed(client);
  });

  tearDown(() => client.dispose());

  /// Entrega a organização a quem estiver ouvindo, como o core faz ao assinar.
  Future<void> publish([Map<String, Object?>? state]) async {
    await pump();
    connection.say(state ?? organization());
    await pump();
  }

  /// Responde ok a cada comando que a UI mandar até [action] terminar; devolve
  /// os comandos, sem o id e sem a assinatura.
  Future<List<Map<String, Object?>>> serve(
    Future<void> action, {
    Map<String, List<Map<String, Object?>>> answers = const {},
  }) async {
    var finished = false;
    Object? failure;
    unawaited(
      action.then(
        (_) => finished = true,
        onError: (Object e) {
          failure = e;
          finished = true;
        },
      ),
    );
    final out = <Map<String, Object?>>[];
    final given = <Object?, int>{};
    while (!finished) {
      await pump();
      while (answered < connection.sent.length) {
        final message = connection.sent[answered++];
        if (message['cmd'] != 'subscribe') out.add(withoutId(message));
        final queue = answers[message['cmd']] ?? const [];
        final turn = given[message['cmd']] = (given[message['cmd']] ?? 0) + 1;
        connection.say({
          'ok': true,
          if (queue.isNotEmpty) ...queue[(turn - 1).clamp(0, queue.length - 1)],
          // O id é o do pedido, não o da fixture.
          're': message['id'],
        });
      }
    }
    if (failure != null) throw failure!;
    return out;
  }

  /// A UI manda só o que mudou; o resto da mensagem é da fixture. Confere que
  /// cada chave mandada existe nela com o mesmo valor.
  void expectSubsetOf(Map<String, Object?> sent, String fixture) {
    final expected = commands[fixture]!;
    for (final entry in sent.entries) {
      expect(
        expected.containsKey(entry.key),
        isTrue,
        reason: '$fixture não tem a chave ${entry.key}',
      );
      expect(entry.value, expected[entry.key], reason: '$fixture.${entry.key}');
    }
  }

  void expectLike(Map<String, Object?> sent, String fixture) =>
      expect(sent, withoutId(commands[fixture]!));

  test('os três assinantes dividem uma assinatura só, e o atrasado recebe o último', () async {
    final sidebar = SocketSidebarRepository(feed);
    final tabs = SocketTabsRepository(feed);
    final shell = SocketShellRepository(feed);

    final first = sidebar.watch().listen((_) {});
    await publish();

    expect(await tabs.watch().first, isNotEmpty);
    expect((await shell.watch().first).bench!.id, deck);
    final subscribes = connection.sent.where((m) => m['cmd'] == 'subscribe');
    expect(subscribes.length, 1);
    expectLike(withoutId(subscribes.single), 'subscribe_workspaces');
    await first.cancel();
  });

  test('a barra lateral nasce da fixture do core', () async {
    final tree = SocketSidebarRepository(feed).watch().first;
    await publish();
    final t = await tree;

    final agro = t.workspaces.single;
    expect(agro.name, 'Agro');
    expect(agro.storedOpen, isTrue);
    expect(agro.activeProjects.map((p) => p.name), ['nexus-backend']);
    expect(agro.storedProjects.map((p) => p.name), ['nexus']);

    final backend = agro.projects.first;
    expect(backend.pathExists, isTrue);
    expect(backend.benches.map((b) => b.name), ['deck', 'deck-2']);
    expect(backend.benches.first.selected, isTrue);
    expect(backend.benches.first.live, isTrue);
    expect(backend.benches.first.color, 'teal');

    final multi = agro.projects.last;
    expect(multi.collapsed, isTrue);
    expect(multi.pathExists, isFalse, reason: 'a fixture manda exists:false');
    expect(multi.joins, [
      'nexus-backend',
    ], reason: 'p2 não está na fixture: só os membros que existem');

    final lost = t.orphans.single;
    expect(lost.name, 'solta');
    expect(lost.pathExists, isFalse);
    expect(lost.removing, isTrue, reason: 'o core manda removing:true');
    expect(lost.live, isFalse, reason: 'o core manda live:false');

    expect(t.recent.map((b) => b.name), ['deck']);
    expect(t.stale.map((b) => b.name), ['solta']);
    expect(t.recent.single.owner!.name, 'Agro');
    expect(t.recent.single.project, 'nexus-backend');
    expect(t.stale.single.owner, isNull, reason: 'órfã não tem de onde vir');
  });

  test(
    'as abas são as bancadas com posição, na ordem, e a ativa marcada',
    () async {
      final list = SocketTabsRepository(feed).watch().first;
      await publish();
      final t = await list;
      expect(t.map((x) => x.name), ['deck', 'deck-2']);
      expect(t.map((x) => x.isActive), [true, false]);
      expect(t.first.color, 'teal');
    },
  );

  test('a casca mostra a bancada da aba ativa, no modo dela', () async {
    final state = SocketShellRepository(feed).watch().first;
    await publish();
    final s = await state;
    expect(s.bench!.id, deck);
    expect(s.bench!.view, ViewMode.canvas);
  });

  test('os gestos da barra mandam o que a fixture do core grava', () async {
    final sidebar = SocketSidebarRepository(feed);
    final sub = sidebar.watch().listen((_) {});
    await publish();

    expectLike((await serve(sidebar.select(deck))).single, 'open_workbench');
    expectLike((await serve(sidebar.toggleDrawer(ws))).single, 'move_drawer');
    expectLike(
      (await serve(sidebar.setStored(ws, 'p2', stored: true))).single,
      'move_store',
    );
    expectLike(
      (await serve(sidebar.moveBench(deck, 'p1', 2))).single,
      'move_workbench',
    );
    // O projeto p1 está aberto na fixture: recolher manda collapsed:true.
    expect((await serve(sidebar.toggleProject(ws, 'p1'))).single, {
      'cmd': 'set_project',
      'project': 'p1',
      'collapsed': true,
    });
    expect((await serve(sidebar.toggleWorkspace(ws))).single, {
      'cmd': 'set_workspace',
      'workspace': ws,
      'collapsed': true,
    });
    await sub.cancel();
  });

  test(
    'soltar um projeto na gaveta guarda já na posição: um comando só',
    () async {
      final sidebar = SocketSidebarRepository(feed);
      final sub = sidebar.watch().listen((_) {});
      await publish();
      expectLike(
        (await serve(sidebar.moveProject('p2', ws, 1, stored: true))).single,
        'move_store',
      );
      await sub.cancel();
    },
  );

  test(
    'tirar da gaveta e soltar fora dela são unstore e project, com a posição',
    () async {
      final sidebar = SocketSidebarRepository(feed);
      final sub = sidebar.watch().listen((_) {});
      await publish();
      // p9 está guardado na fixture; p1 não.
      expect(
        (await serve(sidebar.moveProject('p9', ws, 1, stored: false))).single,
        {'cmd': 'move', 'kind': 'unstore', 'item': 'p9', 'parent': ws, 'to': 1},
      );
      expect(
        (await serve(sidebar.moveProject('p1', ws, 0, stored: false))).single,
        {'cmd': 'move', 'kind': 'project', 'item': 'p1', 'parent': ws, 'to': 0},
      );
      await sub.cancel();
    },
  );

  test('abas: escolher, fechar e reordenar mandam um movimento só', () async {
    final tabs = SocketTabsRepository(feed);
    final sub = tabs.watch().listen((_) {});
    // Na fixture o deck é a aba 0; invertida, o arrasto o devolve ao começo.
    final swapped = organization();
    final benches = [
      for (final b in swapped['workbenches']! as List<Object?>)
        {...b! as Map<String, Object?>},
    ];
    benches[0]['tab_order'] = 1;
    benches[1]['tab_order'] = 0;
    swapped['workbenches'] = benches;
    await publish(swapped);

    expectLike((await serve(tabs.pick(deck))).single, 'activate_workbench');
    expectLike((await serve(tabs.close(deck))).single, 'close_workbench');
    expectLike(
      (await serve(tabs.reorder([deck, '5e6f7a8b']))).single,
      'move_tab',
    );
    await sub.cancel();
  });

  test('trocar o modo vale para a bancada da aba ativa', () async {
    final shell = SocketShellRepository(feed);
    final sub = shell.watch().listen((_) {});
    await publish();
    expectSubsetOf(
      (await serve(shell.setView(ViewMode.chat))).single..remove('cmd'),
      'set_workbench',
    );
    await sub.cancel();
  });

  test('os gestos da bancada mandam o que a fixture grava', () async {
    final bench = SocketWorkbenchRepository(feed);
    final sub = SocketSidebarRepository(feed).watch().listen((_) {});
    await publish();

    expectSubsetOf(
      (await serve(bench.rename(deck, 'deck'))).single..remove('cmd'),
      'set_workbench',
    );
    expectSubsetOf(
      (await serve(bench.recolor(deck, 'teal'))).single..remove('cmd'),
      'set_workbench',
    );
    expectLike((await serve(bench.clear(deck))).single, 'clear_workbench');
    expectLike((await serve(bench.resetClock(deck))).single, 'reset_clock');
    expectLike(
      (await serve(bench.remove(deck, deleteWorktrees: true))).single,
      'remove_workbench',
    );
    expectLike(
      (await serve(bench.setRules(deck, 'não commite sem me perguntar')))
          .single,
      'set_workbench_rules',
    );
    expectLike(
      (await serve(bench.setRules(deck, ''))).single,
      'set_workbench_rules_apaga',
    );
    expectLike(
      (await serve(bench.setRules(deck, '  \n '))).single,
      'set_workbench_rules_apaga',
    );
    await sub.cancel();
  });

  test('agentes e regras saem da bancada que já está no estado', () async {
    final bench = SocketWorkbenchRepository(feed);
    final sub = SocketSidebarRepository(feed).watch().listen((_) {});
    final state = organization();
    final benches = [
      for (final b in state['workbenches']! as List<Object?>)
        {...b! as Map<String, Object?>},
    ];
    benches[0]['agents'] = 3;
    benches[0]['rules'] = 'português';
    state['workbenches'] = benches;
    await publish(state);

    expect(await bench.agentCount(deck), 3);
    expect(await bench.rules(deck), 'português');
    expect(await bench.rules('5e6f7a8b'), '', reason: 'sem regras é vazio');
    await expectLater(bench.agentCount('x'), throwsA(isA<WorkbenchRefused>()));
    expect(connection.sent.where((m) => m['cmd'] != 'subscribe'), isEmpty);
    await sub.cancel();
  });

  test('o plano de remoção é a resposta do core', () async {
    final bench = SocketWorkbenchRepository(feed);
    final plan = bench.planRemoval(deck);
    await pump();
    final sent = connection.sent.last;
    expect(sent['cmd'], 'plan_remove_workbench');
    expect(sent['workbench'], deck);
    connection.say({...replies['plan_remove_workbench']!, 're': sent['id']});
    final p = await plan;
    expect(p.live, isTrue);
    expect(p.worktrees.map((w) => w.repo), ['nexus-backend', 'nexus-front']);
    expect(p.worktrees.last.usedBy, 'front-fix');
    expect(p.deletable.single.branch, 'feat/login');
    expect(p.deletable.single.owners, ['bancada']);
  });

  test('o que se perde vem depois, pelo core', () async {
    final bench = SocketWorkbenchRepository(feed);
    final losses = bench.removalLosses(deck);
    await pump();
    final sent = connection.sent.last;
    expect(withoutId(sent), withoutId(commands['removal_losses']!));
    connection.say({...replies['removal_losses']!, 're': sent['id']});
    final lines = await losses;
    expect(lines.first, 'nexus-backend · feat/login');
    expect(lines, contains(''), reason: 'uma seção por worktree');
  });

  test('remover que falha devolve o texto do core', () async {
    final bench = SocketWorkbenchRepository(feed);
    final removal = bench.remove(deck, deleteWorktrees: true);
    await pump();
    final sent = connection.sent.last;
    expect(withoutId(sent), withoutId(commands['remove_workbench']!));
    connection.say({...replies['erro_remover_bancada']!, 're': sent['id']});
    await expectLater(
      removal,
      throwsA(
        isA<WorkbenchRefused>().having(
          (e) => e.message,
          'message',
          contains('Não consegui apagar'),
        ),
      ),
    );
  });

  test(
    'workspace e projeto: remover e criar mandam o que a fixture grava',
    () async {
      final workspace = SocketWorkspaceRepository(feed);
      expectLike(
        (await serve(workspace.removeWorkspace(ws, dryRun: true))).single,
        'remove_workspace',
      );
      expectLike(
        (await serve(workspace.removeProject(ws, 'p2'))).single,
        'remove_project',
      );
      expectLike(
        (await serve(
          workspace.createProject(
            ws,
            name: 'nexus-api',
            parent: '~/Documents/agro',
            git: true,
          ),
        )).single,
        'create_project',
      );
    },
  );

  test('o formulário salva de uma vez, como a fixture do core', () async {
    final workspace = SocketWorkspaceRepository(feed);
    const folders = [
      '~/Documents/agro/nexus-backend',
      '~/Documents/agro/nexus-front',
    ];
    final sent = await serve(
      workspace.save(
        const WorkspaceDraft(
          name: 'Agro',
          iconSource: '/Users/eu/Desktop/agro.png',
          folders: folders,
          multis: [MultiDraft(name: 'nexus', folders: folders)],
        ),
        id: ws,
      ),
    );
    expectLike(sent.single, 'save_workspace');
  });

  test(
    'workspace novo não manda o id; tirar a imagem manda icon null',
    () async {
      final workspace = SocketWorkspaceRepository(feed);
      var sent = await serve(
        workspace.save(const WorkspaceDraft(name: 'Agro')),
      );
      expect(sent.single.containsKey('workspace'), isFalse);
      expect(sent.single.containsKey('icon'), isFalse);

      sent = await serve(
        workspace.save(
          const WorkspaceDraft(name: 'Agro', clearIcon: true),
          id: ws,
        ),
      );
      expect(sent.single['icon'], isNull);
      expect(sent.single.containsKey('icon'), isTrue);
    },
  );

  test('o rascunho de edição sai do que o tópico já tem', () async {
    final workspace = SocketWorkspaceRepository(feed);
    final sub = SocketSidebarRepository(feed).watch().listen((_) {});
    await publish();
    final draft = await workspace.draft(ws);
    expect(draft.name, 'Agro');
    expect(draft.icon, 'icon.png');
    expect(draft.folders, ['~/Documents/agro/nexus-backend']);
    expect(draft.multis.single.name, 'nexus');
    expect(draft.multis.single.id, 'p9');
    expect(draft.multis.single.folders, ['~/Documents/agro/nexus-backend']);
    await expectLater(workspace.draft('x'), throwsA(isA<WorkspaceRefused>()));
    await sub.cancel();
  });

  test('o nome padrão do multi-projeto é a resposta do core', () async {
    final workspace = SocketWorkspaceRepository(feed);
    final future = workspace.multiName(ws, [
      '~/Documents/agro/nexus-backend',
      '~/Documents/agro/nexus-front',
    ]);
    await pump();
    final sent = connection.sent.last;
    expectLike(withoutId(sent), 'multi_name');
    connection.say({...replies['multi_name']!, 're': sent['id']});
    expect(await future, 'nexus-backend + nexus-front');
  });

  test('o destino sugerido para o projeto novo é a resposta do core', () async {
    final workspace = SocketWorkspaceRepository(feed);
    final future = workspace.suggestedParent(ws);
    await pump();
    final sent = connection.sent.last;
    expectLike(withoutId(sent), 'suggest_parent');
    connection.say({...replies['suggest_parent']!, 're': sent['id']});
    expect(await future, '~/Documents/agro');
  });

  test('a recusa do core vira WorkbenchRefused com o texto dele', () async {
    final bench = SocketWorkbenchRepository(feed);
    final future = bench.rename(deck, 'deck');
    await pump();
    final reply = replies['erro_bancada']!;
    connection.say({...reply, 're': connection.sent.last['id']});
    await expectLater(
      future,
      throwsA(
        isA<WorkbenchRefused>().having(
          (e) => e.message,
          'message',
          reply['error'],
        ),
      ),
    );
  });

  test(
    'templates, bancada nova e worktree: comandos e respostas do core',
    () async {
      final bench = SocketWorkbenchRepository(feed);

      final templates = bench.templates();
      expectLike(
        (await serve(
          templates,
          answers: {
            'templates': [replies['templates']!],
          },
        )).single,
        'templates',
      );
      final listed = await templates;
      expect(listed.single.name, 'dupla');
      expect(listed.single.nodes, 2);
      expect(listed.single.view, 'chat');
      expect(listed.single.basePath, '~/Documents/agro');

      final created = bench.create(
        path: '~/Documents/agro/nexus-backend',
        project: 'p1',
        template: 'dupla',
      );
      expectLike(
        (await serve(
          created,
          answers: {
            'create_workbench': [replies['bancada_criada']!],
          },
        )).single,
        'create_workbench',
      );
      expect(await created, '5e6f7a8b');

      final info = bench.worktreeInfo(const WorktreeSource.bench(deck));
      expectLike(
        (await serve(
          info,
          answers: {
            'worktree_info': [replies['worktree_info']!],
          },
        )).single,
        'worktree_info',
      );
      final read = await info;
      expect(read.suggestedBranch, 'main-2');
      expect(read.summary, contains('nexus-backend'));
      expect(read.nodes.map((n) => n.state), [
        NodeWorktreeState.ownWorktree,
        NodeWorktreeState.followsWorkbench,
        NodeWorktreeState.noRepo,
      ]);
      expect(read.nodes.first.branch, 'fix/api');
      expect(read.nodes.last.editable, isFalse);

      final plan = bench.worktreePlan(
        const WorktreeSource.bench(deck),
        'feature/PROJ-1234',
      );
      expectLike(
        (await serve(
          plan,
          answers: {
            'worktree_plan': [replies['worktree_plan']!],
          },
        )).single,
        'worktree_plan',
      );
      final verdict = await plan;
      expect(verdict.verdict, WorktreeVerdict.followRemote);
      expect(verdict.isFresh, isFalse);
      expect(verdict.message, 'segue origin/feature/PROJ-1234');

      final made = bench.createWorktree(
        const WorktreeSource.bench(deck),
        'feature/PROJ-1234',
        destination: WorktreeDestination.moveCurrent,
        nodes: {'back': 'fix/api', 'sub': ''},
      );
      expectLike(
        (await serve(
          made,
          answers: {
            'worktree': [replies['worktree_criada']!],
          },
        )).single,
        'worktree',
      );
      expect((await made).workbench, '5e6f7a8b');
    },
  );

  test('worktree de um terminal só: a origem leva o nó', () async {
    final bench = SocketWorkbenchRepository(feed);
    const source = WorktreeSource.node(deck, 'back');
    final info = bench.worktreeInfo(source);
    expectLike(
      (await serve(
        info,
        answers: {
          'worktree_info': [replies['worktree_info']!],
        },
      )).single,
      'worktree_info_no',
    );
    await info;
    final plan = bench.worktreePlan(source, 'fix/api');
    expectLike(
      (await serve(
        plan,
        answers: {
          'worktree_plan': [replies['worktree_plan']!],
        },
      )).single,
      'worktree_plan_no',
    );
    await plan;
    final made = bench.createWorktree(source, 'fix/api');
    expectLike(
      (await serve(
        made,
        answers: {
          'worktree': [replies['worktree_criada']!],
        },
      )).single,
      'worktree_no',
    );
    await made;
  });

  test('worktree sem bancada de origem e multi-projeto', () async {
    final bench = SocketWorkbenchRepository(feed);

    final info = bench.worktreeInfo(
      const WorktreeSource.folder(path: '~/Documents/agro/nexus-backend'),
    );
    expectSubsetOf(
      (await serve(
        info,
        answers: {
          'worktree_info': [replies['worktree_info_multi']!],
        },
      )).single,
      'worktree_info_de_pasta',
    );
    final multi = (await info).multi!;
    expect(multi.project, 'Nexus');
    expect(multi.repos, ['nexus-backend', 'nexus-front']);

    final plan = bench.worktreePlan(
      const WorktreeSource.folder(project: 'p1'),
      'feature/PROJ-1234',
    );
    expectLike(
      (await serve(
        plan,
        answers: {
          'worktree_plan': [replies['worktree_plan']!],
        },
      )).single,
      'worktree_plan_de_pasta',
    );

    final made = bench.createWorktree(
      const WorktreeSource.folder(project: 'm1'),
      'feat/login',
      repos: {'nexus-front': 'fix/front'},
      template: 'dupla',
    );
    expectLike(
      (await serve(
        made,
        answers: {
          'worktree': [replies['worktree_criada']!],
        },
      )).single,
      'worktree_multi',
    );
    expect((await made).failed, isEmpty);
  });

  test('salvar template: plano, salvar como e atualizar o de origem', () async {
    final bench = SocketWorkbenchRepository(feed);

    final plan = bench.planTemplate(deck, name: 'dupla');
    expectLike(
      (await serve(
        plan,
        answers: {
          'save_template': [replies['template_plan']!],
        },
      )).single,
      'save_template_dry_run',
    );
    final read = await plan;
    expect(read.nodes, 3);
    expect(read.exists, isTrue);
    expect(read.template, 'dupla');
    expect(read.summary, startsWith('2 agentes, 1 terminal'));

    final saved = bench.saveTemplate(deck, name: 'dupla');
    expectSubsetOf(
      (await serve(
        saved,
        answers: {
          'save_template': [replies['template_salvo']!],
        },
      )).single,
      'save_template',
    );
    expect(await saved, 'dupla');

    final updated = bench.saveTemplate(deck);
    expectSubsetOf(
      (await serve(
        updated,
        answers: {
          'save_template': [replies['template_salvo']!],
        },
      )).single,
      'save_template_origem',
    );
  });
}

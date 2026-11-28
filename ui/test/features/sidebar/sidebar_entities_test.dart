import 'package:egeon_deck/core/domain/entities/activity_summary.dart';
import 'package:egeon_deck/core/domain/entities/organization.dart';
import 'package:egeon_deck/core/domain/entities/workbench_clock.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_bench.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_filters.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/protocol_fixtures.dart';
import '../../support/sidebar_fixtures.dart';

void main() {
  test(
    'a organização do core vira a árvore, com o que ela manda por bancada',
    () {
      final org = Organization.fromMap(
        loadProtocolFixture('events')['workspaces']!,
      );
      final tree = SidebarTree.fromOrganization(org);
      expect(tree.workspaces.single.name, 'Agro');
      expect(tree.orphans.single.removing, isTrue);
      expect(tree.orphans.single.live, isFalse);
      expect(tree.workspaces.single.projects.last.pathExists, isFalse);
    },
  );

  test('clock, agents e rules da bancada chegam como o core manda', () {
    final org = Organization.fromMap({
      'workbenches': [
        {
          'id': 'b',
          'name': 'solta',
          'path': '~/x',
          'agents': 2,
          'rules': 'só leitura',
          'clock': {
            'running': 754,
            'waiting': 120,
            'failed': 0,
            'ticking': ['running'],
          },
        },
      ],
      'orphans': ['b'],
    });
    final bench = org.bench('b')!;
    expect(bench.agents, 2);
    expect(bench.rules, 'só leitura');
    expect(bench.clock!.running, 754);
    expect(bench.clock!.ticking, {ClockPhase.running});
    final row = SidebarTree.fromOrganization(org).orphans.single;
    expect(row.clock!.waiting, 120);
  });

  test('campos ausentes têm padrão: o core pode omitir o que é falso', () {
    final org = Organization.fromMap({
      'workspaces': [
        {'id': 'w', 'name': 'A'},
      ],
    });
    final ws = org.workspaces.single;
    expect(ws.collapsed, isFalse);
    expect(ws.storedOpen, isFalse);
    expect(ws.projects, isEmpty);
    expect(SidebarTree.fromOrganization(org).isEmpty, isTrue);
  });

  test('as contagens somam o que está embaixo', () {
    final tree = sampleTree();
    expect(tree.workspaces.first.benchCount, 3);
    expect(tree.allCount, 4, reason: 'três nos projetos e uma órfã');
    expect(tree.activeCount, 2);
  });

  test('a atividade do grupo é a que o core manda, sem soma na UI', () {
    final events = loadProtocolFixture('events');
    final org = Organization.fromMap(events['workspaces']!);
    final tree = SidebarTree.fromOrganization(org);

    final workspace = org.workspaces.first;
    final project = workspace.projects.first;
    expect(tree.workspaces.first.activity, workspace.activity);
    expect(tree.workspaces.first.projects.first.activity, project.activity);
    expect(
      workspace.activity.attention,
      1,
      reason: 'a fixture do core traz o que a UI antes somava',
    );
    expect(project.activity.working, 1);

    // O que o core não manda fica vazio: a UI não completa com a soma das
    // bancadas.
    final bare = SidebarProject(
      id: 'p',
      name: 'x',
      benches: [
        bench('a', activity: const ActivitySummary(working: 1, done: 1)),
      ],
    );
    expect(bare.activity, ActivitySummary.none);
  });

  test('"preparando" só vale com terminais subindo e mais nada', () {
    expect(const ActivitySummary(starting: 2).isPreparing, isTrue);
    expect(const ActivitySummary(starting: 1, working: 1).isPreparing, isFalse);
    expect(const ActivitySummary(starting: 1, done: 1).isPreparing, isFalse);
    expect(ActivitySummary.none.isPreparing, isFalse);
  });

  test('a inicial do workspace é a primeira letra, em maiúscula', () {
    expect(const BenchOwner(id: 'w', name: '  duck').initial, 'D');
    expect(const BenchOwner(id: 'w', name: '').initial, '');
  });

  group('a busca (filtered)', () {
    test('busca vazia ou só de espaços devolve a mesma árvore', () {
      final tree = sampleTree();
      expect(identical(tree.filtered(''), tree), isTrue);
      expect(identical(tree.filtered('   '), tree), isTrue);
    });

    test('casa pelo nome da bancada, sem diferenciar maiúsculas', () {
      final shown = sampleTree().filtered('NEX');
      final benches = [
        for (final w in shown.workspaces)
          for (final p in w.projects) ...p.benches,
      ];
      expect(benches.map((b) => b.id), ['nexus']);
      expect(shown.orphans, isEmpty);
    });

    test('casar o projeto traz todas as bancadas dele', () {
      final shown = sampleTree().filtered('egeon');
      final p = shown.workspaces.single.projects.single;
      expect(p.name, 'egeon');
      expect(p.benches.map((b) => b.id), ['deck', 'nexus']);
    });

    test(
      'casar o workspace traz tudo o que há nele (menos os sem nome casado)',
      () {
        final shown = sampleTree().filtered('duck');
        expect(shown.workspaces.map((w) => w.name), ['Duck']);
        expect(shown.workspaces.single.projects.length, 3);
        expect(shown.orphans, isEmpty, reason: 'a órfã não é do workspace');
      },
    );

    test('grupos recolhidos abrem para mostrar o que casou', () {
      final shown = sampleTree(collapsed: true).filtered('nexus');
      expect(shown.workspaces.single.collapsed, isFalse);
    });

    test('a órfã casa pelo próprio nome', () {
      final shown = sampleTree().filtered('solta');
      expect(shown.orphans.map((b) => b.id), ['solta']);
      expect(shown.workspaces, isEmpty);
    });

    test('as ativas casam pelo workspace e pelo projeto do dono', () {
      final tree = SidebarTree(
        recent: [
          bench(
            'a',
            owner: const BenchOwner(id: 'w', name: 'Duck'),
            project: 'egeon',
          ),
          bench(
            'b',
            owner: const BenchOwner(id: 'w2', name: 'Casa'),
            project: 'x',
          ),
        ],
        stale: [bench('c', project: 'egeon')],
      );
      expect(tree.filtered('duck').recent.map((b) => b.id), ['a']);
      expect(tree.filtered('egeon').stale.map((b) => b.id), ['c']);
      expect(tree.filtered('zzz').activeCount, 0);
    });

    test('sem resultado a árvore fica vazia', () {
      expect(sampleTree().filtered('zzz').isEmpty, isTrue);
    });
  });

  test('wantsAttention vê os workspaces e as órfãs', () {
    expect(sampleTree().wantsAttention, isFalse);
    final tree = SidebarTree(
      orphans: [bench('a', activity: const ActivitySummary(attention: 1))],
    );
    expect(tree.wantsAttention, isTrue);
    const ws = SidebarWorkspace(
      id: 'w',
      name: 'W',
      activity: ActivitySummary(attention: 2),
    );
    expect(const SidebarTree(workspaces: [ws]).wantsAttention, isTrue);
  });

  group('os filtros do painel (narrowed)', () {
    SidebarTree tree() => SidebarTree(
      workspaces: [
        SidebarWorkspace(
          id: 'w1',
          name: 'Duck',
          projects: [
            SidebarProject(
              id: 'p1',
              name: 'egeon',
              benches: [
                bench('a', activity: const ActivitySummary(attention: 1)),
                bench('b', activity: const ActivitySummary(working: 1)),
                bench('c'),
              ],
            ),
            SidebarProject(id: 'p2', name: 'quieto', benches: [bench('d')]),
          ],
        ),
        SidebarWorkspace(
          id: 'w2',
          name: 'Casa',
          projects: [
            SidebarProject(
              id: 'p3',
              name: 'x',
              benches: [bench('e', activity: const ActivitySummary(done: 2))],
            ),
          ],
        ),
      ],
      orphans: [bench('f', activity: const ActivitySummary(attention: 1))],
    );

    List<String> ids(SidebarTree t) => [
      for (final w in t.workspaces)
        for (final p in w.projects) ...p.benches.map((b) => b.id),
      ...t.orphans.map((b) => b.id),
    ];

    test('sem filtro devolve a mesma árvore', () {
      final t = tree();
      expect(identical(t.narrowed(SidebarFilters.none), t), isTrue);
    });

    test('uma situação deixa só as bancadas dela, e some o vazio', () {
      final t = tree().narrowed(
        SidebarFilters.none.toggled(BenchSituation.needsYou),
      );
      expect(ids(t), ['a', 'f']);
      expect(t.workspaces.single.projects.single.name, 'egeon');
    });

    test('situações somam (ou), e trabalhando inclui terminais subindo', () {
      final f = SidebarFilters.none
          .toggled(BenchSituation.working)
          .toggled(BenchSituation.done);
      expect(ids(tree().narrowed(f)), ['b', 'e']);
      expect(f.count, 2);
    });

    test('Paradas: sem trabalho, sem pedido e sem terminou', () {
      final t = tree().narrowed(
        SidebarFilters.none.toggled(BenchSituation.idle),
      );
      expect(ids(t), ['c', 'd']);
    });

    test('um workspace deixa de fora os demais e as órfãs', () {
      final t = tree().narrowed(SidebarFilters.none.inWorkspace('w2'));
      expect(ids(t), ['e']);
    });

    test('as ativas respeitam situação e workspace do dono', () {
      final owner = const BenchOwner(id: 'w1', name: 'Duck');
      final t = SidebarTree(
        recent: [
          bench('a', owner: owner, activity: const ActivitySummary(done: 1)),
          bench(
            'b',
            owner: const BenchOwner(id: 'w2', name: 'Casa'),
          ),
        ],
        stale: [bench('c', owner: owner)],
      );
      final f = SidebarFilters.none.inWorkspace('w1');
      expect(t.narrowed(f).recent.map((b) => b.id), ['a']);
      expect(t.narrowed(f).stale.map((b) => b.id), ['c']);
      expect(t.narrowed(f.toggled(BenchSituation.done)).stale, isEmpty);
    });

    test('desligar a situação volta ao conjunto', () {
      final f = SidebarFilters.none
          .toggled(BenchSituation.done)
          .toggled(BenchSituation.done);
      expect(f.isEmpty, isTrue);
    });
  });
}

import 'package:egeon_deck/core/domain/entities/activity_summary.dart';
import 'package:egeon_deck/core/domain/entities/organization.dart';
import 'package:egeon_deck/core/domain/entities/workbench_clock.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_bench.dart';
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
}

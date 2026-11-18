import 'dart:async';

import 'package:egeon_deck/features/workbench/domain/entities/worktree_info.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_plan.dart';
import 'package:egeon_deck/features/workbench/domain/usecase/bench_creation.dart';
import 'package:egeon_deck/features/workbench/presentation/cubit/worktree_form_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_workbench_repository.dart';

void main() {
  late FakeWorkbenchRepository repository;

  WorktreeFormCubit open({Duration debounce = Duration.zero}) {
    final cubit = WorktreeFormCubit(
      benchId: 'b1',
      actions: WorktreeActions(repository),
      debounce: debounce,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  setUp(() {
    repository = FakeWorkbenchRepository()
      ..info = const WorktreeInfo(
        summary: 's',
        suggestedBranch: 'main-2',
        nodes: [
          NodeWorktree(
            node: 'a',
            branch: 'own',
            state: NodeWorktreeState.ownWorktree,
          ),
          NodeWorktree(node: 'b', state: NodeWorktreeState.followsWorkbench),
          NodeWorktree(node: 'c', state: NodeWorktreeState.noRepo),
        ],
      );
  });

  test('abre com a branch sugerida e já pergunta o veredito dela', () async {
    final cubit = open();
    await settle();
    expect(cubit.state.branch, 'main-2');
    expect(cubit.state.plan?.verdict, WorktreeVerdict.create);
    expect(repository.planned, ['main-2']);
  });

  test(
    'o veredito de uma branch que já não é a escrita é descartado',
    () async {
      final cubit = open();
      await settle();
      repository.plans['antiga'] = const WorktreePlan(
        verdict: WorktreeVerdict.openExisting,
        folder: '~/antiga',
      );
      final slow = repository.gates['antiga'] = Completer<void>();
      cubit.setBranch('antiga');
      await settle();
      expect(repository.planned.last, 'antiga', reason: 'a pergunta saiu');

      cubit.setBranch('nova');
      await settle();
      expect(cubit.state.plan?.folder, '~/worktrees/nova');

      slow.complete();
      await settle();
      expect(
        cubit.state.plan?.folder,
        '~/worktrees/nova',
        reason: 'a resposta tardia da branch antiga não pode sobrescrever',
      );
    },
  );

  test('digitar espera a pessoa parar: uma pergunta só', () async {
    final cubit = open(debounce: const Duration(milliseconds: 60));
    await settle();
    repository.planned.clear();
    for (final text in ['f', 'fe', 'fea', 'feat']) {
      cubit.setBranch(text);
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(repository.planned, ['feat']);
  });

  test('branch vazia limpa o veredito e não pergunta', () async {
    final cubit = open();
    await settle();
    repository.planned.clear();
    cubit.setBranch('  ');
    await settle();
    expect(cubit.state.plan, isNull);
    expect(repository.planned, isEmpty);
  });

  test(
    'o mapa dos terminais só leva quem está em repositório e tem branch',
    () async {
      final cubit = open();
      await settle();
      expect(cubit.state.nodes, {'a': 'own'});
      cubit.editNode('b', ' feature/b ');
      cubit.editNode('c', 'ignorada');
      expect(cubit.state.nodes, {'a': 'own', 'b': 'feature/b'});
      cubit.editNode('a', '');
      expect(cubit.state.nodes, {'b': 'feature/b'});
    },
  );

  test('falha ao abrir deixa o formulário vazio, sem exceção', () async {
    repository.refuse = 'sem git';
    final cubit = open();
    await settle();
    expect(cubit.state, isA<WorktreeFormOpening>());
  });

  test('fechar antes da resposta não emite', () async {
    final completer = Completer<void>();
    final cubit = open();
    unawaited(cubit.close().then((_) => completer.complete()));
    await completer.future;
    await settle();
  });
}

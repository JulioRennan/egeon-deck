import 'dart:async';

import 'package:egeon_deck/features/workbench/domain/entities/worktree_info.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_plan.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_source.dart';
import 'package:egeon_deck/features/workbench/domain/usecase/bench_creation.dart';
import 'package:egeon_deck/features/workbench/presentation/cubit/worktree_branch_cubit.dart';
import 'package:egeon_deck/features/workbench/presentation/cubit/worktree_form_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_workbench_repository.dart';

void main() {
  late FakeWorkbenchRepository repository;
  const source = WorktreeSource.bench('b1');

  WorktreeFormCubit open() {
    final cubit = WorktreeFormCubit(
      source: source,
      actions: WorktreeActions(repository),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  WorktreeBranchCubit branch({
    String? suggested,
    Duration debounce = Duration.zero,
  }) {
    final cubit = WorktreeBranchCubit(
      source: source,
      actions: WorktreeActions(repository),
      suggested: suggested,
      debounce: debounce,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  WorktreePlan? planOf(WorktreeBranchCubit cubit) => switch (cubit.state) {
    BranchJudged(:final plan) => plan,
    BranchEmpty() || BranchAsking() => null,
  };

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

  group('o formulário', () {
    test('abre pedindo o resumo e fica pronto com ele', () async {
      final cubit = open();
      expect(cubit.state, isA<WorktreeFormOpening>());
      await settle();
      expect(
        cubit.state,
        isA<WorktreeFormReady>().having(
          (s) => s.info.suggestedBranch,
          'sugerida',
          'main-2',
        ),
      );
    });

    test('o destino escolhido antes do resumo sobrevive a ele', () async {
      final cubit = open();
      cubit.setDestination(WorktreeDestination.moveCurrent);
      await settle();
      expect(cubit.state, isA<WorktreeFormReady>());
      expect(cubit.state.destination, WorktreeDestination.moveCurrent);
    });

    test('o mapa leva quem diverge da bancada; vazio é não levar; fora do git, nada', () async {
      final cubit = open();
      await settle();
      expect(
        cubit.state.nodes('main-2'),
        isEmpty,
        reason: 'linha não tocada acompanha a bancada',
      );
      cubit.editNode('b', ' feature/b ');
      cubit.editNode('c', 'ignorada');
      expect(cubit.state.nodes('main-2'), {'b': 'feature/b'});
      cubit.editNode('a', '');
      expect(cubit.state.nodes('main-2'), {'a': '', 'b': 'feature/b'});
      cubit.editNode('b', 'main-2');
      expect(cubit.state.nodes('main-2'), {'a': ''});
    });

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
  });

  group('a branch', () {
    test('a sugerida pergunta o veredito já', () async {
      final cubit = branch(suggested: 'main-2');
      expect(cubit.state, isA<BranchAsking>());
      await settle();
      expect(cubit.branch, 'main-2');
      expect(planOf(cubit)?.verdict, WorktreeVerdict.create);
      expect(repository.planned, ['main-2']);
    });

    test(
      'o veredito de uma branch que já não é a escrita é descartado',
      () async {
        final cubit = branch(suggested: 'main-2');
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
        expect(planOf(cubit)?.folder, '~/worktrees/nova');

        slow.complete();
        await settle();
        expect(
          planOf(cubit)?.folder,
          '~/worktrees/nova',
          reason: 'a resposta tardia da branch antiga não pode sobrescrever',
        );
      },
    );

    test('digitar espera a pessoa parar: uma pergunta só', () async {
      final cubit = branch(debounce: const Duration(milliseconds: 60));
      for (final text in ['f', 'fe', 'fea', 'feat']) {
        cubit.setBranch(text);
      }
      expect(cubit.state, isA<BranchAsking>());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(repository.planned, ['feat']);
    });

    test('branch vazia é BranchEmpty e não pergunta', () async {
      final cubit = branch(suggested: 'main-2');
      await settle();
      repository.planned.clear();
      cubit.setBranch('  ');
      await settle();
      expect(cubit.state, isA<BranchEmpty>());
      expect(cubit.branch, '');
      expect(repository.planned, isEmpty);
    });
  });
}

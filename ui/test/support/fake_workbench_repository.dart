import 'dart:async';

import 'package:egeon_deck/features/workbench/domain/errors/workbench_error.dart';
import 'package:egeon_deck/features/workbench/domain/entities/bench_template.dart';
import 'package:egeon_deck/features/workbench/domain/entities/removal_plan.dart';
import 'package:egeon_deck/features/workbench/domain/entities/template_plan.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_source.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_info.dart';
import 'package:egeon_deck/features/workbench/domain/entities/worktree_plan.dart';
import 'package:egeon_deck/features/workbench/domain/repository/workbench_repository.dart';

/// A bancada falsa: guarda os gestos e devolve o que o teste preparou.
class FakeWorkbenchRepository implements WorkbenchRepository {
  final log = <String>[];
  var agents = 2;
  var currentRules = '';
  var plan = const RemovalPlan();

  /// Se preenchido, o próximo comando é recusado com esta mensagem.
  String? refuse;

  Future<T> _run<T>(String entry, T value) async {
    final reason = refuse;
    if (reason != null) throw WorkbenchRefused(reason);
    log.add(entry);
    return value;
  }

  @override
  Future<void> rename(String id, String name) =>
      _run('renomear:$id:$name', null);

  @override
  Future<void> recolor(String id, String color) => _run('cor:$id:$color', null);

  @override
  Future<int> agentCount(String id) => _run('agentes:$id', agents);

  @override
  Future<void> clear(String id) => _run('limpar:$id', null);

  @override
  Future<void> resetClock(String id) => _run('zerar:$id', null);

  @override
  Future<String> rules(String id) => _run('regras?:$id', currentRules);

  @override
  Future<void> setRules(String id, String rules) =>
      _run('regras:$id:$rules', null);

  @override
  Future<RemovalPlan> planRemoval(String id) => _run('plano:$id', plan);

  /// O que a 2ª confirmação diz que se perde.
  var losses = <String>[];

  @override
  Future<List<String>> removalLosses(String id) => _run('perdas:$id', losses);

  @override
  Future<void> remove(String id, {bool deleteWorktrees = false}) =>
      _run('remover:$id:$deleteWorktrees', null);

  var templateList = <BenchTemplate>[];
  var info = const WorktreeInfo(summary: '', suggestedBranch: 'main-2');

  /// O veredito por branch; o que não está aqui é "criar".
  final plans = <String, WorktreePlan>{};
  final planned = <String>[];

  /// Segura a resposta do veredito de uma branch até o teste liberar.
  final gates = <String, Completer<void>>{};

  @override
  Future<List<BenchTemplate>> templates() => _run('templates', templateList);

  @override
  Future<String> create({
    required String path,
    String? name,
    String? project,
    String? template,
  }) => _run(
    'criar:$path:${name ?? ''}:${project ?? ''}:${template ?? ''}',
    'nova',
  );

  /// Como a origem aparece no registro: o id da bancada, ou `pasta=`/`projeto=`.
  static String _of(WorktreeSource source) =>
      (source.nodeId == null ? null : '${source.benchId}/${source.nodeId}') ??
      source.benchId ??
      (source.project != null
          ? 'projeto=${source.project}'
          : 'pasta=${source.path}');

  @override
  Future<WorktreeInfo> worktreeInfo(WorktreeSource source) =>
      _run('worktree_info:${_of(source)}', info);

  @override
  Future<WorktreePlan> worktreePlan(
    WorktreeSource source,
    String branch,
  ) async {
    planned.add(branch);
    await gates[branch]?.future;
    return _run(
      'worktree_plan:${_of(source)}:$branch',
      plans[branch] ??
          WorktreePlan(
            verdict: WorktreeVerdict.create,
            folder: '~/worktrees/$branch',
          ),
    );
  }

  /// Os repositórios que o próximo `worktree` diz que recusaram.
  var failedRepos = <String>[];

  @override
  Future<WorktreeCreated> createWorktree(
    WorktreeSource source,
    String branch, {
    WorktreeDestination destination = WorktreeDestination.newWorkbench,
    Map<String, String> nodes = const {},
    Map<String, String> repos = const {},
    String? template,
  }) => _run(
    'worktree:${_of(source)}:$branch:${destination.wire}:$nodes'
    '${repos.isEmpty ? '' : ':repos=$repos'}'
    '${template == null ? '' : ':template=$template'}',
    WorktreeCreated(workbench: 'nova', failed: failedRepos),
  );

  var templatePlan = const TemplatePlan(summary: '1 agente', nodes: 1);

  /// O plano por nome pedido (nulo é o de origem); o que não está aqui é
  /// [templatePlan].
  final templatePlans = <String?, TemplatePlan>{};

  @override
  Future<TemplatePlan> planTemplate(String id, {String? name}) =>
      _run('template?:$id:${name ?? ''}', templatePlans[name] ?? templatePlan);

  @override
  Future<String> saveTemplate(String id, {String? name}) =>
      _run('template:$id:${name ?? ''}', name ?? 'origem');
}

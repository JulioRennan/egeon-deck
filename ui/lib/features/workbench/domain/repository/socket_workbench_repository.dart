import '../../../../core/adapters/organization_feed.dart';
import '../../../../core/domain/entities/command_failed.dart';
import '../../../../core/domain/entities/organization.dart';
import '../entities/bench_template.dart';
import '../entities/removal_plan.dart';
import '../entities/worktree_info.dart';
import '../entities/worktree_plan.dart';
import 'workbench_repository.dart';

/// Os gestos sobre uma bancada, pelo core Rust. Número de agentes e regras
/// já vêm na bancada do tópico `workspaces`: não há consulta a fazer.
class SocketWorkbenchRepository implements WorkbenchRepository {
  const SocketWorkbenchRepository(this._feed);

  final OrganizationFeed _feed;

  OrgBench _bench(String id) {
    final bench = _feed.last?.bench(id);
    if (bench == null) throw CommandFailed("bancada desconhecida '$id'");
    return bench;
  }

  @override
  Future<void> rename(String id, String name) =>
      _feed.command('set_workbench', {'workbench': id, 'name': name});

  @override
  Future<void> recolor(String id, String color) =>
      _feed.command('set_workbench', {'workbench': id, 'color': color});

  @override
  Future<int> agentCount(String id) async => _bench(id).agents;

  @override
  Future<void> clear(String id) =>
      _feed.command('clear_workbench', {'workbench': id});

  @override
  Future<String> rules(String id) async => _bench(id).rules ?? '';

  /// Texto vazio (ou só espaços) apaga as regras: o core quer `null`.
  @override
  Future<void> setRules(String id, String rules) => _feed.command(
    'set_workbench_rules',
    {'workbench': id, 'rules': rules.trim().isEmpty ? null : rules},
  );

  @override
  Future<RemovalPlan> planRemoval(String id) async => RemovalPlan.fromMap(
    await _feed.command('plan_remove_workbench', {'workbench': id}),
  );

  @override
  Future<void> remove(String id, {bool deleteWorktrees = false}) =>
      _feed.command('remove_workbench', {
        'workbench': id,
        'worktrees': deleteWorktrees,
      });

  @override
  Future<List<BenchTemplate>> templates() async {
    final reply = await _feed.command('templates');
    return [
      for (final raw in reply['templates'] as List<Object?>? ?? const [])
        BenchTemplate.fromMap(raw! as Map<String, Object?>),
    ];
  }

  @override
  Future<String> create({
    required String path,
    String? name,
    String? project,
    String? template,
  }) async {
    final reply = await _feed.command('create_workbench', {
      'path': path,
      if (name != null && name.isNotEmpty) 'name': name,
      'project': ?project,
      'template': ?template,
    });
    return reply['workbench']! as String;
  }

  @override
  Future<WorktreeInfo> worktreeInfo(String id) async => WorktreeInfo.fromMap(
    await _feed.command('worktree_info', {'workbench': id}),
  );

  @override
  Future<WorktreePlan> worktreePlan(String id, String branch) async =>
      WorktreePlan.fromMap(
        await _feed.command('worktree_plan', {
          'workbench': id,
          'branch': branch,
        }),
      );

  @override
  Future<String> createWorktree(
    String id,
    String branch, {
    required WorktreeDestination destination,
    Map<String, String> nodes = const {},
  }) async {
    final reply = await _feed.command('worktree', {
      'workbench': id,
      'branch': branch,
      'destination': destination.wire,
      if (nodes.isNotEmpty) 'nodes': nodes,
    });
    return reply['workbench']! as String;
  }
}

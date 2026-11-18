import '../../../../core/adapters/organization_feed.dart';
import '../../../../core/domain/entities/organization.dart';
import '../entities/bench_template.dart';
import '../entities/removal_plan.dart';
import '../entities/worktree_info.dart';
import '../entities/worktree_plan.dart';
import 'workbench_repository.dart';
import '../../../../core/adapters/egeon_socket_client.dart';
import '../errors/workbench_error.dart';

/// Os gestos sobre uma bancada, pelo core Rust. Número de agentes e regras
/// já vêm na bancada do tópico `workspaces`: não há consulta a fazer.
class SocketWorkbenchRepository implements WorkbenchRepository {
  const SocketWorkbenchRepository(this._feed);

  final OrganizationFeed _feed;

  /// Recusa e queda do socket viram [WorkbenchError].
  Future<EgeonMessage> _command(String cmd, [EgeonMessage args = const {}]) =>
      _feed
          .command(cmd, args)
          .failingAs(
            refused: WorkbenchRefused.new,
            offline: WorkbenchOffline.new,
          );

  OrgBench _bench(String id) {
    final bench = _feed.last?.bench(id);
    if (bench == null) throw WorkbenchRefused("bancada desconhecida '$id'");
    return bench;
  }

  @override
  Future<void> rename(String id, String name) =>
      _command('set_workbench', {'workbench': id, 'name': name});

  @override
  Future<void> recolor(String id, String color) =>
      _command('set_workbench', {'workbench': id, 'color': color});

  @override
  Future<int> agentCount(String id) async => _bench(id).agents;

  @override
  Future<void> clear(String id) =>
      _command('clear_workbench', {'workbench': id});

  @override
  Future<String> rules(String id) async => _bench(id).rules ?? '';

  /// Texto vazio (ou só espaços) apaga as regras: o core quer `null`.
  @override
  Future<void> setRules(String id, String rules) => _command(
    'set_workbench_rules',
    {'workbench': id, 'rules': rules.trim().isEmpty ? null : rules},
  );

  @override
  Future<RemovalPlan> planRemoval(String id) async => RemovalPlan.fromMap(
    await _command('plan_remove_workbench', {'workbench': id}),
  );

  @override
  Future<void> remove(String id, {bool deleteWorktrees = false}) => _command(
    'remove_workbench',
    {'workbench': id, 'worktrees': deleteWorktrees},
  );

  @override
  Future<List<BenchTemplate>> templates() async {
    final reply = await _command('templates');
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
    final reply = await _command('create_workbench', {
      'path': path,
      if (name != null && name.isNotEmpty) 'name': name,
      'project': ?project,
      'template': ?template,
    });
    return reply['workbench']! as String;
  }

  @override
  Future<WorktreeInfo> worktreeInfo(String id) async =>
      WorktreeInfo.fromMap(await _command('worktree_info', {'workbench': id}));

  @override
  Future<WorktreePlan> worktreePlan(String id, String branch) async =>
      WorktreePlan.fromMap(
        await _command('worktree_plan', {'workbench': id, 'branch': branch}),
      );

  @override
  Future<String> createWorktree(
    String id,
    String branch, {
    required WorktreeDestination destination,
    Map<String, String> nodes = const {},
  }) async {
    final reply = await _command('worktree', {
      'workbench': id,
      'branch': branch,
      'destination': destination.wire,
      if (nodes.isNotEmpty) 'nodes': nodes,
    });
    return reply['workbench']! as String;
  }
}

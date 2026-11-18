import '../entities/bench_template.dart';
import '../entities/removal_plan.dart';
import '../entities/worktree_info.dart';
import '../entities/worktree_plan.dart';

/// Os gestos sobre uma bancada que já existe. Quem decide se vale (nome livre,
/// terminais, worktrees) é o core Rust; recusa chega como `CommandFailed`.
abstract interface class WorkbenchRepository {
  Future<void> rename(String id, String name);

  Future<void> recolor(String id, String color);

  /// Quantos agentes o "limpar" vai atingir, para a confirmação dizer.
  Future<int> agentCount(String id);

  Future<void> clear(String id);

  Future<String> rules(String id);

  Future<void> setRules(String id, String rules);

  Future<RemovalPlan> planRemoval(String id);

  Future<void> remove(String id, {bool deleteWorktrees = false});

  /// Os templates que o seletor de bancada nova oferece.
  Future<List<BenchTemplate>> templates();

  /// Cria a bancada em [path]; devolve o id. [name] vazio deixa o core nomear.
  Future<String> create({
    required String path,
    String? name,
    String? project,
    String? template,
  });

  /// O que o formulário de worktree mostra ao abrir.
  Future<WorktreeInfo> worktreeInfo(String id);

  /// O veredito para a branch escrita, sem criar nada.
  Future<WorktreePlan> worktreePlan(String id, String branch);

  /// Cria a worktree; devolve o id da bancada que a tem. [nodes] leva a branch
  /// de cada terminal que difere da da bancada (vazia, fica onde está).
  Future<String> createWorktree(
    String id,
    String branch, {
    required WorktreeDestination destination,
    Map<String, String> nodes = const {},
  });
}

import '../entities/bench_template.dart';
import '../entities/removal_plan.dart';
import '../entities/template_plan.dart';
import '../entities/worktree_info.dart';
import '../entities/worktree_plan.dart';
import '../entities/worktree_source.dart';

/// Os gestos sobre uma bancada que já existe. Quem decide se vale (nome livre,
/// terminais, worktrees) é o core Rust; recusa chega como `CommandFailed`.
abstract interface class WorkbenchRepository {
  Future<void> rename(String id, String name);

  Future<void> recolor(String id, String color);

  /// Quantos agentes o "limpar" vai atingir, para a confirmação dizer.
  Future<int> agentCount(String id);

  Future<void> clear(String id);

  /// "Zerar cronômetro": o tempo da bancada volta a zero.
  Future<void> resetClock(String id);

  Future<String> rules(String id);

  Future<void> setRules(String id, String rules);

  Future<RemovalPlan> planRemoval(String id);

  /// O texto da 2ª confirmação: o trabalho não commitado que apagar as
  /// worktrees da bancada leva. Vazio, não há o que perguntar. A bancada fica
  /// com a cortina enquanto o core confere.
  Future<List<String>> removalLosses(String id);

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
  Future<WorktreeInfo> worktreeInfo(WorktreeSource source);

  /// O veredito para a branch escrita, sem criar nada.
  Future<WorktreePlan> worktreePlan(WorktreeSource source, String branch);

  /// Cria a worktree; devolve a bancada que a tem. [nodes] leva a branch de
  /// cada terminal que difere da da bancada (vazia, fica onde está); [repos],
  /// a de cada repositório de um multi-projeto. [template] só vale sem bancada
  /// de origem.
  Future<WorktreeCreated> createWorktree(
    WorktreeSource source,
    String branch, {
    WorktreeDestination destination = WorktreeDestination.newWorkbench,
    Map<String, String> nodes = const {},
    Map<String, String> repos = const {},
    String? template,
  });

  /// O que salvar o canvas como template vai gravar, sem gravar. Sem [name],
  /// o template de que a bancada nasceu.
  Future<TemplatePlan> planTemplate(String id, {String? name});

  /// Grava o canvas como template [name] (sem ele, regrava o de origem);
  /// devolve o nome gravado.
  Future<String> saveTemplate(String id, {String? name});
}

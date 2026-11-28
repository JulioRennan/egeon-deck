import '../entities/bench_template.dart';
import '../entities/worktree_info.dart';
import '../entities/worktree_plan.dart';
import '../entities/worktree_source.dart';
import '../repository/workbench_repository.dart';

/// Os templates que o formulário de bancada nova oferece.
class ListTemplates {
  const ListTemplates(this._repository);

  final WorkbenchRepository _repository;

  Future<List<BenchTemplate>> call() => _repository.templates();
}

/// Cria a bancada na pasta; o core nomeia se o nome vier vazio.
class CreateWorkbench {
  const CreateWorkbench(this._repository);

  final WorkbenchRepository _repository;

  Future<String> call({
    required String path,
    String? name,
    String? project,
    String? template,
  }) => _repository.create(
    path: path,
    name: name,
    project: project,
    template: template,
  );
}

/// As três perguntas e o gesto do formulário de worktree, com ou sem bancada
/// de origem.
class WorktreeActions {
  const WorktreeActions(this._repository);

  final WorkbenchRepository _repository;

  Future<WorktreeInfo> info(WorktreeSource source) =>
      _repository.worktreeInfo(source);

  Future<WorktreePlan> plan(WorktreeSource source, String branch) =>
      _repository.worktreePlan(source, branch);

  Future<WorktreeCreated> create(
    WorktreeSource source,
    String branch, {
    WorktreeDestination destination = WorktreeDestination.newWorkbench,
    Map<String, String> nodes = const {},
    Map<String, String> repos = const {},
    String? template,
  }) => _repository.createWorktree(
    source,
    branch,
    destination: destination,
    nodes: nodes,
    repos: repos,
    template: template,
  );
}

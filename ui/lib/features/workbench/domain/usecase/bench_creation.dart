import '../entities/bench_template.dart';
import '../entities/worktree_info.dart';
import '../entities/worktree_plan.dart';
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

/// As três perguntas e o gesto do formulário de worktree.
class WorktreeActions {
  const WorktreeActions(this._repository);

  final WorkbenchRepository _repository;

  Future<WorktreeInfo> info(String id) => _repository.worktreeInfo(id);

  Future<WorktreePlan> plan(String id, String branch) =>
      _repository.worktreePlan(id, branch);

  Future<String> create(
    String id,
    String branch, {
    required WorktreeDestination destination,
    Map<String, String> nodes = const {},
  }) => _repository.createWorktree(
    id,
    branch,
    destination: destination,
    nodes: nodes,
  );
}

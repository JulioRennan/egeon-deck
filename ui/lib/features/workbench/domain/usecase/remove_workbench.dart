import '../entities/removal_plan.dart';
import '../repository/workbench_repository.dart';

class RemoveWorkbench {
  const RemoveWorkbench(this._repository);

  final WorkbenchRepository _repository;

  Future<RemovalPlan> plan(String id) => _repository.planRemoval(id);

  Future<List<String>> losses(String id) => _repository.removalLosses(id);

  Future<void> call(String id, {bool deleteWorktrees = false}) =>
      _repository.remove(id, deleteWorktrees: deleteWorktrees);
}

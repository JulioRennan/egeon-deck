import '../repository/workbench_repository.dart';

class RenameWorkbench {
  const RenameWorkbench(this._repository);

  final WorkbenchRepository _repository;

  Future<void> call(String id, String name) => _repository.rename(id, name);
}

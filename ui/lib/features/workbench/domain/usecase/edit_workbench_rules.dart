import '../repository/workbench_repository.dart';

class EditWorkbenchRules {
  const EditWorkbenchRules(this._repository);

  final WorkbenchRepository _repository;

  Future<String> current(String id) => _repository.rules(id);

  Future<void> save(String id, String rules) => _repository.setRules(id, rules);
}

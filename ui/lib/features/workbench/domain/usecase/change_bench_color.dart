import '../repository/workbench_repository.dart';

class ChangeBenchColor {
  const ChangeBenchColor(this._repository);

  final WorkbenchRepository _repository;

  Future<void> call(String id, String color) => _repository.recolor(id, color);
}

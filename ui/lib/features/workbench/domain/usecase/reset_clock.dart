import '../repository/workbench_repository.dart';

/// "Zerar cronômetro" do relógio da bancada.
class ResetClock {
  const ResetClock(this._repository);

  final WorkbenchRepository _repository;

  Future<void> call(String id) => _repository.resetClock(id);
}

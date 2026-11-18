import '../repository/core_repository.dart';

class StopCore {
  const StopCore(this._repository);

  final CoreRepository _repository;

  Future<void> call() => _repository.stop();
}

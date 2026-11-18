import '../repository/core_repository.dart';

/// O core caiu: sobe outro. O canal já reconecta sozinho.
class RelaunchCore {
  const RelaunchCore(this._repository);

  final CoreRepository _repository;

  Future<void> call() => _repository.launch();
}

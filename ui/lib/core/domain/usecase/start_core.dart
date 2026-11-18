import '../repository/core_repository.dart';

/// Sobe o core Rust (se preciso) e liga o canal com ele.
class StartCore {
  const StartCore(this._repository);

  final CoreRepository _repository;

  Future<void> call() async {
    await _repository.launch();
    _repository.connect();
  }
}

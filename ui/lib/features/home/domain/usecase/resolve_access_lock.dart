import '../repository/shell_repository.dart';

/// Os dois botões da cortina de "sem acesso à pasta".
class ResolveAccessLock {
  const ResolveAccessLock(this._repository);

  final ShellRepository _repository;

  Future<void> openSettings() => _repository.openSettings();

  Future<void> askAgain() => _repository.askAccessAgain();
}

import '../entities/shell_state.dart';
import '../repository/shell_repository.dart';

class WatchShell {
  const WatchShell(this._repository);

  final ShellRepository _repository;

  Stream<ShellState> call() => _repository.watch();
}

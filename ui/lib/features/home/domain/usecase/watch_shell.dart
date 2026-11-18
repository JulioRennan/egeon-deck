import '../entities/shell_snapshot.dart';
import '../repository/shell_repository.dart';

class WatchShell {
  const WatchShell(this._repository);

  final ShellRepository _repository;

  Stream<ShellSnapshot> call() => _repository.watch();
}

import '../repository/core_repository.dart';

class WatchCoreLink {
  const WatchCoreLink(this._repository);

  final CoreRepository _repository;

  Stream<bool> call() => _repository.watchLink();
}

import '../repository/tabs_repository.dart';

class PickTab {
  const PickTab(this._repository);

  final TabsRepository _repository;

  Future<void> call(String id) => _repository.pick(id);
}

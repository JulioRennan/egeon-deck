import '../repository/tabs_repository.dart';

class CloseTab {
  const CloseTab(this._repository);

  final TabsRepository _repository;

  Future<void> call(String id) => _repository.close(id);
}

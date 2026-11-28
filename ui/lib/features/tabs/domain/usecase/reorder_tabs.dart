import '../repository/tabs_repository.dart';

class ReorderTabs {
  const ReorderTabs(this._repository);

  final TabsRepository _repository;

  Future<void> call(List<String> ids) => _repository.reorder(ids);
}

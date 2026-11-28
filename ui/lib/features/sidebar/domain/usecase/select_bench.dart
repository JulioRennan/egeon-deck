import '../repository/sidebar_repository.dart';

class SelectBench {
  const SelectBench(this._repository);

  final SidebarRepository _repository;

  Future<void> call(String benchId) => _repository.select(benchId);
}

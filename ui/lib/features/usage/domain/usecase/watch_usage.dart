import '../entities/usage_view.dart';
import '../repository/usage_repository.dart';

class WatchUsage {
  const WatchUsage(this._repository);
  final UsageRepository _repository;

  Stream<UsageView> call(String workbenchId) => _repository.watch(workbenchId);
}

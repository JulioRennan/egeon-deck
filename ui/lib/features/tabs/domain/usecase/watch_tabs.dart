import '../entities/workbench_tab.dart';
import '../repository/tabs_repository.dart';

class WatchTabs {
  const WatchTabs(this._repository);

  final TabsRepository _repository;

  Stream<List<WorkbenchTab>> call() => _repository.watch();
}

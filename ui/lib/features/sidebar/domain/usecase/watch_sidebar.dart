import '../entities/sidebar_tree.dart';
import '../repository/sidebar_repository.dart';

class WatchSidebar {
  const WatchSidebar(this._repository);

  final SidebarRepository _repository;

  Stream<SidebarTree> call() => _repository.watch();
}

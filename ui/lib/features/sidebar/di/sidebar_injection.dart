import '../../../core/adapters/injector.dart';
import '../domain/repository/sidebar_repository.dart';
import '../domain/repository/socket_sidebar_repository.dart';
import '../domain/usecase/copy_project_path.dart';
import '../domain/usecase/move_item.dart';
import '../domain/usecase/plan_move.dart';
import '../domain/usecase/select_bench.dart';
import '../domain/usecase/set_project_stored.dart';
import '../domain/usecase/toggle_group.dart';
import '../domain/usecase/watch_sidebar.dart';
import '../presentation/cubit/sidebar_cubit.dart';

void registerSidebarRepositories() {
  Injector.factory<SidebarRepository>(() => SocketSidebarRepository(inject()));
}

void registerSidebarDomain() {
  Injector.factory(() => WatchSidebar(inject()));
  Injector.factory(() => SelectBench(inject()));
  Injector.factory(() => ToggleGroup(inject()));
  Injector.factory(() => SetProjectStored(inject()));
  Injector.factory(() => MoveItem(inject()));
  Injector.factory(() => PlanMove(inject()));
  Injector.factory(() => CopyProjectPath(inject()));
  Injector.factory(
    () => SidebarCubit(
      watch: inject(),
      select: inject(),
      toggle: inject(),
      setStored: inject(),
      move: inject(),
      plan: inject(),
    ),
  );
}

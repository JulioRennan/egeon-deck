import '../../../core/adapters/injector.dart';
import '../domain/repository/socket_tabs_repository.dart';
import '../domain/repository/tabs_repository.dart';
import '../domain/usecase/close_tab.dart';
import '../domain/usecase/pick_tab.dart';
import '../domain/usecase/reorder_tabs.dart';
import '../domain/usecase/watch_tabs.dart';
import '../presentation/cubit/tabs_cubit.dart';

void registerTabsRepositories() {
  Injector.factory<TabsRepository>(() => SocketTabsRepository(inject()));
}

void registerTabsDomain() {
  Injector.factory(() => WatchTabs(inject()));
  Injector.factory(() => PickTab(inject()));
  Injector.factory(() => CloseTab(inject()));
  Injector.factory(() => ReorderTabs(inject()));
  Injector.factory(
    () => TabsCubit(
      watch: inject(),
      pick: inject(),
      close: inject(),
      reorder: inject(),
    ),
  );
}

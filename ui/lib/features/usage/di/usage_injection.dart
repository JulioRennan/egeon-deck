import '../../../core/adapters/injector.dart';
import '../domain/repository/socket_usage_repository.dart';
import '../domain/repository/usage_repository.dart';
import '../domain/usecase/watch_usage.dart';
import '../presentation/cubit/usage_cubit.dart';

void registerUsageRepositories() {
  Injector.factory<UsageRepository>(() => SocketUsageRepository(inject()));
}

void registerUsageDomain() {
  Injector.factory(() => WatchUsage(inject()));
  Injector.factoryParam<UsageCubit, String>(
    (workbenchId) => UsageCubit(workbenchId: workbenchId, watch: inject()),
  );
}

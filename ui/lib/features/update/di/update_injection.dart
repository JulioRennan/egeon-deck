import '../../../core/adapters/injector.dart';
import '../domain/repository/app_repository.dart';
import '../domain/repository/socket_app_repository.dart';
import '../domain/usecase/answer_app.dart';
import '../domain/usecase/watch_app.dart';
import '../presentation/cubit/update_cubit.dart';

void registerUpdateRepositories() {
  Injector.factory<AppRepository>(() => SocketAppRepository(inject()));
}

void registerUpdateDomain() {
  Injector.factory(() => WatchApp(inject()));
  Injector.factory(() => AnswerApp(inject()));
  Injector.factory(() => UpdateCubit(watch: inject(), answer: inject()));
}

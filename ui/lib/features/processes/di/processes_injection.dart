import '../../../core/adapters/injector.dart';
import '../domain/repository/processes_repository.dart';
import '../domain/repository/socket_processes_repository.dart';
import '../domain/usecase/manage_processes.dart';
import '../presentation/cubit/processes_cubit.dart';

void registerProcessesRepositories() {
  Injector.factory<ProcessesRepository>(
    () => SocketProcessesRepository(inject()),
  );
}

void registerProcessesDomain() {
  Injector.factory(() => ManageProcesses(inject()));
  Injector.factory(() => ProcessesCubit(manage: inject()));
}

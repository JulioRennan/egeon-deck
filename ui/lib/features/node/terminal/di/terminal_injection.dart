import '../../../../core/adapters/injector.dart';
import '../domain/repository/socket_terminal_repository.dart';
import '../domain/repository/terminal_repository.dart';
import '../domain/usecase/resize_terminal.dart';
import '../domain/usecase/send_terminal_input.dart';
import '../domain/usecase/watch_terminal.dart';
import '../domain/usecase/watch_terminal_effects.dart';
import '../presentation/cubit/terminal_cubit.dart';

void registerTerminalRepositories() {
  Injector.factory<TerminalRepository>(
    () => SocketTerminalRepository(inject()),
  );
}

void registerTerminalDomain() {
  Injector.factory(() => WatchTerminal(inject()));
  Injector.factory(() => SendTerminalInput(inject()));
  Injector.factory(() => ResizeTerminal(inject()));
  Injector.factory(() => WatchTerminalEffects(inject()));
  Injector.factoryParam<TerminalCubit, String>(
    (nodeId) => TerminalCubit(
      nodeId: nodeId,
      watch: inject(),
      input: inject(),
      resize: inject(),
      effects: inject(),
    ),
  );
}

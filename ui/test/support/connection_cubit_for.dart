import 'package:egeon_deck/core/adapters/egeon_app_launcher.dart';
import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/core/cubits/connection_cubit.dart';
import 'package:egeon_deck/core/domain/repository/socket_core_repository.dart';
import 'package:egeon_deck/core/domain/usecase/relaunch_core.dart';
import 'package:egeon_deck/core/domain/usecase/start_core.dart';
import 'package:egeon_deck/core/domain/usecase/stop_core.dart';
import 'package:egeon_deck/core/domain/usecase/watch_core_link.dart';

/// O mesmo encadeamento do `main`, para os testes montarem o cubit global.
ConnectionCubit connectionCubitFor(
  EgeonAppLauncher launcher,
  EgeonSocketClient client,
) {
  final core = SocketCoreRepository(launcher: launcher, client: client);
  return ConnectionCubit(
    startCore: StartCore(core),
    watchLink: WatchCoreLink(core),
    relaunchCore: RelaunchCore(core),
    stopCore: StopCore(core),
  );
}

import '../adapters/app_windows.dart';
import '../domain/usecase/join_core.dart';
import '../../features/canvas/di/canvas_injection.dart';
import '../../features/chat/di/chat_injection.dart';
import '../../features/home/di/home_injection.dart';
import '../../features/node/agent/di/agent_injection.dart';
import '../../features/node/queue/di/queue_injection.dart';
import '../../features/node/terminal/di/terminal_injection.dart';
import '../../features/node/web/di/web_injection.dart';
import '../../features/processes/di/processes_injection.dart';
import '../../features/sidebar/di/sidebar_injection.dart';
import '../../features/tabs/di/tabs_injection.dart';
import '../../features/update/di/update_injection.dart';
import '../../features/usage/di/usage_injection.dart';
import '../../features/workbench/di/workbench_injection.dart';
import '../../features/workspace/di/workspace_injection.dart';
import '../adapters/clipboard_writer.dart';
import '../adapters/egeon_app_launcher.dart';
import '../adapters/egeon_paths.dart';
import '../adapters/egeon_socket_client.dart';
import '../adapters/egeon_transport.dart';
import '../adapters/injector.dart';
import '../adapters/organization_feed.dart';
import '../adapters/path_picker.dart';
import '../cubits/connection_cubit.dart';
import '../domain/repository/core_repository.dart';
import '../domain/repository/socket_core_repository.dart';
import '../domain/usecase/relaunch_core.dart';
import '../domain/usecase/start_core.dart';
import '../domain/usecase/stop_core.dart';
import '../domain/usecase/watch_core_link.dart';

/// O que fala com o mundo: o do core do front (socket, lançador do core Rust,
/// escolha de pasta) e os repositórios reais de cada módulo. Os testes não
/// chamam esta; registram os falsos.
///
/// Únicos: o caminho, o transport e o cliente do socket (uma conexão só); o
/// lançador (guarda o processo do core que lançou); e o [OrganizationFeed]
/// (uma assinatura de `organization` repartida por todos).
void registerInfrastructure(Map<String, String> environment) {
  final paths = EgeonPaths(environment);
  Injector.singleton(paths);
  Injector.singleton<EgeonTransport>(UnixSocketTransport(paths.socket));
  Injector.lazySingleton(() => EgeonSocketClient(inject<EgeonTransport>()));
  Injector.lazySingleton(
    () => EgeonAppLauncher(
      paths: inject(),
      probe: inject<EgeonTransport>(),
      environment: environment,
    ),
  );
  Injector.lazySingleton(() => OrganizationFeed(inject()));
  Injector.factory<CoreRepository>(
    () => SocketCoreRepository(launcher: inject(), client: inject()),
  );
  Injector.factory<PathPicker>(SystemPathPicker.new);
  Injector.factory<ClipboardWriter>(SystemClipboard.new);
  Injector.factory<AppWindows>(MultiWindowAppWindows.new);
  Injector.factory<CurrentWindow>(ChannelCurrentWindow.new);

  registerHomeRepositories();
  registerTabsRepositories();
  registerSidebarRepositories();
  registerWorkbenchRepositories();
  registerWorkspaceRepositories();
  registerCanvasRepositories();
  registerChatRepositories();
  registerUsageRepositories();
  registerProcessesRepositories();
  registerUpdateRepositories();
  registerTerminalRepositories();
  registerAgentRepositories();
  registerQueueRepositories();
  registerWebRepositories();
}

/// Usecases, cubits e registros de cada módulo, sobre os repositórios que
/// estiverem registrados — os reais ou os falsos dos testes.
///
/// Único aqui: o [ConnectionCubit] — a conexão com o core Rust é uma só, e a
/// raiz a fecha ao sair.
void registerDomain() {
  Injector.factory(() => StartCore(inject()));
  Injector.factory(() => JoinCore(inject()));
  Injector.factory(() => WatchCoreLink(inject()));
  Injector.factory(() => RelaunchCore(inject()));
  Injector.factory(() => StopCore(inject()));
  Injector.lazySingleton(
    () => ConnectionCubit(
      startCore: inject(),
      watchLink: inject(),
      relaunchCore: inject(),
      stopCore: inject(),
    ),
  );

  registerHomeDomain();
  registerTabsDomain();
  registerSidebarDomain();
  registerWorkbenchDomain();
  registerWorkspaceDomain();
  registerCanvasDomain();
  registerChatDomain();
  registerUsageDomain();
  registerProcessesDomain();
  registerUpdateDomain();
  registerTerminalDomain();
  registerAgentDomain();
  registerQueueDomain();
  registerWebDomain();
}

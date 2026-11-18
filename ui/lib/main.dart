import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/adapters/egeon_app_launcher.dart';
import 'core/adapters/egeon_paths.dart';
import 'core/adapters/egeon_socket_client.dart';
import 'core/adapters/egeon_transport.dart';
import 'core/cubits/connection_cubit.dart';
import 'core/domain/repository/socket_core_repository.dart';
import 'core/domain/usecase/relaunch_core.dart';
import 'core/domain/usecase/start_core.dart';
import 'core/domain/usecase/stop_core.dart';
import 'core/domain/usecase/watch_core_link.dart';
import 'core/adapters/organization_feed.dart';
import 'features/home/domain/repository/node_repositories.dart';
import 'features/chat/domain/repository/chat_repository.dart';
import 'features/chat/domain/repository/socket_chat_repository.dart';
import 'features/canvas/domain/repository/canvas_repository.dart';
import 'features/canvas/domain/repository/socket_canvas_repository.dart';
import 'core/adapters/path_picker.dart';
import 'features/home/domain/repository/shell_repository.dart';
import 'features/processes/domain/repository/processes_repository.dart';
import 'features/processes/domain/repository/socket_processes_repository.dart';
import 'features/usage/domain/repository/socket_usage_repository.dart';
import 'features/usage/domain/repository/usage_repository.dart';
import 'features/update/domain/repository/app_repository.dart';
import 'features/update/domain/repository/socket_app_repository.dart';
import 'features/home/domain/repository/socket_ui_request_repository.dart';
import 'features/home/domain/repository/ui_request_repository.dart';
import 'features/home/domain/repository/socket_shell_repository.dart';
import 'features/home/presentation/page/home_page.dart';
import 'features/sidebar/domain/repository/sidebar_repository.dart';
import 'features/sidebar/domain/repository/socket_sidebar_repository.dart';
import 'features/tabs/domain/repository/socket_tabs_repository.dart';
import 'features/tabs/domain/repository/tabs_repository.dart';
import 'features/workbench/domain/repository/socket_workbench_repository.dart';
import 'features/workbench/domain/repository/workbench_repository.dart';
import 'features/workspace/domain/repository/socket_workspace_repository.dart';
import 'features/workspace/domain/repository/workspace_repository.dart';
import 'features/node/terminal/domain/repository/socket_terminal_repository.dart';
import 'features/node/terminal/domain/repository/terminal_repository.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() => runApp(createEgeonDeckApp(Platform.environment));

/// Monta o app real: socket, lançador do core Rust e repositórios.
EgeonDeckApp createEgeonDeckApp(Map<String, String> environment) {
  final paths = EgeonPaths(environment);
  final transport = UnixSocketTransport(paths.socket);
  final client = EgeonSocketClient(transport);
  final core = SocketCoreRepository(
    launcher: EgeonAppLauncher(
      paths: paths,
      probe: transport,
      environment: environment,
    ),
    client: client,
  );
  final organization = OrganizationFeed(client);
  return EgeonDeckApp(
    sidebar: SocketSidebarRepository(organization),
    tabs: SocketTabsRepository(organization),
    shell: SocketShellRepository(organization),
    uiRequests: SocketUiRequestRepository(client),
    app: SocketAppRepository(client),
    usage: SocketUsageRepository(client),
    processes: SocketProcessesRepository(client),
    workbenches: SocketWorkbenchRepository(organization),
    workspaces: SocketWorkspaceRepository(organization),
    paths: SystemPathPicker(),
    canvas: SocketCanvasRepository(client),
    chat: SocketChatRepository(client),
    nodes: SocketNodeRepositories(client),
    connection: ConnectionCubit(
      startCore: StartCore(core),
      watchLink: WatchCoreLink(core),
      relaunchCore: RelaunchCore(core),
      stopCore: StopCore(core),
    ),
    terminals: SocketTerminalRepository(client),
  );
}

/// Raiz do app: entrega a conexão com o core Rust e os repositórios à `home`.
class EgeonDeckApp extends StatefulWidget {
  const EgeonDeckApp({
    super.key,
    required this.connection,
    required this.terminals,
    required this.sidebar,
    required this.tabs,
    required this.shell,
    required this.workbenches,
    required this.workspaces,
    required this.paths,
    required this.canvas,
    required this.chat,
    required this.nodes,
    required this.uiRequests,
    required this.app,
    required this.usage,
    required this.processes,
  });

  final ConnectionCubit connection;
  final TerminalRepository terminals;
  final SidebarRepository sidebar;
  final TabsRepository tabs;
  final ShellRepository shell;
  final WorkbenchRepository workbenches;
  final WorkspaceRepository workspaces;
  final PathPicker paths;
  final CanvasRepository canvas;
  final ChatRepository chat;
  final NodeRepositories nodes;
  final UiRequestRepository uiRequests;
  final AppRepository app;
  final UsageRepository usage;
  final ProcessesRepository processes;

  @override
  State<EgeonDeckApp> createState() => _EgeonDeckAppState();
}

class _EgeonDeckAppState extends State<EgeonDeckApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Ao sair, o core lançado por esta UI sai junto.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.connection.close();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<TerminalRepository>.value(value: widget.terminals),
        RepositoryProvider<SidebarRepository>.value(value: widget.sidebar),
        RepositoryProvider<TabsRepository>.value(value: widget.tabs),
        RepositoryProvider<ShellRepository>.value(value: widget.shell),
        RepositoryProvider<WorkbenchRepository>.value(
          value: widget.workbenches,
        ),
        RepositoryProvider<WorkspaceRepository>.value(value: widget.workspaces),
        RepositoryProvider<PathPicker>.value(value: widget.paths),
        RepositoryProvider<CanvasRepository>.value(value: widget.canvas),
        RepositoryProvider<ChatRepository>.value(value: widget.chat),
        RepositoryProvider<NodeRepositories>.value(value: widget.nodes),
        RepositoryProvider<AppRepository>.value(value: widget.app),
        RepositoryProvider<UsageRepository>.value(value: widget.usage),
        RepositoryProvider<ProcessesRepository>.value(value: widget.processes),
        RepositoryProvider<UiRequestRepository>.value(value: widget.uiRequests),
      ],
      child: BlocProvider.value(
        value: widget.connection,
        child: WidgetsApp(
          title: 'Egeon Deck',
          color: AppColors.background,
          textStyle: AppTheme.textStyle,
          builder: (context, _) => const HomePage(),
        ),
      ),
    );
  }
}

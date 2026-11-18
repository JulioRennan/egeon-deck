import 'package:egeon_deck/core/adapters/egeon_app_launcher.dart';
import 'package:egeon_deck/core/adapters/egeon_paths.dart';
import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/core/cubits/connection_cubit.dart';

import '../../support/connection_cubit_for.dart';

import 'package:egeon_deck/main.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_canvas_repository.dart';

import '../../support/fake_chat_repository.dart';
import '../../support/fake_app_repository.dart';
import '../../support/fake_processes_repository.dart';
import '../../support/fake_usage_repository.dart';
import '../../support/fake_agent_repository.dart';
import '../../support/in_memory_queue_repository.dart';
import '../../support/in_memory_web_repository.dart';
import '../../support/inject_fakes.dart';
import '../../support/fake_ui_request_repository.dart';
import '../../support/fake_path_picker.dart';
import '../../support/fake_shell_repository.dart';
import '../../support/fake_sidebar_repository.dart';
import '../../support/fake_tabs_repository.dart';
import '../../support/fake_terminal_repository.dart';
import '../../support/fake_workbench_repository.dart';
import '../../support/fake_workspace_repository.dart';
import '../../support/fake_transport.dart';

void main() {
  testWidgets(
    'conecta e, sem bancada, não abre terminal nenhum (como no Swift)',
    (tester) async {
      final transport = FakeTransport();
      final repository = FakeTerminalRepository();
      final shell = FakeShellRepository();
      late ConnectionCubit connection;

      await tester.runAsync(() async {
        connection = connectionCubitFor(
          EgeonAppLauncher(
            paths: EgeonPaths({'HOME': '/tmp/x'}),
            probe: transport,
          ),
          EgeonSocketClient(transport),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        transport.connections.last.upgrade();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      injectFakes(
        terminals: repository,
        sidebar: FakeSidebarRepository(),
        tabs: FakeTabsRepository(),
        shell: shell,
        workbenches: FakeWorkbenchRepository(),
        workspaces: FakeWorkspaceRepository(),
        paths: FakePathPicker(),
        canvas: InMemoryCanvasRepository(),
        chat: FakeChatRepository(),
        agent: (_) => FakeAgentRepository(),
        queue: (_) => InMemoryQueueRepository(),
        web: (_) => InMemoryWebRepository(),
        uiRequests: FakeUiRequestRepository(),
        app: FakeAppRepository(),
        usage: FakeUsageRepository(),
        processes: FakeProcessesRepository(const []),
      );
      await tester.pumpWidget(EgeonDeckApp(connection: connection));
      await tester.pump();
      await tester.pump();

      expect(find.byType(TerminalView), findsNothing);
      expect(repository.created, 0);
      await tester.runAsync(connection.close);
    },
  );
}

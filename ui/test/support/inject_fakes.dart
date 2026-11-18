import 'package:egeon_deck/core/adapters/injector.dart';
import 'package:egeon_deck/core/adapters/path_picker.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';
import 'package:egeon_deck/features/chat/domain/repository/chat_repository.dart';
import 'package:egeon_deck/features/home/domain/repository/shell_repository.dart';
import 'package:egeon_deck/features/home/domain/repository/ui_request_repository.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/agent_repository.dart';
import 'package:egeon_deck/features/node/queue/domain/repository/queue_repository.dart';
import 'package:egeon_deck/features/node/terminal/domain/repository/terminal_repository.dart';
import 'package:egeon_deck/features/node/web/domain/repository/web_repository.dart';
import 'package:egeon_deck/features/node/web/presentation/cubit/web_cubit.dart';
import 'package:egeon_deck/features/processes/domain/repository/processes_repository.dart';
import 'package:egeon_deck/features/sidebar/domain/repository/sidebar_repository.dart';
import 'package:egeon_deck/features/tabs/domain/repository/tabs_repository.dart';
import 'package:egeon_deck/features/update/domain/repository/app_repository.dart';
import 'package:egeon_deck/features/usage/domain/repository/usage_repository.dart';
import 'package:egeon_deck/features/workbench/domain/repository/workbench_repository.dart';
import 'package:egeon_deck/features/workspace/domain/repository/workspace_repository.dart';
import 'package:egeon_deck/core/di/injection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registra o domínio do app (usecases, cubits, registros da casca) sobre os
/// repositórios falsos dados, e zera o registro no fim do teste. Os de
/// bancada vêm por fábrica: recebem o id da bancada.
void injectFakes({
  TerminalRepository? terminals,
  SidebarRepository? sidebar,
  TabsRepository? tabs,
  ShellRepository? shell,
  WorkbenchRepository? workbenches,
  WorkspaceRepository? workspaces,
  PathPicker? paths,
  CanvasRepository? canvas,
  ChatRepository? chat,
  UiRequestRepository? uiRequests,
  AppRepository? app,
  UsageRepository? usage,
  ProcessesRepository? processes,
  AgentRepository Function(String workbenchId)? agent,
  QueueRepository Function(String workbenchId)? queue,
  WebRepository Function(String workbenchId)? web,
  WebControllerFactory? createWebController,
}) {
  registerDomain();
  void put<T extends Object>(T? fake) {
    if (fake != null) Injector.singleton<T>(fake);
  }

  put(terminals);
  put(sidebar);
  put(tabs);
  put(shell);
  put(workbenches);
  put(workspaces);
  put(paths);
  put(canvas);
  put(chat);
  put(uiRequests);
  put(app);
  put(usage);
  put(processes);
  put(createWebController);
  if (agent != null) Injector.factoryParam<AgentRepository, String>(agent);
  if (queue != null) Injector.factoryParam<QueueRepository, String>(queue);
  if (web != null) Injector.factoryParam<WebRepository, String>(web);
  addTearDown(Injector.reset);
}

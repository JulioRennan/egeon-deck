import 'package:egeon_deck/core/adapters/injector.dart';
import 'package:egeon_deck/core/adapters/clipboard_writer.dart';
import 'package:egeon_deck/core/adapters/path_picker.dart';
import 'package:egeon_deck/features/home/domain/repository/menu_repository.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';
import 'package:egeon_deck/features/chat/domain/repository/chat_repository.dart';
import 'package:egeon_deck/features/home/domain/repository/shell_repository.dart';
import 'package:egeon_deck/features/home/domain/repository/ui_request_repository.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/agent_repository.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/node_form_repository.dart';
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

import 'fake_chat_repository.dart';
import 'fake_menu.dart';
import 'fake_usage_repository.dart';

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
  NodeFormRepository? nodeForms,
  MenuRepository? menu,
  ClipboardWriter? clipboard,
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
  put<ChatRepository>(chat ?? FakeChatRepository());
  put(uiRequests);
  put(app);
  // Toda linha da barra lateral assina o consumo da sua bancada: sem falso
  // dado, um que nunca entrega nada.
  put<UsageRepository>(usage ?? FakeUsageRepository());
  put(processes);
  put(createWebController);
  put(nodeForms);
  // A casca sempre os pede (⇧⌘T): sem falso dado, um que não copia nada.
  put<MenuRepository>(menu ?? FakeMenuRepository());
  put<ClipboardWriter>(clipboard ?? FakeClipboard());
  if (agent != null) Injector.factoryParam<AgentRepository, String>(agent);
  if (queue != null) Injector.factoryParam<QueueRepository, String>(queue);
  if (web != null) Injector.factoryParam<WebRepository, String>(web);
  addTearDown(Injector.reset);
}

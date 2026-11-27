import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/utils/app_shortcut.dart';
import '../../../../commons/widgets/eg/menu.dart';
import '../../../../commons/widgets/eg/popover.dart';
import '../../../../core/domain/entities/view_mode.dart';
import '../../../canvas/domain/entities/canvas_tool.dart';
import '../../../update/domain/entities/app_snapshot.dart';
import '../../../update/presentation/cubit/update_cubit.dart';
import '../cubit/shell_cubit.dart';
import 'app_menu.dart';

/// O menu ☰ do cabeçalho da barra lateral: o que o menu do app é no macOS
/// (decisão 55), para o Windows e o Linux, que não têm barra de menus. Os
/// mesmos itens e as mesmas ações do [AppMenu]; o Editar fica de fora, porque
/// ali cada caixa de texto já tem o seu copiar e colar.
///
/// Precisa do [UpdateCubit] e do [ShellCubit] acima de [context].
void showAppOverflowMenu(
  BuildContext context,
  Rect anchor,
  AppMenuActions actions,
) {
  final cubit = context.read<UpdateCubit>();
  final inChat =
      context.read<ShellCubit>().state.snapshot.bench?.view == ViewMode.chat;
  final app = switch (cubit.state) {
    UpdateWaiting() => const AppSnapshot(),
    UpdateShown(:final app) => app,
  };
  showMenu(
    context,
    anchor: anchor,
    placement: PopoverPlacement.bottomEnd,
    width: 300,
    items: appOverflowItems(
      actions: actions,
      cubit: cubit,
      app: app,
      inChat: inChat,
    ),
  );
}

/// As linhas do ☰, na ordem do menu do macOS.
List<MenuElement> appOverflowItems({
  required AppMenuActions actions,
  required UpdateCubit cubit,
  required AppSnapshot app,
  required bool inChat,
}) {
  MenuItem item(
    String label,
    VoidCallback? onSelected, {
    String? shortcut,
    bool? checked,
  }) => MenuItem(
    label,
    onSelected: onSelected,
    shortcut: shortcut,
    checked: checked,
  );
  // Em chat o canvas não está na tela: ferramentas e zoom não se aplicam.
  VoidCallback? onCanvas(VoidCallback action) => inChat ? null : action;
  return [
    item(app.update.menu, app.update.menuEnabled ? cubit.pressMenu : null),
    item(
      'Atualizar automaticamente',
      () => cubit.setUpdateAuto(on: !app.update.auto),
      checked: app.update.auto,
    ),
    const MenuSeparator(),
    item('Aba à direita', actions.nextTab, shortcut: appShortcutLabel('→')),
    item(
      'Aba à esquerda',
      actions.previousTab,
      shortcut: appShortcutLabel('←'),
    ),
    item('Avançar', actions.forward, shortcut: appShortcutLabel(']')),
    item('Voltar', actions.back, shortcut: appShortcutLabel('[')),
    item('Fechar a aba', actions.closeTab, shortcut: appShortcutLabel('W')),
    const MenuSeparator(),
    item(
      'Copiar alvos de dispatch',
      actions.copyTargets,
      shortcut: appShortcutLabel('T', shift: true),
    ),
    item(
      'Processos…',
      actions.showProcesses,
      shortcut: appShortcutLabel('P', alt: true),
    ),
    item(
      'Limpar órfãos automaticamente',
      () => cubit.setReaperEnabled(on: !app.reaperEnabled),
      checked: app.reaperEnabled,
    ),
    const MenuSeparator(),
    item('Ver no canvas', actions.showCanvas),
    item('Ver como chat', actions.showChat),
    item(
      'Abrir ou fechar a gaveta de bancadas',
      actions.toggleSidebar,
      shortcut: appShortcutLabel('/'),
    ),
    item('Buscar bancada…', actions.findBench, shortcut: appShortcutLabel('K')),
    const MenuSeparator(),
    for (final (label, tool) in [
      ('Cursor', CanvasTool.cursor),
      ('Novo terminal', CanvasTool.agent),
      ('Novo web', CanvasTool.web),
      ('Nova fila', CanvasTool.queue),
    ])
      item(label, onCanvas(() => actions.canvas.selectTool(tool))),
    const MenuSeparator(),
    item(
      'Aproximar',
      onCanvas(actions.canvas.zoomIn),
      shortcut: appShortcutLabel('='),
    ),
    item(
      'Afastar',
      onCanvas(actions.canvas.zoomOut),
      shortcut: appShortcutLabel('−'),
    ),
    item(
      'Zoom 100%',
      onCanvas(actions.canvas.resetZoom),
      shortcut: appShortcutLabel('0'),
    ),
    item('Enquadrar tudo', onCanvas(actions.canvas.fitAll)),
  ];
}

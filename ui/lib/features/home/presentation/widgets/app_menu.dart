import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/adapters/native_edit.dart';
import '../../../../core/domain/entities/view_mode.dart';
import '../../../canvas/domain/entities/canvas_tool.dart';
import '../../../canvas/presentation/cubit/canvas_commands.dart';
import '../../../update/domain/entities/app_snapshot.dart';
import '../../../update/presentation/cubit/update_cubit.dart';
import '../cubit/shell_cubit.dart';

/// O que o menu do app faz na casca: os mesmos gestos dos atalhos.
///
/// Os atalhos moram também nos itens, como os key equivalents do Swift: com o
/// foco na Flutter quem atende primeiro é o `ShellShortcuts` (o terminal e as
/// caixas de texto ficam com as teclas delas, e a tecla atendida não chega ao
/// menu, como o ⌘C/⌘V do menu Editar). O menu pega o que a Flutter não
/// atendeu: o nó web focado, a janela sem foco nenhum, o painel de Processos.
class AppMenuActions {
  const AppMenuActions({
    required this.showCanvas,
    required this.showChat,
    required this.toggleSidebar,
    required this.nextTab,
    required this.previousTab,
    required this.closeTab,
    required this.showProcesses,
    required this.canvas,
    this.pickTab,
    this.copyTargets,
    this.edit = const ChannelNativeEdit(),
  });

  final VoidCallback showCanvas;
  final VoidCallback showChat;
  final VoidCallback toggleSidebar;
  final VoidCallback nextTab;
  final VoidCallback previousTab;
  final VoidCallback closeTab;
  final VoidCallback showProcesses;

  /// ⌘1…⌘9: a aba de número n (a primeira é 1).
  final ValueChanged<int>? pickTab;

  /// "Copiar alvos de dispatch" (⇧⌘T).
  final VoidCallback? copyTargets;

  /// Ferramentas e zoom do canvas ao vivo (sem canvas, não fazem nada).
  final CanvasCommands canvas;

  /// O menu Editar, para a cadeia de responders do macOS.
  final NativeEdit edit;
}

/// A barra de menus do macOS: o menu do app com a atualização (o título e o
/// estado do item vêm prontos do core) e a limpeza de órfãos, e o menu Canvas.
/// O AppKit não desenha marca de seleção num item da Flutter, então o ligado
/// leva um ✓ no título.
class AppMenu extends StatelessWidget {
  const AppMenu({
    required this.name,
    required this.actions,
    required this.child,
    super.key,
  });

  final String name;
  final AppMenuActions actions;
  final Widget child;

  /// Os itens que o sistema fornece só existem no macOS; em outra plataforma
  /// (os testes) a lista fica sem eles em vez de falhar.
  static List<PlatformMenuItem> _provided(PlatformProvidedMenuItemType type) =>
      PlatformProvidedMenuItem.hasMenu(type)
      ? [PlatformProvidedMenuItem(type: type)]
      : const [];

  /// Um grupo sem membros quebra a barra, e no que não é macOS os itens do
  /// sistema não existem.
  static List<PlatformMenuItem> _group(List<PlatformMenuItem> members) =>
      members.isEmpty ? const [] : [PlatformMenuItemGroup(members: members)];

  /// O item do menu Editar: o atalho padrão do macOS, e a ação vai à cadeia de
  /// responders — onde a página web a atende. Campo de texto e terminal tratam
  /// ⌘C/⌘V em Dart antes de o menu ver a tecla.
  PlatformMenuItem _edit(
    String label,
    EditAction action,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) => PlatformMenuItem(
    label: label,
    shortcut: SingleActivator(key, meta: true, shift: shift),
    onSelected: () => unawaited(actions.edit.send(action)),
  );

  static SingleActivator _meta(
    LogicalKeyboardKey key, {
    bool alt = false,
    bool shift = false,
  }) => SingleActivator(key, meta: true, alt: alt, shift: shift);

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  static String _check(String title, {required bool on}) =>
      on ? '✓ $title' : title;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UpdateCubit>();
    // Em chat o canvas não está na tela: as ferramentas e o zoom não se aplicam.
    final inChat = context.select(
      (ShellCubit shell) => shell.state.snapshot.bench?.view == ViewMode.chat,
    );
    return BlocBuilder<UpdateCubit, UpdateState>(
      builder: (context, state) => _menuBar(cubit, inChat, switch (state) {
        UpdateWaiting() => const AppSnapshot(),
        UpdateShown(:final app) => app,
      }),
    );
  }

  Widget _menuBar(
    UpdateCubit cubit,
    bool inChat,
    AppSnapshot app,
  ) => PlatformMenuBar(
    menus: [
      PlatformMenu(
        label: name,
        menus: [
          PlatformMenuItemGroup(
            members: [
              ..._provided(PlatformProvidedMenuItemType.about),
              PlatformMenuItem(
                label: app.update.menu,
                onSelected: app.update.menuEnabled ? cubit.pressMenu : null,
              ),
              PlatformMenuItem(
                label: _check('Atualizar automaticamente', on: app.update.auto),
                onSelected: () => cubit.setUpdateAuto(on: !app.update.auto),
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Aba à direita',
                shortcut: _meta(LogicalKeyboardKey.arrowRight),
                onSelected: actions.nextTab,
              ),
              PlatformMenuItem(
                label: 'Aba à esquerda',
                shortcut: _meta(LogicalKeyboardKey.arrowLeft),
                onSelected: actions.previousTab,
              ),
              // No Swift estes dois e os "Aba n" são itens escondidos; a barra
              // da Flutter não esconde item, então eles aparecem.
              PlatformMenuItem(
                label: 'Próxima bancada',
                shortcut: _meta(LogicalKeyboardKey.bracketRight),
                onSelected: actions.nextTab,
              ),
              PlatformMenuItem(
                label: 'Bancada anterior',
                shortcut: _meta(LogicalKeyboardKey.bracketLeft),
                onSelected: actions.previousTab,
              ),
              PlatformMenuItem(
                label: 'Fechar a aba',
                shortcut: _meta(LogicalKeyboardKey.keyW),
                onSelected: actions.closeTab,
              ),
              PlatformMenu(
                label: 'Ir para a aba',
                menus: [
                  for (var n = 1; n <= 9; n++)
                    PlatformMenuItem(
                      label: 'Aba $n',
                      shortcut: _meta(_digits[n - 1]),
                      onSelected: switch (actions.pickTab) {
                        final pick? => () => pick(n),
                        null => null,
                      },
                    ),
                ],
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Copiar alvos de dispatch',
                shortcut: _meta(LogicalKeyboardKey.keyT, shift: true),
                onSelected: actions.copyTargets,
              ),
              PlatformMenuItem(
                label: 'Processos…',
                shortcut: _meta(LogicalKeyboardKey.keyP, alt: true),
                onSelected: actions.showProcesses,
              ),
              PlatformMenuItem(
                label: _check(
                  'Limpar órfãos automaticamente',
                  on: app.reaperEnabled,
                ),
                onSelected: () =>
                    cubit.setReaperEnabled(on: !app.reaperEnabled),
              ),
            ],
          ),
          ..._group([
            ..._provided(PlatformProvidedMenuItemType.servicesSubmenu),
            ..._provided(PlatformProvidedMenuItemType.hide),
            ..._provided(PlatformProvidedMenuItemType.hideOtherApplications),
            ..._provided(PlatformProvidedMenuItemType.showAllApplications),
          ]),
          ..._group(_provided(PlatformProvidedMenuItemType.quit)),
        ],
      ),
      PlatformMenu(
        label: 'Editar',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _edit('Desfazer', EditAction.undo, LogicalKeyboardKey.keyZ),
              _edit(
                'Refazer',
                EditAction.redo,
                LogicalKeyboardKey.keyZ,
                shift: true,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              _edit('Recortar', EditAction.cut, LogicalKeyboardKey.keyX),
              _edit('Copiar', EditAction.copy, LogicalKeyboardKey.keyC),
              _edit('Colar', EditAction.paste, LogicalKeyboardKey.keyV),
              _edit(
                'Selecionar tudo',
                EditAction.selectAll,
                LogicalKeyboardKey.keyA,
              ),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Canvas',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Ver no canvas',
                shortcut: _meta(LogicalKeyboardKey.digit1, alt: true),
                onSelected: actions.showCanvas,
              ),
              PlatformMenuItem(
                label: 'Ver como chat',
                shortcut: _meta(LogicalKeyboardKey.digit2, alt: true),
                onSelected: actions.showChat,
              ),
              PlatformMenuItem(
                label: 'Recolher a barra de bancadas',
                shortcut: _meta(LogicalKeyboardKey.slash),
                onSelected: actions.toggleSidebar,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              for (final (label, tool) in [
                ('Cursor', CanvasTool.cursor),
                ('Novo terminal', CanvasTool.terminal),
                ('Novo web', CanvasTool.web),
                ('Nova fila', CanvasTool.queue),
              ])
                PlatformMenuItem(
                  label: label,
                  onSelected: inChat
                      ? null
                      : () => actions.canvas.selectTool(tool),
                ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Aproximar',
                shortcut: _meta(LogicalKeyboardKey.equal),
                onSelected: inChat ? null : actions.canvas.zoomIn,
              ),
              PlatformMenuItem(
                label: 'Afastar',
                shortcut: _meta(LogicalKeyboardKey.minus),
                onSelected: inChat ? null : actions.canvas.zoomOut,
              ),
              PlatformMenuItem(
                label: 'Zoom 100%',
                shortcut: _meta(LogicalKeyboardKey.digit0),
                onSelected: inChat ? null : actions.canvas.resetZoom,
              ),
              PlatformMenuItem(
                label: 'Enquadrar tudo',
                onSelected: inChat ? null : actions.canvas.fitAll,
              ),
            ],
          ),
        ],
      ),
      if (_group([
        ..._provided(PlatformProvidedMenuItemType.minimizeWindow),
        ..._provided(PlatformProvidedMenuItemType.zoomWindow),
        ..._provided(PlatformProvidedMenuItemType.toggleFullScreen),
      ]).isNotEmpty)
        PlatformMenu(
          label: 'Janela',
          menus: _group([
            ..._provided(PlatformProvidedMenuItemType.minimizeWindow),
            ..._provided(PlatformProvidedMenuItemType.zoomWindow),
            ..._provided(PlatformProvidedMenuItemType.toggleFullScreen),
          ]),
        ),
    ],
    child: child,
  );
}

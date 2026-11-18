import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/screen_captures.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../core/adapters/png_file.dart' as png_file;
import '../../../../core/adapters/window_frame.dart';
import '../../../../core/domain/entities/view_mode.dart';
import '../../../../core/domain/entities/workbench.dart';
import '../../../canvas/domain/entities/canvas_probe.dart';
import '../../../canvas/presentation/cubit/canvas_commands.dart';
import '../../../sidebar/presentation/cubit/sidebar_cubit.dart';
import '../../../sidebar/presentation/page/sidebar_page.dart';
import '../../../sidebar/presentation/widgets/sidebar_panel.dart';
import '../../../tabs/presentation/cubit/tabs_cubit.dart';
import '../../../tabs/presentation/page/tabs_page.dart';
import '../cubit/shell_cubit.dart';
import '../cubit/ui_request_cubit.dart';
import '../forms/app_forms.dart';
import '../forms/form_request.dart';
import '../../../update/presentation/widgets/update_host.dart';
import '../../../processes/presentation/widgets/processes_panel.dart';
import '../widgets/app_menu.dart';
import '../widgets/usage_corner.dart';
import '../widgets/root_layout.dart';
import '../widgets/shell_shortcuts.dart';
import '../widgets/shell_curtains.dart';
import '../widgets/view_toolbar.dart';
import '../widgets/workbench_shell.dart';
import 'shell_screen_control.dart';

/// Atende um pedido de formulário. [context] está abaixo do `Overlay` da casca,
/// que é onde as janelas se abrem.
typedef FormsHandler = FutureOr<void> Function(
  BuildContext context,
  FormRequest request,
);

/// A casca do app: barra lateral, barra de cima, faixa de abas e o conteúdo da
/// bancada — canvas ou chat. Só compõe; as janelas se abrem por [onForm].
class HomeShellPage extends StatefulWidget {
  const HomeShellPage({
    required this.canvas,
    required this.chat,
    this.onForm = handleForm,
    this.appName = 'EgeonDeck Next',
    this.window = const ChannelWindowFrame(),
    this.activator = const ChannelWindowFrame(),
    this.writePng = png_file.writePng,
    super.key,
  });

  /// O conteúdo de cada modo. Quem é dono de cada um é a feature dele.
  final Widget Function(BuildContext context, Workbench? bench) canvas;
  final Widget Function(BuildContext context, Workbench bench) chat;
  final FormsHandler onForm;

  /// O título do menu do app.
  final String appName;

  /// De onde vem a posição da janela, e como o PNG vai ao disco: o teste troca.
  final WindowFrameSource window;
  final WindowActivator activator;
  final Future<void> Function(String path, Uint8List png) writePng;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  late final OverlayEntry _entry = OverlayEntry(builder: _build);
  final _captures = ScreenCaptures();

  @override
  void didUpdateWidget(HomeShellPage old) {
    super.didUpdateWidget(old);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    super.dispose();
  }

  // Os cubits da casca nascem com ela, não quando alguém os lê: as assinaturas
  // e os pedidos de tela do core precisam estar abertos desde o começo.
  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(lazy: false, create: (_) => inject<ShellCubit>()),
      BlocProvider(lazy: false, create: (_) => inject<TabsCubit>()),
      BlocProvider(lazy: false, create: (_) => inject<SidebarCubit>()),
      BlocProvider(
        lazy: false,
        create: (context) => inject<UiRequestCubit>((
          screen: ShellScreenControl(
            shell: context.read<ShellCubit>(),
            sidebar: context.read<SidebarCubit>(),
            captures: _captures,
            window: widget.window,
            writePng: widget.writePng,
            canvas: () => inject<CanvasProbeRegistry>().active,
          ),
          activate: widget.activator.activate,
        )),
      ),
    ],
    child: Overlay(initialEntries: [_entry]),
  );

  /// Roda abaixo do `Overlay`: é este `context` que as janelas usam.
  Widget _build(BuildContext overlayContext) {
    final shell = overlayContext.read<ShellCubit>();
    final tabs = overlayContext.read<TabsCubit>();
    return UpdateHost(
      dialogContext: () => overlayContext,
      onShowProcesses: () => unawaited(showProcessesPanel(overlayContext)),
      child: AppMenu(
        name: widget.appName,
        actions: AppMenuActions(
          showCanvas: () => shell.setView(ViewMode.canvas),
          showChat: () => shell.setView(ViewMode.chat),
          toggleSidebar: shell.toggleCollapsed,
          nextTab: tabs.next,
          previousTab: tabs.previous,
          closeTab: tabs.closeActive,
          showProcesses: () => unawaited(showProcessesPanel(overlayContext)),
          canvas: inject<CanvasCommands>(),
        ),
        child: BlocBuilder<ShellCubit, ShellState>(
          builder: (context, view) {
            final bench = view.snapshot.bench;
            final mode = bench?.view ?? ViewMode.canvas;
            final busy = view.snapshot.busy;
            final lock = view.snapshot.lock;
            void ask(FormRequest request) =>
                widget.onForm(overlayContext, request);
            final layout = RootLayout(
              collapsed: view.collapsed,
              beside: mode == ViewMode.chat,
              sidebar: RepaintBoundary(
                key: _captures.keyFor('sidebar'),
                child: SidebarPage(
                  compact: view.collapsed,
                  commands: _commands(shell, ask),
                ),
              ),
              shell: (contentInset, tabsInset) => WorkbenchShell(
                contentInset: contentInset,
                toolbar: ViewToolbar(
                  bench: bench,
                  trailing: bench == null
                      ? null
                      : UsageCorner(workbenchId: bench.id),
                  onSelect: shell.setView,
                  onPickColor: () {
                    if (bench != null) {
                      ask(
                        RecolorBench(
                          bench.id,
                          bench.name,
                          current: bench.color,
                        ),
                      );
                    }
                  },
                ),
                tabs: TabsPage(leftInset: tabsInset),
                content: bench != null && mode == ViewMode.chat
                    ? widget.chat(context, bench)
                    : widget.canvas(context, bench),
                curtains: [
                  if (busy != null) BusyCurtain(busy),
                  if (lock != null)
                    AccessCurtain(
                      lock: lock,
                      onOpenSettings: shell.openSettings,
                      onAskAgain: shell.askAccessAgain,
                    ),
                ],
              ),
            );
            // Os atalhos valem enquanto o foco estiver dentro da casca (o terminal, o
            // composer…); o terminal, quando focado, deixa passar tudo o que tem ⌘.
            return ShellShortcuts(
              actions: ShellShortcutActions(
                toggleSidebar: shell.toggleCollapsed,
                showView: shell.setView,
                nextTab: tabs.next,
                previousTab: tabs.previous,
                closeTab: tabs.closeActive,
                pickTab: tabs.selectNumber,
              ),
              child: RepaintBoundary(
                key: _captures.keyFor('window'),
                child: layout,
              ),
            );
          },
        ),
      ),
    );
  }

  SidebarCommands _commands(
    ShellCubit cubit,
    void Function(FormRequest) onForm,
  ) => SidebarCommands(
    onToggleCollapse: cubit.toggleCollapsed,
    onCreateWorkspace: () => onForm(const NewWorkspace()),
    onCreateBench: () => onForm(const NewBench()),
    onCreateBenchFromWorktree: () => onForm(const NewBench(fromWorktree: true)),
    onCreateBenchIn: (p) => onForm(NewBench(projectId: p.id, path: p.path)),
    onCreateBenchFromWorktreeIn: (p) =>
        onForm(NewBench(projectId: p.id, path: p.path, fromWorktree: true)),
    onEditWorkspace: (ws) => onForm(EditWorkspace(ws.id, ws.name)),
    onCreateProject: (ws) => onForm(NewProject(ws.id, ws.name)),
    onRemoveWorkspace: (ws) => onForm(RemoveWorkspace(ws.id, ws.name)),
    onRemoveProject: (ws, project) => onForm(
      RemoveProject(
        workspaceId: ws.id,
        workspaceName: ws.name,
        projectId: project.id,
        projectName: project.name,
        projectPath: project.path,
      ),
    ),
    onRename: (b) => onForm(RenameBench(b.id, b.name)),
    onDuplicateAsWorktree: (b) => onForm(DuplicateBench(b.id, b.name)),
    onEditRules: (b) => onForm(EditBenchRules(b.id, b.name)),
    onRecolor: (b) => onForm(RecolorBench(b.id, b.name, current: b.color)),
    onClear: (b) => onForm(ClearBench(b.id, b.name)),
    onRemove: (b) => onForm(RemoveBench(b.id, b.name)),
  );
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/screen_captures.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../core/adapters/png_file.dart' as png_file;
import '../../../../core/adapters/window_chrome.dart';
import '../../../../core/adapters/window_frame.dart';
import '../../../../core/domain/entities/view_mode.dart';
import '../../../../core/domain/entities/workbench.dart';
import '../../../canvas/domain/entities/canvas_probe.dart';
import '../../../canvas/presentation/cubit/canvas_commands.dart';
import '../../../sidebar/domain/usecase/copy_project_path.dart';
import '../../../sidebar/presentation/cubit/sidebar_cubit.dart';
import '../../../sidebar/presentation/page/sidebar_page.dart';
import '../../../tabs/presentation/cubit/tabs_cubit.dart';
import '../cubit/navigation_cubit.dart';
import '../cubit/shell_cubit.dart';
import '../cubit/ui_request_cubit.dart';
import '../forms/app_forms.dart';
import '../forms/form_request.dart';
import '../../../update/presentation/widgets/update_host.dart';
import '../../../processes/presentation/widgets/processes_panel.dart';
import '../widgets/app_menu.dart';
import '../../../../commons/widgets/shell_layers.dart';
import '../widgets/usage_corner.dart';
import '../widgets/root_layout.dart';
import '../widgets/shell_shortcuts.dart';
import '../widgets/shell_curtains.dart';
import '../../../sidebar/presentation/widgets/sidebar_commands.dart';
import '../widgets/bench_drawer.dart';
import '../widgets/drawer_hover.dart';
import '../widgets/bench_rail.dart';
import '../widgets/top_bar.dart';
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
    this.title = 'Egeon Deck',
    this.window = const ChannelWindowFrame(),
    this.chrome = const ChannelWindowChrome(),
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

  /// O nome do flavor, para os títulos que dizem de qual app é (Processos).
  final String title;

  /// De onde vem a posição da janela, e como o PNG vai ao disco: o teste troca.
  final WindowFrameSource window;
  final WindowChrome chrome;
  final WindowActivator activator;
  final Future<void> Function(String path, Uint8List png) writePng;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  late final OverlayEntry _entry = OverlayEntry(builder: _build);
  final _captures = ScreenCaptures();

  /// O grupo do clique fora da gaveta: o botão do trilho que a abre é dele.
  final _drawerGroup = Object();

  /// Lido na hora: o cubit da casca nasce abaixo deste estado.
  late final _drawerHover = DrawerHover(
    onOpen: () => _shellContext?.read<ShellCubit>().peek(),
    onClose: () => _shellContext?.read<ShellCubit>().endPeek(),
  );
  BuildContext? _shellContext;

  @override
  void didUpdateWidget(HomeShellPage old) {
    super.didUpdateWidget(old);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _drawerHover.dispose();
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
      BlocProvider(lazy: false, create: (_) => inject<NavigationCubit>()),
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

  /// ⌘K: abre a gaveta e pede à barra que abra a busca.
  void _findBench(ShellCubit shell, SidebarCubit sidebar) {
    shell.setCollapsed(false);
    sidebar.requestFind();
  }

  /// Roda abaixo do `Overlay`: é este `context` que as janelas usam.
  Widget _build(BuildContext overlayContext) {
    _shellContext = overlayContext;
    final shell = overlayContext.read<ShellCubit>();
    final tabs = overlayContext.read<TabsCubit>();
    final navigation = overlayContext.read<NavigationCubit>();
    final sidebar = overlayContext.read<SidebarCubit>();
    return UpdateHost(
      dialogContext: () => overlayContext,
      onShowProcesses: () =>
          unawaited(showProcessesWindow(appName: widget.title)),
      child: AppMenu(
        name: widget.appName,
        actions: AppMenuActions(
          showCanvas: () => shell.setView(ViewMode.canvas),
          showChat: () => shell.setView(ViewMode.chat),
          toggleSidebar: shell.toggleCollapsed,
          findBench: () => _findBench(shell, sidebar),
          nextTab: tabs.next,
          previousTab: tabs.previous,
          back: navigation.back,
          forward: navigation.forward,
          closeTab: tabs.closeActive,
          pickTab: tabs.selectNumber,
          showProcesses: () =>
              unawaited(showProcessesWindow(appName: widget.title)),
          canvas: inject<CanvasCommands>(),
          copyTargets: shell.copyTargets,
        ),
        child: BlocBuilder<ShellCubit, ShellState>(
          builder: (context, view) {
            final bench = view.snapshot.bench;
            final mode = bench?.view ?? ViewMode.canvas;
            final busy = view.snapshot.busy;
            final banner = view.snapshot.banner;
            final lock = view.snapshot.lock;
            final collapsed = view is ShellCollapsed;
            void ask(FormRequest request) =>
                widget.onForm(overlayContext, request);
            final layout = RootLayout(
              collapsed: collapsed,
              beside: mode == ViewMode.chat,
              rail: BlocBuilder<TabsCubit, TabsState>(
                builder: (context, tabsState) => BenchRail(
                  tabs: tabsState.tabs,
                  drawerOpen: !collapsed,
                  drawerGroup: _drawerGroup,
                  drawerHover: _drawerHover,
                  // Reflexo da aba Ativas: a ordem e quem entra são do core,
                  // então o trilho não reordena nem fecha.
                  onPick: tabs.select,
                  onNew: () => ask(const NewBench()),
                  onToggleDrawer: shell.toggleCollapsed,
                ),
              ),
              drawer: BenchDrawer(
                open: !collapsed,
                group: _drawerGroup,
                hover: _drawerHover,
                onClose: () => shell.setCollapsed(true),
                child: RepaintBoundary(
                  key: _captures.keyFor('sidebar'),
                  child: SidebarPage(
                    commands: _commands(shell, ask),
                    onCollapse: () => shell.setCollapsed(true),
                  ),
                ),
              ),
              shell: (frameLeft) => WorkbenchShell(
                leftInset: frameLeft,
                colorName: bench?.color,
                lit: bench != null,
                topBar: BlocBuilder<NavigationCubit, NavigationState>(
                  builder: (context, history) => TopBar(
                    bench: bench,
                    projectName: view.snapshot.projectName,
                    chrome: widget.chrome,
                    canGoBack: history.canGoBack,
                    canGoForward: history.canGoForward,
                    onBack: navigation.back,
                    onForward: navigation.forward,
                    onSelectView: shell.setView,
                    onPickBench: shell.toggleCollapsed,
                  ),
                ),
                // O consumo no canto, no canvas e no chat: a camada fixa do canto.
                layers: bench == null
                    ? null
                    : ShellLayers(
                        corner: UsageCorner(
                          workbenchId: bench.id,
                          clock: view.snapshot.clock,
                        ),
                      ),
                content: bench != null && mode == ViewMode.chat
                    ? widget.chat(context, bench)
                    : widget.canvas(context, bench),
                curtains: [
                  if (banner != null)
                    ShellBanner(
                      banner,
                      top: mode == ViewMode.canvas
                          ? ShellBanner.belowCanvasBars
                          : ShellBanner.chatTop,
                    ),
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
            // Com o foco na casca (o terminal, o composer…) os atalhos chegam
            // aqui primeiro — o terminal deixa passar tudo o que tem ⌘. Sem foco
            // na Flutter (o nó web) quem atende é o mesmo atalho no menu.
            return ShellShortcuts(
              actions: ShellShortcutActions(
                toggleSidebar: shell.toggleCollapsed,
                findBench: () => _findBench(shell, sidebar),
                showView: shell.setView,
                nextTab: tabs.next,
                previousTab: tabs.previous,
                back: navigation.back,
                forward: navigation.forward,
                closeTab: tabs.closeActive,
                pickTab: tabs.selectNumber,
                copyTargets: shell.copyTargets,
                showProcesses: () =>
                    unawaited(showProcessesWindow(appName: widget.title)),
                zoomIn: inject<CanvasCommands>().zoomIn,
                zoomOut: inject<CanvasCommands>().zoomOut,
                resetZoom: inject<CanvasCommands>().resetZoom,
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
    onSaveAsTemplate: (b) => onForm(SaveAsTemplate(b.id, b.name)),
    onCopyPath: (p) => unawaited(inject<CopyProjectPath>()(p.path)),
  );
}

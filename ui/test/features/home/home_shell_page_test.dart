import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:egeon_deck/commons/utils/app_shortcut.dart';
import 'package:egeon_deck/core/adapters/app_windows.dart';
import 'package:egeon_deck/commons/widgets/form_kit.dart';

import 'package:egeon_deck/commons/utils/bench_identity.dart';
import 'package:egeon_deck/commons/widgets/eg/menu.dart';
import 'package:egeon_deck/commons/widgets/eg/toast.dart';
import 'package:egeon_deck/core/adapters/injector.dart';
import 'package:egeon_deck/core/adapters/window_frame.dart';
import 'package:egeon_deck/core/domain/entities/view_mode.dart';
import 'package:egeon_deck/core/domain/entities/workbench.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_probe.dart'
    hide WindowFrame;
import 'package:egeon_deck/features/canvas/domain/entities/canvas_probe.dart'
    as canvas
    show WindowFrame;
import 'package:egeon_deck/features/chat/presentation/page/chat_page.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_composer.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/participants_column.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_tool.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_bench_actions.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_toolbar.dart';
import 'package:egeon_deck/features/usage/domain/usecase/watch_usage.dart';
import 'package:egeon_deck/features/usage/presentation/cubit/usage_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:egeon_deck/features/home/domain/entities/shell_snapshot.dart';
import 'package:egeon_deck/features/home/domain/entities/ui_request.dart';
import 'package:egeon_deck/features/home/presentation/forms/form_request.dart';
import 'package:egeon_deck/features/home/presentation/page/home_shell_page.dart';
import 'package:egeon_deck/features/home/presentation/widgets/bench_drawer.dart';
import 'package:egeon_deck/features/home/presentation/widgets/drawer_hover.dart';
import 'package:egeon_deck/features/home/presentation/widgets/bench_rail.dart';
import 'package:egeon_deck/features/home/presentation/widgets/root_layout.dart';
import 'package:egeon_deck/features/home/presentation/widgets/workbench_shell.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/features/home/presentation/widgets/top_bar.dart';
import 'package:egeon_deck/commons/widgets/shell_layers.dart';
import 'package:egeon_deck/core/domain/entities/workbench_clock.dart';
import 'package:egeon_deck/features/usage/domain/entities/usage_view.dart';
import 'package:egeon_deck/features/usage/presentation/widgets/usage_chip.dart';
import 'package:egeon_deck/features/update/domain/entities/app_snapshot.dart';
import 'package:egeon_deck/features/sidebar/presentation/widgets/sidebar_panel.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_tab.dart';
import 'package:egeon_deck/features/tabs/domain/entities/workbench_tab.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/chat_fixtures.dart';
import '../../support/fake_agent_repository.dart';
import '../../support/fake_chat_repository.dart';
import '../../support/fake_terminal_repository.dart';
import '../../support/fake_shell_repository.dart';
import '../../support/fake_sidebar_repository.dart';
import '../../support/hand_cursor.dart';
import '../../support/inject_fakes.dart';
import '../../support/fake_app_repository.dart';
import '../../support/fake_menu.dart';
import '../../support/fake_processes_repository.dart';
import '../../support/fake_usage_repository.dart';
import '../../support/fake_tabs_repository.dart';
import '../../support/fake_ui_request_repository.dart';
import '../../support/eg_host.dart';
import '../../support/sidebar_fixtures.dart';

const bench = Workbench(
  id: 'b1',
  name: 'deck',
  path: '~/code/deck',
  color: 'blue',
);

class _FixedWindow implements WindowFrameSource {
  const _FixedWindow();

  @override
  Future<WindowFrame> read() async => const WindowFrame(
    x: 10,
    y: 20,
    width: 1000,
    height: 800,
    screenHeight: 1000,
  );
}

class _FakeActivator implements WindowActivator {
  var calls = 0;

  @override
  Future<void> activate() async => calls++;
}

class Shell {
  Shell({this.content, this.chat}) {
    injectFakes(
      shell: shell,
      sidebar: sidebar,
      tabs: tabs,
      uiRequests: requests,
      app: app,
      usage: usage,
      processes: FakeProcessesRepository(const []),
      menu: menu,
      clipboard: clipboard,
      windows: windows,
      chat: chatRepository,
      terminals: FakeTerminalRepository(),
      agent: (_) => FakeAgentRepository(),
    );
  }

  final chatRepository = FakeChatRepository();

  final menu = FakeMenuRepository('deck/claude\ndeck/sh');
  final clipboard = FakeClipboard();
  final windows = FakeAppWindows();

  /// O que ocupa o lugar do canvas; sem isso, um texto.
  final Widget? content;

  /// O que ocupa o lugar do chat; sem isso, um texto.
  final Widget? chat;

  final shell = FakeShellRepository();
  final sidebar = FakeSidebarRepository();
  final tabs = FakeTabsRepository();
  final requests = FakeUiRequestRepository();
  final app = FakeAppRepository();
  final activator = _FakeActivator();
  final usage = FakeUsageRepository();
  final menus = <String>[];
  final pngs = <String, Uint8List>{};
  final forms = <FormRequest>[];

  Widget build() => egHost(
    fill: true,
    HomeShellPage(
      canvas: (_, _) =>
          content ??
          const Focus(
            autofocus: true,
            child: Text('CANVAS', key: ValueKey('canvas')),
          ),
      chat: (_, _) => chat ?? const Text('CHAT', key: ValueKey('chat')),
      onForm: (_, request) => forms.add(request),
      window: const _FixedWindow(),
      activator: activator,
      writePng: (path, png) async => pngs[path] = png,
    ),
  );

  Future<void> show(WidgetTester tester, ShellSnapshot state) async {
    shell.push(state);
    sidebar.push(sampleTree());
    await tester.pump();
    await tester.pump();
  }
}

/// Deixa a gaveta terminar de abrir ou fechar: a animação de 200 ms só começa
/// no primeiro quadro, e a troca do AnimatedSwitcher acaba num quadro a mais.
Future<void> settleDrawer(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

/// Abre a gaveta de bancadas pelo botão do trilho e espera os 200 ms.
Future<void> openDrawer(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Todas as bancadas'));
  await settleDrawer(tester);
}

/// Monta a casca. Com [drawer] (o padrão) a gaveta já está aberta, que é onde
/// a barra lateral mora; sem ele, só o trilho.
Future<Shell> mount(
  WidgetTester tester, [
  ShellSnapshot? state,
  bool drawer = true,
]) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Há teste que monta a casca mais de uma vez: cada uma com o seu registro.
  await Injector.reset();
  final s = Shell();
  await tester.pumpWidget(s.build());
  await s.show(tester, state ?? const ShellSnapshot(bench: bench));
  if (drawer) await openDrawer(tester);
  return s;
}

Workbench _bench(String id) => Workbench(id: id, name: id, path: '~');

/// A casca com três abas, a do meio na frente.
Future<Shell> withTabs(WidgetTester tester) async {
  final s = await mount(tester);
  s.tabs.push([
    const WorkbenchTab(id: 'a', name: 'a'),
    const WorkbenchTab(id: 'b', name: 'b', isActive: true),
    const WorkbenchTab(id: 'c', name: 'c'),
  ]);
  await tester.pump();
  await tester.pump();
  return s;
}

/// O que a casca mandou ao AppKit pelo canal de menu, uma entrada por envio.
final menuCalls = <String>[];

/// O último menu mandado, como o AppKit o recebe.
Object? menuSent;

/// O item de menu com [label], em qualquer nível.
Map<Object?, Object?>? menuItem(Object? node, String label) {
  if (node is Map) {
    if (node['label'] == label) return node;
    for (final value in node.values) {
      final found = menuItem(value, label);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      final found = menuItem(value, label);
      if (found != null) return found;
    }
  }
  return null;
}

/// O AppKit avisando que o item foi escolhido — pelo clique ou pelo key
/// equivalent, sem passar pelo foco da Flutter.
Future<void> chooseMenu(WidgetTester tester, String label) async {
  final id = menuItem(menuSent, label)!['id'];
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.menu.name,
    SystemChannels.menu.codec.encodeMethodCall(
      MethodCall('Menu.selectedCallback', id),
    ),
    (_) {},
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    menuCalls.clear();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, (call) async {
          if (call.method == 'Menu.setMenus') {
            menuCalls.add('${call.arguments}');
            menuSent = call.arguments;
          }
          return null;
        });
  });
  tearDown(
    () => TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, null),
  );

  // Porte de WorkbenchShellLayoutTests.swift: a barra de cima é a faixa da
  // titlebar, corre de borda a borda em todo modo; só o conteúdo cede.
  testWidgets('a barra corre de borda a borda em todo modo', (tester) async {
    for (final mode in ViewMode.values) {
      final s = await mount(
        tester,
        ShellSnapshot(
          bench: Workbench(id: 'b1', name: 'deck', path: '~', view: mode),
        ),
      );
      expect(
        tester.getRect(find.byType(TopBar)),
        const Rect.fromLTWH(0, 0, 1000, TopBar.height),
        reason: 'modo ${mode.wire}',
      );
      expect(s.shell.watchers, 2);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a gaveta empurra o conteúdo no chat e cobre o canvas', (
    tester,
  ) async {
    await mount(
      tester,
      const ShellSnapshot(
        bench: Workbench(id: 'b', name: 'd', path: '~', view: ViewMode.chat),
      ),
    );
    // No chat a gaveta aberta fica ao lado: sobreposição é mensagem coberta.
    final chat = tester.getRect(find.byKey(const ValueKey('shell-content')));
    expect(
      chat.left,
      WorkbenchShell.frameLeft + BenchDrawer.width + RootLayout.gap,
    );
    expect(chat.right, 1000 - WorkbenchShell.gapRight);
    expect(chat.top, TopBar.height + WorkbenchShell.gapTop);
    expect(find.byKey(const ValueKey('chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    final canvas = tester.getRect(find.byKey(const ValueKey('shell-content')));
    expect(
      canvas.left,
      WorkbenchShell.frameLeft,
      reason: 'no canvas a gaveta aberta fica por cima do grid',
    );
    expect(
      canvas.width,
      1000 - WorkbenchShell.frameLeft - WorkbenchShell.gapRight,
    );
    expect(find.byKey(const ValueKey('canvas')), findsOneWidget);
  });

  testWidgets('fechar a gaveta devolve a largura ao chat', (tester) async {
    await mount(
      tester,
      const ShellSnapshot(
        bench: Workbench(id: 'b', name: 'd', path: '~', view: ViewMode.chat),
      ),
    );
    final before = tester
        .getRect(find.byKey(const ValueKey('shell-content')))
        .left;

    // Sem ✕ na gaveta: o botão do trilho a recolhe (e o Esc, sem fixar).
    await tester.tap(find.bySemanticsLabel('Todas as bancadas'));
    await settleDrawer(tester);

    final after = tester
        .getRect(find.byKey(const ValueKey('shell-content')))
        .left;
    expect(after, lessThan(before));
    expect(after, WorkbenchShell.frameLeft);
    expect(find.byType(SidebarPanel), findsNothing);
  });

  testWidgets('Canvas | Chat troca o modo e a trilha diz a bancada', (
    tester,
  ) async {
    final s = await mount(tester);
    expect(
      find.descendant(of: find.byType(TopBar), matching: find.text('deck')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('view-chat')));
    await tester.pump();
    expect(s.shell.views, [ViewMode.chat]);
  });

  testWidgets('a trilha mostra projeto / bancada, e a bancada na cor dela', (
    tester,
  ) async {
    await mount(tester, const ShellSnapshot(bench: bench, projectName: 'loja'));
    expect(find.text('loja'), findsWidgets);
    final name = tester.widget<Text>(
      find.descendant(of: find.byType(TopBar), matching: find.text('deck')),
    );
    expect(name.style!.fontWeight, FontWeight.w600);
    expect(name.style!.color, BenchIdentity.of('blue').color(EgeonColors.dark));
  });

  group('a gaveta de bancadas', () {
    testWidgets('começa fechada: só o trilho de bancadas', (tester) async {
      await mount(tester, null, false);
      expect(find.byType(SidebarPanel), findsNothing);
      expect(find.byType(BenchRail), findsOneWidget);
      final frame = tester.getRect(find.byKey(const ValueKey('shell-content')));
      expect(frame.left, WorkbenchShell.frameLeft);
    });

    testWidgets('o botão do trilho abre e fecha', (tester) async {
      await mount(tester, null, false);
      await openDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
      final drawer = tester.getRect(find.byType(BenchDrawer));
      expect(drawer.left, WorkbenchShell.frameLeft);
      expect(drawer.width, BenchDrawer.width);
      await tester.tap(find.bySemanticsLabel('Todas as bancadas'));
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsNothing);
    });

    testWidgets('passar o mouse no botão abre; tirar fecha', (tester) async {
      await mount(tester, null, false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(900, 700));
      await mouse.moveTo(
        tester.getCenter(find.bySemanticsLabel('Todas as bancadas')),
      );
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
      // Atravessa o vão até a gaveta: ela não pisca.
      final drawer = tester.getRect(find.byType(BenchDrawer));
      await mouse.moveTo(drawer.center);
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
      await mouse.moveTo(const Offset(900, 700));
      await tester.pump(DrawerHover.linger);
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsNothing);

      // A faixa vazia do trilho, junto à borda da janela, também abre.
      await mouse.moveTo(const Offset(8, 500));
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
    });

    testWidgets('abre e fecha em 200 ms', (tester) async {
      await mount(tester, null, false);
      await tester.tap(find.bySemanticsLabel('Todas as bancadas'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      double slide() => tester
          .widgetList<FractionalTranslation>(
            find.ancestor(
              of: find.byType(SidebarPanel),
              matching: find.byType(FractionalTranslation),
            ),
          )
          .first
          .translation
          .dx;
      expect(slide(), inExclusiveRange(-1, 0), reason: 'no meio da entrada');
      await tester.pump(const Duration(milliseconds: 120));
      expect(slide(), 0);
    });

    testWidgets('Esc fecha a gaveta aberta por cima', (tester) async {
      await mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsNothing);
    });

    testWidgets('clicar fora fecha; clicar dentro não', (tester) async {
      await mount(tester);
      await tester.tapAt(
        tester.getCenter(find.byType(SidebarPanel)).translate(0, 60),
      );
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
      // Fora: bem à direita, no conteúdo.
      await tester.tapAt(const Offset(900, 500));
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsNothing);
    });

    testWidgets('escolher outra bancada deixa a gaveta aberta', (tester) async {
      final s = await mount(tester);
      await s.show(
        tester,
        const ShellSnapshot(
          bench: Workbench(id: 'b2', name: 'outra', path: '~'),
        ),
      );
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
    });

    testWidgets('não há fixar: o canvas continua por baixo e Esc a fecha', (
      tester,
    ) async {
      await mount(tester);
      expect(find.bySemanticsLabel('Fixar a gaveta'), findsNothing);
      expect(find.bySemanticsLabel('Soltar a gaveta'), findsNothing);
      final frame = tester.getRect(find.byKey(const ValueKey('shell-content')));
      expect(
        frame.left,
        WorkbenchShell.frameLeft,
        reason: 'no canvas ela flutua, não empurra a moldura',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsNothing);
    });

    testWidgets('o último botão da linha do topo recolhe a gaveta', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.bySemanticsLabel('Recolher barra lateral'));
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsNothing);
    });

    testWidgets('o ⌘/ fecha a gaveta, e ela reabre', (tester) async {
      await mount(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsNothing);
      await tester.tap(find.bySemanticsLabel('Todas as bancadas'));
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
    });

    testWidgets('no macOS não há ☰: o menu é a barra do sistema', (
      tester,
    ) async {
      await mount(tester);
      expect(find.bySemanticsLabel('Menu do app'), findsNothing);
    });

    testWidgets('fora do macOS o ☰ do cabeçalho abre o menu do app', (
      tester,
    ) async {
      debugUsesCommandKey = false;
      addTearDown(() => debugUsesCommandKey = true);
      await mount(tester);
      await tester.tap(find.bySemanticsLabel('Menu do app'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Processos…'), findsOneWidget);
      expect(find.text('Ctrl+Shift+P'), findsOneWidget);
      expect(find.text('Limpar órfãos automaticamente'), findsOneWidget);
      expect(find.text('Fechar a aba'), findsOneWidget);
      expect(find.text('Ctrl+Shift+W'), findsOneWidget);
      expect(find.text('Ver como chat'), findsOneWidget);
      expect(find.text('Aproximar'), findsOneWidget);
    });

    testWidgets('⌘K abre a gaveta', (tester) async {
      await mount(tester, null, false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
    });
  });

  group('o trilho de bancadas na casca', () {
    testWidgets('mostra as abas abertas e troca de bancada pelo clique', (
      tester,
    ) async {
      final s = await withTabs(tester);
      final rail = find.byType(BenchRail);
      expect(
        find.descendant(of: rail, matching: find.text('A')),
        findsOneWidget,
      );
      await tester.tap(find.descendant(of: rail, matching: find.text('C')));
      expect(s.tabs.picked, ['c']);
    });

    testWidgets('Nova bancada pede o formulário', (tester) async {
      final s = await mount(tester, null, false);
      await tester.tap(find.bySemanticsLabel('Nova bancada'));
      expect(s.forms.single, isA<NewBench>());
    });
  });

  testWidgets('H6b: os flutuantes da E1 abrem dentro da casca, sob o tema', (
    tester,
  ) async {
    await mount(tester);
    final context = tester.element(find.byType(TopBar));
    showMenu(
      context,
      anchor: tester.getRect(find.byType(TopBar)),
      items: [MenuItem('Trocar bancada', onSelected: () {})],
    );
    await tester.pumpAndSettle();
    expect(find.text('Trocar bancada'), findsOneWidget);
    showToast(context, title: 'Pronto', tone: ToastTone.success);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Pronto'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a casca não mostra mais a faixa de abas', (tester) async {
    final s = await mount(tester);
    s.tabs.push([
      const WorkbenchTab(id: 'a', name: 'a', isActive: true),
      const WorkbenchTab(id: 'b', name: 'b'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('tab-a')), findsNothing);
  });

  testWidgets('as cortinas cobrem o conteúdo, não a barra de cima', (
    tester,
  ) async {
    final s = await mount(
      tester,
      const ShellSnapshot(
        bench: bench,
        busy: 'Criando a worktree…',
        lock: AccessLock(text: 'Negado.'),
      ),
    );
    expect(find.text('Criando a worktree…'), findsOneWidget);
    expect(find.text('Sem acesso à pasta'), findsOneWidget);
    expect(find.text('Negado.'), findsOneWidget);

    await tester.tap(find.text('Abrir Ajustes'));
    await tester.tap(find.text('Pedir de novo'));
    await tester.pump();
    expect(s.shell.settingsOpened, 1);
    expect(s.shell.askedAgain, 1);

    // A barra de cima segue clicável por baixo das cortinas.
    await tester.tap(find.byKey(const ValueKey('view-chat')));
    expect(s.shell.views, [ViewMode.chat]);
  });

  testWidgets('a faixa do core aparece sobre o conteúdo sem travá-lo', (
    tester,
  ) async {
    await mount(
      tester,
      const ShellSnapshot(
        bench: bench,
        banner: 'Copiando o que o git não versiona em repo (.env, node_modules, build…)',
      ),
    );
    expect(find.byKey(const ValueKey('shell-banner')), findsOneWidget);
    expect(
      find.textContaining('Copiando o que o git não versiona'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('canvas')), findsOneWidget);
    // No canvas, abaixo das barras de ação e informativa: não tapa o
    // cronômetro (`topInset + 110` no Swift).
    final content = tester.getTopLeft(
      find.byKey(const ValueKey('shell-content')),
    );
    final banner = tester.getTopLeft(
      find.byKey(const ValueKey('shell-banner')),
    );
    expect(banner.dy - content.dy, 110);
  });

  testWidgets('o macOS perguntando: o aviso é dele e "pedir de novo" some', (
    tester,
  ) async {
    final s = await mount(
      tester,
      const ShellSnapshot(
        bench: bench,
        lock: AccessLock(text: 'x', asking: true),
      ),
    );
    expect(find.textContaining('responda o aviso dele'), findsOneWidget);
    await tester.tap(find.text('Pedir de novo'));
    expect(
      s.shell.askedAgain,
      0,
      reason: 'desligado enquanto o macOS pergunta',
    );
  });

  testWidgets('os menus da barra lateral chegam como pedidos de formulário', (
    tester,
  ) async {
    final s = await mount(tester);
    await tester.tap(find.bySemanticsLabel('Novo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Novo workspace…'));
    await tester.pump();
    expect(s.forms.single, isA<NewWorkspace>());
  });

  testWidgets('onde se clica, o ponteiro diz: mão em tudo da casca', (
    tester,
  ) async {
    final s = await mount(
      tester,
      const ShellSnapshot(
        bench: bench,
        busy: 'x',
        lock: AccessLock(text: 'y'),
      ),
    );
    s.tabs.push([
      const WorkbenchTab(id: 'a', name: 'a', isActive: true),
      const WorkbenchTab(id: 'b', name: 'b'),
    ]);
    await tester.pump();
    await tester.pump();
    expectHandOnEveryClickable(tester);
  });

  group('atalhos', () {
    Future<void> keys(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      bool alt = false,
    }) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(key);
      if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    testWidgets('⌘→ vai à aba da direita; da última volta à primeira', (
      tester,
    ) async {
      final s = await withTabs(tester);
      await keys(tester, LogicalKeyboardKey.arrowRight);
      expect(s.tabs.picked, ['c']);
    });

    testWidgets('segurar ⌘→ repete a troca de aba', (tester) async {
      final s = await withTabs(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(s.tabs.picked.length, 3);
    });

    testWidgets('⌘← vai à da esquerda', (tester) async {
      final s = await withTabs(tester);
      await keys(tester, LogicalKeyboardKey.arrowLeft);
      expect(s.tabs.picked, ['a']);
    });

    testWidgets('⌘[ e ⌘] voltam e avançam entre as bancadas visitadas', (
      tester,
    ) async {
      final s = await withTabs(tester);
      ShellSnapshot on(String id) =>
          ShellSnapshot(bench: _bench(id), openBenchIds: const {'a', 'b', 'c'});
      // Sem visita anterior, nada.
      await keys(tester, LogicalKeyboardKey.bracketLeft);
      await keys(tester, LogicalKeyboardKey.bracketRight);
      expect(s.shell.activated, isEmpty);

      await s.show(tester, on('b'));
      await s.show(tester, on('c'));
      await keys(tester, LogicalKeyboardKey.bracketLeft);
      expect(s.shell.activated, ['b'], reason: 'voltou à bancada de antes');
      await s.show(tester, on('b'));
      await keys(tester, LogicalKeyboardKey.bracketRight);
      expect(s.shell.activated, ['b', 'c']);
    });

    testWidgets('⌘1…⌘9 vão à aba pelo número; número sem aba não faz nada', (
      tester,
    ) async {
      final s = await withTabs(tester);
      await keys(tester, LogicalKeyboardKey.digit3);
      await keys(tester, LogicalKeyboardKey.digit1);
      await keys(tester, LogicalKeyboardKey.digit9);
      expect(s.tabs.picked, ['c', 'a']);
    });

    testWidgets('⇧⌘T copia os alvos de dispatch que o core diz', (
      tester,
    ) async {
      final s = await mount(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump();
      expect(s.clipboard.written, ['deck/claude\ndeck/sh']);
    });

    testWidgets('⌥⌘P abre Processos com o nome do app', (tester) async {
      final s = await mount(tester);
      await keys(tester, LogicalKeyboardKey.keyP, alt: true);
      await tester.pump();
      expect(s.windows.opened.single.title, 'Processos do Egeon Deck');
    });

    testWidgets('⌘W fecha a aba da frente, não a janela', (tester) async {
      final s = await withTabs(tester);
      await keys(tester, LogicalKeyboardKey.keyW);
      expect(s.tabs.closed, ['b']);
    });

    testWidgets('⌘/ abre e fecha a gaveta, ⌥⌘2 mostra o chat', (tester) async {
      final s = await mount(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
      await keys(tester, LogicalKeyboardKey.slash);
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsNothing);
      await keys(tester, LogicalKeyboardKey.slash);
      await settleDrawer(tester);
      expect(find.byType(SidebarPanel), findsOneWidget);
      await keys(tester, LogicalKeyboardKey.digit2, alt: true);
      await keys(tester, LogicalKeyboardKey.digit1, alt: true);
      expect(s.shell.views, [ViewMode.chat, ViewMode.canvas]);
      expect(s.tabs.picked, isEmpty, reason: '⌥⌘n não é o ⌘n das abas');
    });

    testWidgets(
      'com o foco num campo de texto, ⌘←/→ são início e fim da linha',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        final controller = TextEditingController(text: 'olá mundo');
        addTearDown(controller.dispose);
        try {
          tester.view.physicalSize = const Size(1000, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final s = Shell(
            content: FormTextField(
              controller: controller,
              autofocus: true,
              maxLines: 1,
            ),
          );
          await tester.pumpWidget(s.build());
          s.tabs.push([
            const WorkbenchTab(id: 'a', name: 'a'),
            const WorkbenchTab(id: 'b', name: 'b', isActive: true),
            const WorkbenchTab(id: 'c', name: 'c'),
          ]);
          await s.show(tester, const ShellSnapshot(bench: bench));
          await tester.pump();
          await tester.pump();
          await tester.tap(find.byType(EditableText));
          controller.selection = const TextSelection.collapsed(offset: 5);
          await tester.pump();

          await keys(tester, LogicalKeyboardKey.arrowLeft);
          await keys(tester, LogicalKeyboardKey.arrowRight);
          expect(s.tabs.picked, isEmpty, reason: 'o texto fica com as setas');

          // ⌘[ e ⌘] seguem valendo no campo: sem histórico, não fazem nada.
          await keys(tester, LogicalKeyboardKey.bracketRight);
          expect(s.tabs.picked, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('com uma aba só não há para onde ir', (tester) async {
      final s = await mount(tester);
      s.tabs.push([const WorkbenchTab(id: 'a', name: 'a', isActive: true)]);
      await tester.pump();
      await tester.pump();
      await keys(tester, LogicalKeyboardKey.arrowRight);
      expect(s.tabs.picked, isEmpty);
    });
  });

  testWidgets('o cubit da casca assina ao nascer e cancela ao sair', (
    tester,
  ) async {
    final s = await mount(tester);
    expect(s.shell.watchers, 2);
    await tester.pumpWidget(const SizedBox());
    expect(s.shell.watchers, 0);
  });

  testWidgets('a casca é dona das assinaturas: sair da tela cancela todas', (
    tester,
  ) async {
    final s = await mount(tester);
    expect(s.sidebar.watchers, 1);
    expect(s.shell.watchers, 2);
    await tester.pumpWidget(const SizedBox());
    expect(s.sidebar.watchers, 0);
    expect(s.shell.watchers, 0);
    expect(s.requests.hasListener, isFalse);
  });

  group('uso e processos', () {
    testWidgets('o chip de consumo da bancada fica no canto da moldura', (
      tester,
    ) async {
      final s = Shell();
      s.usage.push(UsageView.fromMap(sampleUsage()));
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(s.build());
      await s.show(
        tester,
        const ShellSnapshot(
          bench: bench,
          clock: WorkbenchClock(running: 75, waiting: 5),
        ),
      );

      expect(
        s.usage.watched,
        contains('b1'),
        reason: 'o canto assina a da tela; a barra lateral, a de cada linha',
      );
      final chip = find.byType(UsageChip);
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('US\$ 12,34')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chip, matching: find.text('01:15')),
        findsOneWidget,
      );
      // Na moldura, no canto de cima à direita, e não mais na barra de cima.
      expect(
        find.descendant(
          of: find.byType(TopBar),
          matching: find.byType(UsageChip),
        ),
        findsNothing,
      );
      final rect = tester.getRect(chip);
      expect(rect.right, closeTo(1000 - 24 - ShellLayers.margin, 1));
    });

    testWidgets('sem bancada não há chip', (tester) async {
      await mount(tester, const ShellSnapshot());
      expect(find.byType(UsageChip), findsNothing);
    });

    testWidgets('o menu oferece Processos…', (tester) async {
      final s = await mount(tester);
      s.app.push(const AppSnapshot());
      await tester.pump();
      expect(menuCalls.last, contains('Processos…'));
    });
  });

  group('o menu do app', () {
    testWidgets(
      'os atalhos moram nos itens, como os key equivalents do Swift',
      (tester) async {
        final s = await mount(tester);
        s.app.push(const AppSnapshot());
        await tester.pump();
        const meta = 1, shift = 2, alt = 4;
        for (final (label, key, modifiers) in [
          ('Aba à direita', LogicalKeyboardKey.arrowRight, meta),
          ('Aba à esquerda', LogicalKeyboardKey.arrowLeft, meta),
          ('Avançar', LogicalKeyboardKey.bracketRight, meta),
          ('Voltar', LogicalKeyboardKey.bracketLeft, meta),
          ('Fechar a aba', LogicalKeyboardKey.keyW, meta),
          ('Aba 1', LogicalKeyboardKey.digit1, meta),
          ('Aba 9', LogicalKeyboardKey.digit9, meta),
          ('Copiar alvos de dispatch', LogicalKeyboardKey.keyT, meta | shift),
          ('Processos…', LogicalKeyboardKey.keyP, meta | alt),
          ('Ver no canvas', LogicalKeyboardKey.digit1, meta | alt),
          ('Ver como chat', LogicalKeyboardKey.digit2, meta | alt),
          (
            'Abrir ou fechar a gaveta de bancadas',
            LogicalKeyboardKey.slash,
            meta,
          ),
          ('Buscar bancada…', LogicalKeyboardKey.keyK, meta),
          ('Aproximar', LogicalKeyboardKey.equal, meta),
          ('Afastar', LogicalKeyboardKey.minus, meta),
          ('Zoom 100%', LogicalKeyboardKey.digit0, meta),
        ]) {
          final item = menuItem(menuSent, label);
          expect(item, isNotNull, reason: label);
          expect(item!['shortcutTrigger'], key.keyId, reason: label);
          expect(item['shortcutModifiers'], modifiers, reason: label);
        }
      },
    );

    testWidgets('sem foco na casca (o nó web), o menu atende o atalho', (
      tester,
    ) async {
      final s = await withTabs(tester);
      s.app.push(const AppSnapshot());
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await chooseMenu(tester, 'Aba 3');
      await chooseMenu(tester, 'Fechar a aba');
      expect(s.tabs.picked, ['c']);
      expect(s.tabs.closed, isNotEmpty);
      await chooseMenu(tester, 'Copiar alvos de dispatch');
      expect(s.clipboard.written, ['deck/claude\ndeck/sh']);
      await chooseMenu(tester, 'Processos…');
      expect(s.windows.opened.single.kind, WindowKind.processes);
      expect(s.windows.opened.single.title, 'Processos do Egeon Deck');
    });

    testWidgets('tem Editar com os atalhos do macOS e o menu Canvas completo', (
      tester,
    ) async {
      final s = await mount(tester);
      s.app.push(const AppSnapshot());
      await tester.pump();
      final menu = menuCalls.last;
      for (final label in [
        'Editar',
        'Desfazer',
        'Refazer',
        'Recortar',
        'Copiar',
        'Colar',
        'Selecionar tudo',
        'Novo terminal',
        'Novo web',
        'Nova fila',
        'Aproximar',
        'Afastar',
        'Zoom 100%',
        'Enquadrar tudo',
      ]) {
        expect(menu, contains(label), reason: label);
      }
    });

    testWidgets('o item de atualização leva o título e o estado do core', (
      tester,
    ) async {
      final s = await mount(tester);
      s.app.push(
        const AppSnapshot(
          update: UpdateView(
            menu: 'Reiniciar para atualizar',
            menuEnabled: false,
            auto: true,
          ),
          reaperEnabled: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      final last = menuCalls.last;
      expect(last, contains('Reiniciar para atualizar'));
      expect(last, contains('✓ Atualizar automaticamente'));
      expect(last, contains('Limpar órfãos automaticamente'));
      expect(last, isNot(contains('✓ Limpar órfãos')));
      expect(last, contains('Ver como chat'));
    });

    testWidgets(
      'o menu só vai de novo ao AppKit quando muda: reenviar fecha o aberto',
      (tester) async {
        final s = await mount(tester);
        // O `PlatformMenuBar` não guarda os itens no initState: a primeira
        // remontagem sempre reenvia uma vez. O que conta é daí em diante.
        s.app.push(const AppSnapshot());
        await tester.pump();
        await tester.pump();
        menuCalls.clear();
        await s.show(
          tester,
          const ShellSnapshot(
            bench: Workbench(id: 'b2', name: 'outra', path: '~'),
          ),
        );
        s.tabs.push([const WorkbenchTab(id: 'b2', name: 'outra')]);
        s.app.push(const AppSnapshot());
        await tester.pump();
        await tester.pump();
        expect(menuCalls, isEmpty);

        await s.show(
          tester,
          const ShellSnapshot(
            bench: Workbench(
              id: 'b2',
              name: 'outra',
              path: '~',
              view: ViewMode.chat,
            ),
          ),
        );
        expect(menuCalls, hasLength(1));
      },
    );
  });

  group('pedidos do core à tela (decisão 35)', () {
    Future<UiReply> ask(
      WidgetTester tester,
      Shell s,
      String route, [
      Map<String, String> params = const {},
    ]) async {
      final before = s.requests.replies.length;
      s.requests.ask(route, params);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(s.requests.replies.length, before + 1);
      return s.requests.replies.last.$2;
    }

    testWidgets('o core pedir a janela para a frente aciona o runner', (
      tester,
    ) async {
      final s = await mount(tester);
      s.requests.activate();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(s.activator.calls, 1);
    });

    testWidgets('layout muda o modo da bancada ativa', (tester) async {
      final s = await mount(tester);
      final reply = await ask(tester, s, 'layout', {'mode': 'chat'});
      expect(s.shell.views, [ViewMode.chat]);
      expect(reply.value, 'chat');
    });

    testWidgets('layout inválido ou sem bancada é 404 e não manda nada', (
      tester,
    ) async {
      final s = await mount(tester);
      var reply = await ask(tester, s, 'layout', {'mode': 'xyz'});
      expect(reply.value, isNull);
      await s.show(tester, const ShellSnapshot());
      reply = await ask(tester, s, 'layout', {'mode': 'chat'});
      expect(reply.value, isNull);
      expect(s.shell.views, isEmpty);
    });

    testWidgets('sidebar recolhe, abre e alterna', (tester) async {
      final s = await mount(tester);
      bool collapsed() =>
          tester.widget<RootLayout>(find.byType(RootLayout)).collapsed;
      expect(collapsed(), isFalse);

      var reply = await ask(tester, s, 'sidebar', {'collapsed': '1'});
      expect(collapsed(), isTrue);
      expect(reply.value, true);

      reply = await ask(tester, s, 'sidebar', {'collapsed': 'toggle'});
      expect(collapsed(), isFalse);
      expect(reply.value, false);

      await ask(tester, s, 'sidebar', {'collapsed': '1'});
      await ask(tester, s, 'sidebar', {'collapsed': '0'});
      expect(collapsed(), isFalse);
    });

    testWidgets('sidebar troca a aba; aba inválida é 404', (tester) async {
      final s = await mount(tester);
      var reply = await ask(tester, s, 'sidebar', {'tab': 'active'});
      expect(reply.value, 'active');
      expect(
        tester.widget<SidebarPanel>(find.byType(SidebarPanel)).tab,
        SidebarTab.active,
      );
      reply = await ask(tester, s, 'sidebar', {'tab': 'nada'});
      expect(reply.value, isNull);
    });

    testWidgets('shot de window e sidebar grava um PNG de verdade', (
      tester,
    ) async {
      final s = await mount(tester);
      for (final target in ['window', 'sidebar']) {
        final file = '/tmp/shots/$target.png';
        s.requests.ask('shot', {'target': target, 'file': file});
        // A captura usa o motor de verdade: roda fora do relógio do teste.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        // A região pode esperar o quadro seguinte: o teste o dá e espera de novo.
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        final reply = s.requests.replies.last.$2;
        expect(reply.value, file);
        expect(s.pngs[file]!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      }
    });

    testWidgets('shot de nó que não existe responde erro, sem gravar', (
      tester,
    ) async {
      final s = await mount(tester);
      final reply = await ask(tester, s, 'shot', {
        'target': 'deck/nada',
        'file': '/tmp/shots/x.png',
      });
      expect(reply.value as String, startsWith('erro:'));
      expect(s.pngs, isEmpty);
    });

    testWidgets('geometry e shot de card vão ao canvas ao vivo', (
      tester,
    ) async {
      final probe = _FakeProbe();
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = Shell(
        content: Builder(
          builder: (context) {
            inject<CanvasProbeRegistry>().register(probe);
            return const Text('CANVAS');
          },
        ),
      );
      await tester.pumpWidget(s.build());
      await s.show(tester, const ShellSnapshot(bench: bench));

      var reply = await ask(tester, s, 'geometry');
      expect(probe.windows.single.x, 10);
      expect(probe.windows.single.y, 20);
      expect(probe.windows.single.screenHeight, 1000);
      final body = reply.value! as Map<String, Object?>;
      expect(body['workbench'], 'deck', reason: 'o nome, como o Swift');
      expect(body['nodes'], isNotEmpty);

      reply = await ask(tester, s, 'shot', {
        'target': 'deck/claude',
        'file': '/tmp/shots/deck_claude.png',
      });
      expect(probe.shots, [('claude', '/tmp/shots/deck_claude.png')]);
      expect(reply.value, '/tmp/shots/deck_claude.png');

      reply = await ask(tester, s, 'shot', {
        'target': 'outra/claude',
        'file': '/tmp/shots/o.png',
      });
      expect(reply.value as String, startsWith('erro:'));
      expect(
        probe.shots,
        hasLength(1),
        reason: 'outra bancada não é desenhada',
      );
    });

    testWidgets('em chat a geometria só diz o modo', (tester) async {
      final s = await mount(
        tester,
        ShellSnapshot(
          bench: Workbench(
            id: 'b1',
            name: 'deck',
            path: '~',
            view: ViewMode.chat,
          ),
        ),
      );
      final reply = await ask(tester, s, 'geometry');
      final body = reply.value! as Map<String, Object?>;
      expect(body['mode'], 'chat');
      expect(body['nodes'], isEmpty);
    });
  });

  test('a gaveta só cobre o canvas; no chat fica ao lado', () {
    expect(
      RootLayout.floatingInset(collapsed: false, beside: false),
      BenchDrawer.width + RootLayout.gap,
    );
    expect(RootLayout.floatingInset(collapsed: true, beside: false), 0);
    expect(
      RootLayout.floatingInset(collapsed: false, beside: true),
      0,
      reason: 'no chat ela empurra a moldura em vez de cobri-la',
    );
  });

  group('janela no tamanho mínimo', () {
    testWidgets(
      'chat com a gaveta aberta ao lado: nada estoura e a conversa tem largura',
      (tester) async {
        tester.view.physicalSize = RootLayout.minWindow;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await Injector.reset();
        final s = Shell(chat: const ChatPage(workbenchId: 'b1'));
        await tester.pumpWidget(s.build());
        await s.show(
          tester,
          const ShellSnapshot(
            bench: Workbench(
              id: 'b1',
              name: 'deck',
              path: '~',
              view: ViewMode.chat,
            ),
          ),
        );
        s.chatRepository.reset(
          1,
          conversation(4),
          participants: const [frontInfo, backInfo],
        );
        await tester.pump();
        await tester.pump();
        await openDrawer(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(ParticipantsColumn), findsOneWidget);
        expect(
          tester.getSize(find.byType(ChatComposer)).width,
          greaterThan(260),
        );
        final chip = tester.getRect(find.byType(UsageChip));
        final column = tester.getRect(find.byType(ParticipantsColumn));
        expect(chip.overlaps(column), isFalse);
      },
    );

    Widget topStack(Widget bar, Widget? corner) => egHost(
      fill: true,
      Stack(
        children: [
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: ToolbarSlot(child: bar),
          ),
          Positioned.fill(child: ShellLayers(corner: corner)),
        ],
      ),
    );

    testWidgets(
      'a barra do canvas não passa por baixo do canto, na largura natural',
      (tester) async {
        addTearDown(tester.view.reset);
        for (final corner in [null, 120.0, 220.0]) {
          for (final width in [892.0, 1000.0, 1400.0]) {
            tester.view.physicalSize = Size(width, 300);
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              topStack(
                SizedBox(
                  key: const ValueKey('bar'),
                  width: 515,
                  height: CanvasToolbar.height,
                ),
                corner == null
                    ? null
                    : SizedBox(
                        key: const ValueKey('corner'),
                        width: corner,
                        height: 46,
                      ),
              ),
            );
            await tester.pump();
            await tester.pump();
            final bar = tester.getRect(find.byKey(const ValueKey('bar')));
            // O que o host dá de largura (ele limita a viewport).
            final room = tester.getSize(find.byType(ToolbarSlot)).width;
            reason(String what) =>
                '$what (canto $corner, largura $width, sala $room, barra $bar)';
            expect(bar.width, 515, reason: reason('sem encolher'));
            expect(bar.left, greaterThanOrEqualTo(16));
            if (corner == null) {
              expect(
                bar.center.dx,
                closeTo(room / 2, 0.5),
                reason: reason('sem peça no canto, no centro'),
              );
            } else {
              final box = tester.getRect(find.byKey(const ValueKey('corner')));
              expect(bar.overlaps(box), isFalse, reason: reason('sobrepôs'));
              if (room - 515 >= 2 * 220 + 64) {
                expect(
                  bar.center.dx,
                  closeTo(room / 2, 0.5),
                  reason: reason('cabendo, no centro'),
                );
              }
            }
          }
        }
      },
    );

    testWidgets(
      'a barra real e o chip real na janela mínima: sem encolher e sem sobrepor',
      (tester) async {
        // A moldura do canvas no tamanho mínimo, sem a gaveta empurrando: a
        // janela menos o trilho (84) e a margem da direita (24).
        final frame = RootLayout.minWindow.width - 84 - 24;
        tester.view.physicalSize = Size(frame, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          topStack(
            CanvasToolbar(
              tool: CanvasTool.cursor,
              zoom: 1,
              onSelect: (_) {},
              onZoom: (_) {},
              onResetZoom: () {},
              onFitAll: () {},
              onPickColor: (_) {},
              benchName: 'deck',
              benchActions: CanvasBenchActions(
                onSaveTemplate: () {},
                onNewWorktree: () {},
                onUpdateTemplate: () {},
              ),
            ),
            BlocProvider(
              create: (_) => UsageCubit(
                workbenchId: 'b1',
                watch: WatchUsage(FakeUsageRepository()),
              ),
              child: const UsageChip(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        final bar = tester.getRect(find.byType(CanvasToolbar));
        final chip = tester.getRect(find.byType(UsageChip));
        expect(bar.overlaps(chip), isFalse);
        expect(
          tester.takeException(),
          isNull,
          reason: 'a barra cabe sem estourar',
        );
        expect(bar.left, greaterThanOrEqualTo(16));
      },
    );
  });
}

class _FakeProbe implements CanvasProbe {
  final windows = <canvas.WindowFrame>[];
  final shots = <(String, String)>[];

  @override
  String get workbenchId => 'b1';

  @override
  Map<String, Object?> geometry(
    canvas.WindowFrame window, {
    String mode = 'canvas',
  }) {
    windows.add(window);
    return {
      'workbench': 'b1',
      'mode': 'canvas',
      'nodes': [
        {'id': 'claude'},
      ],
    };
  }

  @override
  Future<String> snapshot(String cardId, String file) async {
    shots.add((cardId, file));
    return file;
  }
}

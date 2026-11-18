import 'package:egeon_deck/commons/widgets/app_text_field.dart';

import 'package:egeon_deck/core/adapters/window_frame.dart';
import 'package:egeon_deck/core/domain/entities/view_mode.dart';
import 'package:egeon_deck/core/domain/entities/workbench.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_probe.dart'
    hide WindowFrame;
import 'package:egeon_deck/features/canvas/domain/entities/canvas_probe.dart'
    as canvas
    show WindowFrame;
import 'package:egeon_deck/features/home/domain/entities/shell_state.dart';
import 'package:egeon_deck/features/home/domain/entities/ui_request.dart';
import 'package:egeon_deck/features/home/domain/repository/shell_repository.dart';
import 'package:egeon_deck/features/home/domain/repository/ui_request_repository.dart';
import 'package:egeon_deck/features/home/presentation/forms/form_request.dart';
import 'package:egeon_deck/features/home/presentation/page/home_shell_page.dart';
import 'package:egeon_deck/features/home/presentation/widgets/root_layout.dart';
import 'package:egeon_deck/features/home/presentation/widgets/view_toolbar.dart';
import 'package:egeon_deck/features/sidebar/domain/repository/sidebar_repository.dart';
import 'package:egeon_deck/features/processes/domain/repository/processes_repository.dart';
import 'package:egeon_deck/features/usage/domain/entities/usage_view.dart';
import 'package:egeon_deck/features/usage/domain/repository/usage_repository.dart';
import 'package:egeon_deck/features/update/domain/entities/app_state.dart';
import 'package:egeon_deck/features/update/domain/repository/app_repository.dart';
import 'package:egeon_deck/features/sidebar/presentation/widgets/sidebar_panel.dart';
import 'package:egeon_deck/features/sidebar/presentation/widgets/sidebar_segments.dart';
import 'package:egeon_deck/features/tabs/domain/entities/workbench_tab.dart';
import 'package:egeon_deck/features/tabs/domain/repository/tabs_repository.dart';
import 'package:egeon_deck/features/tabs/presentation/widgets/workbench_tabs_bar.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_shell_repository.dart';
import '../../support/fake_sidebar_repository.dart';
import '../../support/hand_cursor.dart';
import '../../support/fake_app_repository.dart';
import '../../support/fake_processes_repository.dart';
import '../../support/fake_usage_repository.dart';
import '../../support/fake_tabs_repository.dart';
import '../../support/fake_ui_request_repository.dart';
import '../../support/overlay_host.dart';
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
  Shell({this.content});

  /// O que ocupa o lugar do canvas; sem isso, um texto.
  final Widget? content;

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

  Widget build() => overlayHost(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ShellRepository>.value(value: shell),
        RepositoryProvider<SidebarRepository>.value(value: sidebar),
        RepositoryProvider<TabsRepository>.value(value: tabs),
        RepositoryProvider<UiRequestRepository>.value(value: requests),
        RepositoryProvider<AppRepository>.value(value: app),
        RepositoryProvider<UsageRepository>.value(value: usage),
        RepositoryProvider<ProcessesRepository>.value(
          value: FakeProcessesRepository(const []),
        ),
      ],
      child: HomeShellPage(
        canvas: (_, _) =>
            content ??
            const Focus(
              autofocus: true,
              child: Text('CANVAS', key: ValueKey('canvas')),
            ),
        chat: (_, _) => const Text('CHAT', key: ValueKey('chat')),
        onForm: (_, request) => forms.add(request),
        window: const _FixedWindow(),
        activator: activator,
        writePng: (path, png) async => pngs[path] = png,
      ),
    ),
  );

  Future<void> show(WidgetTester tester, ShellState state) async {
    shell.push(state);
    sidebar.push(sampleTree());
    await tester.pump();
    await tester.pump();
  }
}

Future<Shell> mount(WidgetTester tester, [ShellState? state]) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = Shell();
  await tester.pumpWidget(s.build());
  await s.show(tester, state ?? const ShellState(bench: bench));
  return s;
}

/// O que a casca mandou ao AppKit pelo canal de menu, uma entrada por envio.
final menuCalls = <String>[];

void main() {
  setUp(() {
    menuCalls.clear();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.menu, (call) async {
          if (call.method == 'Menu.setMenus') {
            menuCalls.add('${call.arguments}');
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
        ShellState(
          bench: Workbench(id: 'b1', name: 'deck', path: '~', view: mode),
        ),
      );
      expect(
        tester.getRect(find.byType(ViewToolbar)),
        const Rect.fromLTWH(0, 0, 1000, ViewToolbar.height),
        reason: 'modo ${mode.wire}',
      );
      expect(s.shell.watchers, 1);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('só o conteúdo cede à barra lateral, e só no chat', (
    tester,
  ) async {
    await mount(
      tester,
      const ShellState(
        bench: Workbench(id: 'b', name: 'd', path: '~', view: ViewMode.chat),
      ),
    );
    final cover =
        RootLayout.margin + SidebarPanel.expandedWidth + RootLayout.gap;
    final chat = tester.getRect(find.byKey(const ValueKey('shell-content')));
    expect(chat.left, cover);
    expect(chat.width, 1000 - cover);
    expect(chat.top, ViewToolbar.height);
    expect(find.byKey(const ValueKey('chat')), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    final canvas = tester.getRect(find.byKey(const ValueKey('shell-content')));
    expect(canvas.left, 0, reason: 'o grid corre por baixo do vidro');
    expect(canvas.width, 1000);
    expect(find.byKey(const ValueKey('canvas')), findsOneWidget);
  });

  testWidgets('recolher a barra devolve a largura ao chat', (tester) async {
    await mount(
      tester,
      const ShellState(
        bench: Workbench(id: 'b', name: 'd', path: '~', view: ViewMode.chat),
      ),
    );
    final before = tester
        .getRect(find.byKey(const ValueKey('shell-content')))
        .left;

    // O botão de recolher é a seta à esquerda do cabeçalho da barra.
    final panel = tester.getRect(find.byType(SidebarPanel));
    await tester.tapAt(Offset(panel.right - 20, panel.top + 24));
    await tester.pump();

    final after = tester
        .getRect(find.byKey(const ValueKey('shell-content')))
        .left;
    expect(after, lessThan(before));
    expect(after, RootLayout.margin + SidebarPanel.railWidth + RootLayout.gap);
    expect(
      tester.getRect(find.byType(SidebarPanel)).width,
      SidebarPanel.railWidth,
    );
  });

  testWidgets('a pílula troca o modo e o título diz a bancada', (tester) async {
    final s = await mount(tester);
    expect(find.text('deck'), findsWidgets);
    expect(find.byKey(const ValueKey('bench-swatch')), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pump();
    expect(s.shell.views, [ViewMode.chat]);
  });

  testWidgets('clicar na bolinha da cor pede o seletor de cor', (tester) async {
    final s = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('bench-swatch')));
    await tester.pump();
    expect(s.forms.single, isA<RecolorBench>());
    expect((s.forms.single as RecolorBench).benchId, 'b1');
  });

  testWidgets('a faixa de abas aparece entre a barra e o conteúdo', (
    tester,
  ) async {
    final s = await mount(tester);
    expect(find.byType(WorkbenchTabsBar), findsNothing);

    s.tabs.push([
      WorkbenchTab(id: 'a', name: 'a', isActive: true),
      const WorkbenchTab(id: 'b', name: 'b'),
    ]);
    await tester.pump();
    await tester.pump();

    final bar = tester.getRect(find.byType(WorkbenchTabsBar));
    expect(bar.top, ViewToolbar.height);
    final content = tester.getRect(find.byKey(const ValueKey('shell-content')));
    expect(
      content.top,
      bar.bottom,
      reason: 'o conteúdo desce a altura da faixa',
    );
  });

  testWidgets('a faixa nunca fica sob o vidro da barra lateral', (
    tester,
  ) async {
    final s = await mount(tester);
    s.tabs.push([
      WorkbenchTab(id: 'a', name: 'a', isActive: true),
      const WorkbenchTab(id: 'b', name: 'b'),
    ]);
    await tester.pump();
    await tester.pump();

    final cover =
        RootLayout.margin + SidebarPanel.expandedWidth + RootLayout.gap;
    final first = tester.getTopLeft(find.byKey(const ValueKey('tab-a'))).dx;
    expect(first, greaterThanOrEqualTo(cover));
  });

  testWidgets('as cortinas cobrem o conteúdo, não a barra de cima', (
    tester,
  ) async {
    final s = await mount(
      tester,
      const ShellState(
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
    await tester.tap(find.text('Chat'));
    expect(s.shell.views, [ViewMode.chat]);
  });

  testWidgets('o macOS perguntando: o aviso é dele e "pedir de novo" some', (
    tester,
  ) async {
    final s = await mount(
      tester,
      const ShellState(
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
    await tester.tap(find.text('+').first);
    await tester.pump();
    await tester.tap(find.text('Novo workspace…'));
    await tester.pump();
    expect(s.forms.single, isA<NewWorkspace>());
  });

  testWidgets('onde se clica, o ponteiro diz: mão em tudo da casca', (
    tester,
  ) async {
    final s = await mount(
      tester,
      const ShellState(
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

    testWidgets('⌘→ e ⌘] vão à aba da direita; da última volta à primeira', (
      tester,
    ) async {
      final s = await withTabs(tester);
      await keys(tester, LogicalKeyboardKey.arrowRight);
      await keys(tester, LogicalKeyboardKey.bracketRight);
      expect(s.tabs.picked, ['c', 'c']);
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

    testWidgets('⌘← e ⌘[ vão à da esquerda', (tester) async {
      final s = await withTabs(tester);
      await keys(tester, LogicalKeyboardKey.arrowLeft);
      await keys(tester, LogicalKeyboardKey.bracketLeft);
      expect(s.tabs.picked, ['a', 'a']);
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

    testWidgets('⌘W fecha a aba da frente, não a janela', (tester) async {
      final s = await withTabs(tester);
      await keys(tester, LogicalKeyboardKey.keyW);
      expect(s.tabs.closed, ['b']);
    });

    testWidgets('⌘/ recolhe a barra e ⌥⌘2 mostra o chat', (tester) async {
      final s = await mount(tester);
      await keys(tester, LogicalKeyboardKey.slash);
      expect(
        tester.getRect(find.byType(SidebarPanel)).width,
        SidebarPanel.railWidth,
      );
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
            content: AppTextField(
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
          await s.show(tester, const ShellState(bench: bench));
          await tester.pump();
          await tester.pump();
          await tester.tap(find.byType(EditableText));
          controller.selection = const TextSelection.collapsed(offset: 5);
          await tester.pump();

          await keys(tester, LogicalKeyboardKey.arrowLeft);
          await keys(tester, LogicalKeyboardKey.arrowRight);
          expect(s.tabs.picked, isEmpty, reason: 'o texto fica com as setas');

          // ⌘[ e ⌘] seguem valendo no campo.
          await keys(tester, LogicalKeyboardKey.bracketRight);
          expect(s.tabs.picked, ['c']);
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
    expect(s.shell.watchers, 1);
    await tester.pumpWidget(const SizedBox());
    expect(s.shell.watchers, 0);
  });

  testWidgets('a casca é dona das assinaturas: sair da tela cancela todas', (
    tester,
  ) async {
    final s = await mount(tester);
    expect(s.sidebar.watchers, 1);
    expect(s.shell.watchers, 1);
    await tester.pumpWidget(const SizedBox());
    expect(s.sidebar.watchers, 0);
    expect(s.shell.watchers, 0);
    expect(s.requests.hasListener, isFalse);
  });

  group('uso e processos', () {
    testWidgets('a pastilha de consumo da bancada fica no canto da barra', (
      tester,
    ) async {
      final s = Shell();
      s.usage.push(UsageView.fromMap(sampleUsage()));
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(s.build());
      await s.show(tester, const ShellState(bench: bench));

      expect(s.usage.watched, ['b1']);
      expect(
        find.descendant(
          of: find.byType(ViewToolbar),
          matching: find.text('US\$ 12,34'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sem bancada não há pastilha', (tester) async {
      final s = await mount(tester, const ShellState());
      expect(find.byKey(const ValueKey('usage-pill')), findsNothing);
      expect(s.usage.watched, isEmpty);
    });

    testWidgets('o menu oferece Processos…', (tester) async {
      final s = await mount(tester);
      s.app.push(const AppState());
      await tester.pump();
      expect(menuCalls.last, contains('Processos…'));
    });
  });

  group('o menu do app', () {
    testWidgets('tem Editar com os atalhos do macOS e o menu Canvas completo', (
      tester,
    ) async {
      final s = await mount(tester);
      s.app.push(const AppState());
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
        const AppState(
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
      await s.show(tester, const ShellState());
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
            context.read<CanvasProbeRegistry>().register(probe);
            return const Text('CANVAS');
          },
        ),
      );
      await tester.pumpWidget(s.build());
      await s.show(tester, const ShellState(bench: bench));

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
        ShellState(
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

  test(
    'a barra flutuante cobre o canvas: aberta, recolhida e ao lado (chat)',
    () {
      final open = RootLayout.floatingInset(collapsed: false, beside: false);
      final rail = RootLayout.floatingInset(collapsed: true, beside: false);
      expect(open, greaterThan(rail));
      expect(rail, greaterThan(0));
      expect(RootLayout.floatingInset(collapsed: false, beside: true), 0);
    },
  );
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

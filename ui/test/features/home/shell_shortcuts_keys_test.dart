import 'package:egeon_deck/commons/utils/app_shortcut.dart';
import 'package:egeon_deck/features/home/presentation/widgets/shell_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// O terminal só deixa para o app as teclas com Ctrl+Shift que o app liga
/// (`appCtrlShiftKeys`, no `commons`, que não vê a feature). Se uma tecla nova
/// entrar no `ShellShortcuts` sem entrar no conjunto, ela iria ao pty e
/// dispararia o atalho junto; se sobrar no conjunto, ficaria muda no terminal.
void main() {
  tearDown(() => debugUsesCommandKey = true);

  test('as teclas Ctrl+Shift do ShellShortcuts são as do conjunto', () {
    debugUsesCommandKey = false;
    void nothing() {}
    final shortcuts = ShellShortcuts(
      actions: ShellShortcutActions(
        toggleSidebar: nothing,
        findBench: nothing,
        showView: (_) {},
        nextTab: nothing,
        previousTab: nothing,
        back: nothing,
        forward: nothing,
        closeTab: nothing,
        pickTab: (_) {},
        copyTargets: nothing,
        showProcesses: nothing,
        zoomIn: nothing,
        zoomOut: nothing,
        resetZoom: nothing,
      ),
      child: const SizedBox(),
    );
    final bound = {
      for (final activator in shortcuts.bindings.keys)
        if (activator is SingleActivator &&
            activator.control &&
            activator.shift)
          activator.trigger,
    };
    // Ctrl+Shift+Tab é a aba anterior, não "tecla do app" no sentido do
    // conjunto: é do `isTabSwitchKey`.
    bound.remove(LogicalKeyboardKey.tab);
    expect(bound, appCtrlShiftKeys);
  });

  // Depois de um clique no vazio do canvas ninguém tem o foco; no macOS o menu
  // do sistema atende, fora dele o atalho tem de achar o escopo sozinho.
  for (final focused in [true, false]) {
    testWidgets('Ctrl+Shift+K age ${focused ? 'com' : 'sem'} widget com foco', (
      tester,
    ) async {
      debugUsesCommandKey = false;
      final calls = <String>[];
      void nothing() {}
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ShellShortcuts(
            actions: ShellShortcutActions(
              toggleSidebar: nothing,
              findBench: () => calls.add('busca'),
              showView: (_) {},
              nextTab: nothing,
              previousTab: nothing,
              back: nothing,
              forward: nothing,
              closeTab: nothing,
              pickTab: (_) {},
            ),
            child: Focus(focusNode: node, child: const SizedBox.expand()),
          ),
        ),
      );
      await tester.pump();
      if (focused) {
        node.requestFocus();
      } else {
        node.requestFocus();
        await tester.pump();
        node.unfocus();
      }
      await tester.pump();
      expect(node.hasPrimaryFocus, focused);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(calls, ['busca']);
    });
  }

  /// Aperta o atalho de Processos e devolve as chamadas e quem solta as teclas.
  Future<(List<String>, Future<void> Function())> pressProcesses(
    WidgetTester tester, {
    required bool command,
    int repeats = 0,
  }) async {
    debugUsesCommandKey = command;
    final calls = <String>[];
    void nothing() {}
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ShellShortcuts(
          actions: ShellShortcutActions(
            toggleSidebar: nothing,
            findBench: nothing,
            showView: (_) {},
            nextTab: nothing,
            previousTab: nothing,
            back: nothing,
            forward: nothing,
            closeTab: nothing,
            pickTab: (_) {},
            showProcesses: () => calls.add('processos'),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    final keys = command
        ? [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.altLeft]
        : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
    for (final key in keys) {
      await tester.sendKeyDownEvent(key);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
    for (var i = 0; i < repeats; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyP);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
    Future<void> release() async {
      for (final key in keys.reversed) {
        await tester.sendKeyUpEvent(key);
      }
    }

    return (calls, release);
  }

  testWidgets('fora do macOS Processos espera Ctrl e Shift soltos, por mais '
      'que se segure', (tester) async {
    final (calls, release) = await pressProcesses(tester, command: false);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, isEmpty, reason: 'ainda apertados: não abre');
    await release();
    expect(calls, isEmpty, reason: 'nem dentro do tratamento da soltura');
    await tester.pump(ShellShortcuts.afterRelease);
    expect(calls, ['processos']);
  });

  testWidgets('sem ver a soltura, Processos abre ao fim do teto', (
    tester,
  ) async {
    final (calls, release) = await pressProcesses(tester, command: false);
    await tester.pump(ShellShortcuts.releaseCeiling);
    expect(calls, ['processos']);
    await release();
    await tester.pump(ShellShortcuts.afterRelease);
    expect(calls, ['processos'], reason: 'só uma vez');
  });

  testWidgets('segurar a tecla não abre Processos várias vezes', (
    tester,
  ) async {
    final (calls, release) = await pressProcesses(
      tester,
      command: false,
      repeats: 3,
    );
    await release();
    await tester.pump(ShellShortcuts.afterRelease);
    await tester.pump(ShellShortcuts.releaseCeiling);
    expect(calls, ['processos']);
  });

  testWidgets('no macOS o ⌥⌘P abre na hora', (tester) async {
    final (calls, release) = await pressProcesses(tester, command: true);
    expect(calls, ['processos']);
    await release();
  });
}

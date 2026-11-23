import 'package:egeon_deck/core/domain/entities/view_mode.dart';
import 'package:egeon_deck/features/home/presentation/widgets/shell_shortcuts.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/resize_terminal.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/send_terminal_input.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/watch_terminal.dart';
import 'package:egeon_deck/features/node/terminal/presentation/cubit/terminal_cubit.dart';
import 'package:egeon_deck/features/node/terminal/presentation/page/terminal_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_terminal_repository.dart';

// Porte de KeyMonitorTests.swift. Tecla com o terminal focado é você falando
// com o agente — menos o atalho do app, que nunca chega ao pty. Contar o ⌘1 da
// troca de aba como digitação apagava a ampulheta de quem estava na frente.
void main() {
  late FakeTerminalRepository repository;
  final calls = <String>[];

  Future<void> mount(WidgetTester tester) async {
    calls.clear();
    repository = FakeTerminalRepository();
    final cubit = TerminalCubit(
      nodeId: 'n1',
      watch: WatchTerminal(repository),
      input: SendTerminalInput(repository),
      resize: ResizeTerminal(repository),
    );
    addTearDown(() => tester.runAsync(cubit.close));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ShellShortcuts(
          actions: ShellShortcutActions(
            toggleSidebar: () => calls.add('barra'),
            findBench: () => calls.add('busca'),
            showView: (mode) => calls.add('modo:${mode.wire}'),
            nextTab: () => calls.add('próxima'),
            previousTab: () => calls.add('anterior'),
            back: () => calls.add('voltar'),
            forward: () => calls.add('avançar'),
            closeTab: () => calls.add('fechar'),
            pickTab: (n) => calls.add('aba$n'),
          ),
          child: BlocProvider.value(
            value: cubit,
            child: const TerminalPage(autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> command(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  testWidgets('os atalhos da casca com ⌘ não chegam ao pty', (tester) async {
    await mount(tester);
    await command(tester, LogicalKeyboardKey.digit1);
    await command(tester, LogicalKeyboardKey.bracketRight);
    await command(tester, LogicalKeyboardKey.keyW);
    expect(calls, ['aba1', 'avançar', 'fechar']);
    expect(repository.keys, isEmpty);
    expect(repository.texts, isEmpty);
    expect(repository.pastes, isEmpty);
  });

  testWidgets('tecla comum e ⌃C chegam ao pty', (tester) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(repository.keys.map((k) => k.key), ['enter', 'c']);
    expect(repository.keys.last.ctrl, isTrue, reason: '⌃C interrompe o agente');
    expect(calls, isEmpty);
  });

  testWidgets('o colar com ⌘V ainda conta: vai como paste', (tester) async {
    await mount(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': 'echo oi'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await command(tester, LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(repository.pastes, ['echo oi']);
    expect(calls, isEmpty);
  });

  testWidgets('⌥⌘1 e ⌥⌘2 trocam o modo mesmo com o terminal focado', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(calls, ['modo:${ViewMode.chat.wire}']);
    expect(repository.keys, isEmpty);
  });
}

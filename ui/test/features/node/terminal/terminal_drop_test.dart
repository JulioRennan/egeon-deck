import 'package:egeon_deck/features/node/terminal/domain/usecase/resize_terminal.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/send_terminal_input.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/watch_terminal.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/watch_terminal_effects.dart';
import 'package:egeon_deck/features/node/terminal/presentation/cubit/terminal_cubit.dart';
import 'package:egeon_deck/features/node/terminal/presentation/page/terminal_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_terminal_repository.dart';

/// Arquivo solto no terminal: o runner nativo avisa pelo canal do plugin; a UI
/// entrega os caminhos ao cubit e leva o foco ao terminal.
void main() {
  Future<void> platform(WidgetTester tester, String method, Object args) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'desktop_drop',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );

  Future<FakeTerminalRepository> pump(WidgetTester tester) async {
    final repository = FakeTerminalRepository();
    final cubit = TerminalCubit(
      nodeId: 'n1',
      watch: WatchTerminal(repository),
      input: SendTerminalInput(repository),
      resize: ResizeTerminal(repository),
      effects: WatchTerminalEffects(repository),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BlocProvider.value(
          value: cubit,
          child: const TerminalPage(autofocus: false),
        ),
      ),
    );
    return repository;
  }

  testWidgets('arquivos soltos viram um dropFiles com os caminhos', (
    tester,
  ) async {
    final repository = await pump(tester);

    await platform(tester, 'entered', [20.0, 20.0]);
    await platform(tester, 'performOperation_macos', [
      {'path': '/tmp/a.png', 'isDirectory': false},
      {'path': '/tmp/b.txt', 'isDirectory': false},
    ]);
    await tester.pump();

    expect(repository.drops, [
      ['/tmp/a.png', '/tmp/b.txt'],
    ]);
  });

  testWidgets('soltar leva o foco ao terminal', (tester) async {
    await pump(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('terminal'));

    await platform(tester, 'entered', [20.0, 20.0]);
    await platform(tester, 'performOperation_macos', [
      {'path': '/tmp/a.png', 'isDirectory': false},
    ]);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'terminal');
  });

  testWidgets('largar fora da tela do terminal não manda nada', (tester) async {
    final repository = await pump(tester);

    await platform(tester, 'entered', [-50.0, -50.0]);
    await platform(tester, 'performOperation_macos', [
      {'path': '/tmp/a.png', 'isDirectory': false},
    ]);
    await tester.pump();

    expect(repository.drops, isEmpty);
  });
}

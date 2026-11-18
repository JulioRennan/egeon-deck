import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_cursor.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_frame.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_line.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/resize_terminal.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/send_terminal_input.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/watch_terminal.dart';
import 'package:egeon_deck/features/node/terminal/presentation/cubit/terminal_cubit.dart';
import 'package:egeon_deck/features/node/terminal/presentation/page/terminal_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_terminal_repository.dart';

TerminalFrame frame(
  Map<int, String> texts, {
  int columns = 20,
  int rows = 4,
  int cursorRow = 0,
  int cursorColumn = 0,
}) => TerminalFrame(
  columns: columns,
  rows: rows,
  lines: {
    for (final e in texts.entries)
      e.key: TerminalLine([
        TerminalRun(column: 0, cells: e.value.length, text: e.value),
      ]),
  },
  cursor: TerminalCursor(row: cursorRow, column: cursorColumn),
);

void main() {
  late FakeTerminalRepository repository;
  late TerminalCubit cubit;

  Future<void> pumpTerminal(WidgetTester tester) async {
    repository = FakeTerminalRepository();
    cubit = TerminalCubit(
      nodeId: 'n1',
      watch: WatchTerminal(repository),
      input: SendTerminalInput(repository),
      resize: ResizeTerminal(repository),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BlocProvider.value(value: cubit, child: const TerminalPage()),
      ),
    );
  }

  Iterable<CustomPaint> rowPaints(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .where((p) => p.painter != null);

  testWidgets('uma linha por linha da grade, com o texto do quadro', (
    tester,
  ) async {
    await pumpTerminal(tester);
    repository.push(frame({0: 'echo oi', 1: 'oi'}));
    await tester.pump();

    expect(rowPaints(tester), hasLength(4));
    expect(cubit.state.live, isTrue);
    expect(cubit.state.columns, 20);
    expect(cubit.lastFrame!.lines[1]!.runs.single.text, 'oi');
  });

  testWidgets('quadro novo só repinta as linhas que mudaram', (tester) async {
    await pumpTerminal(tester);
    repository.push(frame({0: 'a', 1: 'b', 2: 'c'}));
    await tester.pump();
    await tester.pump();
    final before = rowPaints(tester).map((p) => p.painter).toList();

    repository.push(frame({1: 'novo'}));
    await tester.pump();
    await tester.pump();
    final after = rowPaints(tester).map((p) => p.painter).toList();

    expect(identical(before[0], after[0]), isTrue);
    expect(identical(before[1], after[1]), isFalse);
    expect(identical(before[2], after[2]), isTrue);
  });

  testWidgets('texto digitado chega como texto UTF-8 pelo método de entrada', (
    tester,
  ) async {
    await pumpTerminal(tester);
    repository.push(frame({}));
    await tester.pump();

    tester.testTextInput.enterText('ação é ü');
    await tester.pump();

    expect(repository.texts, ['ação é ü']);
    expect(repository.keys, isEmpty);
  });

  testWidgets('letra e espaço sem modificador não viram tecla', (tester) async {
    await pumpTerminal(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyO, character: 'o');
    await tester.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');

    expect(repository.keys, isEmpty);
  });

  testWidgets('tecla morta: o acento só sai junto com a letra', (tester) async {
    await pumpTerminal(tester);
    repository.push(frame({}));
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '´',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      ),
    );
    await tester.pump();
    expect(repository.texts, isEmpty);
    expect(find.text('´'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    expect(repository.keys, isEmpty);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'á',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(repository.texts, ['á']);
    expect(find.text('´'), findsNothing);
  });

  testWidgets('til e ç compostos saem como texto', (tester) async {
    await pumpTerminal(tester);
    tester.testTextInput.enterText('ã');
    tester.testTextInput.enterText('ç');
    await tester.pump();

    expect(repository.texts, ['ã', 'ç']);
  });

  testWidgets('conexão de texto fechada pelo sistema é reaberta com o foco', (
    tester,
  ) async {
    int attaches() => tester.testTextInput.log
        .where((call) => call.method == 'TextInput.setClient')
        .length;

    await pumpTerminal(tester);
    expect(attaches(), 1);

    // O sistema fecha a conexão com o foco ainda no terminal: ele reabre na
    // hora. Sem isso as letras, que ficam com o método de entrada, sumiriam
    // em silêncio.
    tester.testTextInput.closeConnection();
    await tester.pump();
    expect(attaches(), 2);

    tester.testTextInput.enterText('a');
    await tester.pump();
    expect(repository.texts, ['a']);
  });

  testWidgets('⌘V cola pelo comando paste, não por input', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': 'colado\ncom linhas'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpTerminal(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(repository.pastes, ['colado\ncom linhas']);
    expect(repository.texts, isEmpty);
  });

  testWidgets('teclas especiais seguem pelo caminho de tecla', (tester) async {
    await pumpTerminal(tester);
    repository.push(frame({}));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);

    expect(repository.keys.map((k) => k.key), ['enter', 'up', 'backspace']);
  });

  testWidgets('Ctrl+espaço vai como a tecla "space"', (tester) async {
    await pumpTerminal(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(repository.keys.single.key, 'space');
    expect(repository.keys.single.ctrl, isTrue);
  });

  testWidgets('Ctrl+C chega com o modificador', (tester) async {
    await pumpTerminal(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    final key = repository.keys.single;
    expect(key.ctrl, isTrue);
    expect(key.key, 'c');
    expect(key.text, isNull);
  });

  testWidgets('informa colunas × linhas do espaço disponível', (tester) async {
    await pumpTerminal(tester);
    await tester.pump();

    final (columns, rows) = repository.resizes.single;
    expect(columns, greaterThan(10));
    expect(rows, greaterThan(5));
  });

  testWidgets('fechar o cubit cancela a assinatura', (tester) async {
    await pumpTerminal(tester);
    expect(repository.watchers, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(cubit.close);
    expect(repository.watchers, 0);
  });
}

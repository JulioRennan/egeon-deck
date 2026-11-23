import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_cursor.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_effect.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_frame.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_line.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_pointer.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_scrollbar.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/resize_terminal.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/send_terminal_input.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/watch_terminal.dart';
import 'package:egeon_deck/features/node/terminal/domain/usecase/watch_terminal_effects.dart';
import 'package:egeon_deck/features/node/terminal/presentation/cubit/terminal_cubit.dart';
import 'package:egeon_deck/features/node/terminal/presentation/page/terminal_page.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_metrics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/eg_host.dart';
import '../../../support/fake_terminal_repository.dart';

/// Mouse, seleção, rolagem, cópia e efeitos (US-405, lado UI). A UI manda tudo
/// cru; quem decide é o core.
void main() {
  late FakeTerminalRepository repository;
  late TerminalCubit cubit;
  final cell = TerminalMetrics.measure();
  final clipboardWrites = <String>[];
  String clipboardText = '';
  var beeps = 0;

  TerminalFrame frame({
    int rows = 10,
    int columns = 40,
    TerminalScrollbar? scrollbar,
    TerminalSelection? selection,
  }) => TerminalFrame(
    columns: columns,
    rows: rows,
    full: true,
    scrollbar: scrollbar,
    lines: {
      0: TerminalLine([
        const TerminalRun(column: 0, cells: 5, text: 'hello'),
      ], selection: selection),
    },
    cursor: const TerminalCursor(row: 0, column: 0),
  );

  Future<void> pumpTerminal(WidgetTester tester) async {
    repository = FakeTerminalRepository();
    cubit = TerminalCubit(
      nodeId: 'n1',
      watch: WatchTerminal(repository),
      input: SendTerminalInput(repository),
      resize: ResizeTerminal(repository),
      effects: WatchTerminalEffects(repository),
    );
    addTearDown(cubit.close);
    clipboardWrites.clear();
    clipboardText = '';
    beeps = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboardWrites.add((call.arguments as Map)['text']! as String);
          case 'Clipboard.getData':
            return {'text': clipboardText};
          case 'SystemSound.play':
            beeps++;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.view
      ..physicalSize = Size(cell.cellWidth * 40, cell.cellHeight * 10)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      egHost(
        BlocProvider.value(value: cubit, child: const TerminalPage()),
        fill: true,
      ),
    );
    repository.push(frame());
    await tester.pump();
    await tester.pump();
  }

  Offset cellAt(double column, double row) =>
      Offset(column * cell.cellWidth, row * cell.cellHeight);

  testWidgets(
    'apertar, arrastar e soltar chegam crus, em células fracionárias',
    (tester) async {
      await pumpTerminal(tester);
      final gesture = await tester.startGesture(cellAt(3.4, 2.5));
      await gesture.moveTo(cellAt(8.25, 2.5));
      await gesture.up();
      await tester.pump();

      final kinds = repository.pointers.map((p) => p.kind).toList();
      expect(kinds, [PointerKind.press, PointerKind.drag, PointerKind.release]);
      final press = repository.pointers.first;
      expect(press.button, PointerButton.left);
      expect(press.x, closeTo(3.4, 0.01));
      expect(press.y, closeTo(2.5, 0.01));
      expect(repository.pointers[1].x, closeTo(8.25, 0.01));
      expect(repository.pointers.last.button, PointerButton.left);
    },
  );

  testWidgets('os modificadores vão no gesto', (tester) async {
    await pumpTerminal(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final gesture = await tester.startGesture(cellAt(1, 1));
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(repository.pointers.first.shift, isTrue);
    expect(repository.pointers.first.ctrl, isFalse);
    expect(repository.pointers.first.toMap()['mods'], {'shift': true});
  });

  testWidgets('botão do meio e direito levam o nome do botão', (tester) async {
    await pumpTerminal(tester);
    final middle = await tester.startGesture(
      cellAt(1, 1),
      buttons: kMiddleMouseButton,
    );
    await middle.up();
    final right = await tester.startGesture(
      cellAt(1, 1),
      buttons: kSecondaryButton,
    );
    await right.up();
    expect(
      repository.pointers
          .where((p) => p.kind == PointerKind.press)
          .map((p) => p.button),
      [PointerButton.middle, PointerButton.right],
    );
  });

  testWidgets('⌥ é pan do canvas: o terminal não recebe o gesto', (
    tester,
  ) async {
    await pumpTerminal(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final gesture = await tester.startGesture(cellAt(1, 1));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(repository.pointers, isEmpty);
  });

  testWidgets('a roda acumula pixels e solta linhas inteiras, positivo sobe', (
    tester,
  ) async {
    await pumpTerminal(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(cellAt(5, 5)));

    // Menos que uma linha: nada ainda.
    await tester.sendEventToBinding(
      mouse.scroll(Offset(0, -(cell.cellHeight * 0.4))),
    );
    expect(repository.pointers, isEmpty);
    // Completa duas linhas (para cima = dy negativo no Flutter).
    await tester.sendEventToBinding(
      mouse.scroll(Offset(0, -(cell.cellHeight * 1.7))),
    );
    expect(repository.pointers, hasLength(1));
    expect(repository.pointers.single.kind, PointerKind.wheel);
    expect(repository.pointers.single.lines, 2);
    expect(repository.pointers.single.button, isNull);

    // Para baixo: negativo.
    await tester.sendEventToBinding(
      mouse.scroll(Offset(0, cell.cellHeight * 3.2)),
    );
    expect(repository.pointers.last.lines, -3);
  });

  testWidgets('⌘+scroll é zoom do canvas: o terminal o ignora', (tester) async {
    await pumpTerminal(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(cellAt(5, 5)));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendEventToBinding(
      mouse.scroll(Offset(0, -cell.cellHeight * 5)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(repository.pointers, isEmpty);
  });

  testWidgets('segurando fora da vista o arrasto se repete a cada 50 ms', (
    tester,
  ) async {
    await pumpTerminal(tester);
    final gesture = await tester.startGesture(cellAt(2, 5));
    await gesture.moveTo(cellAt(2, 12)); // abaixo das 10 linhas
    final afterMove = repository.pointers.length;
    expect(repository.pointers.last.y, greaterThanOrEqualTo(10));

    await tester.pump(const Duration(milliseconds: 160));
    final repeats = repository.pointers.length - afterMove;
    expect(repeats, inInclusiveRange(2, 4));
    expect(
      repository.pointers
          .skip(afterMove)
          .every((p) => p.kind == PointerKind.drag),
      isTrue,
    );

    // Voltando para dentro, para.
    await gesture.moveTo(cellAt(2, 4));
    final inside = repository.pointers.length;
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.pointers.length, inside);

    await gesture.up();
  });

  testWidgets('soltar fora da vista também para o timer', (tester) async {
    await pumpTerminal(tester);
    final gesture = await tester.startGesture(cellAt(2, 5));
    await gesture.moveTo(cellAt(2, -3));
    await gesture.up();
    await tester.pump();
    final count = repository.pointers.length;
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.pointers.length, count);
    expect(repository.pointers.last.kind, PointerKind.release);
  });

  group('barra de rolagem', () {
    testWidgets('só aparece com histórico acima do que se vê', (tester) async {
      await pumpTerminal(tester);
      expect(find.byKey(const ValueKey('scrollbar-thumb')), findsNothing);

      repository.push(
        frame(
          scrollbar: const TerminalScrollbar(total: 24, offset: 0, len: 24),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('scrollbar-thumb')), findsNothing);

      repository.push(
        frame(
          scrollbar: const TerminalScrollbar(total: 100, offset: 76, len: 24),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('scrollbar-thumb')), findsOneWidget);
    });

    testWidgets('arrastar a pegada manda linhas ao core', (tester) async {
      await pumpTerminal(tester);
      repository.push(
        frame(
          scrollbar: const TerminalScrollbar(total: 100, offset: 76, len: 24),
        ),
      );
      await tester.pump();
      await tester.pump();
      final thumb = tester.getCenter(
        find.byKey(const ValueKey('scrollbar-thumb')),
      );
      final gesture = await tester.startGesture(thumb);
      await gesture.moveBy(const Offset(0, -10));
      await gesture.up();
      await tester.pump();

      final rows = repository.scrolls.whereType<ScrollRows>().map(
        (s) => s.rows,
      );
      expect(rows, isNotEmpty);
      expect(
        rows.every((r) => r < 0),
        isTrue,
        reason: 'puxar a pegada para cima sobe o histórico',
      );
      // Arrastar a pegada não vira clique no terminal.
      expect(
        repository.pointers.where((p) => p.kind == PointerKind.drag),
        isEmpty,
      );
    });
  });

  group('⌘ sobre um link', () {
    Future<TestGesture> hover(WidgetTester tester, Offset at) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(at);
      await tester.pump();
      await tester.pump();
      return mouse;
    }

    MouseCursor cursor() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

    testWidgets('sem ⌘ o ponteiro é I-beam e o core nem é perguntado', (
      tester,
    ) async {
      await pumpTerminal(tester);
      repository.linkUnderCursor = true;
      await hover(tester, cellAt(3.5, 2.5));
      expect(cursor(), SystemMouseCursors.text);
      expect(repository.hovers, isEmpty);
    });

    testWidgets('com ⌘ e link na célula, mostra a mão; sem link, I-beam', (
      tester,
    ) async {
      await pumpTerminal(tester);
      repository.linkUnderCursor = true;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      final mouse = await hover(tester, cellAt(3.5, 2.5));
      expect(repository.hovers.single.$1, closeTo(3.5, 0.01));
      expect(cursor(), SystemMouseCursors.click);

      repository.linkUnderCursor = false;
      await mouse.moveTo(cellAt(9.5, 2.5));
      await tester.pump();
      await tester.pump();
      expect(cursor(), SystemMouseCursors.text);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });

    testWidgets('soltar o ⌘ desfaz a mão sem mexer o mouse', (tester) async {
      await pumpTerminal(tester);
      repository.linkUnderCursor = true;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await hover(tester, cellAt(3.5, 2.5));
      expect(cursor(), SystemMouseCursors.click);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(cursor(), SystemMouseCursors.text);
    });

    testWidgets('na mesma célula o core é perguntado uma vez só', (
      tester,
    ) async {
      await pumpTerminal(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      final mouse = await hover(tester, cellAt(3.2, 2.5));
      await mouse.moveTo(cellAt(3.6, 2.6));
      await tester.pump();
      await tester.pump();
      expect(repository.hovers, hasLength(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });
  });

  testWidgets('⌘A seleciona tudo; ⌘C copia o que o core devolve', (
    tester,
  ) async {
    await pumpTerminal(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    expect(repository.selectAlls, 0, reason: 'sem ⌘ é só uma letra');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(repository.selectAlls, 1);

    repository.copied = 'hello';
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(clipboardWrites, ['hello']);
    expect(repository.keys, isEmpty, reason: 'o atalho não vai ao pty');
  });

  testWidgets('⌘C sem seleção não mexe na área de transferência', (
    tester,
  ) async {
    await pumpTerminal(tester);
    repository.copied = '';
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(clipboardWrites, isEmpty);
  });

  group('efeitos', () {
    testWidgets('bell toca o alerta do sistema', (tester) async {
      await pumpTerminal(tester);
      repository.effectsController.add(const Bell());
      await tester.pump();
      await tester.pump();
      expect(beeps, 1);
    });

    testWidgets('OSC 52 de escrita grava na área de transferência', (
      tester,
    ) async {
      await pumpTerminal(tester);
      repository.effectsController.add(
        const ClipboardWrite('copiado pelo programa'),
      );
      await tester.pump();
      await tester.pump();
      expect(clipboardWrites, ['copiado pelo programa']);
    });

    testWidgets('OSC 52 de leitura só manda a área quando o programa pede', (
      tester,
    ) async {
      await pumpTerminal(tester);
      clipboardText = 'segredo';
      await tester.pump();
      expect(repository.clipboards, isEmpty, reason: 'nada vai sem pedido');

      repository.effectsController.add(const ClipboardRequest());
      await tester.pump();
      await tester.pump();
      expect(repository.clipboards, ['segredo']);
    });
  });

  test('o efeito sai do fio pelo campo `effect`', () {
    expect(TerminalEffect.tryParse({'effect': 'bell'}), isA<Bell>());
    expect(
      (TerminalEffect.tryParse({
        'effect': 'clipboard',
        'text': 'x',
      }) as ClipboardWrite).text,
      'x',
    );
    expect(
      TerminalEffect.tryParse({'effect': 'clipboard_request'}),
      isA<ClipboardRequest>(),
    );
  });

  test('o gesto vai ao fio com os nomes do contrato', () {
    const pointer = TerminalPointer(
      kind: PointerKind.wheel,
      x: 3.4,
      y: 1,
      timeMs: 1200,
      ctrl: true,
      lines: 3,
    );
    expect(pointer.toMap(), {
      'kind': 'wheel',
      'x': 3.4,
      'y': 1.0,
      'mods': {'ctrl': true},
      'time_ms': 1200,
      'lines': 3,
    });
    expect(const ScrollRows(-3).toWire(), {'rows': -3});
    expect(const ScrollTop().toWire(), 'top');
    expect(const ScrollBottom().toWire(), 'bottom');
  });

  test('o cursor do terminal continua I-beam (sem cursor mouse)', () {
    expect(SystemMouseCursors.text, isNotNull);
  });
}

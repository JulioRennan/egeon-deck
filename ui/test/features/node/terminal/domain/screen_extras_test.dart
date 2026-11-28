import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_frame.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

/// scrollbar e selection (US-405): campos opcionais, omitidos quando vazios.
void main() {
  Map<String, Object?> frame({
    String kind = 'full',
    Map<String, Object?>? scrollbar,
    List<int>? selection,
  }) => {
    'kind': kind,
    'cols': 80,
    'rows': 24,
    'cursor': {'col': 0, 'row': 0, 'shape': 'block', 'visible': true},
    'scrollbar': ?scrollbar,
    'lines': [
      {
        'row': 3,
        'spans': [
          {'col': 0, 'cells': 5, 'text': 'hello'},
        ],
        'selection': ?selection,
      },
    ],
  };

  test('a barra e a seleção fazem ida e volta', () {
    final map = frame(
      scrollbar: {'total': 24, 'offset': 0, 'len': 24},
      selection: [6, 10],
    );
    final parsed = TerminalFrame.fromMap(map);
    expect(parsed.scrollbar!.total, 24);
    expect(parsed.lines[3]!.selection, (start: 6, end: 10));
    expect(parsed.toMap(), map);
  });

  test(
    'sem os campos, nada aparece na volta (a fixture antiga segue valendo)',
    () {
      final map = frame();
      final parsed = TerminalFrame.fromMap(map);
      expect(parsed.scrollbar, isNull);
      expect(parsed.lines[3]!.selection, isNull);
      expect(parsed.toMap(), map);
    },
  );

  test('o delta sem barra mantém a última; o full sem barra a limpa', () {
    final buffer = TerminalBuffer();
    buffer.apply(
      TerminalFrame.fromMap(
        frame(scrollbar: {'total': 100, 'offset': 76, 'len': 24}),
      ),
    );
    expect(buffer.scrollbar.value!.offset, 76);

    buffer.apply(TerminalFrame.fromMap(frame(kind: 'delta')));
    expect(buffer.scrollbar.value!.total, 100);

    buffer.apply(
      TerminalFrame.fromMap(
        frame(
          kind: 'delta',
          scrollbar: {'total': 100, 'offset': 10, 'len': 24},
        ),
      ),
    );
    expect(buffer.scrollbar.value!.offset, 10);
    expect(buffer.scrollbar.value!.scrollable, isTrue);

    buffer.apply(TerminalFrame.fromMap(frame()));
    expect(buffer.scrollbar.value, isNull);
    buffer.dispose();
  });
}

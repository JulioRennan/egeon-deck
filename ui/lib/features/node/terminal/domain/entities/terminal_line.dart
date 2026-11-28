import 'terminal_style.dart';

/// Um trecho contíguo de uma linha com o mesmo estilo, a partir da coluna
/// [column] e ocupando [cells] células (um caractere largo ocupa duas).
class TerminalRun {
  const TerminalRun({
    required this.column,
    required this.cells,
    required this.text,
    this.style = TerminalStyle.plain,
  });

  final int column;
  final int cells;
  final String text;
  final TerminalStyle style;

  factory TerminalRun.fromMap(Map<String, Object?> map) => TerminalRun(
    column: map['col']! as int,
    cells: map['cells']! as int,
    text: map['text']! as String,
    style: TerminalStyle.fromMap(map),
  );

  Map<String, Object?> toMap() => {
    'col': column,
    'cells': cells,
    'text': text,
    ...style.toMap(),
  };
}

/// Colunas selecionadas de uma linha, inclusivas nas duas pontas.
typedef TerminalSelection = ({int start, int end});

class TerminalLine {
  const TerminalLine(this.runs, {this.selection});

  static const empty = TerminalLine([]);

  final List<TerminalRun> runs;

  /// Só nas linhas que a seleção cruza. Quem pinta é a UI, com estas colunas.
  final TerminalSelection? selection;

  factory TerminalLine.fromSpans(
    List<Object?> spans, {
    List<Object?>? selection,
  }) => TerminalLine(
    [
      for (final span in spans)
        TerminalRun.fromMap(span! as Map<String, Object?>),
    ],
    selection: selection == null
        ? null
        : (start: selection[0]! as int, end: selection[1]! as int),
  );

  /// A linha como o core a manda: `{row, spans, selection?}` sem o `row`.
  Map<String, Object?> toLineMap(int row) => {
    'row': row,
    'spans': toSpans(),
    if (selection != null) 'selection': [selection!.start, selection!.end],
  };

  List<Map<String, Object?>> toSpans() => [for (final r in runs) r.toMap()];
}

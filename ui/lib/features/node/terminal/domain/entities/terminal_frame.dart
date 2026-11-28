import 'terminal_cursor.dart';
import 'terminal_line.dart';
import 'terminal_scrollbar.dart';

/// A tela de um terminal como o core Rust a manda pelo tópico `screen/<id>`.
///
/// [full] traz a tela inteira (linha que não aparece em [lines] está vazia);
/// senão é só a diferença: as linhas que mudaram, índice → linha.
class TerminalFrame {
  const TerminalFrame({
    required this.columns,
    required this.rows,
    required this.lines,
    required this.cursor,
    this.full = false,
    this.scrollbar,
  });

  final int columns;
  final int rows;
  final Map<int, TerminalLine> lines;
  final TerminalCursor cursor;
  final bool full;

  /// Vem sempre no `full` e no `delta` só quando mudou.
  final TerminalScrollbar? scrollbar;

  factory TerminalFrame.fromMap(Map<String, Object?> map) => TerminalFrame(
    columns: map['cols']! as int,
    rows: map['rows']! as int,
    full: map['kind'] == 'full',
    cursor: TerminalCursor.fromMap(map['cursor']! as Map<String, Object?>),
    scrollbar: map['scrollbar'] == null
        ? null
        : TerminalScrollbar.fromMap(map['scrollbar']! as Map<String, Object?>),
    lines: {
      for (final line in (map['lines']! as List<Object?>))
        (line! as Map<String, Object?>)['row']! as int: TerminalLine.fromSpans(
          (line as Map<String, Object?>)['spans']! as List<Object?>,
          selection: line['selection'] as List<Object?>?,
        ),
    },
  );

  Map<String, Object?> toMap() => {
    'kind': full ? 'full' : 'delta',
    'cols': columns,
    'rows': rows,
    'cursor': cursor.toMap(),
    if (scrollbar != null) 'scrollbar': scrollbar!.toMap(),
    'lines': [for (final e in lines.entries) e.value.toLineMap(e.key)],
  };
}

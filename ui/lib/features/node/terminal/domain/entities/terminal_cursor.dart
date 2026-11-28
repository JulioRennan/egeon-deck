enum TerminalCursorShape { block, bar, underline }

class TerminalCursor {
  const TerminalCursor({
    required this.row,
    required this.column,
    this.shape = TerminalCursorShape.block,
    this.visible = true,
  });

  static const hidden = TerminalCursor(row: 0, column: 0, visible: false);

  final int row;
  final int column;
  final TerminalCursorShape shape;
  final bool visible;

  factory TerminalCursor.fromMap(Map<String, Object?> map) => TerminalCursor(
    row: map['row']! as int,
    column: map['col']! as int,
    shape: TerminalCursorShape.values.firstWhere(
      (s) => s.name == map['shape'],
      orElse: () => TerminalCursorShape.block,
    ),
    visible: map['visible'] != false,
  );

  Map<String, Object?> toMap() => {
    'row': row,
    'col': column,
    'shape': shape.name,
    'visible': visible,
  };
}

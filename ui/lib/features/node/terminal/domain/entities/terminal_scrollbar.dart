/// A barra de rolagem do histórico, em linhas. [offset] é a primeira linha
/// visível contada do topo do histórico; no fim, `offset == total - len`.
class TerminalScrollbar {
  const TerminalScrollbar({
    required this.total,
    required this.offset,
    required this.len,
  });

  final int total;
  final int offset;
  final int len;

  factory TerminalScrollbar.fromMap(Map<String, Object?> map) =>
      TerminalScrollbar(
        total: map['total']! as int,
        offset: map['offset']! as int,
        len: map['len']! as int,
      );

  Map<String, Object?> toMap() => {
    'total': total,
    'offset': offset,
    'len': len,
  };

  /// Há histórico acima do que se vê.
  bool get scrollable => total > len;

  @override
  bool operator ==(Object other) =>
      other is TerminalScrollbar &&
      other.total == total &&
      other.offset == offset &&
      other.len == len;

  @override
  int get hashCode => Object.hash(total, offset, len);
}

/// O que a tela do terminal precisa saber além das linhas, que vão direto do
/// stream para o widget.
class TerminalState {
  const TerminalState({this.live = false, this.columns = 0, this.rows = 0});

  final bool live;
  final int columns;
  final int rows;

  TerminalState copyWith({bool? live, int? columns, int? rows}) =>
      TerminalState(
        live: live ?? this.live,
        columns: columns ?? this.columns,
        rows: rows ?? this.rows,
      );
}

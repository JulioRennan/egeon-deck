part of 'terminal_cubit.dart';

/// O que a tela do terminal precisa saber além das linhas, que vão direto do
/// stream para o widget: se o core já mandou a tela, e o tamanho dela.
sealed class TerminalState {
  const TerminalState();
}

/// Nenhum quadro ainda.
final class TerminalWaiting extends TerminalState {
  const TerminalWaiting();
}

final class TerminalLive extends TerminalState {
  const TerminalLive({required this.columns, required this.rows});

  final int columns;
  final int rows;
}

/// O que pode dar errado num comando do terminal.
sealed class TerminalError implements Exception {
  const TerminalError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class TerminalRefused extends TerminalError {
  const TerminalRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class TerminalOffline extends TerminalError {
  const TerminalOffline();
}

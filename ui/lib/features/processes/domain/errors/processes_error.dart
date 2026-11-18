/// O que pode dar errado num comando da janela Processos.
sealed class ProcessesError implements Exception {
  const ProcessesError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class ProcessesRefused extends ProcessesError {
  const ProcessesRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class ProcessesOffline extends ProcessesError {
  const ProcessesOffline();
}

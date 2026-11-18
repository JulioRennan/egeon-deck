/// O que pode dar errado num comando da bancada.
sealed class WorkbenchError implements Exception {
  const WorkbenchError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class WorkbenchRefused extends WorkbenchError {
  const WorkbenchRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class WorkbenchOffline extends WorkbenchError {
  const WorkbenchOffline();
}

/// O que pode dar errado num comando da fila.
sealed class QueueError implements Exception {
  const QueueError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class QueueRefused extends QueueError {
  const QueueRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class QueueOffline extends QueueError {
  const QueueOffline();
}

/// O que pode dar errado num comando do canvas.
sealed class CanvasError implements Exception {
  const CanvasError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class CanvasRefused extends CanvasError {
  const CanvasRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class CanvasOffline extends CanvasError {
  const CanvasOffline();
}

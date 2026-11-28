/// O que pode dar errado num comando do nó web.
sealed class WebError implements Exception {
  const WebError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class WebRefused extends WebError {
  const WebRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class WebOffline extends WebError {
  const WebOffline();
}

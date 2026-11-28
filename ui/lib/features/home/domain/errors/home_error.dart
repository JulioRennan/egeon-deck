/// O que pode dar errado num comando da casca: vista, acesso à pasta e
/// resposta a pedido de tela.
sealed class HomeError implements Exception {
  const HomeError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class HomeRefused extends HomeError {
  const HomeRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class HomeOffline extends HomeError {
  const HomeOffline();
}

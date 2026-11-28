/// O que pode dar errado num comando da atualização e do menu do app.
sealed class UpdateError implements Exception {
  const UpdateError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class UpdateRefused extends UpdateError {
  const UpdateRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class UpdateOffline extends UpdateError {
  const UpdateOffline();
}

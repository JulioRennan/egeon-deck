/// O que pode dar errado num comando do chat.
sealed class ChatError implements Exception {
  const ChatError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class ChatRefused extends ChatError {
  const ChatRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class ChatOffline extends ChatError {
  const ChatOffline();
}

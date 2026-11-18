/// O que pode dar errado num comando das abas.
sealed class TabsError implements Exception {
  const TabsError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class TabsRefused extends TabsError {
  const TabsRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class TabsOffline extends TabsError {
  const TabsOffline();
}

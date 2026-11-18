/// O que pode dar errado num comando da barra lateral.
sealed class SidebarError implements Exception {
  const SidebarError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class SidebarRefused extends SidebarError {
  const SidebarRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class SidebarOffline extends SidebarError {
  const SidebarOffline();
}

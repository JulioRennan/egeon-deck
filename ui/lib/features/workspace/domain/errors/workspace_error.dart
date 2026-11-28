/// O que pode dar errado num comando do workspace e dos projetos.
sealed class WorkspaceError implements Exception {
  const WorkspaceError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class WorkspaceRefused extends WorkspaceError {
  const WorkspaceRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class WorkspaceOffline extends WorkspaceError {
  const WorkspaceOffline();
}

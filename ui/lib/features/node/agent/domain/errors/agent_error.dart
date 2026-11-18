/// O que pode dar errado num comando da faixa do agente.
sealed class AgentError implements Exception {
  const AgentError();
}

/// O core Rust recusou; [message] é o texto dele, pronto para a tela.
final class AgentRefused extends AgentError {
  const AgentRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A conexão com o core caiu antes da resposta.
final class AgentOffline extends AgentError {
  const AgentOffline();
}

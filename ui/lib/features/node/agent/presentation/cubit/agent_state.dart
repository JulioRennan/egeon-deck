part of 'agent_cubit.dart';

/// A faixa do agente: esperando o core, ou com o estado que ele mandou.
sealed class AgentState {
  const AgentState();
}

/// O core ainda não mandou nada: a faixa não aparece.
final class AgentWaiting extends AgentState {
  const AgentWaiting();
}

final class AgentShown extends AgentState {
  const AgentShown(this.status);

  final AgentStatus status;
}

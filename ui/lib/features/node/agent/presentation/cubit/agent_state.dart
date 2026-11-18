import '../../domain/entities/agent_status.dart';

/// O que a faixa do agente mostra. Nulo enquanto o core não mandou nada.
class AgentState {
  const AgentState({this.status});

  final AgentStatus? status;
}

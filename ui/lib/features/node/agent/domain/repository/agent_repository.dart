import '../entities/agent_status.dart';
import '../entities/model_choice.dart';

abstract interface class AgentRepository {
  /// A faixa do agente [nodeId]. O core manda o estado inteiro a cada mudança.
  Stream<AgentStatus> watch(String nodeId);

  /// Você mexeu em algo. O core reinicia o processo e mantém a conversa.
  Future<void> choose(String nodeId, ModelChoice choice);

  /// Limpa a conversa deste agente. A confirmação é da tela.
  Future<void> clear(String nodeId);
}

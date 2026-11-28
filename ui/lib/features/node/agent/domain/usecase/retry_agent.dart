import '../repository/agent_repository.dart';

/// "Tentar agora" ou "Cancelar tentativa" no status do card (ADR-072).
class RetryAgent {
  const RetryAgent(this._repository);
  final AgentRepository _repository;

  Future<void> call(String nodeId, {required bool now}) =>
      _repository.retry(nodeId, now: now);
}

import '../repository/agent_repository.dart';

class ClearAgent {
  const ClearAgent(this._repository);
  final AgentRepository _repository;

  Future<void> call(String nodeId) => _repository.clear(nodeId);
}

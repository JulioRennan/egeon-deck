import '../entities/agent_status.dart';
import '../repository/agent_repository.dart';

class WatchAgent {
  const WatchAgent(this._repository);
  final AgentRepository _repository;

  Stream<AgentStatus> call(String nodeId) => _repository.watch(nodeId);
}

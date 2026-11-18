import '../entities/model_choice.dart';
import '../repository/agent_repository.dart';

class ChooseAgentOption {
  const ChooseAgentOption(this._repository);
  final AgentRepository _repository;

  Future<void> call(String nodeId, ModelChoice choice) =>
      _repository.choose(nodeId, choice);
}

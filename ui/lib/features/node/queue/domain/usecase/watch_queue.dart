import '../entities/prompt_queue.dart';
import '../repository/queue_repository.dart';

class WatchQueue {
  const WatchQueue(this._repository);
  final QueueRepository _repository;

  Stream<PromptQueue> call(String nodeId) => _repository.watch(nodeId);
}

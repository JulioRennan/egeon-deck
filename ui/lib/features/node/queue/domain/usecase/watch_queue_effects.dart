import '../entities/queue_effect.dart';
import '../repository/queue_repository.dart';

class WatchQueueEffects {
  const WatchQueueEffects(this._repository);
  final QueueRepository _repository;

  Stream<QueueEffect> call(String nodeId) => _repository.effects(nodeId);
}

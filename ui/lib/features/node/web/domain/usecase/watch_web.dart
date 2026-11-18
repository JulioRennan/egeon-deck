import '../entities/web_node_state.dart';
import '../repository/web_repository.dart';

class WatchWeb {
  const WatchWeb(this._repository);
  final WebRepository _repository;

  Stream<WebNodeState> call(String nodeId) => _repository.watch(nodeId);
}

import '../entities/web_node.dart';
import '../repository/web_repository.dart';

class WatchWeb {
  const WatchWeb(this._repository);
  final WebRepository _repository;

  Stream<WebNode> call(String nodeId) => _repository.watch(nodeId);
}

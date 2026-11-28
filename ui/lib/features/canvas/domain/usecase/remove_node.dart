import '../repository/canvas_repository.dart';

class RemoveNode {
  const RemoveNode(this._repository);
  final CanvasRepository _repository;

  Future<void> call(String workbenchId, String nodeId) =>
      _repository.removeNode(workbenchId, nodeId);
}

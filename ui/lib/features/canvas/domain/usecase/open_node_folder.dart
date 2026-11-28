import '../repository/canvas_repository.dart';

/// O ⌘-clique no subtítulo do card: a pasta do terminal no Finder.
class OpenNodeFolder {
  const OpenNodeFolder(this._repository);
  final CanvasRepository _repository;

  Future<void> call(String workbenchId, String nodeId) =>
      _repository.openFolder(workbenchId, nodeId);
}

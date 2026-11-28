import '../repository/canvas_repository.dart';

class WatchCanvas {
  const WatchCanvas(this._repository);
  final CanvasRepository _repository;

  Stream<CanvasSnapshot> call(String workbenchId) =>
      _repository.watch(workbenchId);
}

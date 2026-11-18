import 'dart:ui';

import '../repository/canvas_repository.dart';

class SaveFrames {
  const SaveFrames(this._repository);
  final CanvasRepository _repository;

  Future<void> call(String workbenchId, Map<String, Rect> frames) =>
      _repository.saveFrames(workbenchId, frames);
}

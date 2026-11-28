import 'dart:ui';

import '../entities/canvas_tool.dart';
import '../repository/canvas_repository.dart';

class PlaceNode {
  const PlaceNode(this._repository);
  final CanvasRepository _repository;

  Future<void> call(
    String workbenchId,
    CanvasTool tool,
    Rect frame, {
    String? component,
  }) => _repository.placeNode(workbenchId, tool, frame, component: component);
}

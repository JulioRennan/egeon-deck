import 'dart:ui';

import '../repository/canvas_repository.dart';

/// Avisa o core de onde está o foco: o app, e o nó de teclado.
class SetUiFocus {
  const SetUiFocus(this._repository);
  final CanvasRepository _repository;

  Future<void> call({
    required bool appActive,
    String? workbenchId,
    String? nodeId,
    Size? window,
  }) => _repository.setFocus(
    appActive: appActive,
    workbenchId: workbenchId,
    nodeId: nodeId,
    window: window,
  );
}

part of 'canvas_motion_cubit.dart';

/// Se a vista ou os cards se mexeram há pouco. Os corpos nativos (a página
/// web) esperam parar para voltar ao vivo.
sealed class CanvasMotionState {
  const CanvasMotionState();
}

final class CanvasStill extends CanvasMotionState {
  const CanvasStill();
}

/// Pan, zoom ou arrasto de card em curso, ou acabados há menos que o tempo de
/// assentar.
final class CanvasMoving extends CanvasMotionState {
  const CanvasMoving();
}

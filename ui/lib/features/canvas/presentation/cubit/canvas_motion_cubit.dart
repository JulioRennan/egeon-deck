import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

part 'canvas_motion_state.dart';

/// O movimento do canvas, à parte da interação: o realce de uma ligação
/// convive com o zoom pela roda. Segue o que o canvas diz ([moving]) e é dono
/// dessa assinatura.
class CanvasMotionCubit extends Cubit<CanvasMotionState> {
  CanvasMotionCubit(Stream<bool> moving) : super(const CanvasStill()) {
    _subscription = moving.listen(
      (on) => emit(on ? const CanvasMoving() : const CanvasStill()),
    );
  }

  StreamSubscription<bool>? _subscription;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

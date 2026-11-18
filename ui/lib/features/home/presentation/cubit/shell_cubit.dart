import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/entities/view_mode.dart';
import '../../domain/entities/shell_snapshot.dart';
import '../../domain/errors/home_error.dart';
import '../../domain/usecase/resolve_access_lock.dart';
import '../../domain/usecase/set_view_mode.dart';
import '../../domain/usecase/watch_shell.dart';

part 'shell_state.dart';

/// Dono da assinatura da casca: abre ao nascer e cancela no `close()`.
class ShellCubit extends Cubit<ShellState> {
  ShellCubit({
    required WatchShell watch,
    required this._setView,
    required this._access,
  }) : super(const ShellState()) {
    _subscription = watch().listen(
      (snapshot) => emit(state.copyWith(snapshot: snapshot)),
    );
  }

  final SetViewMode _setView;
  final ResolveAccessLock _access;
  StreamSubscription<ShellSnapshot>? _subscription;

  void toggleCollapsed() => setCollapsed(!state.collapsed);

  void setCollapsed(bool collapsed) =>
      emit(state.copyWith(collapsed: collapsed));

  void setView(ViewMode mode) => _fire(_setView(mode));

  void openSettings() => _fire(_access.openSettings());

  void askAccessAgain() => _fire(_access.askAgain());

  /// Gesto é "mande e siga": o que vale é o estado que o core devolve.
  void _fire(Future<void> future) =>
      unawaited(future.catchError((_) {}, test: (error) => error is HomeError));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

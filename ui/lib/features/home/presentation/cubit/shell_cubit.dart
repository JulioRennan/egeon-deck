import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/entities/view_mode.dart';
import '../../domain/entities/shell_state.dart';
import '../../domain/usecase/resolve_access_lock.dart';
import '../../domain/usecase/set_view_mode.dart';
import '../../domain/usecase/watch_shell.dart';

/// O que a casca guarda: o que o core mandou e se a barra está recolhida —
/// esta só da UI, é passageira.
class ShellView {
  const ShellView({this.shell = const ShellState(), this.collapsed = false});

  final ShellState shell;

  /// A barra lateral recolhida ao trilho (⌘/).
  final bool collapsed;

  ShellView copyWith({ShellState? shell, bool? collapsed}) => ShellView(
    shell: shell ?? this.shell,
    collapsed: collapsed ?? this.collapsed,
  );
}

/// Dono da assinatura da casca: abre ao nascer e cancela no `close()`.
class ShellCubit extends Cubit<ShellView> {
  ShellCubit({
    required WatchShell watch,
    required this._setView,
    required this._access,
  }) : super(const ShellView()) {
    _subscription = watch().listen(
      (shell) => emit(state.copyWith(shell: shell)),
    );
  }

  final SetViewMode _setView;
  final ResolveAccessLock _access;
  StreamSubscription<ShellState>? _subscription;

  void toggleCollapsed() => setCollapsed(!state.collapsed);

  void setCollapsed(bool collapsed) =>
      emit(state.copyWith(collapsed: collapsed));

  void setView(ViewMode mode) => _fire(_setView(mode));

  void openSettings() => _fire(_access.openSettings());

  void askAccessAgain() => _fire(_access.askAgain());

  /// Gesto é "mande e siga": o que vale é o estado que o core devolve.
  void _fire(Future<void> future) => unawaited(future.catchError((_) {}));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

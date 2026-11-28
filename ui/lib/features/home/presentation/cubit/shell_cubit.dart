import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/entities/view_mode.dart';
import '../../domain/entities/shell_snapshot.dart';
import '../../domain/errors/home_error.dart';
import '../../domain/usecase/copy_dispatch_targets.dart';
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
    required this._copyTargets,
  }) : super(const ShellCollapsed()) {
    _subscription = watch().listen((snapshot) => emit(_withSnapshot(snapshot)));
  }

  final SetViewMode _setView;
  final ResolveAccessLock _access;
  final CopyDispatchTargets _copyTargets;
  StreamSubscription<ShellSnapshot>? _subscription;

  /// A gaveta de bancadas está fechada.
  bool get collapsed => state is ShellCollapsed;

  /// O estado novo do core, com a gaveta como estava: escolher outra bancada
  /// por ela não a fecha (o usuário quer seguir navegando). Quem a fecha é o
  /// clique fora, o Esc, o ⌘/ ou o mouse que sai.
  ShellState _withSnapshot(ShellSnapshot snapshot) => switch (state) {
    ShellCollapsed() => ShellCollapsed(snapshot),
    ShellExpanded() => ShellExpanded(snapshot),
    ShellPeeking() => ShellPeeking(snapshot),
  };

  /// ⌘/: abre a gaveta ou, com ela à vista, fecha. Aberta pelo mouse, o
  /// clique a deixa aberta: quem passou o mouse e clicou quer ela ali.
  void toggleCollapsed() {
    if (state is ShellPeeking) {
      emit(ShellExpanded(state.snapshot));
    } else {
      setCollapsed(!collapsed);
    }
  }

  /// O mouse entrou no botão da gaveta: abre enquanto ele estiver por ali.
  void peek() {
    if (state is ShellCollapsed) emit(ShellPeeking(state.snapshot));
  }

  /// O mouse saiu: fecha só a que ele abriu.
  void endPeek() {
    if (state is ShellPeeking) emit(ShellCollapsed(state.snapshot));
  }

  void setCollapsed(bool collapsed) {
    if (collapsed == this.collapsed) return;
    if (collapsed) {
      emit(ShellCollapsed(state.snapshot));
    } else {
      emit(ShellExpanded(state.snapshot));
    }
  }

  void setView(ViewMode mode) => _fire(_setView(mode));

  void openSettings() => _fire(_access.openSettings());

  void askAccessAgain() => _fire(_access.askAgain());

  /// ⇧⌘T: sem core, não há o que copiar e a área de transferência fica.
  void copyTargets() => _fire(_copyTargets());

  /// Gesto é "mande e siga": o que vale é o estado que o core devolve.
  void _fire(Future<void> future) =>
      unawaited(future.catchError((_) {}, test: (error) => error is HomeError));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

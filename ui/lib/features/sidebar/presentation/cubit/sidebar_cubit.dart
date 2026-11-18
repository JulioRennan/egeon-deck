import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/sidebar_tree.dart';
import '../../domain/errors/sidebar_error.dart';
import '../../domain/repository/sidebar_repository.dart' show MoveLanding;
import '../../domain/usecase/move_item.dart';
import '../../domain/usecase/plan_move.dart';
import '../../domain/usecase/select_bench.dart';
import '../../domain/usecase/set_project_stored.dart';
import '../../domain/usecase/toggle_group.dart';
import '../../domain/usecase/watch_sidebar.dart';
import '../widgets/sidebar_segments.dart';

part 'sidebar_state.dart';

/// Dono da assinatura da barra lateral: abre ao nascer e cancela no
/// `close()`. Cada evento do core traz a árvore inteira.
class SidebarCubit extends Cubit<SidebarState> {
  SidebarCubit({
    required WatchSidebar watch,
    required this._select,
    required this._toggle,
    required this._setStored,
    required this._move,
    required this._plan,
  }) : super(const SidebarState()) {
    _subscription = watch().listen(_onTree);
  }

  final SelectBench _select;
  final ToggleGroup _toggle;
  final SetProjectStored _setStored;
  final MoveItem _move;
  final PlanMove _plan;
  StreamSubscription<SidebarTree>? _subscription;

  void _onTree(SidebarTree tree) => emit(state.copyWith(tree: tree));

  void showTab(SidebarTab tab) => emit(state.copyWith(tab: tab));

  void select(String benchId) => _fire(_select(benchId));

  void toggleWorkspace(String id) => _fire(_toggle.workspace(id));

  void toggleProject(String workspaceId, String projectId) =>
      _fire(_toggle.project(workspaceId, projectId));

  void toggleDrawer(String workspaceId) => _fire(_toggle.drawer(workspaceId));

  void setStored(
    String workspaceId,
    String projectId, {
    required bool stored,
  }) => _fire(_setStored(workspaceId, projectId, stored: stored));

  void moveWorkspace(String id, int position) =>
      _fire(_move.workspace(id, position));

  void moveProject(
    String id,
    String workspaceId,
    int position, {
    required bool stored,
  }) => _fire(_move.project(id, workspaceId, position, stored: stored));

  void moveBench(String id, String projectId, int position) =>
      _fire(_move.bench(id, projectId, position));

  /// Durante o arrasto: o core diz onde cairia, ou `null` se não pode.
  Future<MoveLanding?> planMove(
    String kind,
    String item, {
    String? parent,
    required int to,
  }) => _plan(
    kind,
    item,
    parent: parent,
    to: to,
  ).catchError((_) => null, test: (error) => error is SidebarError);

  /// Gesto é "mande e siga": o que vale é a árvore que o core devolve.
  void _fire(Future<void> future) => unawaited(
    future.catchError((_) {}, test: (error) => error is SidebarError),
  );

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

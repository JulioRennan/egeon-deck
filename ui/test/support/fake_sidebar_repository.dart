import 'dart:async';

import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_tree.dart';
import 'package:egeon_deck/features/sidebar/domain/repository/sidebar_repository.dart';

/// A barra falsa: o teste empurra árvores e lê os gestos que a UI mandou.
class FakeSidebarRepository implements SidebarRepository {
  final _trees = StreamController<SidebarTree>.broadcast();
  final selected = <String>[];
  final toggledWorkspaces = <String>[];
  final toggledProjects = <(String, String)>[];
  final toggledDrawers = <String>[];
  final stored = <(String, String, bool)>[];
  final moves = <String>[];
  final plans = <String>[];

  /// O que o "core" responde ao plan_move: por padrão, cai onde se pediu.
  MoveLanding? Function(String kind, String item, String? parent, int to)
  landing = (kind, item, parent, to) => MoveLanding(parent: parent, to: to);
  var watchers = 0;

  void push(SidebarTree tree) => _trees.add(tree);

  @override
  Stream<SidebarTree> watch() {
    late StreamController<SidebarTree> controller;
    StreamSubscription<SidebarTree>? inner;
    controller = StreamController<SidebarTree>(
      onListen: () {
        watchers++;
        inner = _trees.stream.listen(controller.add);
      },
      onCancel: () {
        watchers--;
        return inner?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> select(String benchId) async => selected.add(benchId);

  @override
  Future<void> toggleWorkspace(String workspaceId) async =>
      toggledWorkspaces.add(workspaceId);

  @override
  Future<void> toggleProject(String workspaceId, String projectId) async =>
      toggledProjects.add((workspaceId, projectId));

  @override
  Future<void> toggleDrawer(String workspaceId) async =>
      toggledDrawers.add(workspaceId);

  @override
  Future<void> setStored(
    String workspaceId,
    String projectId, {
    required bool stored,
  }) async => this.stored.add((workspaceId, projectId, stored));

  @override
  Future<MoveLanding?> planMove(
    String kind,
    String item, {
    String? parent,
    required int to,
  }) async {
    plans.add('$kind:$item@${parent ?? '-'}/$to');
    return landing(kind, item, parent, to);
  }

  @override
  Future<void> moveWorkspace(String id, int position) async =>
      moves.add('workspace:$id@$position');

  @override
  Future<void> moveProject(
    String id,
    String workspaceId,
    int position, {
    required bool stored,
  }) async => moves.add('project:$id@$workspaceId/$position/$stored');

  @override
  Future<void> moveBench(String id, String projectId, int position) async =>
      moves.add('bench:$id@$projectId/$position');
}

import '../repository/sidebar_repository.dart';

/// Reordena ou muda de pai o que se arrastou na árvore. A posição é entre os
/// irmãos, sem contar o próprio item; quem decide se vale é o core Rust.
class MoveItem {
  const MoveItem(this._repository);

  final SidebarRepository _repository;

  Future<void> workspace(String id, int position) =>
      _repository.moveWorkspace(id, position);

  Future<void> project(
    String id,
    String workspaceId,
    int position, {
    required bool stored,
  }) => _repository.moveProject(id, workspaceId, position, stored: stored);

  Future<void> bench(String id, String projectId, int position) =>
      _repository.moveBench(id, projectId, position);
}

import '../repository/sidebar_repository.dart';

/// Recolhe ou abre um workspace, um projeto ou a gaveta.
class ToggleGroup {
  const ToggleGroup(this._repository);

  final SidebarRepository _repository;

  Future<void> workspace(String workspaceId) =>
      _repository.toggleWorkspace(workspaceId);

  Future<void> project(String workspaceId, String projectId) =>
      _repository.toggleProject(workspaceId, projectId);

  Future<void> drawer(String workspaceId) =>
      _repository.toggleDrawer(workspaceId);
}

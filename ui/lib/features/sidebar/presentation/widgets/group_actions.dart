import '../../domain/entities/sidebar_tree.dart';

/// O que os cabeçalhos de workspace e de projeto podem pedir.
class GroupActions {
  const GroupActions({
    required this.onToggleWorkspace,
    required this.onToggleProject,
    required this.onCreateBench,
    required this.onCreateBenchFromWorktree,
    required this.onEditWorkspace,
    required this.onCreateProject,
    required this.onRemoveWorkspace,
    required this.onRemoveProject,
    required this.onSetStored,
    required this.onToggleDrawer,
  });

  final void Function(String workspaceId) onToggleWorkspace;
  final void Function(String workspaceId, String projectId) onToggleProject;
  final void Function(SidebarProject project) onCreateBench;
  final void Function(SidebarProject project) onCreateBenchFromWorktree;
  final void Function(SidebarWorkspace workspace) onEditWorkspace;
  final void Function(SidebarWorkspace workspace) onCreateProject;
  final void Function(SidebarWorkspace workspace) onRemoveWorkspace;
  final void Function(SidebarWorkspace workspace, SidebarProject project)
  onRemoveProject;
  final void Function(
    String workspaceId,
    String projectId, {
    required bool stored,
  })
  onSetStored;
  final void Function(String workspaceId) onToggleDrawer;
}

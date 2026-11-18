import '../repository/workspace_repository.dart';

/// Tirar um workspace, ou um projeto dele. `check` pergunta ao core antes de
/// confirmar: se ele recusar (bancadas dentro, por exemplo), a recusa é o que
/// se mostra.
class RemoveWorkspace {
  const RemoveWorkspace(this._repository);

  final WorkspaceRepository _repository;

  Future<void> checkWorkspace(String id) =>
      _repository.removeWorkspace(id, dryRun: true);

  Future<void> workspace(String id) => _repository.removeWorkspace(id);

  Future<void> checkProject(String workspaceId, String projectId) =>
      _repository.removeProject(workspaceId, projectId, dryRun: true);

  Future<void> project(String workspaceId, String projectId) =>
      _repository.removeProject(workspaceId, projectId);
}

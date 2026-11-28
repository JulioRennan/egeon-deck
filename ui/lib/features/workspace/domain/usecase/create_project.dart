import '../repository/workspace_repository.dart';

class CreateProject {
  const CreateProject(this._repository);

  final WorkspaceRepository _repository;

  Future<String> suggestedParent(String workspaceId) =>
      _repository.suggestedParent(workspaceId);

  Future<void> call(
    String workspaceId, {
    required String name,
    required String parent,
    required bool git,
  }) => _repository.createProject(
    workspaceId,
    name: name,
    parent: parent,
    git: git,
  );
}

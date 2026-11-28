import '../repository/sidebar_repository.dart';

/// Guarda o projeto na gaveta do workspace, ou tira de lá.
class SetProjectStored {
  const SetProjectStored(this._repository);

  final SidebarRepository _repository;

  Future<void> call(
    String workspaceId,
    String projectId, {
    required bool stored,
  }) => _repository.setStored(workspaceId, projectId, stored: stored);
}

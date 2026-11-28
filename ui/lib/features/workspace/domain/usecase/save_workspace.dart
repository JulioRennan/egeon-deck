import '../entities/workspace_draft.dart';
import '../entities/workspace_saved.dart';
import '../repository/workspace_repository.dart';

class SaveWorkspace {
  const SaveWorkspace(this._repository);

  final WorkspaceRepository _repository;

  Future<WorkspaceDraft> draft(String id) => _repository.draft(id);

  Future<String> multiName(String? workspaceId, List<String> folders) =>
      _repository.multiName(workspaceId, folders);

  Future<WorkspaceSaved> call(WorkspaceDraft draft, {String? id}) =>
      _repository.save(draft, id: id);
}

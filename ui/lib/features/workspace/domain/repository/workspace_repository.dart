import '../entities/workspace_draft.dart';

/// Os gestos sobre workspaces e projetos. Quem decide se vale é o core Rust;
/// a recusa chega como `CommandFailed`, com o texto dele.
abstract interface class WorkspaceRepository {
  /// Com [dryRun] o core só diz se aceitaria; recusa vem como `CommandFailed`.
  Future<void> removeWorkspace(String id, {bool dryRun = false});

  Future<void> removeProject(
    String workspaceId,
    String projectId, {
    bool dryRun = false,
  });

  /// O workspace como o formulário o edita.
  Future<WorkspaceDraft> draft(String id);

  /// Cria (sem [id]) ou grava o workspace do formulário.
  Future<void> save(WorkspaceDraft draft, {String? id});

  /// Onde sugerir criar o próximo projeto deste workspace.
  Future<String> suggestedParent(String workspaceId);

  /// O nome que o core daria a um multi-projeto sem nome, para estas pastas.
  Future<String> multiName(String? workspaceId, List<String> folders);

  Future<void> createProject(
    String workspaceId, {
    required String name,
    required String parent,
    required bool git,
  });
}

import 'package:egeon_deck/features/workspace/domain/errors/workspace_error.dart';
import 'package:egeon_deck/features/workspace/domain/entities/workspace_draft.dart';
import 'package:egeon_deck/features/workspace/domain/repository/workspace_repository.dart';

/// O workspace falso: guarda os gestos; `refuse` recusa o próximo.
class FakeWorkspaceRepository implements WorkspaceRepository {
  final log = <String>[];
  String? refuse;

  Future<void> _run(String entry) async {
    final reason = refuse;
    if (reason != null) throw WorkspaceRefused(reason);
    log.add(entry);
  }

  @override
  Future<void> removeWorkspace(String id, {bool dryRun = false}) =>
      _run('${dryRun ? 'checar-' : ''}remover-ws:$id');

  @override
  Future<void> removeProject(
    String workspaceId,
    String projectId, {
    bool dryRun = false,
  }) =>
      _run('${dryRun ? 'checar-' : ''}remover-projeto:$workspaceId/$projectId');

  /// O que `draft` devolve na edição.
  WorkspaceDraft existing = const WorkspaceDraft(name: 'Duck');
  final saved = <(String?, WorkspaceDraft)>[];
  var parent = '~/code';
  final created = <String>[];

  @override
  Future<WorkspaceDraft> draft(String id) async {
    await _run('carregar:$id');
    return existing;
  }

  @override
  Future<void> save(WorkspaceDraft draft, {String? id}) async {
    await _run('salvar:$id');
    saved.add((id, draft));
  }

  /// O nome que o "core" dá ao multi-projeto sem nome.
  String multiNameAnswer = 'egeon + nexus';
  final multiNames = <String>[];

  @override
  Future<String> multiName(String? workspaceId, List<String> folders) async {
    multiNames.add('$workspaceId:${folders.join(',')}');
    return multiNameAnswer;
  }

  @override
  Future<String> suggestedParent(String workspaceId) async => parent;

  @override
  Future<void> createProject(
    String workspaceId, {
    required String name,
    required String parent,
    required bool git,
  }) async {
    await _run('criar-projeto:$workspaceId/$name@$parent/$git');
    created.add('$name@$parent/$git');
  }
}
